defmodule Reach.Plugins.Ecto.Smells.ImplicitCrossJoinTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Ecto
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags multiple from generators without explicit join" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Query do
        import Ecto.Query

        def query do
          from u in User, p in Post, where: u.id == p.user_id
        end
      end
      ''')

    assert [%Finding{kind: :ecto_implicit_cross_join}] = Smells.run(project)
  end

  test "allows explicit joins" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Query do
        import Ecto.Query

        def query do
          from u in User,
            join: p in Post,
            on: u.id == p.user_id
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  defp project_from_file(source) do
    dir = Path.join(System.tmp_dir!(), "reach-ecto-cross-join-smell-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Project.from_sources([path], plugins: [Ecto])
  end
end
