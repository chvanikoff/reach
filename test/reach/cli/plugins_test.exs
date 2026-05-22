defmodule Reach.CLI.PluginsTest do
  use ExUnit.Case, async: true

  alias Reach.CLI.Plugins

  test "resolves short plugin names" do
    assert Plugins.plugins(plugin: ["Phoenix", "Ecto"]) == [
             Reach.Plugins.Phoenix,
             Reach.Plugins.Ecto
           ]
  end

  test "resolves fully qualified plugin modules" do
    Code.ensure_loaded!(Reach.Plugins.Phoenix)

    assert Plugins.plugins(plugin: ["Reach.Plugins.Phoenix"]) == [Reach.Plugins.Phoenix]
  end

  test "preserves programmatic plugin options" do
    assert Plugins.project_opts(plugins: [Reach.Plugins.Phoenix]) == [
             plugins: [Reach.Plugins.Phoenix]
           ]
  end

  test "rejects unknown plugin names without creating requested atoms" do
    plugin_name =
      "Elixir.Reach.CLI.PluginsTest.UnknownPlugin#{System.unique_integer([:positive])}"

    assert_raise Mix.Error, fn ->
      Plugins.plugins(plugin: [plugin_name])
    end

    assert_raise ArgumentError, fn ->
      String.to_existing_atom(plugin_name)
    end
  end
end
