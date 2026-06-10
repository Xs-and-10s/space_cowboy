-module(space_cowboy_quic_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 50).
-define(H3_NUMTESTS, 10).
-define(H3_TIMEOUT, 5000).

quic_available_returns_boolean_test() ->
    ?assert(is_boolean(space_cowboy:quic_available())).

start_quic_unavailable_golden_test() ->
    case space_cowboy:quic_available() of
        false ->
            ?assertEqual({error, quic_unavailable}, space_cowboy:start_quic([], #{})),
            ?assertEqual({error, quic_unavailable}, space_cowboy:stop_quic(make_ref()));
        true ->
            ok
    end.

start_quic_unavailable_property_test() ->
    case space_cowboy:quic_available() of
        false ->
            ?assert(proper:quickcheck(prop_start_quic_unavailable_is_stable(), proper_opts()));
        true ->
            ok
    end.

start_quic_available_smoke_test() ->
    case {space_cowboy:quic_available(), quicer_fixture_certs()} of
        {true, {ok, CertFile, KeyFile}} ->
            Routes = [{"/", fun(_Req) -> {html, <<"ok">>} end}],
            Options = #{
                start_timeout => 5000,
                transport_options => #{
                    socket_opts => [
                        {certfile, CertFile},
                        {keyfile, KeyFile},
                        {verify, none}
                    ]
                }
            },
            {ok, Listener} = space_cowboy:start_quic(space_cowboy_quic_smoke, Routes, Options),
            ?assertEqual(ok, space_cowboy:stop_quic(Listener));
        _ ->
            ok
    end.

start_quic_available_handshake_test() ->
    case {space_cowboy:quic_available(), quicer_fixture_certs()} of
        {true, {ok, CertFile, KeyFile}} ->
            Port = available_udp_port(),
            Routes = [{"/", fun(_Req) -> {html, <<"ok">>} end}],
            Options = #{
                start_timeout => 5000,
                transport_options => #{
                    socket_opts => [
                        {port, Port},
                        {certfile, CertFile},
                        {keyfile, KeyFile},
                        {verify, none}
                    ]
                }
            },
            {ok, Listener} = space_cowboy:start_quic(space_cowboy_quic_handshake, Routes, Options),
            try
                {ok, Conn} = quicer:connect("localhost", Port, [{alpn, ["h3"]}, {verify, none}], 5000),
                ?assertEqual(ok, quicer:close_connection(Conn))
            after
                ?assertEqual(ok, space_cowboy:stop_quic(Listener))
            end;
        _ ->
            ok
    end.

start_quic_available_h3_get_golden_test() ->
    case {space_cowboy:quic_available(), quicer_fixture_certs()} of
        {true, Certs = {ok, _CertFile, _KeyFile}} ->
            with_quic_listener(space_cowboy_quic_h3_get, Certs, [{"/", fun(_Req) -> {html, <<"ok">>} end}],
                fun(Port) ->
                    ?assertMatch({ok, {200, _Headers, <<"ok">>}},
                        space_cowboy_h3_test_client:get(Port, <<"/">>))
                end);
        _ ->
            ok
    end.

start_quic_available_h3_route_property_test() ->
    case {space_cowboy:quic_available(), quicer_fixture_certs()} of
        {true, Certs = {ok, _CertFile, _KeyFile}} ->
            Routes = [{"/prop/:value", fun(Req) -> {html, cowboy_req:binding(value, Req)} end}],
            with_quic_listener(space_cowboy_quic_h3_prop, Certs, Routes,
                fun(Port) ->
                    ?assert(proper:quickcheck(prop_h3_route_roundtrip(Port), h3_proper_opts()))
                end);
        _ ->
            ok
    end.

datastar_sse_h3_parity_test_() ->
    case {space_cowboy:quic_available(), quicer_fixture_certs()} of
        {true, Certs = {ok, _CertFile, _KeyFile}} ->
            {setup,
                fun() -> setup_h3_conformance(Certs) end,
                fun cleanup_h3_conformance/1,
                fun({_Name, _Listener, Port}) ->
                    [
                        ?_test(h3_counter_patches_signals(Port)),
                        ?_test(h3_search_patches_elements(Port)),
                        ?_test(h3_progress_stream_sends_ordered_events(Port)),
                        ?_test(h3_script_endpoint_executes_script_patch(Port)),
                        ?_test(h3_template_patch_roundtrip(Port)),
                        ?_test(h3_body_signals_post_roundtrip(Port)),
                        ?_test(h3_heartbeat_stream_roundtrip(Port)),
                        ?_test(h3_malformed_query_returns_sse_error(Port)),
                        ?_test(h3_counter_property(Port)),
                        ?_test(h3_search_property(Port)),
                        ?_test(h3_template_patch_property(Port)),
                        ?_test(h3_body_signals_post_property(Port))
                    ]
                end};
        _ ->
            []
    end.

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

h3_proper_opts() ->
    [{numtests, ?H3_NUMTESTS}, {to_file, user}].

