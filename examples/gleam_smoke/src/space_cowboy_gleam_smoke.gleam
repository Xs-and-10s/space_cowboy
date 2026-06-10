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
