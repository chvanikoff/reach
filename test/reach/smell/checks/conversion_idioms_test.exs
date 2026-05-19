defmodule Reach.Smell.Checks.ConversionIdiomsTest do
  use ExUnit.Case, async: true

  alias Reach.Check.Smells
  alias Reach.Project

  test "flags List.to_tuple followed by one-shot elem access" do
    findings =
      findings("""
      defmodule Sample do
        def first(items) do
          tuple = List.to_tuple(items)
          elem(tuple, 0)
        end
      end
      """)

    assert Enum.any?(findings, &(&1.kind == :list_to_tuple_for_access))
  end

  test "allows List.to_tuple used for repeated access inside loops" do
    findings =
      findings("""
      defmodule Sample do
        def lookup(items, indexes) do
          tuple = List.to_tuple(items)
          Enum.map(indexes, fn index -> elem(tuple, index) end)
        end
      end
      """)

    refute Enum.any?(findings, &(&1.kind == :list_to_tuple_for_access))
  end

  test "flags identity float arithmetic on compound expressions" do
    findings =
      findings("""
      defmodule Sample do
        def midpoint(items, index) do
          Enum.at(items, index) * 1.0
        end
      end
      """)

    assert Enum.any?(findings, &(&1.kind == :identity_float_coercion))
  end

  test "does not flag bare variable float coercion" do
    findings =
      findings("""
      defmodule Sample do
        def coerce(value), do: value * 1.0
      end
      """)

    refute Enum.any?(findings, &(&1.kind == :identity_float_coercion))
  end

  test "does not flag negating with zero float" do
    findings =
      findings("""
      defmodule Sample do
        def negate(value), do: 0.0 - value
      end
      """)

    refute Enum.any?(findings, &(&1.kind == :identity_float_coercion))
  end

  defp findings(source) do
    dir = Path.join(System.tmp_dir!(), "reach-conversion-smell-#{System.unique_integer()}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "sample.ex")
    File.write!(path, source)
    on_exit(fn -> File.rm_rf(dir) end)

    [path]
    |> Project.from_sources()
    |> Smells.run([])
  end
end
