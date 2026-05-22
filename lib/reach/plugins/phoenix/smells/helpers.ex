defmodule Reach.Plugins.Phoenix.Smells.Helpers do
  @moduledoc false

  def mount_findings(project, findings_fun) when is_function(findings_fun, 1) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :function_def, meta: %{name: :mount, arity: 3}} = function} ->
        findings_fun.(function)

      _entry ->
        []
    end)
  end
end
