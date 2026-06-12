%% @doc Test-only Datastar conformance app for Space Cowboy integration tests.
-module(space_cowboy_conformance_app).

-export([
    routes/0,
    home/1,
    counter/1,
    search/1,
    progress/1,
    script/1,
    malformed/1,
    template/1,
    template_patch/1,
    template_matrix/1,
    template_matrix_patch/1,
    body_signals/1,
    heartbeat/1,
    loop_init/2,
    loop_info/3,
    heartbeat_loop_init/2
]).

routes() ->
    [
        {"/", fun ?MODULE:home/1},
        {"/counter", fun ?MODULE:counter/1},
        {"/search", fun ?MODULE:search/1},
        {"/progress", fun ?MODULE:progress/1},
        {"/script", fun ?MODULE:script/1},
        {"/malformed", fun ?MODULE:malformed/1},
        {"/template", fun ?MODULE:template/1},
        {"/template-patch", fun ?MODULE:template_patch/1},
        {"/template-matrix/:style", fun ?MODULE:template_matrix/1},
        {"/template-matrix-patch/:style", fun ?MODULE:template_matrix_patch/1},
        {"/body-signals", fun ?MODULE:body_signals/1},
        {"/heartbeat", fun ?MODULE:heartbeat/1},
        {"/loop", space_cowboy:sse_loop(fun ?MODULE:loop_init/2, fun ?MODULE:loop_info/3)},
        {"/loop-heartbeat", space_cowboy:sse_loop(#{
            init => fun ?MODULE:heartbeat_loop_init/2,
            heartbeat => #{interval => 10, label => <<"loop-heartbeat">>}
        })}
    ].

home(_Req) ->
    Body = [
        <<"<main id=\"app\" data-signals='{ \"count\": 0, \"query\": \"\" }'>">>,
        <<"<button id=\"counter\" data-on:click=\"@get('/counter')\" data-text=\"$count\"></button>">>,
        <<"<input id=\"search\" data-bind:query data-on:input__debounce.200ms=\"@get('/search')\">">>,
        <<"<ul id=\"results\"></ul>">>,
        <<"<progress id=\"progress\" max=\"100\" data-attr:value=\"$progress\"></progress>">>,
        <<"</main>">>
    ],
    {html, space_cowboy_html:page(<<"Space Cowboy Conformance">>, Body)}.

counter(Req) ->
    Signals = signals_or_empty(Req),
    Count = maps:get(<<"count">>, Signals, 0),
    {sse, [
        datastar_beam:patch_signals(#{<<"count">> => Count + 1})
    ]}.

search(Req) ->
    Signals = signals_or_empty(Req),
    Query = maps:get(<<"query">>, Signals, <<>>),
    Results = search_results(Query),
    {sse, [
        datastar_beam:patch_elements(Results, #{
            selector => <<"#results">>,
            mode => inner
        })
    ]}.

