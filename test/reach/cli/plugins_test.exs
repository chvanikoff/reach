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
    assert Plugins.plugins(plugin: ["Reach.Plugins.Phoenix"]) == [Reach.Plugins.Phoenix]
  end

  test "preserves programmatic plugin options" do
    assert Plugins.project_opts(plugins: [Reach.Plugins.Phoenix]) == [
             plugins: [Reach.Plugins.Phoenix]
           ]
  end
end
