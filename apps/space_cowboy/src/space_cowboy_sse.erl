%% @doc Cowboy adapter for Datastar SSE events.
-module(space_cowboy_sse).

-export([
    start/1,
    start/2,
    finish/1,
    stream/2,
    stream/3,
    stream_reply/1,
    stream_reply/2,
    send/2,
    comment/1,
    comment/2,
    heartbeat/0,
    heartbeat/1,
    heartbeat/2,
    patch_elements/2,
    patch_elements/3,
    patch_signals/2,
    patch_signals/3,
    execute_script/2,
    execute_script/3,
    read_signals/1
]).

-opaque stream() :: {?MODULE, cowboy_req:req()}.

-export_type([stream/0]).

-spec start(cowboy_req:req()) -> stream().
start(Req0) ->
    start(Req0, #{}).

-spec start(cowboy_req:req(), #{binary() => iodata()}) -> stream().
start(Req0, ExtraHeaders) ->
    {?MODULE, stream_reply(Req0, ExtraHeaders)}.

-spec finish(stream() | cowboy_req:req()) -> ok.
finish({?MODULE, Req}) ->
    cowboy_req:stream_body(<<>>, fin, Req);
finish(Req) ->
    cowboy_req:stream_body(<<>>, fin, Req).

-spec stream(cowboy_req:req(), fun((stream()) -> ok)) -> cowboy_req:req().
stream(Req0, Fun) ->
    stream(Req0, #{}, Fun).

-spec stream(cowboy_req:req(), #{binary() => iodata()}, fun((stream()) -> ok)) -> cowboy_req:req().
stream(Req0, ExtraHeaders, Fun) ->
    Stream = {?MODULE, Req} = start(Req0, ExtraHeaders),
    ok = Fun(Stream),
    ok = finish(Stream),
    Req.

-spec stream_reply(cowboy_req:req()) -> cowboy_req:req().
stream_reply(Req0) ->
    stream_reply(Req0, #{}).

-spec stream_reply(cowboy_req:req(), #{binary() => iodata()}) -> cowboy_req:req().
stream_reply(Req0, ExtraHeaders) ->
    Headers = maps:merge(datastar_beam:sse_headers(), ExtraHeaders),
    cowboy_req:stream_reply(200, Headers, Req0).

-spec send(stream() | cowboy_req:req(), iodata()) -> ok.
send({?MODULE, Req}, Event) ->
    send(Req, Event);
send(Req, Event) ->
    cowboy_req:stream_body(Event, nofin, Req).

-spec comment(iodata()) -> iodata().
comment(Text) ->
    Lines = binary:split(to_binary(Text), <<"\n">>, [global]),
    [comment_line(Line) || Line <- Lines] ++ [<<"\n">>].

-spec comment(stream() | cowboy_req:req(), iodata()) -> ok.
comment(Stream, Text) ->
    send(Stream, comment(Text)).

-spec heartbeat() -> iodata().
heartbeat() ->
    comment(<<"heartbeat">>).

-spec heartbeat(iodata() | stream()) -> iodata() | ok.
heartbeat({?MODULE, _Req} = Stream) ->
    heartbeat(Stream, <<"heartbeat">>);
heartbeat(Label) ->
    comment(Label).

-spec heartbeat(stream() | cowboy_req:req(), iodata()) -> ok.
heartbeat(Stream, Label) ->
    comment(Stream, Label).

-spec patch_elements(stream() | cowboy_req:req(), iodata()) -> ok.
patch_elements(Req, Elements) ->
    patch_elements(Req, Elements, #{}).

-spec patch_elements(stream() | cowboy_req:req(), iodata(), datastar_beam:options()) -> ok.
patch_elements(Req, Elements, Options) ->
    send(Req, datastar_beam:patch_elements(Elements, Options)).

-spec patch_signals(stream() | cowboy_req:req(), iodata() | map()) -> ok.
patch_signals(Req, Signals) ->
    patch_signals(Req, Signals, #{}).

-spec patch_signals(stream() | cowboy_req:req(), iodata() | map(), datastar_beam:options()) -> ok.
patch_signals(Req, Signals, Options) ->
    send(Req, datastar_beam:patch_signals(Signals, Options)).

-spec execute_script(stream() | cowboy_req:req(), iodata()) -> ok.
execute_script(Req, Script) ->
    execute_script(Req, Script, #{}).

-spec execute_script(stream() | cowboy_req:req(), iodata(), datastar_beam:options()) -> ok.
execute_script(Req, Script, Options) ->
    send(Req, datastar_beam:execute_script(Script, Options)).

-spec read_signals(cowboy_req:req()) -> {ok, term()} | {error, term()}.
read_signals(Req) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"GET">> ->
            datastar_beam:read_signals(get, cowboy_req:qs(Req), <<>>);
        _ ->
            case cowboy_req:read_body(Req) of
                {ok, Body, _Req1} -> datastar_beam:read_signals(Method, <<>>, Body);
                {more, Body, _Req1} -> datastar_beam:read_signals(Method, <<>>, Body)
            end
    end.

comment_line(<<>>) ->
    <<":\n">>;
comment_line(Line) ->
    [<<": ">>, Line, <<"\n">>].

to_binary(Value) when is_binary(Value) ->
    Value;
to_binary(Value) ->
    unicode:characters_to_binary(Value).
