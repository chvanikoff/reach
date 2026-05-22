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
    explicit = Keyword.get(opts, :plugins, [])
    cli = Keyword.get_values(opts, :plugin)

    (List.wrap(explicit) ++ Enum.flat_map(cli, &List.wrap/1))
    |> Enum.map(&plugin!/1)
  end

  defp plugin!(plugin) when is_atom(plugin), do: plugin

  defp plugin!(name) when is_binary(name) do
    normalized = name |> String.trim() |> String.trim_leading("Reach.Plugins.")
    alias_key = normalized |> Macro.underscore()

    module = Map.get(@aliases, alias_key) || Module.concat(["Reach", "Plugins", normalized])

    if Code.ensure_loaded?(module) do
      module
    else
      Mix.raise("Could not load plugin #{inspect(name)}")
    end
  end
end
