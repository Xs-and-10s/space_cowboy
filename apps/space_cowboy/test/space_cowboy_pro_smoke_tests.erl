-module(space_cowboy_pro_smoke_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 10).

pro_smoke_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun
            (skip) ->
                [];
            (BaseUrl) ->
                [
                    ?_test(home_uses_local_pro_scripts(BaseUrl)),
                    ?_test(serves_pro_bundle(BaseUrl)),
                    ?_test(serves_inspector_bundle(BaseUrl)),
                    ?_test(rocket_manifest_get_golden(BaseUrl)),
                    ?_test(rocket_manifest_post_roundtrip(BaseUrl)),
                    ?_test(rocket_manifest_post_property(BaseUrl))
                ]
        end}.

setup() ->
    compile_pro_smoke_example(),
    case space_cowboy_pro_smoke:load_config() of
        {ok, _Config} ->
            {ok, _} = application:ensure_all_started(inets),
            {ok, _} = application:ensure_all_started(space_cowboy),
            Name = listener_name(),
            {ok, _Pid} = space_cowboy_pro_smoke:start(Name, #{transport_options => [{port, 0}]}),
            Port = ranch:get_port(Name),
            {Name, "http://127.0.0.1:" ++ integer_to_list(Port)};
        {error, _Reason} ->
            skip
    end.

cleanup(skip) ->
    ok;
cleanup({Name, _BaseUrl}) ->
    _ = space_cowboy_pro_smoke:stop(Name),
    ok.

home_uses_local_pro_scripts({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/"),
    ?assertEqual("text/html; charset=utf-8", header("content-type", Headers)),
    ?assertMatch({_, _}, binary:match(Body, <<"<script type=\"module\" src=\"/assets/datastar-pro.js\"></script>">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"<script type=\"module\" src=\"/assets/datastar-inspector.js\"></script>">>)),
    ?assertEqual(nomatch, binary:match(Body, <<"cdn.jsdelivr.net">>)),
    ?assertMatch({_, _}, binary:match(
        Body,
        <<"<space-counter count=\"5\" data-label=\"Rocket\"><p data-text=\"$count\"></p></space-counter>">>
    )).

serves_pro_bundle({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/assets/datastar-pro.js"),
    ?assertEqual("application/javascript; charset=utf-8", header("content-type", Headers)),
    ?assert(byte_size(Body) > 0).

serves_inspector_bundle({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/assets/datastar-inspector.js"),
    ?assertEqual("application/javascript; charset=utf-8", header("content-type", Headers)),
    ?assert(byte_size(Body) > 0).

rocket_manifest_get_golden({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/api/rocket/manifests"),
    ?assertEqual("application/json", header("content-type", Headers)),
    ?assertEqual(<<"{\"version\":1,\"components\":[{\"tag\":\"space-counter\"}]}">>, Body).

rocket_manifest_post_roundtrip({_Name, BaseUrl}) ->
    Manifest = #{<<"version">> => 1, <<"components">> => [#{<<"tag">> => <<"space-counter">>}]},
    {202, Headers, Body} = http_post(BaseUrl ++ "/api/rocket/manifests", json:encode(Manifest)),
    ?assertEqual("application/json", header("content-type", Headers)),
    ?assertEqual({ok, #{<<"received">> => Manifest}}, decode_json(Body)).

rocket_manifest_post_property({_Name, BaseUrl}) ->
    ?assert(proper:quickcheck(prop_rocket_manifest_post_roundtrip(BaseUrl), proper_opts())).

prop_rocket_manifest_post_roundtrip(BaseUrl) ->
    ?FORALL(Tag, rocket_tag(),
        begin
            Manifest = #{<<"version">> => 1, <<"components">> => [#{<<"tag">> => Tag}]},
            {202, Headers, Body} = http_post(BaseUrl ++ "/api/rocket/manifests", json:encode(Manifest)),
            header("content-type", Headers) =:= "application/json"
                andalso decode_json(Body) =:= {ok, #{<<"received">> => Manifest}}
        end).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

compile_pro_smoke_example() ->
    Source = "examples/pro_smoke/src/space_cowboy_pro_smoke.erl",
    {ok, space_cowboy_pro_smoke, Binary} = compile:file(Source, [binary, return_errors]),
    code:purge(space_cowboy_pro_smoke),
    code:delete(space_cowboy_pro_smoke),
    {module, space_cowboy_pro_smoke} = code:load_binary(space_cowboy_pro_smoke, Source, Binary),
    ok.

rocket_tag() ->
    ?LET(Generated, {tag_part(), tag_part()},
        begin
            {Prefix, Suffix} = Generated,
            <<Prefix/binary, "-", Suffix/binary>>
        end).

tag_part() ->
    ?LET(Chars, non_empty(list(tag_char())), list_to_binary(Chars)).

tag_char() ->
    oneof(lists:seq($a, $z) ++ lists:seq($0, $9)).

http_get(Url) ->
    Request = {Url, []},
    HttpOptions = [],
    Options = [{body_format, binary}],
    {ok, {{_Version, Status, _Reason}, Headers, Body}} =
        httpc:request(get, Request, HttpOptions, Options),
    {Status, Headers, Body}.

http_post(Url, BodyBytes) ->
    Request = {Url, [], "application/json", iolist_to_binary(BodyBytes)},
    HttpOptions = [],
    Options = [{body_format, binary}],
    {ok, {{_Version, Status, _Reason}, Headers, Body}} =
        httpc:request(post, Request, HttpOptions, Options),
    {Status, Headers, Body}.

decode_json(Body) ->
    try {ok, json:decode(Body)}
    catch _:_ -> error
    end.

header(Name, Headers) ->
    LowerName = string:lowercase(Name),
    case lists:keyfind(LowerName, 1, [{string:lowercase(Key), Value} || {Key, Value} <- Headers]) of
        {_, Value} -> Value;
        false -> undefined
    end.

listener_name() ->
    list_to_atom("space_cowboy_pro_smoke_" ++ integer_to_list(erlang:unique_integer([positive]))).
