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

```erlang
start() ->
    application:ensure_all_started(space_cowboy),
    space_cowboy:start_clear([
        {"/", fun home/1},
        {"/ping", fun ping/1}
    ], #{port => 8080}).
```

## Research And Plan

- [Datastar 1.0 research notes](docs/datastar-1.0-research.md)
- [ADR-compliant SDK plan](docs/sdk-adr-plan.md)
- [Space Cowboy framework plan](docs/space-cowboy-plan.md)

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

The optional QUIC EUnit smoke opens UDP sockets and may need to run outside
restricted sandboxes:

```sh
rebar3 as quic eunit
```
