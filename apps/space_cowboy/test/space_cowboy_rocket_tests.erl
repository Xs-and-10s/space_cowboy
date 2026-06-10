-module(space_cowboy_rocket_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 50).

component_golden_test() ->
    ?assertEqual(
        <<"<demo-counter count=\"5\" disabled data-label=\"Inventory\">Ready</demo-counter>">>,
        iolist_to_binary(space_cowboy_rocket:component(
            <<"demo-counter">>,
            [
                {<<"count">>, 5},
                {<<"disabled">>, true},
                {<<"hidden">>, false},
                {<<"data-label">>, <<"Inventory">>}
            ],
            <<"Ready">>
        ))
    ).

component_escapes_attrs_golden_test() ->
    ?assertEqual(
        <<"<demo-card label=\"A &amp; B &quot;quoted&quot;\"></demo-card>">>,
        iolist_to_binary(space_cowboy_rocket:component(<<"demo-card">>, #{
            <<"label">> => <<"A & B \"quoted\"">>
        }))
    ).

component_requires_custom_element_tag_test() ->
    ?assertError(
        {invalid_rocket_tag, <<"button">>},
        iolist_to_binary(space_cowboy_rocket:component(<<"button">>, #{}))
    ).

component_property_test() ->
    ?assert(proper:quickcheck(prop_component_wraps_valid_tags(), proper_opts())).

manifest_endpoint_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(BaseUrl) ->
            [
                ?_test(get_manifest_golden(BaseUrl)),
                ?_test(post_manifest_golden(BaseUrl)),
                ?_test(post_manifest_callback_error_golden(BaseUrl)),
                ?_test(post_manifest_invalid_json_golden(BaseUrl)),
                ?_test(manifest_endpoint_rejects_other_methods(BaseUrl))
            ]
        end}.

setup() ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(space_cowboy),
    CallbackKey = {?MODULE, erlang:unique_integer([positive])},
    ManifestJson =
        <<"{\"version\":1,\"generatedAt\":\"2026-06-10T00:00:00Z\","
          "\"components\":[{\"tag\":\"demo-counter\"}]}">>,
    Routes = [
        {"/rocket/manifests", space_cowboy_rocket:manifest_endpoint(ManifestJson, #{
            on_publish => fun(Manifest, _Req) ->
                persistent_term:put(CallbackKey, Manifest),
                {ok, #{<<"stored">> => true}}
            end
        })},
        {"/rocket/fail", space_cowboy_rocket:manifest_endpoint(<<"{}">>, #{
            on_publish => fun(_Manifest, _Req) -> {error, rejected} end
        })}
    ],
    Name = listener_name(),
    {ok, _Pid} = space_cowboy:start_clear(Name, Routes, #{transport_options => [{port, 0}]}),
    Port = ranch:get_port(Name),
    {Name, "http://127.0.0.1:" ++ integer_to_list(Port), CallbackKey}.

cleanup({Name, _BaseUrl, CallbackKey}) ->
    _ = space_cowboy:stop(Name),
    _ = persistent_term:erase(CallbackKey),
    ok.

get_manifest_golden({_Name, BaseUrl, _CallbackKey}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/rocket/manifests"),
    ?assertEqual("application/json", header("content-type", Headers)),
    ?assertEqual(
        <<"{\"version\":1,\"generatedAt\":\"2026-06-10T00:00:00Z\","
          "\"components\":[{\"tag\":\"demo-counter\"}]}">>,
        Body
    ).

post_manifest_golden({_Name, BaseUrl, CallbackKey}) ->
    BodyIn =
        <<"{\"version\":1,\"generatedAt\":\"2026-06-10T00:00:01Z\","
          "\"components\":[{\"tag\":\"demo-dialog\"}]}">>,
    {202, Headers, Body} = http_post(BaseUrl ++ "/rocket/manifests", BodyIn),
    ?assertEqual("application/json", header("content-type", Headers)),
    ?assertEqual(<<"{\"stored\":true}">>, Body),
    ?assertMatch(
        #{<<"components">> := [#{<<"tag">> := <<"demo-dialog">>}]},
        persistent_term:get(CallbackKey)
    ).

post_manifest_callback_error_golden({_Name, BaseUrl, _CallbackKey}) ->
    {422, Headers, Body} = http_post(BaseUrl ++ "/rocket/fail", <<"{\"version\":1}">>),
    ?assertEqual("application/json", header("content-type", Headers)),
    ?assertEqual(<<"{\"error\":\"rejected\"}">>, Body).

post_manifest_invalid_json_golden({_Name, BaseUrl, _CallbackKey}) ->
    {400, Headers, Body} = http_post(BaseUrl ++ "/rocket/manifests", <<"{">>),
    ?assertEqual("application/json", header("content-type", Headers)),
    ?assertEqual(<<"{\"error\":\"invalid_json\"}">>, Body).

manifest_endpoint_rejects_other_methods({_Name, BaseUrl, _CallbackKey}) ->
    {405, Headers, Body} = http_request(put, BaseUrl ++ "/rocket/manifests", <<"{}">>),
    ?assertEqual("application/json", header("content-type", Headers)),
    ?assertEqual(<<"{\"error\":\"method_not_allowed\"}">>, Body).

prop_component_wraps_valid_tags() ->
    ?FORALL(Generated, {rocket_tag(), printable_binary()},
        begin
            {Tag, Body} = Generated,
            Component = iolist_to_binary(space_cowboy_rocket:component(Tag, [], Body)),
            Component =:= <<"<", Tag/binary, ">", Body/binary, "</", Tag/binary, ">">>
        end).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

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

printable_binary() ->
    ?LET(Chars, list(printable_char()), list_to_binary(Chars)).

printable_char() ->
    oneof(lists:seq(32, 126)).

http_get(Url) ->
    http_request(get, Url, <<>>).

http_post(Url, Body) ->
    http_request(post, Url, Body).

http_request(Method, Url, _Body) when Method =:= get ->
    Request = {Url, []},
    HttpOptions = [],
    Options = [{body_format, binary}],
    {ok, {{_Version, Status, _Reason}, Headers, ResponseBody}} =
        httpc:request(get, Request, HttpOptions, Options),
    {Status, Headers, ResponseBody};
http_request(Method, Url, Body) ->
    Request = {Url, [], "application/json", Body},
    HttpOptions = [],
    Options = [{body_format, binary}],
    {ok, {{_Version, Status, _Reason}, Headers, ResponseBody}} =
        httpc:request(Method, Request, HttpOptions, Options),
    {Status, Headers, ResponseBody}.

header(Name, Headers) ->
    LowerName = string:lowercase(Name),
    case lists:keyfind(LowerName, 1, [{string:lowercase(Key), Value} || {Key, Value} <- Headers]) of
        {_, Value} -> Value;
        false -> undefined
    end.

listener_name() ->
    list_to_atom("space_cowboy_rocket_" ++ integer_to_list(erlang:unique_integer([positive]))).
