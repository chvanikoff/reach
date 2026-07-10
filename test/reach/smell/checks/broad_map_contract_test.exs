defmodule Reach.Smell.Checks.BroadMapContractTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Project

  test "flags map specs whose implementation reads a fixed shape" do
    findings =
      project_from_source("""
      defmodule Contract do
        @spec metadata(map()) :: tuple()
        def metadata(data) do
          {Map.get(data, :id), Map.get(data, :name), Map.get(data, :type)}
        end
      end
      """)
      |> Smells.run()

    assert [%{kind: :broad_map_contract, keys: ["id", "name", "type"]}] =
             Enum.filter(findings, &(&1.kind == :broad_map_contract))
  end

  test "does not flag broad maps without enough observed shape evidence" do
    findings =
      project_from_source("""
      defmodule Contract do
        @spec value(map()) :: term()
        def value(data), do: Map.get(data, :value)
      end
      """)
      |> Smells.run()

    refute Enum.any?(findings, &(&1.kind == :broad_map_contract))
  end

  test "does not flag explicit map types" do
    findings =
      project_from_source("""
      defmodule Contract do
        @spec metadata(%{id: term(), name: term(), type: term()}) :: tuple()
        def metadata(data) do
          {Map.get(data, :id), Map.get(data, :name), Map.get(data, :type)}
        end
      end
      """)
      |> Smells.run()

    refute Enum.any?(findings, &(&1.kind == :broad_map_contract))
  end

  defp project_from_source(source) do
    path = Path.join(System.tmp_dir!(), "reach-broad-map-#{System.unique_integer()}.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm(path) end)
    Project.from_sources([path], plugins: [])
  end
end
