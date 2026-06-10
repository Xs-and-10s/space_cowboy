-module(data_starship_prop_tests).

-include_lib("eunit/include/eunit.hrl").
-undef(LET).
-include_lib("proper/include/proper.hrl").

-define(NUMTESTS, 100).

event_framing_property_test() ->
    ?assert(proper:quickcheck(prop_event_framing(), proper_opts())).

patch_elements_multiline_property_test() ->
    ?assert(proper:quickcheck(prop_patch_elements_multiline(), proper_opts())).

patch_elements_option_elision_property_test() ->
    ?assert(proper:quickcheck(prop_patch_elements_option_elision(), proper_opts())).

patch_signals_map_roundtrip_property_test() ->
    ?assert(proper:quickcheck(prop_patch_signals_map_roundtrip(), proper_opts())).

read_get_signals_property_test() ->
    ?assert(proper:quickcheck(prop_read_get_signals(), proper_opts())).

read_body_signals_property_test() ->
    ?assert(proper:quickcheck(prop_read_body_signals(), proper_opts())).

execute_script_escapes_closing_script_property_test() ->
    ?assert(proper:quickcheck(prop_execute_script_escapes_closing_script(), proper_opts())).

proper_opts() ->
    [{numtests, ?NUMTESTS}, {to_file, user}].

prop_event_framing() ->
    ?FORALL(Generated, {event_type(), list(sse_line()), event_options()},
        begin
            {EventType, Lines, Options} = Generated,
            Event = iolist_to_binary(data_starship:event(EventType, Lines, Options)),
            BinaryEventType = event_type_to_binary(EventType),
            ExpectedLines = [
                <<"event: ", BinaryEventType/binary>>,
                optional_prefixed_line(<<"id: ">>, maps:get(event_id, Options, undefined)),
                optional_retry_line(maps:get(retry_duration, Options, 1000))
                | [<<"data: ", Line/binary>> || Line <- Lines]
            ],
            Expected = join_event_lines(flatten_optional(ExpectedLines)),
            Event =:= Expected
                andalso binary:last(Event) =:= $\n
                andalso binary:match(Event, <<"\n\n">>) =/= nomatch
        end).

prop_patch_elements_multiline() ->
    ?FORALL(Lines, non_empty(list(sse_line())),
        begin
            Elements = join_with_newlines(Lines),
            Event = iolist_to_binary(data_starship:patch_elements(Elements)),
            ExpectedDataLines = [<<"data: elements ", Line/binary>> || Line <- Lines],
            Expected = join_event_lines([<<"event: datastar-patch-elements">> | ExpectedDataLines]),
            Event =:= Expected
        end).

prop_patch_elements_option_elision() ->
    ?FORALL(Generated,
        {sse_line(), maybe_gen(sse_line()), patch_mode(), namespace(), boolean(), maybe_gen(sse_line())},
        begin
            {Elements, Selector, Mode, Namespace, UseViewTransition, ViewTransitionSelector} = Generated,
            Options = compact_options(#{
                selector => Selector,
                mode => Mode,
                namespace => Namespace,
                use_view_transition => UseViewTransition,
                view_transition_selector => ViewTransitionSelector
            }),
            Event = iolist_to_binary(data_starship:patch_elements(Elements, Options)),
            has_line(Event, <<"data: elements ", Elements/binary>>)
                andalso (Selector =:= undefined orelse has_line(Event, <<"data: selector ", Selector/binary>>))
                andalso (Mode =:= outer orelse has_line(Event, <<"data: mode ", (atom_to_binary(Mode))/binary>>))
                andalso (Namespace =:= html orelse has_line(Event, <<"data: namespace ", (atom_to_binary(Namespace))/binary>>))
                andalso (UseViewTransition =:= false orelse has_line(Event, <<"data: useViewTransition true">>))
                andalso (ViewTransitionSelector =:= undefined orelse has_line(Event, <<"data: viewTransitionSelector ", ViewTransitionSelector/binary>>))
                andalso not has_line(Event, <<"data: mode outer">>)
                andalso not has_line(Event, <<"data: namespace html">>)
                andalso not has_line(Event, <<"data: useViewTransition false">>)
        end).

prop_patch_signals_map_roundtrip() ->
    ?FORALL(Signals, signal_map(),
        begin
            Event = iolist_to_binary(data_starship:patch_signals(Signals)),
            case extract_single_data_value(<<"signals">>, Event) of
                {ok, Json} -> json:decode(Json) =:= Signals;
                error -> false
            end
        end).

