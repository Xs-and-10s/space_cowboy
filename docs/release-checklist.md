# Release Checklist

This repository is the development umbrella for two publishable pieces:

- `datastar_beam`: portable, web-server-neutral Datastar SDK core.
- `space_cowboy`: Cowboy adapter and Datastar-first mini-framework.

## Publish Order

1. Publish or extract `datastar_beam` first.
2. Publish `space_cowboy` after it depends on the released `datastar_beam`
   package.
3. Keep Datastar Pro files local-only. The Pro smoke example must never publish
   or vendor licensed assets.

## Metadata Preflight

Before publishing:

- Confirm both OTP app files have a version, description, license, and GitHub
  link.
- Confirm `datastar_beam` runtime applications are only `kernel` and `stdlib`.
- Confirm `space_cowboy` runtime applications include `cowboy`, `ranch`, and
  `datastar_beam`.
- Confirm the root `LICENSE` is MIT.
- Confirm `.local/` is ignored.
- Confirm all tests pass:

```sh
rebar3 eunit
rebar3 as quic eunit
```

## Datastar Beam Package

Package name: `datastar_beam`

Current version: `0.1.0`

Publication contents:

- `apps/datastar_beam/src/datastar_beam.erl`
- `apps/datastar_beam/src/datastar_beam.app.src`
- `apps/datastar_beam/test/*`
- `examples/elixir_smoke.exs`
- `examples/elixir_usage.exs`
- `examples/gleam_smoke` modules that only call `datastar_beam`
- `docs/datastar-beam-api.md`
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

After `datastar_beam` is extracted, update `space_cowboy` to depend on the
published Hex package instead of the umbrella app path.
