defmodule Reach.Smell.Checks.ETSPartialKeyMatchTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Smell.Finding

  test "flags wildcard matches over tuple keys" do
    project =
      project_from_string(~S'''
      defmodule Cache do
        def get_file(path) do
          case :ets.match_object(:cache, {{path, :_}, :_}) do
            [{{^path, _mtime}, entry} | _] -> entry
            [] -> nil
          end
        end
      end
      ''')

    assert [%Finding{kind: :ets_partial_key_match}] = Smells.run(project)
  end

  test "allows exact lookup" do
    project =
      project_from_string(~S'''
      defmodule Cache do
        def get(path, mtime) do
          :ets.lookup(:cache, {path, mtime})
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :ets_partial_key_match))
  end

  defp project_from_string(source) do
    path = Path.join(System.tmp_dir!(), "reach-ets-partial-#{System.unique_integer()}.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)
    Reach.Project.from_sources([path])
  end
end
