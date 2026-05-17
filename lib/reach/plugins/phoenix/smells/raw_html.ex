defmodule Reach.Plugins.Phoenix.Smells.RawHTML do
  @moduledoc "Detects explicit Phoenix.HTML.raw/1 with dynamic content."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id,
       %{type: :call, meta: %{module: Phoenix.HTML, function: :raw}, children: [content]} = call} ->
        if trusted_content?(content), do: [], else: [finding(call)]

      _entry ->
        []
    end)
  end

  defp trusted_content?(%{type: :literal, meta: %{value: value}}), do: is_binary(value)

  defp trusted_content?(%{
         type: :tuple,
         children: [%{type: :literal, meta: %{value: :safe}} | _]
       }),
       do: true

  defp trusted_content?(%{type: :call, meta: %{module: Phoenix.HTML, function: function}})
       when function in [:html_escape, :safe_to_string],
       do: true

  defp trusted_content?(%{type: :call, meta: %{function: function}})
       when function in [:html_escape, :safe_to_string],
       do: true

  defp trusted_content?(_content), do: false

  defp finding(call) do
    Finding.new(
      kind: :phoenix_raw_html,
      message:
        "Phoenix.HTML.raw/1 bypasses HTML escaping for dynamic content; sanitize or render trusted content only",
      location: Helpers.location(call)
    )
  end
end
