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
    |> Enum.filter(&(builtin_check_module?(&1) and check?(&1)))
    |> Enum.sort()
  end

  defp plugin_checks(%{plugins: plugins}),
    do: plugins |> Reach.Plugin.smell_checks() |> validate_plugin_checks()

  defp plugin_checks(_project), do: []

  defp custom_checks(%{smells: %{custom_checks: checks}}), do: validate_custom_checks(checks)
  defp custom_checks(_config), do: []

  defp validate_plugin_checks(checks) do
    Enum.map(checks, fn check ->
      if reach_plugin_check?(check), do: check, else: validate_custom_check(check)
    end)
  end

  defp validate_custom_checks(checks), do: Enum.map(checks, &validate_custom_check/1)

  defp validate_custom_check(check) do
    if check?(check) do
      check
    else
      Mix.raise("Configured smell check #{inspect(check)} must implement Reach.Smell.Check")
    end
  end

  defp builtin_check_module?(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.Reach.Smell.Checks.")
  end

  defp builtin_check_module?(_module), do: false

  defp reach_plugin_check?(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.starts_with?("Elixir.Reach.Plugins.")
  end

  defp reach_plugin_check?(_module), do: false

  defp check?(module) do
    Code.ensure_loaded?(module) and Check in behaviours(module)
  end

  defp behaviours(module) do
    module.module_info(:attributes)
    |> Keyword.get_values(:behaviour)
    |> List.flatten()
  end
end
