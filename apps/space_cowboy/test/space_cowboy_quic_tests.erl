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
                    ?assertMatch({ok, {200, _Headers, <<"ok">>}}, h3_get(Port, <<"/">>))
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
                        ?_test(h3_heartbeat_stream_roundtrip(Port)),
                        ?_test(h3_malformed_query_returns_sse_error(Port)),
                        ?_test(h3_counter_property(Port)),
                        ?_test(h3_search_property(Port)),
                        ?_test(h3_template_patch_property(Port))
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
            case h3_get(Port, Path) of
                {ok, {200, _Headers, Value}} -> true;
                _ -> false
            end
        end).

prop_h3_counter_roundtrip(Port) ->
    ?FORALL(Count, range(0, 100000),
        begin
            {200, Headers, Body} = h3_get_with_signals(Port, <<"/counter">>, #{<<"count">> => Count}),
            ExpectedJson = iolist_to_binary(json:encode(#{<<"count">> => Count + 1})),
            header(<<"content-type">>, Headers) =:= <<"text/event-stream">>
                andalso Body =:= <<"event: datastar-patch-signals\n"
                                    "data: signals ", ExpectedJson/binary, "\n\n">>
        end).

prop_h3_search_escapes_and_patches(Port) ->
    ?FORALL(Query, search_query(),
        begin
            {200, Headers, Body} = h3_get_with_signals(Port, <<"/search">>, #{<<"query">> => Query}),
            ExpectedBody = <<"event: datastar-patch-elements\n"
                             "data: selector #results\n"
                             "data: mode inner\n"
                             "data: elements ", (expected_search_element(Query))/binary, "\n\n">>,
            header(<<"content-type">>, Headers) =:= <<"text/event-stream">>
                andalso Body =:= ExpectedBody
        end).

prop_h3_template_patch_escapes_and_patches(Port) ->
    ?FORALL(Label, search_query(),
        begin
            {200, Headers, Body} =
                h3_get_with_signals(Port, <<"/template-patch">>, #{<<"label">> => Label}),
            ExpectedBody = <<"event: datastar-patch-elements\n"
                             "data: selector #template-widget\n"
                             "data: elements ", (expected_template_widget(Label))/binary, "\n\n">>,
            header(<<"content-type">>, Headers) =:= <<"text/event-stream">>
                andalso Body =:= ExpectedBody
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
    {200, Headers, Body} = h3_get_with_signals(Port, <<"/counter">>, #{<<"count">> => 41}),
    ?assertEqual(<<"text/event-stream">>, header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-signals\n"
          "data: signals {\"count\":42}\n\n">>,
        Body
    ).

h3_search_patches_elements(Port) ->
    {200, Headers, Body} = h3_get_with_signals(Port, <<"/search">>, #{<<"query">> => <<"Mars">>}),
    ?assertEqual(<<"text/event-stream">>, header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #results\n"
          "data: mode inner\n"
          "data: elements <li id=\"result-primary\">Mars Station</li>\n\n">>,
        Body
    ).

h3_progress_stream_sends_ordered_events(Port) ->
    {200, Headers, Body} = h3_get_ok(Port, <<"/progress">>),
    ?assertEqual(<<"text/event-stream">>, header(<<"content-type">>, Headers)),
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
    {200, Headers, Body} = h3_get_ok(Port, <<"/script">>),
    ?assertEqual(<<"text/event-stream">>, header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector body\n"
          "data: mode append\n"
          "data: elements <script data-effect=\"el.remove()\">window.spaceCowboyReady = true;</script>\n\n">>,
        Body
    ).

h3_template_patch_roundtrip(Port) ->
    {200, Headers, Body} =
        h3_get_with_signals(Port, <<"/template-patch">>, #{<<"label">> => <<"Launch">>}),
    ?assertEqual(<<"text/event-stream">>, header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<"event: datastar-patch-elements\n"
          "data: selector #template-widget\n"
          "data: elements <button id=\"template-widget\" data-on:click__prevent=\"@post(&#39;/template-patch&#39;)\" data-bind:label data-text=\"$label\" aria-label=\"Launch\">Launch</button>\n\n">>,
        Body
    ).

h3_heartbeat_stream_roundtrip(Port) ->
    {200, Headers, Body} = h3_get_ok(Port, <<"/heartbeat">>),
    ?assertEqual(<<"text/event-stream">>, header(<<"content-type">>, Headers)),
    ?assertEqual(
        <<": stream-open\n\n"
          ": heartbeat\n\n"
          "event: datastar-patch-signals\n"
          "data: signals {\"alive\":true}\n\n"
          ": stream-close\n\n">>,
        Body
    ).

h3_malformed_query_returns_sse_error(Port) ->
    {200, Headers, Body} = h3_get_ok(Port, <<"/malformed?datastar=%GG">>),
    ?assertEqual(<<"text/event-stream">>, header(<<"content-type">>, Headers)),
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

h3_get_with_signals(Port, Path, Signals) ->
    Json = iolist_to_binary(json:encode(Signals)),
    h3_get_ok(Port, <<Path/binary, "?datastar=", (percent_encode(Json))/binary>>).

h3_get_ok(Port, Path) ->
    {ok, Result} = h3_get(Port, Path),
    Result.

h3_get(Port, Path) ->
    case quicer:connect("localhost", Port, h3_conn_opts(), ?H3_TIMEOUT) of
        {ok, Conn} ->
            try
                h3_request(Conn, Port, Path)
            after
                _ = quicer:close_connection(Conn)
            end;
        Error ->
            Error
    end.

h3_conn_opts() ->
    [
        {alpn, ["h3"]},
        {verify, none},
        {peer_unidi_stream_count, 3},
        {peer_bidi_stream_count, 100}
    ].

h3_request(Conn, Port, Path) ->
    {ok, HTTP3Machine0} = h3_client_preface(Conn),
    {ok, StreamRef} = quicer:start_stream(Conn, #{active => true}),
    {ok, StreamID} = quicer:get_stream_id(StreamRef),
    put({quicer_stream, StreamID}, StreamRef),
    HTTP3Machine1 = cow_http3_machine:init_bidi_stream(StreamID, <<"GET">>, HTTP3Machine0),
    PseudoHeaders = #{
        method => <<"GET">>,
        scheme => <<"https">>,
        authority => iolist_to_binary(["localhost:", integer_to_list(Port)]),
        path => Path
    },
    {ok, fin, HeaderBlock, Instructions, HTTP3Machine2} =
        cow_http3_machine:prepare_headers(StreamID, HTTP3Machine1, fin, PseudoHeaders, []),
    ok = h3_send_instructions(Conn, Instructions),
    ok = cowboy_quicer:send(Conn, StreamID, cow_http3:headers(HeaderBlock), fin),
    h3_recv(Conn, HTTP3Machine2, #{stream_id => StreamID, headers => [], body => <<>>, unidi => #{}}).

h3_client_preface(Conn) ->
    {ok, SettingsBin, HTTP3Machine0} = cow_http3_machine:init(client, #{}),
    {ok, ControlID} = cowboy_quicer:start_unidi_stream(Conn, [<<0>>, SettingsBin]),
    {ok, EncoderID} = cowboy_quicer:start_unidi_stream(Conn, <<2>>),
    {ok, DecoderID} = cowboy_quicer:start_unidi_stream(Conn, <<3>>),
    put(h3_encoder_id, EncoderID),
    put(h3_decoder_id, DecoderID),
    HTTP3Machine = cow_http3_machine:init_unidi_local_streams(ControlID, EncoderID, DecoderID, HTTP3Machine0),
    {ok, HTTP3Machine}.

h3_recv(Conn, HTTP3Machine, State = #{stream_id := StreamID}) ->
    receive
        Msg when is_tuple(Msg), tuple_size(Msg) >= 1, element(1, Msg) =:= quic ->
            case cowboy_quicer:handle(Msg) of
                {stream_started, NewStreamID, unidi} ->
                    HTTP3Machine1 = cow_http3_machine:init_unidi_stream(NewStreamID, unidi_remote, HTTP3Machine),
                    h3_recv(Conn, HTTP3Machine1, put_unidi(NewStreamID, undefined, State));
                {stream_started, NewStreamID, bidi} ->
                    HTTP3Machine1 = cow_http3_machine:init_bidi_stream(NewStreamID, HTTP3Machine),
                    h3_recv(Conn, HTTP3Machine1, State);
                {data, StreamID, fin, Data} ->
                    case h3_parse_data(Conn, StreamID, fin, Data, HTTP3Machine, State) of
                        {ok, _HTTP3Machine1, State1} ->
                            {ok, {maps:get(status, State1), maps:get(headers, State1), maps:get(body, State1)}};
                        {continue, HTTP3Machine1, State1} ->
                            h3_recv(Conn, HTTP3Machine1, State1)
                    end;
                {data, DataStreamID, IsFin, Data} ->
                    {HTTP3Machine1, State1} = h3_parse_data_continue(Conn, DataStreamID, IsFin, Data, HTTP3Machine, State),
                    h3_recv(Conn, HTTP3Machine1, State1);
                {stream_closed, StreamID, _ErrorCode} ->
                    {ok, {maps:get(status, State), maps:get(headers, State), maps:get(body, State)}};
                closed ->
                    {error, closed};
                _ ->
                    h3_recv(Conn, HTTP3Machine, State)
            end
    after ?H3_TIMEOUT ->
        {error, timeout}
    end.

h3_parse_data_continue(Conn, StreamID, IsFin, Data, HTTP3Machine, State) ->
    case h3_parse_data(Conn, StreamID, IsFin, Data, HTTP3Machine, State) of
        {ok, HTTP3Machine1, State1} -> {HTTP3Machine1, State1};
        {continue, HTTP3Machine1, State1} -> {HTTP3Machine1, State1}
    end.

h3_parse_data(Conn, StreamID, IsFin, Data, HTTP3Machine, State = #{stream_id := StreamID}) ->
    h3_parse_frames(Conn, StreamID, IsFin, Data, HTTP3Machine, State);
h3_parse_data(Conn, StreamID, IsFin, Data, HTTP3Machine, State) ->
    case unidi_type(StreamID, State) of
        undefined ->
            case cow_http3:parse_unidi_stream_header(Data) of
                {ok, Type, Rest} ->
                    {ok, HTTP3Machine1} = cow_http3_machine:set_unidi_remote_stream_type(StreamID, Type, HTTP3Machine),
                    h3_parse_unidi(Conn, StreamID, Type, IsFin, Rest, HTTP3Machine1, put_unidi(StreamID, Type, State));
                {undefined, _Rest} ->
                    {continue, HTTP3Machine, put_unidi(StreamID, ignored, State)};
                more ->
                    {continue, HTTP3Machine, State}
            end;
        ignored ->
            {continue, HTTP3Machine, State};
        Type ->
            h3_parse_unidi(Conn, StreamID, Type, IsFin, Data, HTTP3Machine, State)
    end.

h3_parse_unidi(_Conn, _StreamID, _Type, _IsFin, <<>>, HTTP3Machine, State) ->
    {continue, HTTP3Machine, State};
h3_parse_unidi(Conn, StreamID, control, IsFin, Data, HTTP3Machine, State) ->
    h3_parse_frames(Conn, StreamID, IsFin, Data, HTTP3Machine, State);
h3_parse_unidi(Conn, StreamID, Type, IsFin, Data, HTTP3Machine, State) when Type =:= encoder; Type =:= decoder ->
    case cow_http3_machine:unidi_data(Data, IsFin, StreamID, HTTP3Machine) of
        {ok, Instructions, HTTP3Machine1} ->
            ok = h3_send_instructions(Conn, Instructions),
            {continue, HTTP3Machine1, State};
        {error, Error, _HTTP3Machine1} ->
            {continue, HTTP3Machine, State#{error => Error}}
    end.

h3_parse_frames(_Conn, _StreamID, _IsFin, <<>>, HTTP3Machine, State) ->
    {continue, HTTP3Machine, State};
h3_parse_frames(Conn, StreamID, IsFin, Data, HTTP3Machine, State) ->
    case cow_http3:parse(Data) of
        {ok, Frame, Rest} ->
            FrameFin = case Rest of
                <<>> -> IsFin;
                _ -> nofin
            end,
            case cow_http3_machine:frame(Frame, FrameFin, StreamID, HTTP3Machine) of
                {ok, HTTP3Machine1} ->
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State);
                {ok, {data, Body}, HTTP3Machine1} ->
                    State1 = State#{body => <<(maps:get(body, State))/binary, Body/binary>>},
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State1);
                {ok, {headers, Headers, #{status := Status}, _Len}, Instructions, HTTP3Machine1} ->
                    ok = h3_send_instructions(Conn, Instructions),
                    State1 = State#{status => Status, headers => Headers},
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State1);
                {ok, {_Other, _Value}, HTTP3Machine1} ->
                    h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine1, State);
                {error, Error, HTTP3Machine1} ->
                    {continue, HTTP3Machine1, State#{error => Error}};
                {error, Error, Instructions, HTTP3Machine1} ->
                    ok = h3_send_instructions(Conn, Instructions),
                    {continue, HTTP3Machine1, State#{error => Error}}
            end;
        {ignore, Rest} ->
            h3_parse_frames(Conn, StreamID, IsFin, Rest, HTTP3Machine, State);
        {more, _More, _Needed} ->
            {continue, HTTP3Machine, State};
        more ->
            {continue, HTTP3Machine, State}
    end.

h3_send_instructions(_Conn, undefined) ->
    ok;
h3_send_instructions(Conn, {encoder_instructions, Data}) ->
    cowboy_quicer:send(Conn, get(h3_encoder_id), Data);
h3_send_instructions(Conn, {decoder_instructions, Data}) ->
    cowboy_quicer:send(Conn, get(h3_decoder_id), Data).

header(Name, Headers) ->
    LowerName = string:lowercase(binary_to_list(Name)),
    Normalized = [{string:lowercase(binary_to_list(Key)), Value} || {Key, Value} <- Headers],
    case lists:keyfind(LowerName, 1, Normalized) of
        {_, Value} -> Value;
        false -> undefined
    end.

expected_search_element(<<>>) ->
    <<"<li data-empty>No query</li>">>;
expected_search_element(Query) ->
    Escaped = space_cowboy_html:escape(Query),
    <<"<li id=\"result-primary\">", Escaped/binary, " Station</li>">>.

expected_template_widget(Label) ->
    Escaped = space_cowboy_html:escape(Label),
    <<"<button id=\"template-widget\" data-on:click__prevent=\"@post(&#39;/template-patch&#39;)\" data-bind:label data-text=\"$label\" aria-label=\"",
      Escaped/binary, "\">", Escaped/binary, "</button>">>.

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

unidi_type(StreamID, #{unidi := Unidi}) ->
    maps:get(StreamID, Unidi, undefined).

put_unidi(StreamID, Type, State = #{unidi := Unidi}) ->
    State#{unidi => Unidi#{StreamID => Type}}.

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
