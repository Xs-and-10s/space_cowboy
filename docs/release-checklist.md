# Release Checklist

This repository is the development umbrella for two publishable pieces:

- `data_starship`: portable, web-server-neutral Datastar SDK core.
- `space_cowboy`: Cowboy adapter and Datastar-first mini-framework.

## Publish Order

1. Publish or extract `data_starship` first.
2. Publish `space_cowboy` after it depends on the released `data_starship`
   package.
3. Keep Datastar Pro files local-only. The Pro smoke example must never publish
   or vendor licensed assets.

## Metadata Preflight

Before publishing:

- Confirm both OTP app files have a version, description, license, and GitHub
  link.
- Confirm `data_starship` runtime applications are only `kernel` and `stdlib`.
- Confirm `space_cowboy` runtime applications include `cowboy`, `ranch`, and
  `data_starship`.
- Confirm the root `LICENSE` is MIT.
- Confirm `.local/` is ignored.
- Confirm all tests pass:

```sh
rebar3 eunit
rebar3 as quic eunit
```

## Data Starship Package

Package name: `data_starship`

Current version: `0.1.0`

Publication contents:

- `apps/data_starship/src/data_starship.erl`
- `apps/data_starship/src/data_starship.app.src`
- `apps/data_starship/test/*`
- `examples/elixir_smoke.exs`
- `examples/elixir_usage.exs`
- `examples/gleam_smoke` modules that only call `data_starship`
- `docs/data-starship-api.md`
- `docs/sdk-adr-plan.md`
- `LICENSE`

Do not include:

- Cowboy or Space Cowboy modules.
- Datastar Pro files.
- `.local/` contents.

## Space Cowboy Package

Package name: `space_cowboy`

Current version: `0.1.0`

Publication contents:

- `apps/space_cowboy/src/*`
- `apps/space_cowboy/test/*`
- `examples/basic`
- `examples/elixir_smoke.exs`
- `examples/gleam_smoke`
- `examples/pro_smoke` without `.local/` assets
- `docs/*`
- `LICENSE`

Do not include:

- `.local/` contents.
- Datastar Pro bundle files.
- Generated build directories.

## Post-Split Follow-Up

After `data_starship` is extracted, update `space_cowboy` to depend on the
published Hex package instead of the umbrella app path.
