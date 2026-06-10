%% @doc Datastar-first convenience layer for Cowboy.
-module(space_cowboy).

-export([
    start_clear/2,
    start_clear/3,
    stop/1,
    dispatch/1,
    datastar_script/0,
    datastar_script/1
]).

-type route() :: {binary() | string(), fun()} | {binary() | string(), module(), term()}.
-type listener_name() :: atom().

-export_type([route/0, listener_name/0]).

%% @doc Start an HTTP listener with Datastar-friendly route specs.
-spec start_clear([route()], map()) -> {ok, pid()} | {error, term()}.
start_clear(Routes, Options) ->
    start_clear(space_cowboy_http, Routes, Options).

%% @doc Start a named HTTP listener.
-spec start_clear(listener_name(), [route()], map()) -> {ok, pid()} | {error, term()}.
start_clear(Name, Routes, Options) ->
    Port = maps:get(port, Options, 8080),
    TransOpts = maps:get(transport_options, Options, [{port, Port}]),
    ProtoOpts = maps:get(protocol_options, Options, #{}),
    cowboy:start_clear(Name, TransOpts, ProtoOpts#{env => #{dispatch => dispatch(Routes)}}).

-spec stop(listener_name()) -> ok | {error, not_found}.
stop(Name) ->
    cowboy:stop_listener(Name).

%% @doc Compile route specs into a Cowboy dispatch table.
-spec dispatch([route()]) -> cowboy_router:dispatch_rules().
dispatch(Routes) ->
    cowboy_router:compile([{'_', [route(Route) || Route <- Routes]}]).

%% @doc Script tag for the public Datastar bundle.
-spec datastar_script() -> iodata().
datastar_script() ->
    datastar_script(<<"https://cdn.jsdelivr.net/gh/starfederation/datastar@main/bundles/datastar.js">>).

%% @doc Script tag for a self-hosted or Pro Datastar bundle.
-spec datastar_script(iodata()) -> iodata().
datastar_script(Src) ->
    [<<"<script type=\"module\" src=\"">>, Src, <<"\"></script>">>].

route({Path, Handler}) when is_function(Handler) ->
    {Path, space_cowboy_handler, #{handler => Handler}};
route({Path, Module, State}) ->
    {Path, Module, State}.
