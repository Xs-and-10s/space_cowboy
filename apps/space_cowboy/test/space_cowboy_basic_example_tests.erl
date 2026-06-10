-module(space_cowboy_basic_example_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 25).

basic_example_test_() ->
    {setup,
        fun setup/0,
        fun cleanup/1,
        fun(BaseUrl) ->
            [
                ?_test(home_page_contains_datastar_workflows(BaseUrl)),
                ?_test(ping_patches_message(BaseUrl)),
                ?_test(active_search_patches_results(BaseUrl)),
                ?_test(click_to_edit_patches_editor(BaseUrl)),
                ?_test(save_title_patches_signal_and_editor(BaseUrl)),
                ?_test(progress_loop_streams_ordered_updates(BaseUrl)),
                ?_test(active_search_property(BaseUrl)),
                ?_test(save_title_property(BaseUrl))
            ]
        end}.

setup() ->
    compile_basic_example(),
    {ok, _} = application:ensure_all_started(inets),
    {ok, _} = application:ensure_all_started(space_cowboy),
    Name = listener_name(),
    {ok, _Pid} = space_cowboy_basic:start(Name, #{transport_options => [{port, 0}]}),
    Port = ranch:get_port(Name),
    {Name, "http://127.0.0.1:" ++ integer_to_list(Port)}.

cleanup({Name, _BaseUrl}) ->
    _ = space_cowboy_basic:stop(Name),
    ok.

home_page_contains_datastar_workflows({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/"),
    ?assertEqual("text/html; charset=utf-8", header("content-type", Headers)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-signals='{ \"message\": \"Ready\"">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-on:click=\"@get('/ping')\"">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-bind:query">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-on:input__debounce.200ms=\"@get('/search')\"">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"id=\"editor\"">>)),
    ?assertMatch({_, _}, binary:match(Body, <<"data-on:click=\"@get('/progress')\"">>)).

ping_patches_message({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/ping"),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"message\":\"Datastar over Cowboy SSE\"}\n\n">>,
        Body
    ).

active_search_patches_results({_Name, BaseUrl}) ->
    {200, Headers, Body} = get_with_signals(BaseUrl ++ "/search", #{<<"query">> => <<"Mars">>}),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #results\n"
          "data: mode inner\n"
          "data: elements <li id=\"result-primary\">Mars Station</li>\n\n">>,
        Body
    ).

click_to_edit_patches_editor({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/edit-title"),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #editor\n"
          "data: mode inner\n"
          "data: elements <label for=\"title-input\">Title</label><input id=\"title-input\" data-bind:title value=\"Docking Checklist\"><button data-on:click=\"@post('/save-title')\">Save</button>\n\n">>,
        Body
    ).

save_title_patches_signal_and_editor({_Name, BaseUrl}) ->
    {200, Headers, Body} = post_with_signals(BaseUrl ++ "/save-title", #{<<"title">> => <<"Launch Plan">>}),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"title\":\"Launch Plan\"}\n\n"
          "event: datastar-patch-elements\n"
          "data: selector #editor\n"
          "data: mode inner\n"
          "data: elements <h2 id=\"title\" data-text=\"$title\">Launch Plan</h2><button data-on:click=\"@get('/edit-title')\">Edit</button>\n\n">>,
        Body
    ).

progress_loop_streams_ordered_updates({_Name, BaseUrl}) ->
    {200, Headers, Body} = http_get(BaseUrl ++ "/progress"),
    ?assertEqual("text/event-stream", header("content-type", Headers)),
    ?assertEqual(
        <<": progress-open\n\n"
          "event: datastar-patch-signals\n"
          "data: signals {\"progress\":25}\n\n"
          "event: datastar-patch-elements\n"
          "data: selector #phase\n"
          "data: elements <p id=\"phase\">Ignition</p>\n\n"
          "event: datastar-patch-signals\n"
          "data: signals {\"progress\":60}\n\n"
          "event: datastar-patch-elements\n"
          "data: selector #phase\n"
          "data: elements <p id=\"phase\">Telemetry lock</p>\n\n"
          "event: datastar-patch-signals\n"
          "data: signals {\"progress\":100}\n\n"
          "event: datastar-patch-elements\n"
          "data: selector #phase\n"
          "data: elements <p id=\"phase\">Docking complete</p>\n\n"
          ": progress-close\n\n">>,
        Body
    ).

active_search_property({_Name, BaseUrl}) ->
    ?assert(proper:quickcheck(prop_active_search_escapes(BaseUrl), proper_opts())).

save_title_property({_Name, BaseUrl}) ->
    ?assert(proper:quickcheck(prop_save_title_escapes(BaseUrl), proper_opts())).

prop_active_search_escapes(BaseUrl) ->
    ?FORALL(Query, printable_binary(),
        begin
            {200, Headers, Body} = get_with_signals(BaseUrl ++ "/search", #{<<"query">> => Query}),
            ExpectedElement = expected_search_result(Query),
            ExpectedBody = <<"event: datastar-patch-elements\n"
                             "data: selector #results\n"
                             "data: mode inner\n"
                             "data: elements ", ExpectedElement/binary, "\n\n">>,
            header("content-type", Headers) =:= "text/event-stream"
                andalso Body =:= ExpectedBody
        end).

prop_save_title_escapes(BaseUrl) ->
    ?FORALL(Title, printable_binary(),
        begin
            {200, Headers, Body} = post_with_signals(BaseUrl ++ "/save-title", #{<<"title">> => Title}),
            ExpectedJson = iolist_to_binary(json:encode(#{<<"title">> => Title})),
            ExpectedElement = expected_title_display(Title),
            ExpectedBody = <<"event: datastar-patch-signals\n"
                             "data: signals ", ExpectedJson/binary, "\n\n"
                             "event: datastar-patch-elements\n"
                             "data: selector #editor\n"
                             "data: mode inner\n"
                             "data: elements ", ExpectedElement/binary, "\n\n">>,
            header("content-type", Headers) =:= "text/event-stream"
                andalso Body =:= ExpectedBody
        end).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

compile_basic_example() ->
    Source = "examples/basic/src/space_cowboy_basic.erl",
    {ok, space_cowboy_basic, Binary} = compile:file(Source, [binary, return_errors]),
    code:purge(space_cowboy_basic),
    code:delete(space_cowboy_basic),
    {module, space_cowboy_basic} = code:load_binary(space_cowboy_basic, Source, Binary),
    ok.

expected_search_result(<<>>) ->
    <<"<li data-empty>No query</li>">>;
expected_search_result(Query) ->
    Escaped = space_cowboy_html:escape(Query),
    <<"<li id=\"result-primary\">", Escaped/binary, " Station</li>">>.

expected_title_display(Title) ->
    Escaped = space_cowboy_html:escape(Title),
    <<"<h2 id=\"title\" data-text=\"$title\">", Escaped/binary,
      "</h2><button data-on:click=\"@get('/edit-title')\">Edit</button>">>.

printable_binary() ->
    ?LET(Chars, list(printable_char()), list_to_binary(Chars)).

printable_char() ->
    oneof(lists:seq(32, 126)).

get_with_signals(BaseUrl, Signals) ->
    Json = iolist_to_binary(json:encode(Signals)),
    http_get(BaseUrl ++ "?datastar=" ++ binary_to_list(percent_encode(Json))).

post_with_signals(Url, Signals) ->
    Json = iolist_to_binary(json:encode(Signals)),
    http_post(Url, Json).

http_get(Url) ->
    Request = {Url, []},
    HttpOptions = [],
    Options = [{body_format, binary}],
    {ok, {{_Version, Status, _Reason}, Headers, Body}} =
        httpc:request(get, Request, HttpOptions, Options),
    {Status, Headers, Body}.

http_post(Url, BodyBytes) ->
    Request = {Url, [], "application/json", BodyBytes},
    HttpOptions = [],
    Options = [{body_format, binary}],
    {ok, {{_Version, Status, _Reason}, Headers, Body}} =
        httpc:request(post, Request, HttpOptions, Options),
    {Status, Headers, Body}.

header(Name, Headers) ->
    LowerName = string:lowercase(Name),
    case lists:keyfind(LowerName, 1, [{string:lowercase(Key), Value} || {Key, Value} <- Headers]) of
        {_, Value} -> Value;
        false -> undefined
    end.

listener_name() ->
    list_to_atom("space_cowboy_basic_example_" ++ integer_to_list(erlang:unique_integer([positive]))).

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
