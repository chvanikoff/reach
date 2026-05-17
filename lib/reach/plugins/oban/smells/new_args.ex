defmodule Reach.Plugins.Oban.Smells.NewArgs do
  @moduledoc "Detects non-portable Oban job args at enqueue time."

  @behaviour Reach.Smell.Check

  alias Reach.IR
  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :module_def} = module} ->
        module_worker? = oban_worker_module?(module)

        module
        |> IR.all_nodes()
        |> Enum.flat_map(&findings_for_node(&1, module_worker?))

      _entry ->
        []
    end)
  end

  defp findings_for_node(call, module_worker?) do
    with true <- call_node?(call),
         %{function: :new} <- Map.get(call, :meta, %{}),
         [%{type: :map} = args] <- Map.get(call, :children, []) do
      findings_for_args(call, args, module_worker?)
    else
      _ -> []
    end
  end

  defp findings_for_args(call, args, module_worker?) do
    if oban_new_call?(call, module_worker?) and has_struct_value?(args) do
      [struct_finding(call)]
    else
      []
    end
  end

  defp oban_new_call?(%{meta: %{module: nil}}, true), do: true

  defp oban_new_call?(%{meta: %{module: module}}, _module_worker?) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> String.ends_with?("Worker")
  rescue
    _ -> false
  end

  defp oban_new_call?(_call, _module_worker?), do: false

  defp oban_worker_module?(module) do
    module
    |> IR.all_nodes()
    |> Enum.any?(fn
      node ->
        call_node?(node) and use_call?(node) and
          oban_worker_alias?(List.first(Map.get(node, :children, [])))
    end)
  end

  defp oban_worker_alias?(node) do
    call_node?(node) and Map.get(Map.get(node, :meta, %{}), :function) == :__aliases__ and
      Enum.map(Map.get(node, :children, []), &literal_value/1) == [:Oban, :Worker]
  end

  defp call_node?(node), do: Map.get(node, :type) == :call

  defp use_call?(node), do: Map.get(Map.get(node, :meta, %{}), :function) == :use

  defp literal_value(node) do
    if Map.get(node, :type) == :literal do
      node |> Map.get(:meta, %{}) |> Map.get(:value)
    end
  end

  defp struct_finding(call) do
    Finding.new(
      kind: :oban_struct_args,
      message: "Oban job args should contain JSON primitives; store IDs instead of structs",
      location: Helpers.location(call)
    )
  end

  defp has_struct_value?(%{type: :map, children: fields}) do
    Enum.any?(fields, fn
      %{type: :map_field, children: [_key, value]} -> contains_struct?(value)
      _field -> false
    end)
  end

  defp contains_struct?(%{type: :struct}), do: true

  defp contains_struct?(%{children: children}) when is_list(children),
    do: Enum.any?(children, &contains_struct?/1)

  defp contains_struct?(_node), do: false
end
