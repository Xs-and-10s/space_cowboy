# Template Output In, Datastar Event Out

`data_starship` does not need to know which template engine produced your
HTML. The template engine owns HTML generation and escaping. `data_starship`
owns Datastar's SSE event framing.

The shape is always:

1. Render a complete HTML fragment with your template library.
2. Pass that rendered iodata, binary, or string to `data_starship`.
3. Send the returned iodata as a Datastar SSE event.

For a replacement patch, the event should look like this after encoding:

```text
event: datastar-patch-elements
data: selector #results
data: elements <section id="results">...</section>
```

## Elixir HEEx

HEEx function components return Phoenix rendered structs. Convert that value
with `Phoenix.HTML.Safe.to_iodata/1`, then pass the iodata directly to the
Erlang SDK.

```elixir
defmodule MyAppWeb.SearchFragments do
  use Phoenix.Component

  attr :rows, :list, required: true

  def results(assigns) do
    ~H"""
    <section id="results" data-signals={"{search: '', selected: null}"}>
      <ul>
        <li :for={row <- @rows}>
          <button data-on-click={"$selected = #{row.id}"}>
            {row.name}
          </button>
        </li>
      </ul>
    </section>
    """
  end

  def patch_results(rows) do
    html =
      %{rows: rows}
      |> results()
      |> Phoenix.HTML.Safe.to_iodata()

    :data_starship.patch_elements(html, %{
      selector: "#results",
      mode: :outer
    })
  end
end
```

`patch_results/1` returns iodata for a `datastar-patch-elements` SSE event.
Your adapter, controller, or Cowboy handler writes that iodata to the response.

## Gleam Nakai

Nakai is a good fit for server-rendered Gleam fragments because it builds HTML
nodes in Gleam and can render snippets with `nakai.to_inline_string/1`. Bind the
portable Erlang SDK with `@external` and pass Nakai's string output to it.

```gleam
import gleam/dynamic.{type Dynamic}
import gleam/list
import nakai
import nakai/attr
import nakai/html

@external(erlang, "data_starship", "patch_elements")
fn patch_elements(html: String) -> Dynamic

pub fn results(names: List(String)) -> String {
  html.section(
    [attr.id("results"), attr.data("signals", "{search: '', selected: null}")],
    [
      html.ul(
        [],
        list.map(names, fn(name) {
          html.li_text([], name)
        }),
      ),
    ],
  )
  |> nakai.to_inline_string()
}

pub fn patch_results(names: List(String)) -> Dynamic {
  names
  |> results()
  |> patch_elements()
}
```

That one-argument call emits the default Datastar element patch. If you want a
typed Gleam facade for selectors and modes, keep that facade in your Gleam app
or a thin Gleam helper package and let it call `data_starship:patch_elements/2`.

## Erlang ErlyDTL

ErlyDTL compiles Django-style templates to Erlang modules. Rendering returns
`{ok, IOList}`, which can be handed to `data_starship` without flattening.

```erlang
-module(my_search_fragments).

-export([compile/0, patch_results/1]).

compile() ->
    Template =
          <<"<section id=\"results\" data-signals=\"{search: '', selected: null}\">"
          "<ul>"
          "{% for name in names %}"
          "<li>{{ name }}</li>"
          "{% endfor %}"
          "</ul>"
          "</section>">>,
    erlydtl:compile_template(Template, my_search_results_dtl, [
        {out_dir, false}
    ]).

patch_results(Names) ->
    {ok, Html} = my_search_results_dtl:render([{names, Names}]),
    data_starship:patch_elements(Html, #{
        selector => <<"#results">>,
        mode => outer
    }).
```

In an OTP release you normally compile templates during build/startup rather
than per request. The request path should only call the compiled template's
`render/1` or `render/2` function, then pass the returned iodata into
`data_starship`.

## Contract

- Template engines own escaping and HTML validity.
- `data_starship:patch_elements/1,2` accepts rendered fragments as iodata,
  binaries, or strings.
- `data_starship` does not take dependencies on Phoenix, Nakai, ErlyDTL,
  Cowboy, Plug, Mist, Elli, or any other adapter/template package.
- Adapters decide how to write the returned iodata to HTTP, SSE, HTTP/2, or
  HTTP/3 responses.

## References

- [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html)
- [Phoenix.HTML.Safe](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Safe.html)
- [Nakai](https://hexdocs.pm/nakai/)
- [ErlyDTL](https://github.com/erlydtl/erlydtl)
