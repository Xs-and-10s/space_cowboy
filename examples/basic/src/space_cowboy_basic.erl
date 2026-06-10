-module(space_cowboy_basic).

-export([start/0, stop/0, home/1, ping/1]).

start() ->
    application:ensure_all_started(space_cowboy),
    space_cowboy:start_clear(space_cowboy_basic, [
        {"/", fun ?MODULE:home/1},
        {"/ping", fun ?MODULE:ping/1}
    ], #{port => 8080}).

stop() ->
    space_cowboy:stop(space_cowboy_basic).

home(_Req) ->
    Body = [
        <<"<main data-signals:message=\"'Ready'\">">>,
        <<"<h1>Space Cowboy</h1>">>,
        <<"<button data-on:click=\"@get('/ping')\">Ping Erlang</button>">>,
        <<"<p id=\"message\" data-text=\"$message\"></p>">>,
        <<"</main>">>
    ],
    {html, space_cowboy_html:page(<<"Space Cowboy">>, Body)}.

ping(_Req) ->
    {sse, [
        data_starship:patch_signals(#{<<"message">> => <<"Datastar over Cowboy SSE">>})
    ]}.
