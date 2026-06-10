# space_cowboy

A Datastar-first web app server built on Cowboy, for Erlang, Gleam, Elixir,
and any other BEAM language.

This repository currently contains two OTP applications:

- `data_starship`: a portable Erlang Datastar SDK core that emits ADR-shaped
  SSE events as iodata and parses incoming Datastar signals.
- `space_cowboy`: a Cowboy adapter and mini-framework layer that treats
  Datastar and Server-Sent Events as the happy path.

## Status

Early scaffold. The SDK core is intentionally small and extractable so it can
be published later as its own Hex package.

## Quick Shape

```erlang
ping(_Req) ->
    {sse, [
        data_starship:patch_signals(#{<<"message">> => <<"Hello from Erlang">>})
    ]}.
```

Long-lived Datastar streams can use a Cowboy loop handler through the route
helper:

```erlang
events_init(_Req, Stream) ->
    space_cowboy_sse:comment(Stream, <<"open">>),
    {ok, #{}}.

events_info({progress, Percent}, Stream, State) ->
    space_cowboy_sse:patch_signals(Stream, #{<<"progress">> => Percent}),
    {ok, State};
events_info(done, Stream, State) ->
    space_cowboy_sse:heartbeat(Stream, <<"close">>),
    {stop, State}.
```

```erlang
start() ->
    application:ensure_all_started(space_cowboy),
    space_cowboy:start_clear([
        {"/", fun home/1},
        {"/ping", fun ping/1},
        {"/events", space_cowboy:sse_loop(fun events_init/2, fun events_info/3)}
    ], #{port => 8080}).
```

## Research And Plan

- [Datastar 1.0 research notes](docs/datastar-1.0-research.md)
- [ADR-compliant SDK plan](docs/sdk-adr-plan.md)
- [Space Cowboy framework plan](docs/space-cowboy-plan.md)

## Examples

The basic example in `examples/basic` demonstrates active search,
click-to-edit, a POST-backed save action, finite SSE responses, and a
long-lived progress stream built with `space_cowboy:sse_loop/1,2`.

## Optional HTTP/3 / QUIC Spike

The default build does not require QUIC. `space_cowboy:start_quic/2,3`
returns `{error, quic_unavailable}` unless Cowboy and the optional `quicer`
NIF are available.

To experiment with HTTP/3 support:

```sh
rebar3 as quic compile
```

QUIC listeners are experimental in Cowboy 2.13 and are closed with
`space_cowboy:stop_quic/1`, not `space_cowboy:stop/1`.

The optional `quicer` dependency builds msquic and requires CMake. On macOS:

```sh
brew install cmake
```

The optional QUIC EUnit smoke opens UDP sockets and includes an HTTP/3 GET
roundtrip. It may need to run outside restricted sandboxes:

```sh
rebar3 as quic eunit
```
