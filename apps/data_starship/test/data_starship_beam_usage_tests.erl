-module(data_starship_beam_usage_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 25).

erlang_usage_golden_test() ->
    ?assertEqual(expected_erlang_usage(), erlang_usage()).

erlang_usage_property_test() ->
    ?assert(proper:quickcheck(prop_erlang_usage_roundtrip(), proper_opts())).

elixir_usage_golden_test() ->
    case executable("elixir") of
        false ->
            ok;
        Elixir ->
            Output = run(Elixir, ["-pa", data_starship_ebin(), "examples/elixir_usage.exs"], "."),
            ?assertEqual(expected_elixir_usage(), Output)
    end.

elixir_usage_sections_property_test() ->
    case executable("elixir") of
        false ->
            ok;
        Elixir ->
            Output = run(Elixir, ["-pa", data_starship_ebin(), "examples/elixir_usage.exs"], "."),
            ?assert(proper:quickcheck(prop_usage_sections(Output, elixir_sections()), proper_opts()))
    end.

gleam_usage_golden_test() ->
    case executable("gleam") of
        false ->
            ok;
        Gleam ->
            Output = usage_output(run(Gleam, ["run", "-m", "data_starship_usage"], "examples/gleam_smoke", [
                {"ERL_FLAGS", "-pa " ++ data_starship_ebin()}
            ])),
            ?assertEqual(expected_gleam_usage(), Output)
    end.

gleam_usage_sections_property_test() ->
    case executable("gleam") of
        false ->
            ok;
        Gleam ->
            Output = usage_output(run(Gleam, ["run", "-m", "data_starship_usage"], "examples/gleam_smoke", [
                {"ERL_FLAGS", "-pa " ++ data_starship_ebin()}
            ])),
            ?assert(proper:quickcheck(prop_usage_sections(Output, gleam_sections()), proper_opts()))
    end.

prop_erlang_usage_roundtrip() ->
    ?FORALL(Value, usage_value(),
        begin
            Signals = #{<<"value">> => Value},
            Json = iolist_to_binary(json:encode(Signals)),
            Query = <<"datastar=", (percent_encode(Json))/binary>>,
            Event = iolist_to_binary(data_starship:patch_signals(Signals)),
            ExpectedEvent = <<"event: datastar-patch-signals\n"
                              "data: signals ", Json/binary, "\n\n">>,
            data_starship:read_signals(get, Query, <<>>) =:= {ok, Signals}
                andalso Event =:= ExpectedEvent
        end).

prop_usage_sections(Output, Sections) ->
    ?FORALL(Section, elements(Sections),
        begin
            {Name, ExpectedBody} = Section,
            section(Output, Name) =:= ExpectedBody
        end).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

erlang_usage() ->
    [
        {"patch-elements", iolist_to_binary(data_starship:patch_elements(
            <<"<section id=\"panel\">Hello from Erlang</section>">>,
            #{selector => <<"#panel">>, mode => inner}
        ))},
        {"patch-signals", iolist_to_binary(data_starship:patch_signals(
            <<"{\"message\":\"Hello from Erlang\",\"count\":3}">>
        ))},
        {"execute-script", iolist_to_binary(data_starship:execute_script(
            <<"window.erlangReady = true;</script>">>
        ))},
        {"read-signals", begin
            {ok, Signals} = data_starship:read_signals(
                <<"GET">>,
                <<"datastar=%7B%22count%22%3A3%2C%22message%22%3A%22Launch%22%7D">>,
                <<>>
            ),
            Signals
        end}
    ].

