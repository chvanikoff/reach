defmodule Reach.CLI.Plugins do
  @moduledoc false

  @aliases %{
    "ash" => Reach.Plugins.Ash,
    "ecto" => Reach.Plugins.Ecto,
    "ex_unit" => Reach.Plugins.ExUnit,
    "exunit" => Reach.Plugins.ExUnit,
    "gen_stage" => Reach.Plugins.GenStage,
    "genstage" => Reach.Plugins.GenStage,
    "jason" => Reach.Plugins.Jason,
    "jido" => Reach.Plugins.Jido,
    "live_view" => Reach.Plugins.LiveView,
    "liveview" => Reach.Plugins.LiveView,
    "oban" => Reach.Plugins.Oban,
    "opentelemetry" => Reach.Plugins.OpenTelemetry,
    "open_telemetry" => Reach.Plugins.OpenTelemetry,
    "phoenix" => Reach.Plugins.Phoenix,
    "poison" => Reach.Plugins.Poison,
    "quickbeam" => Reach.Plugins.QuickBEAM,
    "quick_beam" => Reach.Plugins.QuickBEAM
  }

  def project_opts(opts) do
    case plugins(opts) do
      [] -> []
      plugins -> [plugins: plugins]
    end
  end

  def plugins(opts) do
    opts
    |> Keyword.get_values(:plugins)
    |> Enum.flat_map(&List.wrap/1)
    |> Enum.map(&plugin!/1)
  end

  defp plugin!(plugin) when is_atom(plugin), do: plugin

  defp plugin!(name) when is_binary(name) do
    trimmed = String.trim(name)
    alias_key = trimmed |> String.trim_leading("Reach.Plugins.") |> Macro.underscore()

    module = Map.get(@aliases, alias_key) || existing_module(trimmed)

    cond do
      is_nil(module) ->
        raise Mix.Error, message: "Could not load plugin #{inspect(name)}"

      Map.has_key?(@aliases, alias_key) ->
        module

      loaded?(module) ->
        module

      true ->
        raise Mix.Error, message: "Could not load plugin #{inspect(name)}"
    end
  end

  defp existing_module(name) do
    name
    |> module_segments()
    |> existing_module_from_segments()
  end

  defp module_segments("Elixir." <> name), do: String.split(name, ".", trim: true)

  defp module_segments("Reach.Plugins." <> name),
    do: ["Reach", "Plugins" | String.split(name, ".", trim: true)]

  defp module_segments(name), do: String.split(name, ".", trim: true)

  defp existing_module_from_segments([]), do: nil

  defp existing_module_from_segments(segments) do
    segments
    |> Enum.map(&String.to_existing_atom/1)
    |> Module.safe_concat()
  rescue
    ArgumentError -> nil
  end

  defp loaded?(module), do: :code.is_loaded(module) != false
end
