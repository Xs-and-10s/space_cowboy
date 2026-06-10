-module(space_cowboy_quic_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 50).

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

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

prop_start_quic_unavailable_is_stable() ->
    ?FORALL(Generated, {listener_name(), port()},
        begin
            {Name, Port} = Generated,
            Result = space_cowboy:start_quic(Name, [], #{port => Port}),
            Result =:= {error, quic_unavailable}
        end).

listener_name() ->
    ?LET(N, pos_integer(), list_to_atom("space_cowboy_quic_prop_" ++ integer_to_list(N))).

port() ->
    range(1024, 65535).

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
