defmodule Reach.AnalysisTest do
  use ExUnit.Case, async: true

  alias Reach.Analysis
  alias Reach.IR.Node

  defmodule BoundaryPlugin do
    @behaviour Reach.Plugin

    @impl true
    def analyze(_all_nodes, _opts), do: []

    @impl true
    def expected_effect_boundary?(_module, :framework_callback, 2), do: true
    def expected_effect_boundary?(_module, _function, _arity), do: false
  end

  test "expected effect boundary ignores Erlang module atoms" do
    node = %Node{
      id: "fun",
      type: :function_def,
      meta: %{module: :zigler, name: :run, arity: 0},
      source_span: nil,
      children: []
    }

    refute Analysis.expected_effect_boundary?(node)
  end

  test "expected effect boundary uses plugin-owned callback semantics" do
    node = %Node{
      id: "fun",
      type: :function_def,
      meta: %{module: Demo, name: :framework_callback, arity: 2},
      source_span: nil,
      children: []
    }

    refute Analysis.expected_effect_boundary?(node)
    assert Analysis.expected_effect_boundary?(node, [BoundaryPlugin])
  end
end
