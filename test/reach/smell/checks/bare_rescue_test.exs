defmodule Reach.Smell.Checks.BareRescueTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Smell.Finding

  test "flags wildcard rescue clauses" do
    project =
      project_from_string(~S'''
      defmodule M do
        def run do
          risky()
        rescue
          _ -> :error
        end
      end
      ''')

    assert [%Finding{kind: :bare_rescue, location: %{line: 5}}] = Smells.run(project)
  end

  test "flags variable rescue clauses" do
    project =
      project_from_string(~S'''
      defmodule M do
        def run do
          risky()
        rescue
          error -> {:error, error}
        end
      end
      ''')

    assert [%Finding{kind: :bare_rescue}] = Smells.run(project)
  end

  test "allows narrowed rescue clauses" do
    project =
      project_from_string(~S'''
      defmodule M do
        def one do
          risky()
        rescue
          RuntimeError -> :error
        end

        def two do
          risky()
        rescue
          error in [RuntimeError, ArgumentError] -> {:error, error}
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :bare_rescue))
  end

  defp project_from_string(source) do
    path = Path.join(System.tmp_dir!(), "reach-bare-rescue-#{System.unique_integer()}.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)
    Reach.Project.from_sources([path])
  end
end
