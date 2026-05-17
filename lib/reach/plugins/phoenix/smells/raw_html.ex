defmodule Reach.Plugins.Phoenix.Smells.RawHTML do
  @moduledoc "Detects explicit Phoenix.HTML.raw/1 with dynamic content."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn {_id, node} -> findings_for_node(node) end)
  end

  defp findings_for_node(call) do
    if raw_call?(call), do: findings_for_raw_call(call), else: []
  end

  defp raw_call?(call) do
    meta = Map.get(call, :meta, %{})
    Map.get(call, :type) == :call and meta.module == Phoenix.HTML and meta.function == :raw
  end

  defp findings_for_raw_call(call) do
    case Map.get(call, :children, []) do
      [content] -> if trusted_content?(content), do: [], else: [finding(call)]
      _children -> []
    end
  end

  defp trusted_content?(content) do
    literal_string?(content) or safe_tuple?(content) or escaped_call?(content)
  end

  defp literal_string?(content) do
    Map.get(content, :type) == :literal and
      is_binary(Map.get(Map.get(content, :meta, %{}), :value))
  end

  defp safe_tuple?(content) do
    Map.get(content, :type) == :tuple and
      match?([first | _] when is_map(first), Map.get(content, :children, [])) and
      literal_value(List.first(Map.get(content, :children, []))) == :safe
  end

  defp escaped_call?(content) do
    meta = Map.get(content, :meta, %{})

    Map.get(content, :type) == :call and
      meta.module in [nil, Phoenix.HTML] and meta.function in [:html_escape, :safe_to_string]
  end

  defp literal_value(node), do: node |> Map.get(:meta, %{}) |> Map.get(:value)

  defp finding(call) do
    Finding.new(
      kind: :phoenix_raw_html,
      message:
        "Phoenix.HTML.raw/1 bypasses HTML escaping for dynamic content; sanitize or render trusted content only",
      location: Helpers.location(call)
    )
  end
end
