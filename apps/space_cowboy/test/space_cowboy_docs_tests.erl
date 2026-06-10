-module(space_cowboy_docs_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 25).
-define(BEAM_USAGE_DOC, "docs/beam-usage.md").

beam_usage_links_from_readme_test() ->
    {ok, Readme} = file:read_file("README.md"),
    ?assertMatch({_, _}, binary:match(Readme, <<"(docs/beam-usage.md)">>)).

beam_usage_elixir_snippet_matches_example_golden_test() ->
    ?assertEqual(
        read_file_trimmed("examples/elixir_smoke.exs"),
        doc_snippet(<<"elixir-smoke">>)
    ).

beam_usage_gleam_snippet_matches_example_golden_test() ->
    ?assertEqual(
        read_file_trimmed("examples/gleam_smoke/src/space_cowboy_gleam_smoke.gleam"),
        doc_snippet(<<"gleam-smoke">>)
    ).

beam_usage_snippets_property_test() ->
    ?assert(proper:quickcheck(prop_beam_usage_snippets_match_sources(), proper_opts())).

prop_beam_usage_snippets_match_sources() ->
    ?FORALL(Snippet, snippet_source(),
        begin
            {Name, Path} = Snippet,
            doc_snippet(Name) =:= read_file_trimmed(Path)
        end).

snippet_source() ->
    elements([
        {<<"elixir-smoke">>, "examples/elixir_smoke.exs"},
        {<<"gleam-smoke">>, "examples/gleam_smoke/src/space_cowboy_gleam_smoke.gleam"}
    ]).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

doc_snippet(Name) ->
    {ok, Doc} = file:read_file(?BEAM_USAGE_DOC),
    StartMarker = <<"<!-- BEGIN: ", Name/binary, " -->">>,
    EndMarker = <<"<!-- END: ", Name/binary, " -->">>,
    {Start, StartLength} = binary:match(Doc, StartMarker),
    AfterStart = binary:part(Doc, Start + StartLength, byte_size(Doc) - Start - StartLength),
    {End, _EndLength} = binary:match(AfterStart, EndMarker),
    Block = binary:part(AfterStart, 0, End),
    trim(fenced_body(Block)).

fenced_body(Block0) ->
    Block = trim(Block0),
    [Fence | Rest] = binary:split(Block, <<"\n">>, []),
    true = binary:part(Fence, 0, 3) =:= <<"```">>,
    BodyWithFence = iolist_to_binary(join_lines(Rest)),
    {End, _} = binary:match(BodyWithFence, <<"\n```">>),
    binary:part(BodyWithFence, 0, End).

join_lines([]) ->
    [];
join_lines([Line]) ->
    Line;
join_lines([Line | Lines]) ->
    [Line, <<"\n">>, join_lines(Lines)].

read_file_trimmed(Path) ->
    {ok, Bytes} = file:read_file(Path),
    trim(Bytes).

trim(Binary) ->
    trim_left(trim_right(Binary)).

trim_left(<<"\n", Rest/binary>>) ->
    trim_left(Rest);
trim_left(<<"\r", Rest/binary>>) ->
    trim_left(Rest);
trim_left(<<" ", Rest/binary>>) ->
    trim_left(Rest);
trim_left(<<"\t", Rest/binary>>) ->
    trim_left(Rest);
trim_left(Binary) ->
    Binary.

trim_right(Binary) ->
    Size = byte_size(Binary),
    case Size of
        0 ->
            Binary;
        _ ->
            Last = binary:at(Binary, Size - 1),
            case Last of
                $\n -> trim_right(binary:part(Binary, 0, Size - 1));
                $\r -> trim_right(binary:part(Binary, 0, Size - 1));
                $\s -> trim_right(binary:part(Binary, 0, Size - 1));
                $\t -> trim_right(binary:part(Binary, 0, Size - 1));
                _ -> Binary
            end
    end.
