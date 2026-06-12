# ADR-Compliant SDK Plan

The pure SDK should become a separate Hex package named `datastar_beam` unless naming changes before publication.

The current public API and extraction checklist live in
[`datastar-beam-api.md`](datastar-beam-api.md).

## Name

`datastar_beam` is memorable, BEAM-friendly, and adjacent to Datastar without impersonating the upstream project. It also gives us module names that work from Erlang, Elixir, and Gleam:

- Erlang: `datastar_beam:patch_elements(Html).`
- Elixir: `:datastar_beam.patch_elements(html)`
- Gleam: external functions targeting `datastar_beam`.

Alternatives worth reserving/checking before release:

- `datastar_erlang`
- `datastar_beam`
- `starship_datastar`

## Core API

Required ADR surface:

- `sse_headers/0`
- `event/2`, `event/3`
- `patch_elements/1`, `patch_elements/2`
- `patch_signals/1`, `patch_signals/2`
- `execute_script/1`, `execute_script/2`
- `read_signals/3`

The core package should stay web-server-neutral and return iodata. Adapters should handle request/response objects.

## Options

Use maps or proplists so every BEAM language can call the same functions:

```erlang
datastar_beam:patch_elements(Html, #{
    selector => <<"#feed">>,
    mode => append,
    event_id => <<"42">>,
    retry_duration => 2000
}).
```

## Cowboy Adapter

`space_cowboy_sse` is the first adapter:

- Start stream with Datastar SSE headers.
- Send any iodata event.
- Convenience wrappers for patch elements/signals/script.
- Read incoming signals from Cowboy requests.

Next adapter candidates:

- `datastar_beam_plug` for Elixir Plug/Phoenix.
- `datastar_beam_mist` for Gleam/Mist.
- `datastar_beam_elli` for pure Erlang/Elli.

## Compliance Tests

Golden tests from the ADR examples now cover:

- Event order: `event`, optional `id`, optional non-default `retry`, data lines, blank line.
- `patch_elements` default elision.
- `patch_elements` all options.
- `patch_elements` multiline HTML.
- `patch_elements` remove mode without elements.
- `patch_signals` JSON merge patch examples.
- `execute_script` auto-remove behavior.
- `read_signals` GET query and non-GET body behavior.

Property tests also cover:

- Map and proplist option parity, so Erlang, Elixir, Gleam, and other BEAM callers can use whichever shape is most natural.
- Multiline `patch_signals` payload framing.

## Ergonomics

Keep the low-level API exact and predictable, then add sugar in server-specific packages:

- Streaming helpers.
- Route helpers.
- Heartbeat helpers.
- Template integration examples.
- Dev-only Inspector/Rocket manifest endpoints.

## Compatibility

The current scaffold uses OTP's built-in `json` module. Before Hex release, decide whether the minimum OTP should be:

- OTP 27+ with built-in JSON; or
- older OTP support via optional `thoas`/`jsone`.

For broad BEAM adoption, publish with `rebar3` metadata and document Elixir and Gleam dependency snippets.
Initial dependency snippets are documented in `docs/datastar-beam-api.md`.
