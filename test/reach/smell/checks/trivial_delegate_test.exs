defmodule Reach.Smell.Checks.TrivialDelegateTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Project
  alias Reach.Smell.Finding

  test "allows defdelegate pass-throughs because they are often public facades" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        defdelegate get_user(id), to: MyApp.Users.Query
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_delegate))
  end

  test "flags private hand-written forwarders with the same name and arguments" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        defp get_user(id), do: MyApp.Users.Query.get_user(id)
      end
      ''')

    assert [
             %Finding{
               kind: :trivial_forwarder,
               message: message,
               evidence: %{target: "MyApp.Users.Query.get_user", function: :get_user, arity: 1}
             }
           ] = findings_of_kind(project, :trivial_forwarder)

    assert message =~ "only forwards"
  end

  test "flags block-body private forwarders" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        defp get_user(id) do
          MyApp.Users.Query.get_user(id)
        end
      end
      ''')

    assert [%Finding{kind: :trivial_forwarder}] = findings_of_kind(project, :trivial_forwarder)
  end

  test "flags private hand-written forwarders with default arguments" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        defp get_user(id \\ "me"), do: MyApp.Users.Query.get_user(id)
      end
      ''')

    assert [%Finding{kind: :trivial_forwarder}] = findings_of_kind(project, :trivial_forwarder)
  end

  test "allows documented public facade delegates" do
    project =
      project_from_file(~S'''
      defmodule MyApp do
        @doc "Returns true when a node is pure."
        @spec pure?(term()) :: boolean()
        defdelegate pure?(node), to: MyApp.Effects
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_delegate))
  end

  test "allows behaviour callbacks that adapt to another implementation" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Plugin do
        @behaviour MyApp.Behaviour

        @impl true
        def parse_file(path, opts \\ []), do: MyApp.Parser.parse_file(path, opts)
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_forwarder))
  end

  test "allows defdelegate when it gives the target function a semantic alias" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Parser do
        defdelegate from_string(source, opts \\ []), to: MyApp.Parser.Impl, as: :parse
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_delegate))
  end

  test "flags private wrappers around Erlang module calls" do
    project =
      project_from_file(~S'''
      defmodule MyApp.HPack do
        defp encode(headers, context), do: :hpack.encode(headers, context)
      end
      ''')

    assert [
             %Finding{
               kind: :trivial_forwarder,
               evidence: %{target: "hpack.encode", function: :encode, arity: 2}
             }
           ] = findings_of_kind(project, :trivial_forwarder)
  end

  test "ignores local calls with no explicit target module" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Parser do
        import MyApp.Parser.Helpers

        def parse(input), do: parse(input)
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_forwarder))
  end

  test "resolves aliases in private remote calls and allows delegates" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        alias MyApp.Users.Query

        defdelegate list_users(), to: Query
        defp get_user(id), do: Query.get_user(id)
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_delegate))

    assert [%Finding{evidence: %{target: "MyApp.Users.Query.get_user"}}] =
             findings_of_kind(project, :trivial_forwarder)
  end

  test "allows dynamic defdelegate targets from for generators" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Dynamic do
        for target <- [MyApp.A, MyApp.B] do
          defdelegate run(value), to: target
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_delegate))
  end

  test "ignores defdelegate with unknown dynamic target modules" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Dynamic do
        for target <- configured_targets() do
          defdelegate run(value), to: target
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_delegate))
  end

  test "allows wrappers that transform arguments" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        def get_user(id), do: MyApp.Users.Query.get_user(String.trim(id))
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_forwarder))
  end

  test "allows wrappers that add behavior" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        def get_user(id) do
          Logger.debug("loading user")
          MyApp.Users.Query.get_user(id)
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_forwarder))
  end

  test "allows differently named functions that create a semantic alias" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        def find(id), do: MyApp.Users.Query.get_user(id)
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :trivial_forwarder))
  end

  test "handles dynamic alias forms without crashing" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Users do
        alias __MODULE__.Query
        defdelegate get_user(id), to: Query
      end
      ''')

    assert Smells.run(project)
  end

  defp findings_of_kind(project, kind) do
    project
    |> Smells.run()
    |> Enum.filter(&(&1.kind == kind))
  end

  defp project_from_file(source) do
    dir = Path.join(System.tmp_dir!(), "reach-trivial-delegate-smell-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Project.from_sources([path])
  end
end
