import gleam/dynamic.{type Dynamic}
import gleam/io

@external(erlang, "data_starship", "patch_elements")
fn patch_elements(elements: String) -> Dynamic

@external(erlang, "data_starship", "patch_signals")
fn patch_signals(signals: String) -> Dynamic

@external(erlang, "data_starship", "execute_script")
fn execute_script(script: String) -> Dynamic

@external(erlang, "erlang", "iolist_to_binary")
fn iolist_to_binary(iodata: Dynamic) -> String

pub fn main() {
  let elements =
    patch_elements("<section id=\"panel\">Hello from Gleam</section>")
    |> iolist_to_binary

  let signals =
    patch_signals("{\"message\":\"Hello from Gleam\",\"count\":7}")
    |> iolist_to_binary

  let script =
    execute_script("window.gleamReady = true;</script>")
    |> iolist_to_binary

  assert_equal(
    "patch-elements",
    elements,
    "event: datastar-patch-elements\n"
    <> "data: elements <section id=\"panel\">Hello from Gleam</section>\n\n",
  )

  assert_equal(
    "patch-signals",
    signals,
    "event: datastar-patch-signals\n"
    <> "data: signals {\"message\":\"Hello from Gleam\",\"count\":7}\n\n",
  )

  assert_equal(
    "execute-script",
    script,
    "event: datastar-patch-elements\n"
    <> "data: selector body\n"
    <> "data: mode append\n"
    <> "data: elements <script data-effect=\"el.remove()\">window.gleamReady = true;<\\/script></script>\n\n",
  )

  property_check("{\"value\":\"\"}")
  property_check("{\"value\":\"A\"}")
  property_check("{\"value\":\"A & B\"}")
  property_check("{\"value\":\"Line 1\\nLine 2\"}")

  print_section("patch-elements", elements)
  print_section("patch-signals", signals)
  print_section("execute-script", script)
  print_section("property-checks", "ok")
}

fn property_check(json: String) {
  let actual =
    patch_signals(json)
    |> iolist_to_binary

  let expected =
    "event: datastar-patch-signals\n"
    <> "data: signals "
    <> json
    <> "\n\n"

  assert_equal("property-check", actual, expected)
}

fn assert_equal(name: String, actual: String, expected: String) {
  case actual == expected {
    True -> Nil
    False -> panic as name
  }
}

fn print_section(name: String, body: String) {
  io.println("-- " <> name <> " --")
  io.println(body)
}
