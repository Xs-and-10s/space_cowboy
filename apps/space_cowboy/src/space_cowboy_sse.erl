%% @doc Cowboy adapter for Datastar SSE events.
-module(space_cowboy_sse).

-export([
    stream_reply/1,
    stream_reply/2,
    send/2,
    patch_elements/2,
    patch_elements/3,
    patch_signals/2,
    patch_signals/3,
    execute_script/2,
    execute_script/3,
    read_signals/1
]).

-spec stream_reply(cowboy_req:req()) -> cowboy_req:req().
stream_reply(Req0) ->
    stream_reply(Req0, #{}).

-spec stream_reply(cowboy_req:req(), #{binary() => iodata()}) -> cowboy_req:req().
stream_reply(Req0, ExtraHeaders) ->
    Headers = maps:merge(data_starship:sse_headers(), ExtraHeaders),
    cowboy_req:stream_reply(200, Headers, Req0).

-spec send(cowboy_req:req(), iodata()) -> ok.
send(Req, Event) ->
    cowboy_req:stream_body(Event, nofin, Req).

-spec patch_elements(cowboy_req:req(), iodata()) -> ok.
patch_elements(Req, Elements) ->
    patch_elements(Req, Elements, #{}).

-spec patch_elements(cowboy_req:req(), iodata(), data_starship:options()) -> ok.
patch_elements(Req, Elements, Options) ->
    send(Req, data_starship:patch_elements(Elements, Options)).

-spec patch_signals(cowboy_req:req(), iodata() | map()) -> ok.
patch_signals(Req, Signals) ->
    patch_signals(Req, Signals, #{}).

-spec patch_signals(cowboy_req:req(), iodata() | map(), data_starship:options()) -> ok.
patch_signals(Req, Signals, Options) ->
    send(Req, data_starship:patch_signals(Signals, Options)).

-spec execute_script(cowboy_req:req(), iodata()) -> ok.
execute_script(Req, Script) ->
    execute_script(Req, Script, #{}).

-spec execute_script(cowboy_req:req(), iodata(), data_starship:options()) -> ok.
execute_script(Req, Script, Options) ->
    send(Req, data_starship:execute_script(Script, Options)).

-spec read_signals(cowboy_req:req()) -> {ok, term()} | {error, term()}.
read_signals(Req) ->
    Method = cowboy_req:method(Req),
    case Method of
        <<"GET">> ->
            data_starship:read_signals(get, cowboy_req:qs(Req), <<>>);
        _ ->
            case cowboy_req:read_body(Req) of
                {ok, Body, _Req1} -> data_starship:read_signals(Method, <<>>, Body);
                {more, Body, _Req1} -> data_starship:read_signals(Method, <<>>, Body)
            end
    end.
