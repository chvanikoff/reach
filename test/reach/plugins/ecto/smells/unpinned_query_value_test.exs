defmodule Reach.Plugins.Ecto.Smells.UnpinnedQueryValueTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Ecto
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags unpinned local variables in where comparisons" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Query do
        import Ecto.Query

        def by_user(user_id) do
          from u in User, where: u.id == user_id
        end
      end
      ''')

    assert [%Finding{kind: :ecto_unpinned_query_value}] = Smells.run(project)
  end

  test "ignores malformed from calls" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Query do
        def query do
          from()
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  test "allows pinned local variables" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Query do
        import Ecto.Query

        def by_user(user_id) do
          from u in User, where: u.id == ^user_id
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  test "allows field to field comparisons" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Query do
        import Ecto.Query

        def joined do
          from u in User,
            join: o in Org,
            on: u.org_id == o.id,
            where: u.org_id == o.id
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  test "allows literal comparisons" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Query do
        import Ecto.Query

        def published do
          from p in Post, where: p.status == "published"
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  defp project_from_file(source) do
    dir = Path.join(System.tmp_dir!(), "reach-ecto-unpinned-smell-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Project.from_sources([path], plugins: [Ecto])
  end
end
