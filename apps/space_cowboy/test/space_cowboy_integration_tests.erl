-module(space_cowboy_integration_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 25).

conformance_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(BaseUrl) ->
            [
                ?_test(home_page_preserves_datastar_attributes(BaseUrl)),
                ?_test(counter_patches_signals(BaseUrl)),
                ?_test(search_patches_elements(BaseUrl)),
                ?_test(progress_stream_sends_ordered_events(BaseUrl)),
                ?_test(script_endpoint_executes_script_patch(BaseUrl)),
                ?_test(malformed_query_returns_sse_error(BaseUrl)),
                ?_test(counter_property(BaseUrl)),
                ?_test(search_property(BaseUrl))
            ]
        end}.

setup() ->
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(space_cowboy),
    Name = listener_name(),
    {ok, _Pid} = space_cowboy:start_clear(Name, space_cowboy_conformance_app:routes(), #{
        transport_options => [{port, 0}]
    }),
    Port = ranch:get_port(Name),
    {Name, "http://127.0.0.1:" ++ integer_to_list(Port), Port}.

cleanup({Name, _BaseUrl, _Port}) ->
    _ = space_cowboy:stop(Name),
    ok.

home_page_preserves_datastar_attributes({_Name, BaseUrl, _Port}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/"),
    ?assertEqual("text/html; charset=utf-8", header("content-type", Headers)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-signals='{ \"count\": 0, \"query\": \"\" }'">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-on:click=\"@get('/counter')\"">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-bind:query">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-on:input__debounce.200ms=\"@get('/search')\"">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-attr:value=\"$progress\"">>)).

counter_patches_signals({_Name, BaseUrl, _Port}) ->
    {200, Headers, Body} = get_with_signals(BaseUrl ++ "/counter", #{<<"count">> => 41}),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"count\":42}\n\n">>,
        Body
    ).

search_patches_elements({_Name, BaseUrl, _Port}) ->
    {200, Headers, Body} = get_with_signals(BaseUrl ++ "/search", #{<<"query">> => <<"Mars">>}),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #results\n"
          "data: mode inner\n"
          "data: elements <li id=\"result-primary\">Mars Station</li>\n\n">>,
        Body
    ).

progress_stream_sends_ordered_events({_Name, BaseUrl, _Port}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/progress"),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"progress\":25}\n\n"
          "event: datastar-patch-elements\n"
          "data: selector #phase\n"
          "data: elements <span id=\"phase\">Ignition</span>\n\n"
          "event: datastar-patch-signals\n"
          "data: signals {\"progress\":100}\n\n">>,
        Body
    ).

script_endpoint_executes_script_patch({_Name, BaseUrl, _Port}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/script"),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector body\n"
          "data: mode append\n"
          "data: elements <script data-effect=\"el.remove()\">window.spaceCowboyReady = true;</script>\n\n">>,
        Body
    ).

malformed_query_returns_sse_error({_Name, _BaseUrl, Port}) ->
    RawResponse = raw_http_get(Port, <<"/malformed?datastar=%GG">>),
    ?assertMatch({_, _}, binary:match(RawResponse, <<"HTTP/1.1 200 OK">>)),
    ?assertMatch({_, _}, binary:match(RawResponse, <<"content-type: text/event-stream">>)),
    ?assertMatch({_, _}, binary:match(
        RawResponse,
        <<"event: datastar-patch-signals\n"
          "data: signals {\"error\":\"invalid_query\"}\n\n">>
    )).

counter_property({_Name, BaseUrl, _Port}) ->
    ?assert(proper:quickcheck(prop_counter_roundtrip(BaseUrl), proper_opts())).

search_property({_Name, BaseUrl, _Port}) ->
    ?assert(proper:quickcheck(prop_search_escapes_and_patches(BaseUrl), proper_opts())).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

