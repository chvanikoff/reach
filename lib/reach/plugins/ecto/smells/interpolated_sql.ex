defmodule Reach.Plugins.Ecto.Smells.InterpolatedSQL do
  @moduledoc "Detects string interpolation in Ecto SQL fragments and raw queries."

  use Reach.Smell.ASTCheck

  alias Reach.Smell.Finding

  @impl true
  def kinds, do: [:ecto_interpolated_fragment, :ecto_interpolated_repo_query]

  defp scan_ast(ast, file) do
    find_interpolated_sql(ast, file)
  end

  defp find_interpolated_sql(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, findings ->
        case interpolated_sql_finding(node, file) do
          nil -> {node, findings}
          finding -> {node, [finding | findings]}
        end
      end)

    Enum.reverse(findings)
  end

  defp interpolated_sql_finding({:fragment, meta, [sql | _args]}, file) do
    if interpolated_binary?(sql), do: fragment_finding(file, meta)
  end

  defp interpolated_sql_finding({{:., meta, [module_ast, function]}, _call_meta, args}, file)
       when function in [:query, :query!] do
    cond do
      repo_module?(module_ast) and first_arg_interpolated?(args) ->
        repo_query_finding(file, meta, function)

      ecto_adapters_sql_module?(module_ast) and second_arg_interpolated?(args) ->
        repo_query_finding(file, meta, function)

      true ->
        nil
    end
  end

  defp interpolated_sql_finding(_node, _file), do: nil

  defp first_arg_interpolated?([sql | _args]), do: interpolated_binary?(sql)
  defp first_arg_interpolated?(_args), do: false

  defp second_arg_interpolated?([_repo, sql | _args]), do: interpolated_binary?(sql)
  defp second_arg_interpolated?(_args), do: false

  defp interpolated_binary?({:<<>>, _meta, parts}) do
    Enum.any?(parts, &match?({:"::", _, _}, &1))
  end

  defp interpolated_binary?(_ast), do: false

  defp repo_module?(module_ast) do
    module_ast
    |> alias_parts()
    |> case do
      [] -> false
      parts -> List.last(parts) == :Repo
    end
  end

  defp ecto_adapters_sql_module?(module_ast) do
    alias_parts(module_ast) == [:Ecto, :Adapters, :SQL]
  end

  defp alias_parts({:__aliases__, _meta, parts}), do: parts
  defp alias_parts(_ast), do: []

  defp fragment_finding(file, meta) do
    Finding.new(
      kind: :ecto_interpolated_fragment,
      message:
        "SQL fragment uses string interpolation; use fragment placeholders and pinned parameters instead",
      location: location(file, meta)
    )
  end

  defp repo_query_finding(file, meta, function) do
    Finding.new(
      kind: :ecto_interpolated_repo_query,
      message: "Repo.#{function} uses string interpolation; use parameterized queries instead",
      location: location(file, meta)
    )
  end

  defp location(file, meta), do: "#{file}:#{meta[:line] || 0}"
end
