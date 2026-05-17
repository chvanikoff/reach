defmodule Reach.Smell.Source do
  @moduledoc false

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
