%% @doc Small Cowboy handler that accepts ergonomic Space Cowboy return values.
-module(space_cowboy_handler).

-export([init/2]).

init(Req0, #{handler := Handler} = State) ->
    case Handler(Req0) of
        {html, Body} ->
            reply(
                200,
                #{<<"content-type">> => <<"text/html; charset=utf-8">>},
                space_cowboy_template:to_iodata(Body),
                Req0,
                State
            );
        {html, Body, Headers} ->
            reply(200, maps:merge(html_headers(), Headers), space_cowboy_template:to_iodata(Body), Req0, State);
        {json, Body} ->
            reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0, State);
        {reply, Status, Headers, Body} ->
            reply(Status, Headers, Body, Req0, State);
        {sse, Events} ->
            Req = space_cowboy_sse:stream_reply(Req0),
            lists:foreach(fun(Event) -> space_cowboy_sse:send(Req, Event) end, Events),
            cowboy_req:stream_body(<<>>, fin, Req),
            {ok, Req, State};
        {stream, StreamFun} ->
            Req = space_cowboy_sse:stream_reply(Req0),
            Sender = fun(Event) -> space_cowboy_sse:send(Req, Event) end,
            ok = StreamFun(Sender),
            cowboy_req:stream_body(<<>>, fin, Req),
            {ok, Req, State};
        {ok, Req} ->
            {ok, Req, State}
    end.

reply(Status, Headers, Body, Req0, State) ->
    Req = cowboy_req:reply(Status, Headers, Body, Req0),
    {ok, Req, State}.

html_headers() ->
    #{<<"content-type">> => <<"text/html; charset=utf-8">>}.
