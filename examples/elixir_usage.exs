defmodule DataStarshipUsage do
  def main do
    print_section("patch-elements", patch_elements())
    print_section("patch-signals", patch_signals())
    print_section("execute-script", execute_script())
    print_section("read-signals", read_signals())
    print_section("property-checks", property_checks())
  end

  defp patch_elements do
    :data_starship.patch_elements(
      "<section id=\"panel\">Ready</section>",
      %{
        selector: "#panel",
        mode: :inner,
        event_id: "elixir-elements",
        retry_duration: 2_000
      }
    )
    |> IO.iodata_to_binary()
  end

  defp patch_signals do
    :data_starship.patch_signals(
      "{\"count\":42,\"message\":\"Hello from Elixir\"}",
      only_if_missing: true
    )
    |> IO.iodata_to_binary()
  end

  defp execute_script do
    :data_starship.execute_script(
      "window.ready = true;</script>",
      auto_remove: false,
      attributes: ["type=\"module\""]
    )
    |> IO.iodata_to_binary()
  end

  defp read_signals do
    {:ok, signals} =
      :data_starship.read_signals(
        "GET",
        "datastar=%7B%22count%22%3A41%2C%22message%22%3A%22Launch%22%7D",
        ""
      )

    "count=#{signals["count"]}; message=#{signals["message"]}"
  end

  defp property_checks do
    option_cases = [
      {%{selector: "#items", mode: :append}, [selector: "#items", mode: :append]},
      {%{event_id: "evt-1", retry_duration: 2_500}, [event_id: "evt-1", retry_duration: 2_500]},
      {%{only_if_missing: true}, [only_if_missing: true]}
    ]

    Enum.each(option_cases, fn {map_opts, proplist_opts} ->
      assert_equal(
        :data_starship.patch_elements("<li>Dock</li>", map_opts),
        :data_starship.patch_elements("<li>Dock</li>", proplist_opts)
      )

      assert_equal(
        :data_starship.patch_signals("{\"ready\":true}", map_opts),
        :data_starship.patch_signals("{\"ready\":true}", proplist_opts)
      )
    end)

    Enum.each(["", "A", "A & B", "Line 1\\nLine 2"], fn value ->
      json = "{\"value\":\"#{escape_json(value)}\"}"
      query = "datastar=#{percent_encode(json)}"
      expected = %{"value" => value}
      {:ok, ^expected} = :data_starship.read_signals(:get, query, "")
    end)

    "ok"
  end

  defp assert_equal(left, right) do
    unless IO.iodata_to_binary(left) == IO.iodata_to_binary(right) do
      raise "expected values to match"
    end
  end

  defp escape_json(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
    |> String.replace("\n", "\\n")
  end

  defp percent_encode(value) do
    value
    |> String.to_charlist()
    |> Enum.map(&percent_encode_char/1)
    |> IO.iodata_to_binary()
  end

  defp percent_encode_char(char)
       when (char >= ?a and char <= ?z) or
              (char >= ?A and char <= ?Z) or
              (char >= ?0 and char <= ?9) or
              char in [?-, ?., ?_, ?~] do
    <<char>>
  end

  defp percent_encode_char(char) do
    "%" <> Base.encode16(<<char>>)
  end

  defp print_section(name, body) do
    IO.puts("-- #{name} --")
    IO.puts(body)
  end
end

DataStarshipUsage.main()
