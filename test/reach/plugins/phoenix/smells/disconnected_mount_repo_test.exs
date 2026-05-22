defmodule Reach.Plugins.Phoenix.Smells.DisconnectedMountRepoTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Smell.Finding

  test "flags Repo work in LiveView mount without connected guard" do
    project =
      project_from_string(~S'''
      defmodule M do
        def mount(_params, _session, socket) do
          users = MyApp.Repo.all(User)
          {:ok, assign(socket, users: users)}
        end
      end
      ''')

    assert [%Finding{kind: :phoenix_disconnected_mount_repo}] = Smells.run(project)
  end

  test "allows Repo work guarded by connected?" do
    project =
      project_from_string(~S'''
      defmodule M do
        def mount(_params, _session, socket) do
          users = if connected?(socket), do: MyApp.Repo.all(User), else: []
          {:ok, assign(socket, users: users)}
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :phoenix_disconnected_mount_repo))
  end

  test "allows async LiveView loading" do
    project =
      project_from_string(~S'''
      defmodule M do
        def mount(_params, _session, socket) do
          {:ok, assign_async(socket, :users, fn -> {:ok, %{users: MyApp.Repo.all(User)}} end)}
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :phoenix_disconnected_mount_repo))
  end

  defp project_from_string(source) do
    path = Path.join(System.tmp_dir!(), "reach-phoenix-mount-repo-#{System.unique_integer()}.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)

    project = Reach.Project.from_sources([path])
    %{project | plugins: [Reach.Plugins.Phoenix]}
  end
end
