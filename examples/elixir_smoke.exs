event =
  :datastar_beam.patch_signals(%{
    "message" => "Hello from Elixir"
  })

IO.puts(IO.iodata_to_binary(event))
