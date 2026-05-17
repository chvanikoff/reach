defmodule Reach.Smell.Registry do
  @moduledoc "Auto-discovers and lists all smell check modules."

  alias Reach.Smell.Check

  def checks(config \\ nil) do
    config
    |> custom_checks()
    |> Kernel.++(builtin_checks())
    |> Enum.uniq()
  end

  defp builtin_checks do
    :reach
    |> Application.spec(:modules)
    |> List.wrap()
    |> Enum.filter(&check?/1)
    |> Enum.sort()
  end

  defp custom_checks(%{smells: %{custom_checks: checks}}), do: validate_custom_checks(checks)
  defp custom_checks(_config), do: []

  defp validate_custom_checks(checks) do
    Enum.map(checks, fn check ->
      if check?(check) do
        check
      else
        Mix.raise("Configured smell check #{inspect(check)} must implement Reach.Smell.Check")
      end
    end)
  end

  defp check?(module) do
    Code.ensure_loaded?(module) and Check in behaviours(module)
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
