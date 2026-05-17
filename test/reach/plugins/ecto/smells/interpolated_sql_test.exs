defmodule Reach.Plugins.Ecto.Smells.InterpolatedSQLTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Ecto
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags interpolated SQL fragments" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Search do
        def by_name(name) do
          fragment("name = '#{name}'")
        end
      end
      ''')

    assert [%Finding{kind: :ecto_interpolated_fragment}] = Smells.run(project)
  end

  test "flags interpolated raw Repo queries" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Search do
        def by_name(name) do
          Repo.query("SELECT * FROM users WHERE name = '#{name}'")
        end
      end
      ''')

    assert [%Finding{kind: :ecto_interpolated_repo_query}] = Smells.run(project)
  end

  test "allows parameterized raw Repo queries" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Search do
        def by_name(name) do
          Repo.query("SELECT * FROM users WHERE name = $1", [name])
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  defp project_from_file(source) do
    dir = Path.join(System.tmp_dir!(), "reach-ecto-sql-smell-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Project.from_sources([path], plugins: [Ecto])
  end
end
