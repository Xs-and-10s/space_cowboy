%% @doc Cowboy loop handler for long-lived Datastar SSE streams.
-module(space_cowboy_loop).

-export([init/2, info/3, terminate/3]).

-type stream() :: space_cowboy_sse:stream().
-type init_fun() :: fun((cowboy_req:req(), stream()) -> init_result()).
-type info_fun() :: fun((term(), stream(), term()) -> info_result()).
-type init_result() :: term() | {ok, term()} | {ok, term(), timeout()}.
-type info_result() :: ok | stop | term() | {ok, term()} | {ok, term(), timeout()} | {stop, term()}.
-type heartbeat_options() ::
    timeout()
    | #{interval := timeout(), label => iodata()}.
-type options() :: #{
    init => init_fun(),
    info => info_fun(),
    heartbeat => heartbeat_options(),
    headers => #{binary() => iodata()}
}.

-export_type([init_fun/0, info_fun/0, options/0]).

-record(state, {
    stream :: stream(),
    app_state = undefined :: term(),
    info_fun = undefined :: info_fun() | undefined,
    heartbeat = undefined :: undefined | #{interval := timeout(), label := iodata()}
}).

-define(HEARTBEAT_MSG, {?MODULE, heartbeat}).
-define(DEFAULT_HEARTBEAT_LABEL, <<"heartbeat">>).

-spec init(cowboy_req:req(), options()) -> {cowboy_loop, cowboy_req:req(), #state{}}.
init(Req0, Options) ->
    Headers = maps:get(headers, Options, #{}),
    Stream = {space_cowboy_sse, Req} = space_cowboy_sse:start(Req0, Headers),
    State0 = #state{
        stream = Stream,
        info_fun = maps:get(info, Options, undefined),
        heartbeat = heartbeat_options(maps:get(heartbeat, Options, undefined))
    },
    State = case maps:get(init, Options, undefined) of
        undefined ->
            State0;
        InitFun ->
            normalize_init_result(InitFun(Req0, Stream), State0)
    end,
    {cowboy_loop, Req, schedule_heartbeat(State)}.

-spec info(term(), cowboy_req:req(), #state{}) ->
    {ok, cowboy_req:req(), #state{}} | {stop, cowboy_req:req(), #state{}}.
info(?HEARTBEAT_MSG, Req, State0 = #state{stream = Stream}) ->
    ok = space_cowboy_sse:heartbeat(Stream, heartbeat_label(State0)),
    {ok, Req, schedule_heartbeat(State0)};
info(_Message, Req, State0 = #state{info_fun = undefined}) ->
    {ok, Req, State0};
info(Message, Req, State0 = #state{stream = Stream, app_state = AppState0, info_fun = InfoFun}) ->
    case normalize_info_result(InfoFun(Message, Stream, AppState0), State0) of
        {ok, State} -> {ok, Req, State};
        {stop, State} ->
            ok = space_cowboy_sse:finish(Stream),
            {stop, Req, State}
    end.

-spec terminate(term(), cowboy_req:req(), #state{}) -> ok.
terminate(_Reason, _Req, _State) ->
    ok.

normalize_init_result({ok, AppState}, State) ->
    State#state{app_state = AppState};
normalize_init_result({ok, AppState, _Timeout}, State) ->
    State#state{app_state = AppState};
normalize_init_result(AppState, State) ->
    State#state{app_state = AppState}.

normalize_info_result(ok, State) ->
    {ok, State};
normalize_info_result(stop, State) ->
    {stop, State};
normalize_info_result({ok, AppState}, State) ->
    {ok, State#state{app_state = AppState}};
normalize_info_result({ok, AppState, _Timeout}, State) ->
    {ok, State#state{app_state = AppState}};
normalize_info_result({stop, AppState}, State) ->
    {stop, State#state{app_state = AppState}};
normalize_info_result(AppState, State) ->
    {ok, State#state{app_state = AppState}}.

heartbeat_options(undefined) ->
    undefined;
heartbeat_options(Interval) when is_integer(Interval), Interval > 0 ->
    #{interval => Interval, label => ?DEFAULT_HEARTBEAT_LABEL};
heartbeat_options(infinity) ->
    undefined;
heartbeat_options(Options = #{interval := Interval}) when Interval =:= infinity ->
    Options#{label => maps:get(label, Options, ?DEFAULT_HEARTBEAT_LABEL)};
heartbeat_options(Options = #{interval := Interval}) when is_integer(Interval), Interval > 0 ->
    Options#{label => maps:get(label, Options, ?DEFAULT_HEARTBEAT_LABEL)}.

schedule_heartbeat(State = #state{heartbeat = undefined}) ->
    State;
schedule_heartbeat(State = #state{heartbeat = #{interval := infinity}}) ->
    State;
schedule_heartbeat(State = #state{heartbeat = #{interval := Interval}}) ->
    _ = erlang:send_after(Interval, self(), ?HEARTBEAT_MSG),
    State.

heartbeat_label(#state{heartbeat = #{label := Label}}) ->
    Label.