progress(_Req) ->
    {stream, fun(Send) ->
        Send(datastar_beam:patch_signals(#{<<"progress">> => 25})),
        Send(datastar_beam:patch_elements(<<"<span id=\"phase\">Ignition</span>">>, #{
            selector => <<"#phase">>,
            mode => outer
        })),
        Send(datastar_beam:patch_signals(#{<<"progress">> => 100})),
        ok
    end}.

script(_Req) ->
    {sse, [
        datastar_beam:execute_script(<<"window.spaceCowboyReady = true;">>)
    ]}.

malformed(Req) ->
    Body = case space_cowboy_sse:read_signals(Req) of
        {ok, Signals} ->
            datastar_beam:patch_signals(#{<<"received">> => Signals});
        {error, Reason} ->
            datastar_beam:patch_signals(#{<<"error">> => reason_to_binary(Reason)})
    end,
    {sse, [Body]}.

template(_Req) ->
    space_cowboy_template:html({safe, [
        <<"<section id=\"template-page\">">>,
        template_widget(<<"Dock">>),
        <<"</section>">>
    ]}).

template_patch(Req) ->
    Signals = signals_or_empty(Req),
    Label = maps:get(<<"label">>, Signals, <<"Dock">>),
    {sse, [
        space_cowboy_template:patch_elements({safe, template_widget(Label)}, #{
            selector => <<"#template-widget">>,
            mode => outer
        })
    ]}.

template_matrix(Req) ->
    Style = cowboy_req:binding(style, Req),
    space_cowboy_template:html(template_rendered(Style, <<"Matrix">>)).

template_matrix_patch(Req) ->
    Style = cowboy_req:binding(style, Req),
    Signals = signals_or_empty(Req),
    Label = maps:get(<<"label">>, Signals, <<"Matrix">>),
    {sse, [
        space_cowboy_template:patch_elements(template_rendered(Style, Label), #{
            selector => <<"#matrix-template">>,
            mode => inner
        })
    ]}.

body_signals(Req) ->
    Signals = signals_or_empty(Req),
    Value = maps:get(<<"value">>, Signals, <<"Dock">>),
    {sse, [
        datastar_beam:patch_signals(#{<<"body">> => Value})
    ]}.

heartbeat(_Req) ->
    {sse_stream, fun(Stream) ->
        space_cowboy_sse:comment(Stream, <<"stream-open">>),
        space_cowboy_sse:heartbeat(Stream),
        space_cowboy_sse:patch_signals(Stream, #{<<"alive">> => true}),
        space_cowboy_sse:heartbeat(Stream, <<"stream-close">>),
        ok
    end}.

loop_init(Req, Stream) ->
    Signals = signals_or_empty(Req),
    Value = maps:get(<<"value">>, Signals, <<"Dock">>),
    space_cowboy_sse:comment(Stream, <<"loop-open">>),
    self() ! {patch, Value},
    {ok, #{}}.

loop_info({patch, Value}, Stream, State) ->
    space_cowboy_sse:patch_signals(Stream, #{<<"loop">> => Value}),
    space_cowboy_sse:heartbeat(Stream, <<"loop-close">>),
    {stop, State};
loop_info(_Message, _Stream, State) ->
    {ok, State}.

heartbeat_loop_init(_Req, Stream) ->
    space_cowboy_sse:comment(Stream, <<"heartbeat-loop-open">>),
    {ok, #{}}.

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

reason_to_binary(Reason) when is_atom(Reason) ->
    atom_to_binary(Reason);
reason_to_binary(Reason) ->
    iolist_to_binary(io_lib:format("~p", [Reason])).

template_widget(Label) ->
    [
        <<"<button">>,
        space_cowboy_html:attrs([
            {<<"id">>, <<"template-widget">>},
            {<<"data-on:click__prevent">>, <<"@post('/template-patch')">>},
            {<<"data-bind:label">>, true},
            {<<"data-text">>, <<"$label">>},
            {<<"aria-label">>, Label}
        ]),
        <<">">>,
        space_cowboy_html:escape(Label),
        <<"</button>">>
    ].

template_rendered(<<"raw">>, Label) ->
    template_matrix_markup(Label);
template_rendered(<<"safe">>, Label) ->
    {safe, template_matrix_markup(Label)};
template_rendered(<<"ok">>, Label) ->
    {ok, template_matrix_markup(Label)};
template_rendered(<<"lazy">>, Label) ->
    fun() -> {safe, template_matrix_markup(Label)} end;
template_rendered(_Style, Label) ->
    template_matrix_markup(Label).

template_matrix_markup(Label) ->
    [
        <<"<article id=\"matrix-template\"">>,
        space_cowboy_html:attrs([
            {<<"data-bind:label">>, true},
            {<<"data-text">>, <<"$label">>},
            {<<"data-on:click__prevent">>, <<"@post('/template-matrix-patch/raw')">>},
            {<<"aria-label">>, Label}
        ]),
        <<">">>,
        space_cowboy_html:escape(Label),
        <<"</article>">>
    ].
