defmodule Reach.CLI.FormatTest do
  use ExUnit.Case, async: true

  alias Reach.CLI.Format

  test "location_text formats map locations" do
    assert Format.location_text(%{file: "lib/demo.ex", line: 12}) =~ "lib/demo.ex:12"
    assert Format.location_text(%{file: "lib/demo.ex", line: 12, column: 4}) =~ "lib/demo.ex:12"
    assert Format.location_text(%{file: "lib/demo.ex", start_line: 7}) =~ "lib/demo.ex:7"
  end
end
