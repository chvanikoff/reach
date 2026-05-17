defmodule Reach.Smell.Checks.MissingExternalResourceTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Project
  alias Reach.Smell.Finding

  test "flags module attribute file reads without external_resource" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Schema do
        @schema File.read!("priv/schema.json")
      end
      ''')

    assert [%Finding{kind: :missing_external_resource}] = Smells.run(project)
  end

  test "allows matching external_resource declarations" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Schema do
        @external_resource "priv/schema.json"
        @schema File.read!("priv/schema.json")
      end
      ''')

    assert [] = Smells.run(project)
  end

  test "ignores runtime file reads" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Schema do
        def schema do
          File.read!("priv/schema.json")
        end
      end
      ''')

    assert [] = Smells.run(project)
  end

  test "ignores dynamic paths" do
    project =
      project_from_file(~S'''
      defmodule MyApp.Schema do
        @schema File.read!(Path.join("priv", "schema.json"))
      end
      ''')

    assert [] = Smells.run(project)
  end

  defp project_from_file(source) do
    dir = Path.join(System.tmp_dir!(), "reach-external-resource-smell-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    Project.from_sources([path])
  end
end
