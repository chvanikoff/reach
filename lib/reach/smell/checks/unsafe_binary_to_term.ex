defmodule Reach.Smell.Checks.UnsafeBinaryToTerm do
  @moduledoc "Detects unsafe binary_to_term calls without the :safe option."

  @behaviour Reach.Smell.Check

  alias Reach.Smell.Finding
  alias Reach.Smell.Helpers

  @impl true
  def run(project) do
    project.nodes
    |> Enum.flat_map(fn
      {_id, %{type: :call, meta: %{module: :erlang, function: :binary_to_term}} = call} ->
        finding_for_call(call)

      _entry ->
        []
    end)
  end

  defp finding_for_call(%{children: [_input, opts]} = call) do
    if safe_option?(opts), do: [], else: unsafe_finding(call)
  end

  defp finding_for_call(call), do: unsafe_finding(call)

  defp safe_option?(%{type: :list, children: children}) do
    Enum.any?(children, &match?(%{type: :literal, meta: %{value: :safe}}, &1))
  end

  defp safe_option?(_opts), do: false

  defp unsafe_finding(call) do
    if suppressed?(call) do
      []
    else
      [
        Finding.new(
          kind: :unsafe_binary_to_term,
          message:
            ":erlang.binary_to_term without [:safe] can deserialize dangerous terms; pass [:safe] for untrusted input",
          location: Helpers.location(call)
        )
      ]
    end
  end

  defp suppressed?(%{source_span: %{file: file, start_line: line}})
       when is_binary(file) and line > 0 do
    file
    |> File.stream!()
    |> Stream.with_index(1)
    |> Stream.filter(fn {_text, index} -> index >= line - 3 and index <= line end)
    |> Enum.any?(fn {text, _index} ->
      String.contains?(text, "sobelow_skip") and String.contains?(text, "BinToTerm")
    end)
  rescue
    _ -> false
  end

  defp suppressed?(_call), do: false
end
