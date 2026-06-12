-module(space_cowboy_beam_language_smoke_tests).

-include_lib("eunit/include/eunit.hrl").

elixir_smoke_test() ->
    case executable("elixir") of
        false ->
            ok;
        Elixir ->
            Expected =
                <<"event: datastar-patch-signals\n"
                  "data: signals {\"message\":\"Hello from Elixir\"}\n\n\n">>,
            ?assertEqual(Expected, event_output(run(Elixir, [
                "-pa",
                datastar_beam_ebin(),
                "examples/elixir_smoke.exs"
            ], ".")))
    end.

gleam_smoke_test() ->
    case executable("gleam") of
        false ->
            ok;
        Gleam ->
            Expected =
                <<"event: datastar-patch-signals\n"
                  "data: signals {\"message\":\"Hello from Gleam\"}\n\n\n">>,
            ?assertEqual(Expected, event_output(run(Gleam, ["run"], "examples/gleam_smoke", [
                {"ERL_FLAGS", "-pa " ++ datastar_beam_ebin()}
            ])))
    end.

executable(Name) ->
    case os:find_executable(Name) of
        false -> false;
        Path -> Path
    end.

datastar_beam_ebin() ->
    filename:dirname(code:which(datastar_beam)).

run(Command, Args, Cwd) ->
    run(Command, Args, Cwd, []).

run(Command, Args, Cwd, Env) ->
    Port = open_port({spawn_executable, Command}, [
        binary,
        exit_status,
        stderr_to_stdout,
        {args, Args},
        {cd, Cwd},
        {env, Env}
    ]),
    collect(Port, []).

collect(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            collect(Port, [Data | Acc]);
        {Port, {exit_status, 0}} ->
            iolist_to_binary(lists:reverse(Acc));
        {Port, {exit_status, Status}} ->
            Output = iolist_to_binary(lists:reverse(Acc)),
            error({command_failed, Status, Output})
    end.

event_output(Output) ->
    case binary:match(Output, <<"event: ">>) of
        {Start, _Length} ->
            binary:part(Output, Start, byte_size(Output) - Start);
        nomatch ->
            Output
    end.
