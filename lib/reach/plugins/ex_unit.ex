defmodule Reach.Plugins.ExUnit do
  @moduledoc "Plugin for ExUnit test-suite semantics."

  @behaviour Reach.Plugin

  @impl true
  def analyze(_all_nodes, _opts), do: []

  @impl true
  def smell_checks do
    [Reach.Plugins.ExUnit.Smells.AsyncGlobalState]
  end
end