prop_read_get_signals() ->
    ?FORALL(Signals, signal_map(),
        begin
            Json = iolist_to_binary(json:encode(Signals)),
            Query = <<"x=1&datastar=", (percent_encode(Json))/binary, "&y=2">>,
            data_starship:read_signals(get, Query, <<>>) =:= {ok, Signals}
        end).

prop_read_body_signals() ->
    ?FORALL(Generated, {non_get_method(), signal_map()},
        begin
            {Method, Signals} = Generated,
            Json = iolist_to_binary(json:encode(Signals)),
            data_starship:read_signals(Method, <<>>, Json) =:= {ok, Signals}
        end).

prop_execute_script_escapes_closing_script() ->
    ?FORALL(Generated, {sse_line(), sse_line()},
        begin
            {Prefix, Suffix} = Generated,
            Script = <<Prefix/binary, "</script>", Suffix/binary>>,
            Event = iolist_to_binary(data_starship:execute_script(Script)),
            length(binary:matches(Event, <<"</script>">>)) =:= 1
                andalso binary:match(Event, <<"<\\/script>">>) =/= nomatch
                andalso has_line(Event, <<"data: selector body">>)
                andalso has_line(Event, <<"data: mode append">>)
        end).

event_type() ->
    oneof([datastar_patch_elements, datastar_patch_signals, custom_event_name()]).

custom_event_name() ->
    ?LET(Name, non_empty(list(elements("abcdefghijklmnopqrstuvwxyz-"))), list_to_binary(Name)).

event_options() ->
    ?LET(Generated, {maybe_gen(sse_line()), retry_duration()},
        begin
            {EventId, RetryDuration} = Generated,
            compact_options(#{
                event_id => EventId,
                retry_duration => RetryDuration
            })
        end).

retry_duration() ->
    oneof([1000, pos_integer()]).

patch_mode() ->
    elements([outer, inner, replace, prepend, append, before, 'after', remove]).

namespace() ->
    elements([html, svg, mathml]).

non_get_method() ->
    oneof([post, put, patch, delete, <<"POST">>, <<"PUT">>, <<"PATCH">>, <<"DELETE">>]).

signal_map() ->
    ?LET(Pairs, list({signal_key(), signal_value()}), maps:from_list(Pairs)).

signal_key() ->
    ?LET(Chars, non_empty(list(elements("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"))),
        list_to_binary(Chars)).

signal_value() ->
    oneof([integer(), boolean(), sse_line(), nested_signal_map()]).

nested_signal_map() ->
    ?LET(Pairs, list({signal_key(), oneof([integer(), boolean(), sse_line()])}),
        maps:from_list(Pairs)).

sse_line() ->
    ?LET(Chars, list(sse_char()), list_to_binary(Chars)).

sse_char() ->
    oneof(lists:seq(32, 126)).

maybe_gen(Generator) ->
    oneof([undefined, Generator]).

compact_options(Options) ->
    maps:filter(fun(_Key, Value) -> Value =/= undefined end, Options).

flatten_optional(Lines) ->
    [Line || Line <- Lines, Line =/= undefined].

optional_prefixed_line(_Prefix, undefined) ->
    undefined;
optional_prefixed_line(Prefix, Value) ->
    <<Prefix/binary, Value/binary>>.

optional_retry_line(1000) ->
    undefined;
optional_retry_line(Retry) ->
    <<"retry: ", (integer_to_binary(Retry))/binary>>.

event_type_to_binary(datastar_patch_elements) ->
    <<"datastar-patch-elements">>;
event_type_to_binary(datastar_patch_signals) ->
    <<"datastar-patch-signals">>;
event_type_to_binary(EventType) when is_binary(EventType) ->
    EventType.

join_event_lines(Lines) ->
    iolist_to_binary([[Line, <<"\n">>] || Line <- Lines] ++ [<<"\n">>]).

join_with_newlines([Line]) ->
    Line;
join_with_newlines([Line | Lines]) ->
    iolist_to_binary([Line, <<"\n">>, join_with_newlines(Lines)]).

has_line(Event, Line) ->
    Pattern = <<"\n", Line/binary, "\n">>,
    EventWithSentinels = <<"\n", Event/binary>>,
    binary:match(EventWithSentinels, Pattern) =/= nomatch.

extract_single_data_value(Key, Event) ->
    Prefix = <<"data: ", Key/binary, " ">>,
    Lines = binary:split(Event, <<"\n">>, [global]),
    Matches = [
        binary:part(Line, byte_size(Prefix), byte_size(Line) - byte_size(Prefix))
        || Line <- Lines,
           byte_size(Line) >= byte_size(Prefix),
           binary:part(Line, 0, byte_size(Prefix)) =:= Prefix
    ],
    case Matches of
        [Value] -> {ok, Value};
        _ -> error
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
