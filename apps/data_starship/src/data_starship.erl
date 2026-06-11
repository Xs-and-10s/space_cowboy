%% @doc Portable Datastar SDK core.
%%
%% This module intentionally knows nothing about Cowboy, Plug, Mist, Elli,
%% or any other web server. It only knows how to produce Datastar-compliant
%% SSE event bytes and parse incoming Datastar signals.
-module(data_starship).

-compile({no_auto_import, [get/1, put/2]}).

-export([
    sse_headers/0,
    event/2,
    event/3,
    patch_elements/1,
    patch_elements/2,
    remove_elements/1,
    remove_elements/2,
    patch_signals/1,
    patch_signals/2,
    remove_signals/1,
    remove_signals/2,
    execute_script/1,
    execute_script/2,
    redirect/1,
    redirect/2,
    console_log/1,
    console_log/2,
    action/2,
    action/3,
    get/1,
    get/2,
    post/1,
    post/2,
    put/1,
    put/2,
    patch/1,
    patch/2,
    delete/1,
    delete/2,
    read_signals/3
]).

-type event_type() :: datastar_patch_elements | datastar_patch_signals | binary() | atom().
-type http_verb() :: get | post | put | patch | delete | binary() | atom().
-type option_key() ::
    event_id
    | retry
    | retry_duration
    | selector
    | mode
    | namespace
    | use_view_transition
    | use_view_transitions
    | view_transition_selector
    | only_if_missing
    | auto_remove
    | attributes
    | level
    | options.
-type options() :: #{option_key() => term()} | [{option_key(), term()}].
-type iodata_or_string() :: iodata() | unicode:chardata() | {safe, iodata()} | {ok, iodata()}.
-type read_method() :: get | post | put | patch | delete | binary() | atom().

-export_type([event_type/0, http_verb/0, options/0, read_method/0]).

-define(DEFAULT_RETRY_DURATION, 1000).

%% @doc Headers recommended for Datastar SSE responses.
-spec sse_headers() -> #{binary() => binary()}.
sse_headers() ->
    #{
        <<"cache-control">> => <<"no-cache">>,
        <<"content-type">> => <<"text/event-stream">>,
        <<"connection">> => <<"keep-alive">>
    }.

