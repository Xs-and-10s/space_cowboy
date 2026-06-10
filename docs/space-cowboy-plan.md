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
- `{reply, Status, Headers, Body}`
- `{ok, Req}`

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

## Pro Support

Open-source package:

- Never vendors Datastar Pro.
- Accepts configured script paths for Pro bundles.
- Provides Rocket manifest endpoints and examples.
- Provides Inspector-friendly development conventions.
- Documents Stellar as CSS/assets the app owner serves.

Future helpers:

- `space_cowboy_rocket:manifest_endpoint/1`
- `space_cowboy_rocket:component/2`
- `space_cowboy_dev:inspector_headers/0`
- `space_cowboy_static:priv_dir/2`

## HTTP/3 / QUIC

Start with Cowboy HTTP/1.1 and HTTP/2 because SSE and Datastar work there today with stable Cowboy APIs.

Add HTTP/3 behind capability detection:

- Prefer Cowboy-native QUIC support when available in the pinned Cowboy version.
- Otherwise evaluate `quicer`/`erlang_quic` as an optional dependency.
- Keep QUIC optional so the pure SDK and basic HTTP server remain easy to install.

## Next Implementation Milestones

1. Split `data_starship` into its own repository/package.
2. Fill ADR golden tests.
3. Add Cowboy loop handler for long-lived SSE and heartbeats.
4. Add a real example app for active search, click-to-edit, and progress streaming.
5. Add Elixir and Gleam smoke projects that import the same Erlang package.
6. Publish docs with side-by-side Erlang, Elixir, and Gleam usage.
