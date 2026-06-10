# Space Cowboy Plan

Space Cowboy should be a Datastar-first Cowboy mini-framework, not a replacement for Cowboy.

## Design Goals

- Datastar SSE is the happy path.
- Ordinary Cowboy handlers and routes still work.
- The pure SDK remains extractable as `data_starship`.
- Elixir and Gleam users can consume the Erlang modules directly.
- Pro users can opt into Rocket, Inspector, and Stellar without license leakage.

## Plug-and-Play Shape

Minimum app:

```erlang
start() ->
    application:ensure_all_started(space_cowboy),
    space_cowboy:start_clear([
        {"/", fun home/1},
        {"/search", fun search/1}
    ], #{port => 8080}).
```

Elixir can call the same modules directly:

```elixir
:data_starship.patch_signals(%{"message" => "Hello from Elixir"})
```

Gleam can bind the Erlang module with an external:

```gleam
@external(erlang, "data_starship", "patch_signals")
fn patch_signals(signals: String) -> Dynamic
```

Handlers return:

- `{html, Body}`
- `{html, Body, Headers}`
- `{json, Body}`
- `{sse, [Event]}`
- `{stream, Fun}`
- `{sse_stream, Fun}`
- `{reply, Status, Headers, Body}`
- `{ok, Req}`

`{stream, Fun}` receives a simple sender function for backwards-compatible SSE event streaming. `{sse_stream, Fun}` receives a `space_cowboy_sse` stream context and can use:

- `space_cowboy_sse:comment/2`
- `space_cowboy_sse:heartbeat/1,2`
- `space_cowboy_sse:patch_elements/2,3`
- `space_cowboy_sse:patch_signals/2,3`
- `space_cowboy_sse:execute_script/2,3`

Long-lived streams use Cowboy's loop handler protocol through
`space_cowboy:sse_loop/1,2`:

- `space_cowboy:sse_loop(InitFun, InfoFun)` turns a route into a
  `space_cowboy_loop` handler.
- `InitFun(Req, Stream)` can send initial comments/events and returns the
  initial app state.
- `InfoFun(Message, Stream, State)` handles Erlang messages and returns
  `{ok, NewState}` or `{stop, NewState}`.
- `#{heartbeat => Interval}` or
  `#{heartbeat => #{interval => Interval, label => Label}}` sends automatic
  SSE comment heartbeats while the stream remains open.

## Templating Story

Do not invent a mandatory Erlang HTML DSL yet.

Recommended layers:

- Raw iodata helpers for Erlang examples and tests.
- Adapters/examples for popular BEAM templating:
  - Elixir: HEEx/Phoenix components can output binaries consumed by `data_starship`.
  - Gleam: Lustre or Nakai-style typed views can output strings/iodata.
  - Erlang: ErlyDTL, Nitrogen/Nitro, or simple iodata.
- Optional `space_cowboy_html` helpers for escaping and attribute generation.

The key promise: any template engine that can emit complete HTML elements can work.

Current compatibility contract:

- Template output should be iodata, or a common wrapper such as `{safe, Iodata}` or `{ok, Iodata}`.
- `space_cowboy_template:to_iodata/1` normalizes those shapes.
- `space_cowboy_template:html/1` builds an HTML handler return value from rendered output.
- `space_cowboy_template:patch_elements/1,2` turns rendered fragments into Datastar patch events.
- Datastar attribute names must be preserved exactly; values should be escaped by the template engine or helper.

The conformance tests cover raw iodata and safe wrapped output over both HTML responses and SSE fragment patches.

## Pro Support

Open-source package:

- Never vendors Datastar Pro.
- Accepts configured script paths for Pro bundles.
- Provides Rocket manifest endpoints and examples.
- Provides Inspector-friendly development conventions.
- Documents Stellar as CSS/assets the app owner serves.

Current helpers:

- `space_cowboy_rocket:component/2,3`
- `space_cowboy_rocket:manifest_endpoint/1,2`

Future helpers:

- `space_cowboy_dev:inspector_headers/0`
- `space_cowboy_static:priv_dir/2`

## HTTP/3 / QUIC

Start with Cowboy HTTP/1.1 and HTTP/2 because SSE and Datastar work there today with stable Cowboy APIs.

Add HTTP/3 behind capability detection:

- Prefer Cowboy-native QUIC support when available in the pinned Cowboy version.
- Otherwise evaluate `quicer`/`erlang_quic` as an optional dependency.
- Keep QUIC optional so the pure SDK and basic HTTP server remain easy to install.

Current spike shape:

- `space_cowboy:start_quic/2,3` mirrors `start_clear/2,3` and uses the same route specs.
- `space_cowboy:stop_quic/1` closes the returned quicer listener handle.
- `space_cowboy:quic_available/0` reports whether the optional `quicer` app is available.
- Without QUIC support, `start_quic/2,3` returns `{error, quic_unavailable}` instead of crashing.
- Cowboy 2.13 marks `cowboy:start_quic/3` experimental and requires Cowboy to be compiled with `COWBOY_QUICER` plus the `quicer` NIF.
- The `quic` profile appends `COWBOY_QUICER` to Cowboy's compile flags and the optional test suite now verifies listener startup, QUIC handshake, and HTTP/3 GET route roundtrips.

## Next Implementation Milestones

1. Split `data_starship` into its own repository/package.
2. Fill ADR golden tests.
3. Add richer long-lived SSE examples using the Cowboy loop handler.
4. Expand the basic example into active search, click-to-edit, POST-backed save, and progress streaming.
5. Add Elixir and Gleam smoke projects that import the same Erlang package.
6. Publish docs with side-by-side Erlang, Elixir, and Gleam usage.
