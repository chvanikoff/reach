import Config

if config_env() == :dev do
  config :volt,
    entry: "assets/js/app.ts",
    outdir: "priv/static",
    hash: false,
    aliases: %{"@reach" => "assets/js"}
end
