-module(space_cowboy_basic).

-export([
    start/0,
    start/2,
    stop/0,
    stop/1,
    routes/0,
    home/1,
    ping/1,
    search/1,
    edit_title/1,
    save_title/1,
    progress_init/2,
    progress_info/3
]).

start() ->
    start(space_cowboy_basic, #{port => 8080}).

start(Name, Options) ->
    application:ensure_all_started(space_cowboy),
    space_cowboy:start_clear(Name, routes(), Options).

stop() ->
    stop(space_cowboy_basic).

stop(Name) ->
    space_cowboy:stop(Name).

routes() ->
    [
        {"/", fun ?MODULE:home/1},
        {"/ping", fun ?MODULE:ping/1},
        {"/search", fun ?MODULE:search/1},
        {"/edit-title", fun ?MODULE:edit_title/1},
        {"/save-title", fun ?MODULE:save_title/1},
        {"/progress", space_cowboy:sse_loop(fun ?MODULE:progress_init/2, fun ?MODULE:progress_info/3)}
    ].

home(_Req) ->
    Body = [
        <<"<main data-signals='{ \"message\": \"Ready\", \"query\": \"\", \"title\": \"Docking Checklist\", \"progress\": 0 }'>">>,
        <<"<h1>Space Cowboy</h1>">>,
        <<"<section>">>,
        <<"<button data-on:click=\"@get('/ping')\">Ping Erlang</button>">>,
        <<"<p id=\"message\" data-text=\"$message\"></p>">>,
        <<"</section>">>,
        <<"<section>">>,
        <<"<label for=\"query\">Active search</label>">>,
        <<"<input id=\"query\" data-bind:query data-on:input__debounce.200ms=\"@get('/search')\">">>,
        <<"<ul id=\"results\"></ul>">>,
        <<"</section>">>,
        <<"<section id=\"editor\">">>,
        title_display(<<"Docking Checklist">>),
        <<"</section>">>,
        <<"<section>">>,
        <<"<button data-on:click=\"@get('/progress')\">Run progress</button>">>,
        <<"<progress id=\"progress-bar\" max=\"100\" data-attr:value=\"$progress\"></progress>">>,
        <<"<p id=\"phase\">Idle</p>">>,
        <<"</section>">>,
        <<"</main>">>
    ],
    {html, space_cowboy_html:page(<<"Space Cowboy">>, Body)}.

ping(_Req) ->
    {sse, [
        data_starship:patch_signals(#{<<"message">> => <<"Datastar over Cowboy SSE">>})
    ]}.

search(Req) ->
    Signals = signals_or_empty(Req),
    Query = maps:get(<<"query">>, Signals, <<>>),
    {sse, [
        data_starship:patch_elements(search_results(Query), #{
            selector => <<"#results">>,
            mode => inner
        })
    ]}.

edit_title(_Req) ->
    {sse, [
        data_starship:patch_elements(title_editor(<<"Docking Checklist">>), #{
            selector => <<"#editor">>,
            mode => inner
        })
    ]}.

save_title(Req) ->
    Signals = signals_or_empty(Req),
    Title = maps:get(<<"title">>, Signals, <<"Docking Checklist">>),
    {sse, [
        data_starship:patch_signals(#{<<"title">> => Title}),
        data_starship:patch_elements(title_display(Title), #{
            selector => <<"#editor">>,
            mode => inner
        })
    ]}.

progress_init(_Req, Stream) ->
    space_cowboy_sse:comment(Stream, <<"progress-open">>),
    self() ! {progress, 25, <<"Ignition">>},
    self() ! {progress, 60, <<"Telemetry lock">>},
    self() ! {progress, 100, <<"Docking complete">>},
    {ok, #{}}.

progress_info({progress, Percent, Phase}, Stream, State) ->
    space_cowboy_sse:patch_signals(Stream, #{<<"progress">> => Percent}),
    space_cowboy_sse:patch_elements(Stream, phase(Phase), #{
        selector => <<"#phase">>,
        mode => outer
    }),
    case Percent of
        100 ->
            space_cowboy_sse:heartbeat(Stream, <<"progress-close">>),
            {stop, State};
        _ ->
            {ok, State}
    end;
progress_info(_Message, _Stream, State) ->
    {ok, State}.

signals_or_empty(Req) ->
    case space_cowboy_sse:read_signals(Req) of
        {ok, Signals} when is_map(Signals) -> Signals;
        _ -> #{}
    end.

search_results(<<>>) ->
    <<"<li data-empty>No query</li>">>;
search_results(Query) ->
    Escaped = space_cowboy_html:escape(Query),
    [<<"<li id=\"result-primary\">">>, Escaped, <<" Station</li>">>].

title_display(Title) ->
    Escaped = space_cowboy_html:escape(Title),
    [
        <<"<h2 id=\"title\" data-text=\"$title\">">>, Escaped, <<"</h2>">>,
        <<"<button data-on:click=\"@get('/edit-title')\">Edit</button>">>
    ].

title_editor(Title) ->
    [
        <<"<label for=\"title-input\">Title</label>">>,
        <<"<input id=\"title-input\" data-bind:title value=\"">>,
        space_cowboy_html:escape(Title),
        <<"\">">>,
        <<"<button data-on:click=\"@post('/save-title')\">Save</button>">>
    ].

phase(Phase) ->
    [<<"<p id=\"phase\">">>, space_cowboy_html:escape(Phase), <<"</p>">>].
