# Datastar 1.0 Research Notes

Datastar is a hypermedia-first frontend framework centered on two ideas:

1. The backend can patch DOM elements and frontend signals.
2. The frontend can declare reactive behavior using `data-*` attributes and Datastar expressions.

## Frontend Model

- `data-bind` creates two-way bindings for inputs and web components.
- `data-text`, `data-show`, `data-class`, `data-attr`, and `data-style` project signal values into the DOM.
- `data-signals` patches signal state from markup. JSON is valid because it is a subset of Datastar object expressions.
- `data-computed` creates read-only derived signals.
- `data-effect`, `data-init`, `data-on`, `data-on-intersect`, `data-on-interval`, and `data-on-signal-patch` express lifecycle and event side effects.
- Modifiers use `__`, for example `data-on:input__debounce.200ms`, `data-on:keydown__window`, and `data-bind:checked__prop.checked`.
- Signal names beginning with `_` are private by default and are not included in backend requests unless `filterSignals` is changed.

## Backend Model

Datastar backend actions are expression helpers such as `@get()`, `@post()`, `@put()`, `@patch()`, and `@delete()`. Responses are interpreted by content type:

- `text/event-stream`: Datastar SSE events.
- `text/html`: patch elements directly, with optional Datastar response headers.
- `application/json`: patch signals directly, with JSON merge patch semantics.
- `text/javascript`: execute script, with optional script attributes.

SSE is the most capable response mode because one request can patch elements, patch signals, and execute scripts in order over a long-lived stream.

## SSE Events

Datastar 1.0 uses these core SSE event types:

- `datastar-patch-elements`
- `datastar-patch-signals`

`datastar-patch-elements` data lines include `elements`, plus optional `selector`, `mode`, `namespace`, `useViewTransition`, and `viewTransitionSelector`.

`datastar-patch-signals` data lines include `signals`, plus optional `onlyIfMissing`.

The SDK ADR also specifies `execute_script` as sugar over `datastar-patch-elements` by appending a `<script>` tag to `body`.

## Examples Survey

The examples emphasize a small set of repeatable server patterns:

- Active search: debounce input, bind query into signals, request filtered HTML.
- Click-to-edit/load/delete/update: server returns replacement elements.
- Infinite/progressive/lazy loading: append/prepend patches and indicators.
- Inline validation/forms/file upload: bound signals or form data submitted to the server.
- Progress bars and DB monitors: streaming SSE with repeated signal/element patches.
- Custom events, event bubbling, sortable, web components: use `data-on` and native DOM events.
- SVG morphing: set the patch namespace.
- Pro examples: Rocket components for reusable UI, data visualization, maps, projection, QR codes, and virtual scrolling.

## How-To Survey

The current how-to set covers:

- Key-specific `data-on:keydown` handlers using `evt`.
- Keeping Datastar code DRY with reusable markup or helpers.
- Loading more list items with append patches.
- Polling with interval-triggered backend actions.
- Keeping SSE connections open with heartbeat/comments/events.
- Redirecting from the backend, typically by executing script or patching location-changing behavior.

## Datastar Pro

Datastar Pro is licensed separately and cannot be redistributed in this OSS repo. Space Cowboy should integrate with it by configuration and conventions, not by vendoring Pro assets.

Friendly Pro support should include:

- `space_cowboy:datastar_script(Src)` for a self-hosted Pro bundle.
- Static asset mounting examples that keep Pro bundles outside public source.
- Rocket manifest endpoints for `publishRocketManifests`.
- Inspector-friendly SSE event formatting and optional dev routes.
- Documentation showing Rocket components as first-class custom elements inside ordinary Erlang/Gleam/Elixir templates.
