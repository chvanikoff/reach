defmodule Reach.Plugins.ExUnit.Smells.AsyncGlobalStateTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Smell.Finding

  test "flags async tests that mutate application env" do
    project =
      project_from_string(~S'''
      defmodule MyApp.ConfigTest do
        use ExUnit.Case, async: true

        test "changes config" do
          Application.put_env(:my_app, :flag, true)
        end
      end
      ''')

    assert [%Finding{kind: :ex_unit_async_global_state}] = Smells.run(project)
  end

  test "allows global mutation in non-async tests" do
    project =
      project_from_string(~S'''
      defmodule MyApp.ConfigTest do
        use ExUnit.Case, async: false

        test "changes config" do
          Application.put_env(:my_app, :flag, true)
        end
      end
      ''')

    refute Enum.any?(Smells.run(project), &(&1.kind == :ex_unit_async_global_state))
  end

  test "flags persistent term mutation in async tests" do
    project =
      project_from_string(~S'''
      defmodule MyApp.CacheTest do
        use ExUnit.Case, async: true

        test "changes cache" do
          :persistent_term.put(:key, :value)
        end
      end
      ''')

    assert [%Finding{kind: :ex_unit_async_global_state}] = Smells.run(project)
  end

  defp project_from_string(source) do
    path = Path.join(System.tmp_dir!(), "reach-exunit-global-#{System.unique_integer()}.exs")
    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)

    Reach.Project.from_sources([path], plugins: [Reach.Plugins.ExUnit])
  end
end