expected_erlang_usage() ->
    [
        {"patch-elements",
            <<"event: datastar-patch-elements\n"
              "data: selector #panel\n"
              "data: mode inner\n"
              "data: elements <section id=\"panel\">Hello from Erlang</section>\n\n">>},
        {"patch-signals",
            <<"event: datastar-patch-signals\n"
              "data: signals {\"message\":\"Hello from Erlang\",\"count\":3}\n\n">>},
        {"execute-script",
            <<"event: datastar-patch-elements\n"
              "data: selector body\n"
              "data: mode append\n"
              "data: elements <script data-effect=\"el.remove()\">window.erlangReady = true;<\\/script></script>\n\n">>},
        {"read-signals", #{<<"count">> => 3, <<"message">> => <<"Launch">>}}
    ].

expected_elixir_usage() ->
    <<"-- patch-elements --\n"
      "event: datastar-patch-elements\n"
      "id: elixir-elements\n"
      "retry: 2000\n"
      "data: selector #panel\n"
      "data: mode inner\n"
      "data: elements <section id=\"panel\">Ready</section>\n\n\n"
      "-- patch-signals --\n"
      "event: datastar-patch-signals\n"
      "data: onlyIfMissing true\n"
      "data: signals {\"count\":42,\"message\":\"Hello from Elixir\"}\n\n\n"
      "-- execute-script --\n"
      "event: datastar-patch-elements\n"
      "data: selector body\n"
      "data: mode append\n"
      "data: elements <script type=\"module\">window.ready = true;<\\/script></script>\n\n\n"
      "-- read-signals --\n"
      "count=41; message=Launch\n"
      "-- property-checks --\n"
      "ok\n">>.

expected_gleam_usage() ->
    <<"-- patch-elements --\n"
      "event: datastar-patch-elements\n"
      "data: elements <section id=\"panel\">Hello from Gleam</section>\n\n\n"
      "-- patch-signals --\n"
      "event: datastar-patch-signals\n"
      "data: signals {\"message\":\"Hello from Gleam\",\"count\":7}\n\n\n"
      "-- execute-script --\n"
      "event: datastar-patch-elements\n"
      "data: selector body\n"
      "data: mode append\n"
      "data: elements <script data-effect=\"el.remove()\">window.gleamReady = true;<\\/script></script>\n\n\n"
      "-- property-checks --\n"
      "ok\n">>.

elixir_sections() ->
    [
        {<<"patch-elements">>, section(expected_elixir_usage(), <<"patch-elements">>)},
        {<<"patch-signals">>, section(expected_elixir_usage(), <<"patch-signals">>)},
        {<<"execute-script">>, section(expected_elixir_usage(), <<"execute-script">>)},
        {<<"read-signals">>, <<"count=41; message=Launch\n">>},
        {<<"property-checks">>, <<"ok\n">>}
    ].

gleam_sections() ->
    [
        {<<"patch-elements">>, section(expected_gleam_usage(), <<"patch-elements">>)},
        {<<"patch-signals">>, section(expected_gleam_usage(), <<"patch-signals">>)},
        {<<"execute-script">>, section(expected_gleam_usage(), <<"execute-script">>)},
        {<<"property-checks">>, <<"ok\n">>}
    ].

section(Output, Name) when is_list(Name) ->
    section(Output, list_to_binary(Name));
section(Output, Name) ->
    Marker = <<"-- ", Name/binary, " --\n">>,
    {Start, Length} = binary:match(Output, Marker),
    AfterStart = binary:part(Output, Start + Length, byte_size(Output) - Start - Length),
    case binary:match(AfterStart, <<"\n-- ">>) of
        {End, _} -> binary:part(AfterStart, 0, End + 1);
        nomatch -> AfterStart
    end.

usage_value() ->
    ?LET(Chars, list(usage_char()), list_to_binary(Chars)).

usage_char() ->
    oneof(lists:seq(32, 126)).

executable(Name) ->
    case os:find_executable(Name) of
        false -> false;
        Path -> Path
    end.

data_starship_ebin() ->
    filename:dirname(code:which(data_starship)).

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
    gather_port(Port, []).

gather_port(Port, Acc) ->
    receive
        {Port, {data, Data}} ->
            gather_port(Port, [Data | Acc]);
        {Port, {exit_status, 0}} ->
            iolist_to_binary(lists:reverse(Acc));
        {Port, {exit_status, Status}} ->
            Output = iolist_to_binary(lists:reverse(Acc)),
            error({command_failed, Status, Output})
    end.

usage_output(Output) ->
    case binary:match(Output, <<"-- patch-elements --">>) of
        {Start, _Length} ->
            binary:part(Output, Start, byte_size(Output) - Start);
        nomatch ->
            Output
    end.

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