%% @doc Encode a generic SSE event.
-spec event(event_type(), [iodata_or_string()]) -> iodata().
event(EventType, DataLines) ->
    event(EventType, DataLines, #{}).

%% @doc Encode a generic SSE event with Datastar/WHATWG SSE options.
-spec event(event_type(), [iodata_or_string()], options()) -> iodata().
event(EventType, DataLines, Options) ->
    Retry = retry_duration(Options),
    [
        <<"event: ">>, event_type(EventType), <<"\n">>,
        maybe_line(<<"id: ">>, get_opt(event_id, Options, undefined)),
        maybe_retry(Retry),
        [[<<"data: ">>, to_binary(Line), <<"\n">>] || Line <- DataLines],
        <<"\n">>
    ].

%% @doc Encode a datastar-patch-elements event.
-spec patch_elements(iodata_or_string() | undefined) -> iodata().
patch_elements(Elements) ->
    patch_elements(Elements, #{}).

%% @doc Encode a datastar-patch-elements event.
%%
%% Supported options:
%% selector, mode, namespace, use_view_transition, view_transition_selector,
%% event_id and retry_duration.
-spec patch_elements(iodata_or_string() | undefined, options()) -> iodata().
patch_elements(Elements, Options) ->
    DataLines0 = [
        maybe_data_line(<<"selector">>, get_opt(selector, Options, undefined)),
        maybe_non_default_line(<<"mode">>, get_opt(mode, Options, outer), outer),
        maybe_true_line(<<"useViewTransition">>, use_view_transition(Options)),
        maybe_non_default_line(<<"namespace">>, get_opt(namespace, Options, html), html),
        maybe_data_line(
            <<"viewTransitionSelector">>,
            get_opt(view_transition_selector, Options, undefined)
        )
    ],
    ElementLines = optional_keyed_lines(<<"elements">>, Elements),
    event(datastar_patch_elements, compact(DataLines0) ++ ElementLines, Options).

%% @doc Encode a datastar-patch-elements event that removes matching elements.
-spec remove_elements(iodata_or_string()) -> iodata().
remove_elements(Selector) ->
    remove_elements(Selector, #{}).

%% @doc Encode a datastar-patch-elements removal event.
%%
%% Supported options: event_id and retry_duration.
-spec remove_elements(iodata_or_string(), options()) -> iodata().
remove_elements(Selector, Options) ->
    patch_elements(undefined, maps:merge(option_map(Options), #{
        selector => Selector,
        mode => remove
    })).

%% @doc Encode a datastar-patch-signals event.
-spec patch_signals(iodata_or_string() | map()) -> iodata().
patch_signals(Signals) ->
    patch_signals(Signals, #{}).

%% @doc Encode a datastar-patch-signals event.
%%
%% `Signals' may be an already-encoded JSON/Datastar object expression, or an
%% Erlang map that OTP's `json' module can encode.
-spec patch_signals(iodata_or_string() | map(), options()) -> iodata().
patch_signals(Signals, Options) ->
    DataLines0 = [
        maybe_true_line(<<"onlyIfMissing">>, get_opt(only_if_missing, Options, false))
    ],
    SignalLines = keyed_lines(<<"signals">>, encode_signals(Signals)),
    event(datastar_patch_signals, compact(DataLines0) ++ SignalLines, Options).

%% @doc Remove one or more signals by setting dot-notated paths to JSON null.
-spec remove_signals(iodata_or_string() | [iodata_or_string()]) -> iodata().
remove_signals(Paths) ->
    remove_signals(Paths, #{}).

%% @doc Remove one or more signals by setting dot-notated paths to JSON null.
%%
%% Paths may be a single path like `<<"user.profile.theme">>' or a list of
%% paths. Shared prefixes are deep-merged.
-spec remove_signals(iodata_or_string() | [iodata_or_string()], options()) -> iodata().
remove_signals(Paths, Options) ->
    patch_signals(paths_to_null_map(Paths), Options).

%% @doc Encode JavaScript execution as a Datastar script patch.
-spec execute_script(iodata_or_string()) -> iodata().
execute_script(Script) ->
    execute_script(Script, #{}).

%% @doc Encode JavaScript execution as a Datastar script patch.
%%
%% Supported options: auto_remove (default true), attributes, event_id and
%% retry_duration. Attributes are trusted iodata snippets such as
%% `<<"type=\"module\"">>'.
-spec execute_script(iodata_or_string(), options()) -> iodata().
execute_script(Script, Options) ->
    AutoRemove = get_opt(auto_remove, Options, true),
    Attributes0 = get_opt(attributes, Options, []),
    Attributes = script_attributes(Attributes0, AutoRemove),
    ScriptTag = [
        <<"<script">>,
        [[<<" ">>, Attr] || Attr <- Attributes],
        <<">">>,
        escape_script(Script),
        <<"</script>">>
    ],
    patch_elements(ScriptTag, maps:merge(option_map(Options), #{
        selector => <<"body">>,
        mode => append
    })).

%% @doc Redirect the browser by executing JavaScript on the client.
-spec redirect(iodata_or_string()) -> iodata().
redirect(Url) ->
    redirect(Url, #{}).

%% @doc Redirect the browser by executing JavaScript on the client.
-spec redirect(iodata_or_string(), options()) -> iodata().
redirect(Url, Options) ->
    execute_script([
        <<"setTimeout(function(){window.location.href=">>,
        json:encode(to_binary(Url)),
        <<"},0)">>
    ], Options).

%% @doc Log a value to the browser console.
-spec console_log(term()) -> iodata().
console_log(Message) ->
    console_log(Message, #{}).

%% @doc Log a value to the browser console.
%%
%% Supported levels: log, warn, error, info and debug.
-spec console_log(term(), options()) -> iodata().
console_log(Message, Options) ->
    Level = console_level(get_opt(level, Options, log)),
    execute_script([
        <<"console.">>,
        Level,
        <<"(">>,
        json:encode(Message),
        <<")">>
    ], remove_opt(level, Options)).

%% @doc Build a Datastar frontend action expression like `@post('/path')'.
-spec action(http_verb(), iodata_or_string()) -> iodata().
action(Verb, Path) ->
    action(Verb, Path, #{}).

%% @doc Build a Datastar frontend action expression.
%%
%% Pass `{options, RawJsObject}' to include a raw Datastar options object, for
%% example `#{options => <<"{retryMaxCount: Infinity}">>}'.
-spec action(http_verb(), iodata_or_string(), options()) -> iodata().
action(Verb, Path, Options) ->
    RawOptions = get_opt(options, Options, undefined),
    EncodedPath = js_single_quoted(to_binary(Path)),
    case RawOptions of
        undefined -> [<<"@">>, action_verb(Verb), <<"(">>, EncodedPath, <<")">>];
        _ -> [<<"@">>, action_verb(Verb), <<"(">>, EncodedPath, <<", ">>, RawOptions, <<")">>]
    end.

-spec get(iodata_or_string()) -> iodata().
get(Path) ->
    get(Path, #{}).

-spec get(iodata_or_string(), options()) -> iodata().
get(Path, Options) ->
    action(get, Path, Options).

-spec post(iodata_or_string()) -> iodata().
post(Path) ->
    post(Path, #{}).

-spec post(iodata_or_string(), options()) -> iodata().
post(Path, Options) ->
    action(post, Path, Options).

-spec put(iodata_or_string()) -> iodata().
put(Path) ->
    put(Path, #{}).

-spec put(iodata_or_string(), options()) -> iodata().
put(Path, Options) ->
    action(put, Path, Options).

-spec patch(iodata_or_string()) -> iodata().
patch(Path) ->
    patch(Path, #{}).

-spec patch(iodata_or_string(), options()) -> iodata().
patch(Path, Options) ->
    action(patch, Path, Options).

-spec delete(iodata_or_string()) -> iodata().
delete(Path) ->
    delete(Path, #{}).

-spec delete(iodata_or_string(), options()) -> iodata().
delete(Path, Options) ->
    action(delete, Path, Options).

%% @doc Parse Datastar signals from request parts.
%%
%% For GET and DELETE requests this reads the URL query parameter named `datastar'.
%% For all other methods it decodes the request body as JSON.
-spec read_signals(read_method(), iodata_or_string(), iodata_or_string()) ->
    {ok, term()} | {error, missing_datastar | invalid_json | invalid_query | term()}.
read_signals(Method, QueryString, Body) ->
    Json = case normalize_method(Method) of
        get -> datastar_query_value(QueryString);
        delete -> datastar_query_value(QueryString);
        _ -> {ok, to_binary(Body)}
    end,
    case Json of
        {ok, Bytes} -> decode_json(Bytes);
        {error, _} = Error -> Error
    end.

event_type(datastar_patch_elements) -> <<"datastar-patch-elements">>;
event_type(datastar_patch_signals) -> <<"datastar-patch-signals">>;
event_type(Atom) when is_atom(Atom) -> atom_to_binary(Atom);
event_type(Other) -> to_binary(Other).

maybe_line(_Prefix, undefined) ->
    [];
maybe_line(Prefix, Value) ->
    [Prefix, to_binary(Value), <<"\n">>].

maybe_retry(?DEFAULT_RETRY_DURATION) ->
    [];
maybe_retry(undefined) ->
    [];
maybe_retry(Retry) ->
    [<<"retry: ">>, to_binary(Retry), <<"\n">>].

maybe_data_line(_Key, undefined) ->
    undefined;
maybe_data_line(Key, Value) ->
    [Key, <<" ">>, to_binary(Value)].

maybe_non_default_line(_Key, Value, Value) ->
    undefined;
maybe_non_default_line(Key, Value, _Default) ->
    maybe_data_line(Key, Value).

maybe_true_line(Key, true) ->
    maybe_data_line(Key, true);
maybe_true_line(_Key, _) ->
    undefined.

keyed_lines(Key, Value) ->
    [[Key, <<" ">>, Line] || Line <- split_lines(to_binary(Value))].

optional_keyed_lines(_Key, undefined) ->
    [];
optional_keyed_lines(Key, Value) ->
    keyed_lines(Key, Value).

split_lines(<<>>) ->
    [<<>>];
split_lines(Binary) ->
    binary:split(Binary, <<"\n">>, [global]).

compact(Lines) ->
    [Line || Line <- Lines, Line =/= undefined].

encode_signals(Signals) when is_map(Signals) ->
    iolist_to_binary(json:encode(Signals));
encode_signals(Signals) ->
    to_binary(Signals).

decode_json(Bytes) ->
    try
        {ok, json:decode(Bytes)}
    catch
        error:Reason -> {error, {invalid_json, Reason}};
        _:Reason -> {error, Reason}
    end.

paths_to_null_map(Path) when is_binary(Path) ->
    paths_to_null_map([Path]);
paths_to_null_map([]) ->
    #{};
paths_to_null_map(Path) when is_list(Path) ->
    case is_charlist(Path) of
        true -> paths_to_null_map([Path]);
        false -> lists:foldl(fun(PathItem, Acc) ->
            deep_merge(Acc, path_to_nested_null(validate_signal_path(to_binary(PathItem))))
        end, #{}, Path)
    end;
paths_to_null_map(Path) ->
    paths_to_null_map([Path]).

path_to_nested_null(Path) ->
    lists:foldr(fun(Segment, Acc) -> #{Segment => Acc} end, null, binary:split(Path, <<".">>, [global])).

deep_merge(Map1, Map2) when is_map(Map1), is_map(Map2) ->
    maps:merge_with(fun(_Key, Value1, Value2) ->
        case {is_map(Value1), is_map(Value2)} of
            {true, true} -> deep_merge(Value1, Value2);
            _ -> Value2
        end
    end, Map1, Map2);
deep_merge(_Map1, Map2) ->
    Map2.

validate_signal_path(<<>>) ->
    error({invalid_signal_path, empty});
validate_signal_path(<<$., _Rest/binary>> = Path) ->
    error({invalid_signal_path, leading_dot, Path});
validate_signal_path(Path) ->
    Size = byte_size(Path),
    case {binary:at(Path, Size - 1), binary:match(Path, <<"..">>)} of
        {$., _} -> error({invalid_signal_path, trailing_dot, Path});
        {_, {_, _}} -> error({invalid_signal_path, consecutive_dots, Path});
        _ -> Path
    end.

datastar_query_value(QueryString) ->
    datastar_query_pairs(binary:split(to_binary(QueryString), <<"&">>, [global])).

datastar_query_pairs([]) ->
    {error, missing_datastar};
datastar_query_pairs([Pair | Rest]) ->
    case decode_query_pair(Pair) of
        {ok, <<"datastar">>, Value} -> {ok, Value};
        {ok, _Key, _Value} -> datastar_query_pairs(Rest);
        {error, invalid_query} -> {error, invalid_query}
    end.

decode_query_pair(Pair) ->
    {RawKey, RawValue} = case binary:split(Pair, <<"=">>) of
        [PairKey] -> {PairKey, <<>>};
        [PairKey, PairValue] -> {PairKey, PairValue}
    end,
    case {percent_decode(RawKey), percent_decode(RawValue)} of
        {{ok, DecodedKey}, {ok, DecodedValue}} -> {ok, DecodedKey, DecodedValue};
        _ -> {error, invalid_query}
    end.

percent_decode(Binary) ->
    percent_decode(Binary, []).

percent_decode(<<>>, Acc) ->
    {ok, iolist_to_binary(lists:reverse(Acc))};
percent_decode(<<$+, Rest/binary>>, Acc) ->
    percent_decode(Rest, [<<" ">> | Acc]);
percent_decode(<<$%, Hi, Lo, Rest/binary>>, Acc) ->
    case {hex_value(Hi), hex_value(Lo)} of
        {{ok, H}, {ok, L}} -> percent_decode(Rest, [<<((H bsl 4) bor L)>> | Acc]);
        _ -> {error, invalid_query}
    end;
percent_decode(<<$%, _Rest/binary>>, _Acc) ->
    {error, invalid_query};
percent_decode(<<Byte, Rest/binary>>, Acc) ->
    percent_decode(Rest, [<<Byte>> | Acc]).

hex_value(Byte) when Byte >= $0, Byte =< $9 ->
    {ok, Byte - $0};
hex_value(Byte) when Byte >= $A, Byte =< $F ->
    {ok, Byte - $A + 10};
hex_value(Byte) when Byte >= $a, Byte =< $f ->
    {ok, Byte - $a + 10};
hex_value(_Byte) ->
    error.

normalize_method(Method) when is_atom(Method) ->
    Method;
normalize_method(Method) ->
    list_to_atom(string:lowercase(binary_to_list(to_binary(Method)))).

retry_duration(Options) ->
    get_opt(retry_duration, Options, get_opt(retry, Options, ?DEFAULT_RETRY_DURATION)).

use_view_transition(Options) ->
    get_opt(use_view_transition, Options, get_opt(use_view_transitions, Options, false)).

get_opt(Key, Options, Default) when is_map(Options) ->
    maps:get(Key, Options, Default);
get_opt(Key, Options, Default) when is_list(Options) ->
    proplists:get_value(Key, Options, Default).

remove_opt(Key, Options) when is_map(Options) ->
    maps:remove(Key, Options);
remove_opt(Key, Options) when is_list(Options) ->
    proplists:delete(Key, Options).

option_map(Options) when is_map(Options) ->
    Options;
option_map(Options) when is_list(Options) ->
    maps:from_list(Options).

script_attributes(Attributes, AutoRemove) when is_map(Attributes) ->
    Attributes1 = case AutoRemove andalso not maps:is_key(<<"data-effect">>, Attributes)
        andalso not maps:is_key("data-effect", Attributes) of
        true -> Attributes#{<<"data-effect">> => <<"el.remove()">>};
        false -> Attributes
    end,
    [format_attribute(Key, Value) || {Key, Value} <- maps:to_list(Attributes1)];
script_attributes(Attributes, true) ->
    [<<"data-effect=\"el.remove()\"">> | Attributes];
script_attributes(Attributes, false) ->
    Attributes.

format_attribute(Key, Value) ->
    [to_binary(Key), <<"=\"">>, escape_html_attr(Value), <<"\"">>].

console_level(log) -> <<"log">>;
console_level(warn) -> <<"warn">>;
console_level(error) -> <<"error">>;
console_level(info) -> <<"info">>;
console_level(debug) -> <<"debug">>;
console_level(<<"log">>) -> <<"log">>;
console_level(<<"warn">>) -> <<"warn">>;
console_level(<<"error">>) -> <<"error">>;
console_level(<<"info">>) -> <<"info">>;
console_level(<<"debug">>) -> <<"debug">>;
console_level(_) -> <<"log">>.

action_verb(get) -> <<"get">>;
action_verb(post) -> <<"post">>;
action_verb(put) -> <<"put">>;
action_verb(patch) -> <<"patch">>;
action_verb(delete) -> <<"delete">>;
action_verb(Verb) -> to_binary(Verb).

js_single_quoted(Value) ->
    [<<"'">>, escape_js_single_quoted(Value), <<"'">>].

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) when is_atom(Value) ->
    atom_to_binary(Value);
to_binary(Value) when is_integer(Value) ->
    integer_to_binary(Value);
to_binary(Value) when is_float(Value) ->
    float_to_binary(Value, [short]);
to_binary(true) ->
    <<"true">>;
to_binary(false) ->
    <<"false">>;
to_binary({safe, Value}) ->
    iolist_to_binary(Value);
to_binary({ok, Value}) ->
    iolist_to_binary(Value);
to_binary(Value) ->
    unicode:characters_to_binary(Value).

escape_script(Script) ->
    binary:replace(to_binary(Script), <<"</script">>, <<"<\\/script">>, [global]).

escape_html_attr(Value) ->
    escape_html_attr(to_binary(Value), []).

escape_html_attr(<<>>, Acc) ->
    iolist_to_binary(lists:reverse(Acc));
escape_html_attr(<<"&", Rest/binary>>, Acc) ->
    escape_html_attr(Rest, [<<"&amp;">> | Acc]);
escape_html_attr(<<"\"", Rest/binary>>, Acc) ->
    escape_html_attr(Rest, [<<"&quot;">> | Acc]);
escape_html_attr(<<"<", Rest/binary>>, Acc) ->
    escape_html_attr(Rest, [<<"&lt;">> | Acc]);
escape_html_attr(<<">", Rest/binary>>, Acc) ->
    escape_html_attr(Rest, [<<"&gt;">> | Acc]);
escape_html_attr(<<Byte, Rest/binary>>, Acc) ->
    escape_html_attr(Rest, [<<Byte>> | Acc]).

escape_js_single_quoted(Value) ->
    escape_js_single_quoted(Value, []).

escape_js_single_quoted(<<>>, Acc) ->
    iolist_to_binary(lists:reverse(Acc));
escape_js_single_quoted(<<"\\", Rest/binary>>, Acc) ->
    escape_js_single_quoted(Rest, [<<"\\\\">> | Acc]);
escape_js_single_quoted(<<"'", Rest/binary>>, Acc) ->
    escape_js_single_quoted(Rest, [<<"\\'">> | Acc]);
escape_js_single_quoted(<<"\n", Rest/binary>>, Acc) ->
    escape_js_single_quoted(Rest, [<<"\\n">> | Acc]);
escape_js_single_quoted(<<"\r", Rest/binary>>, Acc) ->
    escape_js_single_quoted(Rest, [<<"\\r">> | Acc]);
escape_js_single_quoted(<<Byte, Rest/binary>>, Acc) ->
    escape_js_single_quoted(Rest, [<<Byte>> | Acc]).

is_charlist([]) ->
    true;
is_charlist([Head | Tail]) when is_integer(Head) ->
    is_charlist(Tail);
is_charlist(_) ->
    false.