prop_start_quic_unavailable_is_stable() ->
    ?FORALL(Generated, {listener_name(), port()},
        begin
            {Name, Port} = Generated,
            Result = space_cowboy:start_quic(Name, [], #{port => Port}),
            Result =:= {error, quic_unavailable}
        end).

prop_h3_route_roundtrip(Port) ->
    ?FORALL(Value, path_segment(),
        begin
            Path = <<"/prop/", Value/binary>>,
            case space_cowboy_h3_test_client:get(Port, Path) of
                {ok, {200, _Headers, Value}} -> true;
                _ -> false
            end
        end).

prop_h3_counter_roundtrip(Port) ->
    ?FORALL(Count, range(0, 100000),
        begin
            {200, Headers, Body} =
                space_cowboy_h3_test_client:get_with_signals(Port, <<"/counter">>, #{<<"count">> => Count}),
            ExpectedJson = iolist_to_binary(json:encode(#{<<"count">> => Count + 1})),
            space_cowboy_h3_test_client:header(<<"content-type">>, Headers) =:= <<"text/event-stream">>
                andalso Body =:= <<"event: datastar-patch-signals\n"
                                    "data: signals ", ExpectedJson/binary, "\n\n">>
        end).

prop_h3_search_escapes_and_patches(Port) ->
    ?FORALL(Query, search_query(),
        begin
            {200, Headers, Body} =
                space_cowboy_h3_test_client:get_with_signals(Port, <<"/search">>, #{<<"query">> => Query}),
            ExpectedBody = <<"event: datastar-patch-elements\n"
                             "data: selector #results\n"
                             "data: mode inner\n"
                             "data: elements ", (expected_search_element(Query))/binary, "\n\n">>,
            space_cowboy_h3_test_client:header(<<"content-type">>, Headers) =:= <<"text/event-stream">>
                andalso Body =:= ExpectedBody
        end).

prop_h3_template_patch_escapes_and_patches(Port) ->
    ?FORALL(Label, search_query(),
        begin
            {200, Headers, Body} =
                space_cowboy_h3_test_client:get_with_signals(
                    Port, <<"/template-patch">>, #{<<"label">> => Label}),
            ExpectedBody = <<"event: datastar-patch-elements\n"
                             "data: selector #template-widget\n"
                             "data: elements ", (expected_template_widget(Label))/binary, "\n\n">>,
            space_cowboy_h3_test_client:header(<<"content-type">>, Headers) =:= <<"text/event-stream">>
                andalso Body =:= ExpectedBody
        end).

prop_h3_body_signals_post_roundtrip(Port) ->
    ?FORALL(Value, search_query(),
        begin
            {200, Headers, Body} =
                space_cowboy_h3_test_client:post_with_signals(
                    Port, <<"/body-signals">>, #{<<"value">> => Value}),
            ExpectedJson = iolist_to_binary(json:encode(#{<<"body">> => Value})),
            space_cowboy_h3_test_client:header(<<"content-type">>, Headers) =:= <<"text/event-stream">>
                andalso Body =:= <<"event: datastar-patch-signals\n"
                                    "data: signals ", ExpectedJson/binary, "\n\n">>
        end).

listener_name() ->
    ?LET(N, pos_integer(), list_to_atom("space_cowboy_quic_prop_" ++ integer_to_list(N))).

port() ->
    range(1024, 65535).

path_segment() ->
    ?LET(Chars, non_empty(list(path_char())), list_to_binary(Chars)).

path_char() ->
    oneof(lists:seq($0, $9) ++ lists:seq($A, $Z) ++ lists:seq($a, $z) ++ "-_.~").

search_query() ->
    ?LET(Chars, list(search_char()), list_to_binary(Chars)).

search_char() ->
    oneof(lists:seq(32, 126)).

setup_h3_conformance(Certs) ->
    {ok, _} = application:ensure_all_started(space_cowboy),
    Name = conformance_listener_name(),
    Port = available_udp_port(),
    {ok, Listener} = start_quic_listener(Name, Certs, space_cowboy_conformance_app:routes(), Port),
    {Name, Listener, Port}.

cleanup_h3_conformance({_Name, Listener, _Port}) ->
    ?assertEqual(ok, space_cowboy:stop_quic(Listener)).

start_quic_listener(Name, {ok, CertFile, KeyFile}, Routes, Port) ->
    Options = #{
        start_timeout => ?H3_TIMEOUT,
        protocol_options => #{logger => space_cowboy_quic_test_logger},
        transport_options => #{
            socket_opts => [
                {port, Port},
                {certfile, CertFile},
                {keyfile, KeyFile},
                {verify, none}
            ]
        }
    },
    space_cowboy:start_quic(Name, Routes, Options).

with_quic_listener(Name, {ok, CertFile, KeyFile}, Routes, Fun) ->
    Port = available_udp_port(),
    {ok, Listener} = start_quic_listener(Name, {ok, CertFile, KeyFile}, Routes, Port),
    try
        Fun(Port)
    after
        ?assertEqual(ok, space_cowboy:stop_quic(Listener))
    end.

h3_counter_patches_signals(Port) ->
    {200, Headers, Body} =
        space_cowboy_h3_test_client:get_with_signals(Port, <<"/counter">>, #{<<"count">> => 41}),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"count\":42}\n\n">>,
        Body
    ).

h3_search_patches_elements(Port) ->
    {200, Headers, Body} =
        space_cowboy_h3_test_client:get_with_signals(Port, <<"/search">>, #{<<"query">> => <<"Mars">>}),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #results\n"
          "data: mode inner\n"
          "data: elements <li id=\"result-primary\">Mars Station</li>\n\n">>,
        Body
    ).

h3_progress_stream_sends_ordered_events(Port) ->
    {200, Headers, Body} = space_cowboy_h3_test_client:get_ok(Port, <<"/progress">>),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
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

h3_script_endpoint_executes_script_patch(Port) ->
    {200, Headers, Body} = space_cowboy_h3_test_client:get_ok(Port, <<"/script">>),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector body\n"
          "data: mode append\n"
          "data: elements <script data-effect=\"el.remove()\">window.spaceCowboyReady = true;</script>\n\n">>,
        Body
    ).

h3_template_patch_roundtrip(Port) ->
    {200, Headers, Body} =
        space_cowboy_h3_test_client:get_with_signals(
            Port, <<"/template-patch">>, #{<<"label">> => <<"Launch">>}),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #template-widget\n"
          "data: elements <button id=\"template-widget\" data-on:click__prevent=\"@post(&#39;/template-patch&#39;)\" data-bind:label data-text=\"$label\" aria-label=\"Launch\">Launch</button>\n\n">>,
        Body
    ).

h3_body_signals_post_roundtrip(Port) ->
    {200, Headers, Body} =
        space_cowboy_h3_test_client:post_with_signals(
            Port, <<"/body-signals">>, #{<<"value">> => <<"Launch">>}),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"body\":\"Launch\"}\n\n">>,
        Body
    ).

h3_heartbeat_stream_roundtrip(Port) ->
    {200, Headers, Body} = space_cowboy_h3_test_client:get_ok(Port, <<"/heartbeat">>),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<": stream-open\n\n"
          ": heartbeat\n\n"
          "event: datastar-patch-signals\n"
          "data: signals {\"alive\":true}\n\n"
          ": stream-close\n\n">>,
        Body
    ).

h3_malformed_query_returns_sse_error(Port) ->
    {200, Headers, Body} = space_cowboy_h3_test_client:get_ok(Port, <<"/malformed?datastar=%GG">>),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"error\":\"invalid_query\"}\n\n">>,
        Body
    ).

h3_counter_property(Port) ->
    ?assert(proper:quickcheck(prop_h3_counter_roundtrip(Port), h3_proper_opts())).

h3_search_property(Port) ->
    ?assert(proper:quickcheck(prop_h3_search_escapes_and_patches(Port), h3_proper_opts())).

h3_template_patch_property(Port) ->
    ?assert(proper:quickcheck(prop_h3_template_patch_escapes_and_patches(Port), h3_proper_opts())).

h3_body_signals_post_property(Port) ->
    ?assert(proper:quickcheck(prop_h3_body_signals_post_roundtrip(Port), h3_proper_opts())).

expected_search_element(<<>>) ->
    <<"<li data-empty>No query</li>">>;
expected_search_element(Query) ->
    Escaped = space_cowboy_html:escape(Query),
    <<"<li id=\"result-primary\">", Escaped/binary, " Station</li>">>.

expected_template_widget(Label) ->
    Escaped = space_cowboy_html:escape(Label),
    <<"<button id=\"template-widget\" data-on:click__prevent=\"@post(&#39;/template-patch&#39;)\" data-bind:label data-text=\"$label\" aria-label=\"",
      Escaped/binary, "\">", Escaped/binary, "</button>">>.

available_udp_port() ->
    {ok, Socket} = gen_udp:open(0, [{active, false}]),
    {ok, Port} = inet:port(Socket),
    ok = gen_udp:close(Socket),
    Port.

quicer_fixture_certs() ->
    quicer_fixture_certs([
        "_build/quic+test/lib/quicer/msquic/submodules/quictls/test/certs",
        "_build/quic/lib/quicer/msquic/submodules/quictls/test/certs"
    ]).

quicer_fixture_certs([]) ->
    missing;
quicer_fixture_certs([Dir | Rest]) ->
    CertFile = filename:join(Dir, "servercert.pem"),
    KeyFile = filename:join(Dir, "serverkey.pem"),
    case filelib:is_regular(CertFile) andalso filelib:is_regular(KeyFile) of
        true -> {ok, CertFile, KeyFile};
        false -> quicer_fixture_certs(Rest)
    end.

conformance_listener_name() ->
    list_to_atom("space_cowboy_quic_conformance_" ++ integer_to_list(erlang:unique_integer([positive]))).
