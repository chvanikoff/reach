defmodule Reach.Smell.Source do
  @moduledoc false

  @elixir_extensions ~w(.ex .exs)

  def module_files(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :module_def, source_span: source_span}} -> [source_span && source_span[:file]]
      _entry -> []
    end)
    |> Enum.filter(&elixir_file?/1)
    |> Enum.uniq()
  end

  defp elixir_file?(file) when is_binary(file), do: Path.extname(file) in @elixir_extensions
  defp elixir_file?(_file), do: false

  def cached_ast(file) do
    key = {:reach_smell_ast, file}

    case Process.get(key) do
      nil ->
        ast =
          file
          |> File.read!()
          |> Sourceror.parse_string!()

        Process.put(key, ast)
        ast

      ast ->
        ast
    end
  end

  def cached_zipper(file) do
    key = {:reach_smell_zipper, file}

    case Process.get(key) do
      nil ->
        zipper =
          file
          |> cached_ast()
          |> Sourceror.Zipper.zip()

        Process.put(key, zipper)
        zipper

      zipper ->
        zipper
    end
  end
end
