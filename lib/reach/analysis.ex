defmodule Reach.Analysis do
  @moduledoc "Shared analysis helpers for project-wide queries."

  alias Reach.IR.Node

  @effect_boundary_callbacks [
    {:start, 2},
    {:init, 1},
    {:handle_call, 3},
    {:handle_cast, 2},
    {:handle_info, 2},
    {:handle_continue, 2},
    {:terminate, 2},
    {:code_change, 3},
    {:start_link, 1},
    {:child_spec, 1}
  ]

  def expected_effect_boundary?(func, plugins \\ []) do
    module = func.meta[:module]
    function = func.meta[:name]
    arity = func.meta[:arity]

    {function, arity} in @effect_boundary_callbacks or
      Reach.Plugin.expected_effect_boundary?(plugins, module, function, arity) or
      mix_task_module?(module) or
      mix_task_file?(func.source_span)
  end

  defp mix_task_module?(nil), do: false

  defp mix_task_module?(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> case do
      ["Elixir", "Mix", "Tasks" | _] -> true
      ["Mix", "Tasks" | _] -> true
      _parts -> false
    end
  end

  defp mix_task_module?(_module), do: false

  defp mix_task_file?(nil), do: false
  defp mix_task_file?(%{file: file}), do: String.starts_with?(file || "", "lib/mix/tasks/")

  def data_edge?(%Graph.Edge{label: {:data, _}}), do: true

  def data_edge?(%Graph.Edge{label: label})
      when label in [:parameter_in, :parameter_out, :summary],
      do: true

  def data_edge?(_edge), do: false

  def value_edge?(%Graph.Edge{label: label}) when label in [:containment, :match_binding],
    do: true

  def value_edge?(edge), do: data_edge?(edge)

  def call_target(%Node{children: [target | _]}) do
    case target do
      %Node{type: :literal, meta: %{value: mod}} when is_atom(mod) ->
        mod

      %Node{type: :var, meta: %{name: name}} ->
        name

      %Node{type: :call, meta: %{function: :__aliases__}, children: parts} ->
        module_alias(parts)

      _ ->
        nil
    end
  end

  def call_target(_node), do: nil

  def module_alias(parts) do
    atoms =
      Enum.map(parts, fn
        %{type: :literal, meta: %{value: value}} when is_atom(value) -> value
        _node -> nil
      end)

    if Enum.all?(atoms, & &1), do: Module.concat(atoms)
  end

  def location(%{source_span: %{file: file, start_line: line}}), do: "#{file}:#{line}"
  def location(%{source_span: %{start_line: line}}), do: "line #{line}"
  def location(_node), do: "unknown"
end
