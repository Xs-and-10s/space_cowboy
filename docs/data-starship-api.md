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
action/2
action/3
get/1
get/2
post/1
post/2
put/1
put/2
patch/1
patch/2
delete/1
delete/2
patch_elements/1
patch_elements/2
remove_elements/1
remove_elements/2
patch_signals/1
patch_signals/2
remove_signals/1
remove_signals/2
execute_script/1
execute_script/2
redirect/1
redirect/2
console_log/1
console_log/2
read_signals/3
```

## Convenience Helpers

The core helpers stay web-server-neutral and return iodata:

- `remove_elements/1,2` emits a `datastar-patch-elements` event with
  `mode remove`.
- `remove_signals/1,2` converts dot-notated paths such as
  `<<"user.profile.theme">>` into nested JSON null patches.
- `redirect/1,2` and `console_log/1,2` are script-patch helpers built on top of
  `execute_script/1,2`.
- `action/2,3` and the verb helpers `get/1,2`, `post/1,2`, `put/1,2`,
  `patch/1,2`, and `delete/1,2` build Datastar frontend action expressions
  such as `@post('/counter/increment')`.
- HTML arguments may be raw iodata/binaries/strings or common safe wrappers
  such as `{safe, Iodata}` and `{ok, Iodata}`.

Options accept both the ADR-style keys already used by Data Starship and common
Datastar package aliases where they do not change behavior:

- `retry_duration` or `retry`
- `use_view_transition` or `use_view_transitions`

`execute_script/2` accepts either trusted attribute snippets:

```erlang
data_starship:execute_script(<<"run()">>, #{
    attributes => [<<"type=\"module\"">>]
}).
```

or an attribute map whose values are HTML-attribute escaped:

```erlang
data_starship:execute_script(<<"run()">>, #{
    attributes => #{<<"type">> => <<"module">>}
}).
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

## Templates

`data_starship` is template-engine-neutral. HEEx, Nakai, ErlyDTL, and other
BEAM template libraries should render HTML first; then callers pass that
rendered iodata, binary, or string to `data_starship:patch_elements/1,2`.

See [Template Output In, Datastar Event Out](templating.md) for HEEx, Nakai,
and ErlyDTL examples.

## Extraction Checklist

- Keep `apps/data_starship/src/data_starship.erl` free of adapter references.
- Keep `apps/data_starship/src/data_starship.app.src` limited to `kernel` and
  `stdlib` runtime applications.
- Keep ADR golden tests and property tests with the extracted package.
- Keep template examples as docs or optional examples, not runtime
  dependencies of the SDK core.
- Move the BEAM usage examples that only depend on `data_starship`:
  `examples/elixir_smoke.exs`, `examples/elixir_usage.exs`,
  `examples/gleam_smoke/src/space_cowboy_gleam_smoke.gleam`, and
  `examples/gleam_smoke/src/data_starship_usage.gleam`.
- Move Cowboy-specific helpers to `space_cowboy` or another adapter package.
- Decide the minimum OTP version before publishing. The current implementation
  uses OTP's built-in `json` module.
