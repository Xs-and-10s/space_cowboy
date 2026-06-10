-module(space_cowboy_sse_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 100).

comment_golden_test() ->
    ?assertEqual(<<": open\n\n">>, iolist_to_binary(space_cowboy_sse:comment(<<"open">>))),
    ?assertEqual(<<":\n\n">>, iolist_to_binary(space_cowboy_sse:comment(<<>>))),
    ?assertEqual(<<": one\n: two\n\n">>, iolist_to_binary(space_cowboy_sse:comment(<<"one\ntwo">>))).

heartbeat_golden_test() ->
    ?assertEqual(<<": heartbeat\n\n">>, iolist_to_binary(space_cowboy_sse:heartbeat())),
    ?assertEqual(<<": pulse\n\n">>, iolist_to_binary(space_cowboy_sse:heartbeat(<<"pulse">>))).

comment_property_test() ->
    ?assert(proper:quickcheck(prop_comment_prefixes_each_line(), proper_opts())).

heartbeat_property_test() ->
    ?assert(proper:quickcheck(prop_heartbeat_is_comment(), proper_opts())).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

prop_comment_prefixes_each_line() ->
    ?FORALL(Lines, non_empty(list(comment_line())),
        begin
            Text = join_with_newlines(Lines),
            Expected = iolist_to_binary([[expected_comment_line(Line)] || Line <- Lines] ++ [<<"\n">>]),
            iolist_to_binary(space_cowboy_sse:comment(Text)) =:= Expected
        end).

prop_heartbeat_is_comment() ->
    ?FORALL(Label, comment_text(),
        iolist_to_binary(space_cowboy_sse:heartbeat(Label))
            =:= iolist_to_binary(space_cowboy_sse:comment(Label))).

comment_text() ->
    ?LET(Lines, list(comment_line()), join_with_newlines(Lines)).

comment_line() ->
    ?LET(Chars, list(printable_char()), list_to_binary(Chars)).

printable_char() ->
    oneof(lists:seq(32, 126)).

join_with_newlines([]) ->
    <<>>;
join_with_newlines([Line]) ->
    Line;
join_with_newlines([Line | Lines]) ->
    iolist_to_binary([Line, <<"\n">>, join_with_newlines(Lines)]).

expected_comment_line(<<>>) ->
    <<":\n">>;
expected_comment_line(Line) ->
    <<": ", Line/binary, "\n">>.
