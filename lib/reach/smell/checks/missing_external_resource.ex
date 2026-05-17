defmodule Reach.Smell.Checks.MissingExternalResource do
  @moduledoc "Detects compile-time file reads without matching @external_resource declarations."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Source

  @impl true
  def run(project) do
    project
    |> Source.module_files()
    |> Enum.flat_map(&scan_file/1)
  end

  defp scan_file(file) when is_binary(file) do
    if File.regular?(file) do
      file
      |> Source.cached_ast()
      |> modules_in_file()
      |> Enum.flat_map(&find_missing_external_resources(&1, file))
    else
      []
    end
  rescue
    _ -> []
  end

  defp scan_file(_file), do: []

  defp modules_in_file(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, _args} = module, modules -> {module, [module | modules]}
        node, modules -> {node, modules}
      end)

    Enum.reverse(modules)
  end

  defp find_missing_external_resources(module_ast, file) do
    statements = module_body_statements(module_ast)

    external_resources =
      statements
      |> Enum.flat_map(&external_resource_path/1)
      |> MapSet.new()

    statements
    |> Enum.flat_map(&attribute_file_read/1)
    |> Enum.reject(fn %{path: path} -> MapSet.member?(external_resources, path) end)
    |> Enum.map(fn %{path: path, meta: meta} -> finding(file, meta, path) end)
  end

  defp module_body_statements({:defmodule, _meta, [_name, body]}) do
    body
    |> module_body()
    |> case do
      {:__block__, _meta, statements} -> statements
      statement -> [statement]
    end
  end

  defp module_body(body) do
    case Keyword.fetch(body, :do) do
      {:ok, value} -> value
      :error -> body |> List.first() |> elem(1)
    end
  end

  defp external_resource_path({:@, _meta, [{:external_resource, _attr_meta, [path_ast]}]}) do
    case literal_string(path_ast) do
      nil -> []
      path -> [path]
    end
  end

  defp external_resource_path(_statement), do: []

  defp attribute_file_read({:@, attr_meta, [{_name, _name_meta, args}]}) when is_list(args) do
    args
    |> Enum.flat_map(&file_reads_in/1)
    |> Enum.map(&Map.put_new(&1, :meta, attr_meta))
  end

  defp attribute_file_read(_statement), do: []

  defp file_reads_in(ast) do
    {_ast, reads} =
      Macro.prewalk(ast, [], fn node, reads ->
        case file_read_path(node) do
          nil -> {node, reads}
          read -> {node, [read | reads]}
        end
      end)

    Enum.reverse(reads)
  end

  defp file_read_path(
         {{:., meta, [{:__aliases__, _alias_meta, [:File]}, function]}, _call_meta, [path_ast]}
       )
       when function in [:read, :read!, :stream!, :stat, :stat!, :ls, :ls!] do
    case literal_string(path_ast) do
      nil -> nil
      path -> %{path: path, meta: meta}
    end
  end

  defp file_read_path(_node), do: nil

  defp literal_string({:__block__, _meta, [value]}) when is_binary(value), do: value
  defp literal_string(value) when is_binary(value), do: value
  defp literal_string(_ast), do: nil

  defp finding(file, meta, path) do
    line = meta[:line] || 0

    Finding.new(
      kind: :missing_external_resource,
      message:
        "compile-time File read of #{inspect(path)} should declare matching @external_resource",
      location: "#{file}:#{line}"
    )
  end
end
