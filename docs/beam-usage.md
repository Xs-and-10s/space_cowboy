# BEAM Usage

Space Cowboy is written in portable Erlang so Erlang, Elixir, Gleam, and other
BEAM languages can call the same modules.

## Erlang

```erlang
Event = data_starship:patch_signals(#{<<"message">> => <<"Hello from Erlang">>}),
io:put_chars(iolist_to_binary(Event)).
```

Cowboy routes can use the higher-level `space_cowboy` return values:

```erlang
ping(_Req) ->
    {sse, [
        data_starship:patch_signals(#{<<"message">> => <<"Hello from Erlang">>})
    ]}.
```

## Elixir

Elixir can call the Erlang module directly. When working from this repository,
the smoke script can run against the compiled `data_starship` beam files:

```sh
elixir -pa _build/default/lib/data_starship/ebin examples/elixir_smoke.exs
```

<!-- BEGIN: elixir-smoke -->
```elixir
event =
  :data_starship.patch_signals(%{
    "message" => "Hello from Elixir"
  })

IO.puts(IO.iodata_to_binary(event))
```
<!-- END: elixir-smoke -->

For a broader example with golden-style output and property-style checks over
options and signal parsing, see `examples/elixir_usage.exs`.

## Gleam

Gleam can bind the same Erlang module with `@external`. When working from this
repository, the smoke project can run with `ERL_FLAGS` pointing at the compiled
`data_starship` beam files:

```sh
cd examples/gleam_smoke
ERL_FLAGS='-pa ../../_build/default/lib/data_starship/ebin' gleam run
```

<!-- BEGIN: gleam-smoke -->
```gleam
import gleam/dynamic.{type Dynamic}
import gleam/io

@external(erlang, "data_starship", "patch_signals")
fn patch_signals(signals: String) -> Dynamic

@external(erlang, "erlang", "iolist_to_binary")
fn iolist_to_binary(iodata: Dynamic) -> String

pub fn main() {
  patch_signals("{\"message\":\"Hello from Gleam\"}")
  |> iolist_to_binary
  |> io.println
}
```
<!-- END: gleam-smoke -->

For a broader example with golden-style output and property-style checks over
signal event generation, see
`examples/gleam_smoke/src/data_starship_usage.gleam`.

## Shared Contract

For all BEAM languages:

- SDK functions return iodata.
- Options can be maps or proplists.
- Web-server-neutral functions live in `data_starship`.
- Cowboy route helpers live in `space_cowboy`.
- Template libraries only need to emit complete HTML fragments as iodata,
  strings, or common wrappers such as `{safe, Iodata}` / `{ok, Iodata}`.
  See `docs/templating.md` for HEEx, Nakai, and ErlyDTL examples.
