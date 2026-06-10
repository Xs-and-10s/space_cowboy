%% @doc Datastar-first convenience layer for Cowboy.
-module(space_cowboy).

-export([
    start_clear/2,
    start_clear/3,
    start_quic/2,
    start_quic/3,
    stop_quic/1,
    quic_available/0,
    stop/1,
    dispatch/1,
    sse_loop/1,
    sse_loop/2,
    datastar_script/0,
    datastar_script/1
]).

-type loop_options() :: space_cowboy_loop:options().
-type route() ::
    {binary() | string(), fun()}
    | {binary() | string(), {sse_loop, loop_options()}}
    | {binary() | string(), module(), term()}.
-type listener_name() :: atom().
-type quic_listener() :: term().
-type quic_error() :: quic_unavailable | quic_start_timeout | term().

-export_type([route/0, listener_name/0, quic_listener/0, loop_options/0]).

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

%% @doc Start an experimental HTTP/3 over QUIC listener.
%%
%% Cowboy's QUIC support currently depends on the optional `quicer' NIF and
%% Cowboy being compiled with `COWBOY_QUICER'. Normal Space Cowboy builds keep
%% this optional; when QUIC support is unavailable this function returns
%% `{error, quic_unavailable}' instead of crashing.
-spec start_quic([route()], map()) -> {ok, quic_listener()} | {error, quic_error()}.
start_quic(Routes, Options) ->
    start_quic(space_cowboy_quic, Routes, Options).

%% @doc Start a named experimental HTTP/3 over QUIC listener.
-spec start_quic(listener_name(), [route()], map()) -> {ok, quic_listener()} | {error, quic_error()}.
start_quic(Name, Routes, Options) ->
    case quic_available() of
        true ->
            Port = maps:get(port, Options, 8443),
            TransOpts = maps:get(transport_options, Options, #{socket_opts => [{port, Port}]}),
            ProtoOpts = maps:get(protocol_options, Options, #{}),
            Timeout = maps:get(start_timeout, Options, 5000),
            start_quic_with_timeout(Name, TransOpts, ProtoOpts#{env => #{dispatch => dispatch(Routes)}}, Timeout);
        false ->
            {error, quic_unavailable}
    end.

start_quic_with_timeout(Name, TransOpts, ProtoOpts, Timeout) ->
    Parent = self(),
    Ref = make_ref(),
    {Pid, Monitor} = spawn_monitor(fun() ->
        Result = try cowboy:start_quic(Name, TransOpts, ProtoOpts) of
            Value -> Value
        catch
            error:{no_quicer, _} -> {error, quic_unavailable};
            exit:{noproc, _} -> {error, quic_unavailable};
            Class:Reason -> {error, {Class, Reason}}
        end,
        Parent ! {Ref, Result}
    end),
    receive
        {Ref, Result} ->
            erlang:demonitor(Monitor, [flush]),
            Result;
        {'DOWN', Monitor, process, Pid, Reason} ->
            {error, {exit, Reason}}
    after Timeout ->
        exit(Pid, kill),
        erlang:demonitor(Monitor, [flush]),
        {error, quic_start_timeout}
    end.

-spec quic_available() -> boolean().
quic_available() ->
    code:which(quicer) =/= non_existing.

%% @doc Stop an experimental HTTP/3 over QUIC listener.
%%
%% QUIC listeners are managed by quicer, not Ranch, so `stop/1' does not apply.
-spec stop_quic(quic_listener()) -> ok | closed | {error, quic_unavailable | term()}.
stop_quic(Listener) ->
    case quic_available() of
        true ->
            try quicer:close_listener(Listener) of
                Result -> Result
            catch
                Class:Reason -> {error, {Class, Reason}}
            end;
        false ->
            {error, quic_unavailable}
    end.

-spec stop(listener_name()) -> ok | {error, not_found}.
stop(Name) ->
    cowboy:stop_listener(Name).

%% @doc Compile route specs into a Cowboy dispatch table.
-spec dispatch([route()]) -> cowboy_router:dispatch_rules().
dispatch(Routes) ->
    cowboy_router:compile([{'_', [route(Route) || Route <- Routes]}]).

%% @doc Build route options for a long-lived Datastar SSE loop handler.
-spec sse_loop(loop_options() | space_cowboy_loop:info_fun()) -> {sse_loop, loop_options()}.
sse_loop(Options) when is_map(Options) ->
    {sse_loop, Options};
sse_loop(InfoFun) when is_function(InfoFun, 3) ->
    {sse_loop, #{info => InfoFun}}.

%% @doc Build route options with explicit init and info callbacks.
-spec sse_loop(space_cowboy_loop:init_fun(), space_cowboy_loop:info_fun()) ->
    {sse_loop, loop_options()}.
sse_loop(InitFun, InfoFun) ->
    {sse_loop, #{init => InitFun, info => InfoFun}}.

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
route({Path, {sse_loop, Options}}) ->
    {Path, space_cowboy_loop, Options};
route({Path, Module, State}) ->
    {Path, Module, State}.
