defmodule Reach.Plugins.Phoenix.Smells.AssignNewRefreshedValueTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Plugins.Phoenix
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags assign_new for values refreshed every mount" do
    project =
      project_from_file(~S'''
      defmodule MyAppWeb.PageLive do
        def mount(_params, _session, socket) do
          {:ok, assign_new(socket, :current_user, fn -> nil end)}
        end
      end
      ''')

    assert [%Finding{kind: :phoenix_assign_new_refreshed_value}] = Smells.run(project)
  end

  test "allows assign_new for ordinary lazy defaults" do
    project =
      project_from_file(~S'''
      defmodule MyAppWeb.PageLive do
        def mount(_params, _session, socket) do
          {:ok, assign_new(socket, :page_title, fn -> "Dashboard" end)}
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  defp project_from_file(source) do
    dir =
      Path.join(System.tmp_dir!(), "reach-phoenix-assign-new-smell-#{System.unique_integer()}")

    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Project.from_sources([path], plugins: [Phoenix])
  end
end
