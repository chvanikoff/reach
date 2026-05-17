defmodule Reach.Smell.Check.AST do
  @moduledoc "Shared behaviour for smell checks that scan source files with Sourceror AST."

  defmacro __using__(_opts) do
    quote do
      @behaviour Reach.Smell.Check

      alias Reach.Smell.Source

      @impl true
      def run(project) do
        project
        |> Source.module_files()
        |> Enum.flat_map(&scan_source_file/1)
      end

      defp scan_source_file(file) when is_binary(file) do
        if File.regular?(file) do
          file
          |> Source.cached_ast()
          |> scan_ast(file)
        else
          []
        end
      rescue
        _ -> []
      end

      defp scan_source_file(_file), do: []
    end
  end
end