prop_counter_roundtrip(BaseUrl) ->
    ?FORALL(Count, range(0, 100000),
        begin
            {200, Headers, Body} = get_with_signals(BaseUrl ++ "/counter", #{<<"count">> => Count}),
            ExpectedJson = iolist_to_binary(json:encode(#{<<"count">> => Count + 1})),
            header("content-type", Headers) =:= "text/event-stream"
                andalso Body =:= <<"event: datastar-patch-signals\n"
                                    "data: signals ", ExpectedJson/binary, "\n\n">>
        end).

prop_search_escapes_and_patches(BaseUrl) ->
    ?FORALL(Query, search_query(),
        begin
            {200, Headers, Body} = get_with_signals(BaseUrl ++ "/search", #{<<"query">> => Query}),
            ExpectedElement = expected_search_element(Query),
            ExpectedBody = <<"event: datastar-patch-elements\n"
                             "data: selector #results\n"
                             "data: mode inner\n"
                             "data: elements ", ExpectedElement/binary, "\n\n">>,
            header("content-type", Headers) =:= "text/event-stream"
                andalso Body =:= ExpectedBody
        end).

expected_search_element(<<>>) ->
    <<"<li data-empty>No query</li>">>;
expected_search_element(Query) ->
    Escaped = space_cowboy_html:escape(Query),
    <<"<li id=\"result-primary\">", Escaped/binary, " Station</li>">>.

search_query() ->
    ?LET(Chars, list(search_char()), list_to_binary(Chars)).

search_char() ->
    oneof(lists:seq(32, 126)).

get_with_signals(BaseUrl, Signals) ->
    Json = iolist_to_binary(json:encode(Signals)),
    http_get(BaseUrl ++ "?datastar=" ++ binary_to_list(percent_encode(Json))).

http_get(Url) ->
    Request = {Url, []},
    HttpOptions = [],
    Options = [{body_format, binary}],
    {ok, {{_Version, Status, _Reason}, Headers, Body}} =
        httpc:request(get, Request, HttpOptions, Options),
    {Status, Headers, Body}.

raw_http_get(Port, Path) ->
    {ok, Socket} = gen_tcp:connect({127, 0, 0, 1}, Port, [binary, {active, false}, {packet, raw}]),
    Request = [
        <<"GET ">>, Path, <<" HTTP/1.1\r\n">>,
        <<"Host: 127.0.0.1\r\n">>,
        <<"Connection: close\r\n\r\n">>
    ],
    ok = gen_tcp:send(Socket, Request),
    Response = recv_all(Socket, []),
    ok = gen_tcp:close(Socket),
    Response.

recv_all(Socket, Acc) ->
    case gen_tcp:recv(Socket, 0, 5000) of
        {ok, Data} -> recv_all(Socket, [Data | Acc]);
        {error, closed} -> iolist_to_binary(lists:reverse(Acc))
    end.

header(Name, Headers) ->
    LowerName = string:lowercase(Name),
    case lists:keyfind(LowerName, 1, [{string:lowercase(Key), Value} || {Key, Value} <- Headers]) of
        {_, Value} -> Value;
        false -> undefined
    end.

listener_name() ->
    list_to_atom("space_cowboy_conformance_" ++ integer_to_list(erlang:unique_integer([positive]))).

percent_encode(Binary) ->
    iolist_to_binary([percent_encode_byte(Byte) || <<Byte>> <= Binary]).

percent_encode_byte(Byte)
    when Byte >= $a, Byte =< $z;
         Byte >= $A, Byte =< $Z;
         Byte >= $0, Byte =< $9;
         Byte =:= $-;
         Byte =:= $.;
         Byte =:= $_;
         Byte =:= $~ ->
    Byte;
percent_encode_byte(Byte) ->
    <<"%", (hex_digit(Byte bsr 4)), (hex_digit(Byte band 16#0F))>>.

hex_digit(N) when N < 10 ->
    $0 + N;
hex_digit(N) ->
    $A + (N - 10).
