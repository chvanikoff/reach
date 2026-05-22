defmodule Reach.Smell.Registry do
  @moduledoc "Auto-discovers and lists all smell check modules."

  alias Reach.Smell.Check

  def checks(config \\ nil), do: checks(nil, config)

  def checks(project, config) do
    builtin_checks()
    |> Kernel.++(plugin_checks(project))
    |> Kernel.++(custom_checks(config))
    |> Enum.uniq()
  end

  defp builtin_checks do
    :reach
    |> Application.spec(:modules)
    |> List.wrap()
    |> Enum.reject(&plugin_check?/1)
    |> Enum.filter(&check?/1)
    |> Enum.sort()
  end

  defp plugin_checks(%{plugins: plugins}),
    do: plugins |> Reach.Plugin.smell_checks() |> validate_custom_checks()

  defp plugin_checks(_project), do: []

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

  defp plugin_check?(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> case do
      ["Elixir", "Reach", "Plugins" | _] -> true
      ["Reach", "Plugins" | _] -> true
      _parts -> false
    end
  end

  defp plugin_check?(_module), do: false

  defp check?(module) do
    Code.ensure_loaded?(module) and Check in behaviours(module)
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
