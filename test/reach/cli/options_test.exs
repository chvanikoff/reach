defmodule Reach.CLI.OptionsTest do
  use ExUnit.Case, async: true

  alias Reach.CLI.Options

  test "parses valid options and positional args" do
    assert Options.parse(["--format", "json", "lib"], format: :string) ==
             {[format: "json"], ["lib"]}
  end

  test "raises on unknown long options" do
    assert_raise Mix.Error, ~r/Unknown option\(s\): --strcit/, fn ->
      Options.parse(["--strcit"], strict: :boolean)
    end
  end

  test "raises on unknown short options" do
    assert_raise Mix.Error, ~r/Unknown option\(s\): -z/, fn ->
      Options.parse(["-z"], [format: :string], f: :format)
    end
  end
end
