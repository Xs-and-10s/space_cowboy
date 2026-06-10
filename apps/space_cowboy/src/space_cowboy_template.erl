%% @doc Template-output compatibility helpers.
%%
%% Space Cowboy does not prescribe a template engine. A template library is
%% compatible when its rendered output can be represented as iodata, either
%% directly or through a small common wrapper such as `{safe, Iodata}'.
-module(space_cowboy_template).

-export([
    to_iodata/1,
    html/1,
    patch_elements/1,
    patch_elements/2
]).

-type rendered() ::
    iodata()
    | {safe, iodata()}
    | {ok, iodata()}
    | fun(() -> rendered()).

-export_type([rendered/0]).

%% @doc Normalize common rendered-template shapes to iodata.
-spec to_iodata(rendered()) -> iodata().
to_iodata({safe, Iodata}) ->
    Iodata;
to_iodata({ok, Iodata}) ->
    Iodata;
to_iodata(Render) when is_function(Render, 0) ->
    to_iodata(Render());
to_iodata(Iodata) ->
    Iodata.

%% @doc Build a Space Cowboy HTML handler return value from rendered output.
-spec html(rendered()) -> {html, iodata()}.
html(Rendered) ->
    {html, to_iodata(Rendered)}.

%% @doc Build a Datastar patch-elements SSE event from rendered output.
-spec patch_elements(rendered()) -> iodata().
patch_elements(Rendered) ->
    patch_elements(Rendered, #{}).

%% @doc Build a Datastar patch-elements SSE event from rendered output.
-spec patch_elements(rendered(), data_starship:options()) -> iodata().
patch_elements(Rendered, Options) ->
    data_starship:patch_elements(to_iodata(Rendered), Options).
