-module(space_cowboy_h3_test_client_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 50).

percent_encode_golden_test() ->
    ?assertEqual(<<"abcXYZ012-_.~">>, space_cowboy_h3_test_client:percent_encode(<<"abcXYZ012-_.~">>)),
    ?assertEqual(<<"a%20b%26%3F%25">>, space_cowboy_h3_test_client:percent_encode(<<"a b&?%">>)).

header_lookup_golden_test() ->
    Headers = [{<<"Content-Type">>, <<"text/event-stream">>}, {<<"x-test">>, <<"ok">>}],
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"content-type">>, Headers)),
    ?assertEqual(<<"text/event-stream">>, space_cowboy_h3_test_client:header(<<"CONTENT-TYPE">>, Headers)),
    ?assertEqual(undefined, space_cowboy_h3_test_client:header(<<"missing">>, Headers)).

percent_encode_roundtrip_property_test() ->
    ?assert(proper:quickcheck(prop_percent_encode_roundtrip(), proper_opts())).

header_lookup_case_insensitive_property_test() ->
    ?assert(proper:quickcheck(prop_header_lookup_case_insensitive(), proper_opts())).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

prop_percent_encode_roundtrip() ->
    ?FORALL(Bin, binary(),
        percent_decode(space_cowboy_h3_test_client:percent_encode(Bin)) =:= Bin).

prop_header_lookup_case_insensitive() ->
    ?FORALL({Name, Value}, {header_name(), binary()},
        begin
            HeaderName = list_to_binary(Name),
            MixedHeaderName = list_to_binary(mixed_case(Name)),
            UpperHeaderName = list_to_binary(string:uppercase(Name)),
            Headers = [{MixedHeaderName, Value}, {<<"x-other">>, <<"other">>}],
            space_cowboy_h3_test_client:header(HeaderName, Headers) =:= Value
                andalso space_cowboy_h3_test_client:header(UpperHeaderName, Headers) =:= Value
        end).

header_name() ->
    ?LET(Parts, non_empty(list(header_char())), Parts).

header_char() ->
    oneof(lists:seq($a, $z) ++ lists:seq($0, $9) ++ "-").

mixed_case(Name) ->
    [mixed_case_char(Char) || Char <- Name].

mixed_case_char(Char) when Char >= $a, Char =< $z, Char rem 2 =:= 0 ->
    Char - 32;
mixed_case_char(Char) ->
    Char.

percent_decode(Bin) ->
    percent_decode(Bin, []).

percent_decode(<<>>, Acc) ->
    iolist_to_binary(lists:reverse(Acc));
percent_decode(<<"%", Hi, Lo, Rest/binary>>, Acc) ->
    percent_decode(Rest, [(hex_value(Hi) bsl 4) bor hex_value(Lo) | Acc]);
percent_decode(<<Byte, Rest/binary>>, Acc) ->
    percent_decode(Rest, [Byte | Acc]).

hex_value(Byte) when Byte >= $0, Byte =< $9 ->
    Byte - $0;
hex_value(Byte) when Byte >= $A, Byte =< $F ->
    10 + Byte - $A.
