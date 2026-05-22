defmodule Reach.Plugins.ExUnit.Smells.AsyncGlobalState do
  @moduledoc "Detects async ExUnit modules that mutate global process/application state."

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def kinds, do: [:ex_unit_async_global_state]

  defp scan_ast(ast, file) do
    ast
    |> Helpers.ast_modules_in_file()
    |> Enum.flat_map(&findings_for_module(&1, file))
  end

  defp findings_for_module(module_ast, file) do
    if async_ex_unit_module?(module_ast) do
      module_ast
      |> global_mutations()
      |> Enum.map(fn {meta, call} -> finding(file, meta, call) end)
    else
      []
    end
  end

  defp async_ex_unit_module?(module_ast) do
    module_ast
    |> module_body()
    |> statements()
    |> Enum.any?(&async_ex_unit_use?/1)
  end

  defp module_body({:defmodule, _meta, [_name, body]}) when is_list(body) do
    Keyword.get(body, :do) ||
      Enum.find_value(body, fn
        {{:__block__, _meta, [:do]}, value} -> value
        _entry -> nil
      end)
  end

  defp module_body(_module), do: nil

  defp statements({:__block__, _meta, statements}) when is_list(statements), do: statements
  defp statements(nil), do: []
  defp statements(statement), do: [statement]

  defp async_ex_unit_use?({:use, _meta, [{:__aliases__, _alias_meta, [:ExUnit, :Case]}, opts]}) do
    option_value(opts, :async) == true
  end

  defp async_ex_unit_use?({:use, _meta, [{:__aliases__, _alias_meta, [:ExUnit, :Case]}]}),
    do: false

  defp async_ex_unit_use?(_statement), do: false

  defp option_value(opts, key) when is_list(opts) do
    Enum.find_value(opts, fn
      {{:__block__, _meta, [^key]}, value} -> literal(value)
      {^key, value} -> literal(value)
      _entry -> nil
    end)
  end

  defp option_value(_opts, _key), do: nil

  defp literal({:__block__, _meta, [value]}), do: value
  defp literal(value), do: value

  defp global_mutations(ast) do
    {_ast, mutations} =
      Macro.prewalk(ast, [], fn node, mutations ->
        case global_mutation(node) do
          nil -> {node, mutations}
          mutation -> {node, [mutation | mutations]}
        end
      end)

    Enum.reverse(mutations)
  end

  defp global_mutation(
         {{:., meta, [{:__aliases__, _alias_meta, [:Application]}, function]}, _call_meta, _args}
       )
       when function in [:put_env, :delete_env, :put_all_env] do
    {meta, "Application.#{function}"}
  end

  defp global_mutation({{:., meta, [module, :put]}, _call_meta, _args}) do
    if literal(module) == :persistent_term, do: {meta, ":persistent_term.put"}
  end

  defp global_mutation(
         {{:., meta, [{:__aliases__, _alias_meta, [:System]}, function]}, _call_meta, _args}
       )
       when function in [:put_env, :delete_env] do
    {meta, "System.#{function}"}
  end

  defp global_mutation(_node), do: nil

  defp finding(file, meta, call) do
    Finding.new(
      kind: :ex_unit_async_global_state,
      message:
        "async ExUnit test mutates global state with #{call}; use async: false or isolate the state",
      location: %{file: file, line: meta[:line] || 0, column: meta[:column]}
    )
  end
end
