# Data Starship API

`data_starship` is the portable Erlang Datastar SDK core. It is intentionally
web-server-neutral and should remain extractable as its own Hex package.

## Package Boundary

- Runtime applications: `kernel`, `stdlib`.
- No Cowboy, Ranch, Plug, Mist, Elli, Space Cowboy, or other web-server
  dependencies.
- Public functions return iodata or parse request data supplied by adapters.
- Adapter packages own web-server request/response objects.

## Public API

```erlang
sse_headers/0
event/2
event/3
patch_elements/1
patch_elements/2
patch_signals/1
patch_signals/2
execute_script/1
execute_script/2
read_signals/3
```

## Dependency Snippets

Rebar3:

```erlang
{deps, [
    {data_starship, "0.1.0"}
]}.
```

Mix:

```elixir
def deps do
  [
    {:data_starship, "~> 0.1.0"}
  ]
end
```

Gleam:

```sh
gleam add data_starship
```

Gleam code can bind the Erlang module with `@external`:

```gleam
@external(erlang, "data_starship", "patch_signals")
fn patch_signals(signals: String) -> Dynamic
```

## Extraction Checklist

- Keep `apps/data_starship/src/data_starship.erl` free of adapter references.
- Keep `apps/data_starship/src/data_starship.app.src` limited to `kernel` and
  `stdlib` runtime applications.
- Keep ADR golden tests and property tests with the extracted package.
- Move the BEAM usage examples that only depend on `data_starship`:
  `examples/elixir_smoke.exs`, `examples/elixir_usage.exs`,
  `examples/gleam_smoke/src/space_cowboy_gleam_smoke.gleam`, and
  `examples/gleam_smoke/src/data_starship_usage.gleam`.
- Move Cowboy-specific helpers to `space_cowboy` or another adapter package.
- Decide the minimum OTP version before publishing. The current implementation
  uses OTP's built-in `json` module.
