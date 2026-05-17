defmodule Reach.Plugins.Phoenix.Smells.AssignNewRefreshedValue do
  @moduledoc "Detects assign_new/3 for assigns that usually need refreshing on every mount."

  use Reach.Smell.PatternCheck

  @refreshed_keys [
    :current_scope,
    :current_user,
    :locale,
    :organization,
    :tenant,
    :timezone
  ]

  smell(
    from(~p[assign_new(_, key, _)]) |> where(^key in @refreshed_keys),
    :phoenix_assign_new_refreshed_value,
    "assign_new/3 skips when the assign already exists; use assign/3 for values refreshed every mount"
  )

  smell(
    from(~p[Phoenix.Component.assign_new(_, key, _)]) |> where(^key in @refreshed_keys),
    :phoenix_assign_new_refreshed_value,
    "assign_new/3 skips when the assign already exists; use assign/3 for values refreshed every mount"
  )

  smell(
    from(~p[Phoenix.LiveView.assign_new(_, key, _)]) |> where(^key in @refreshed_keys),
    :phoenix_assign_new_refreshed_value,
    "assign_new/3 skips when the assign already exists; use assign/3 for values refreshed every mount"
  )
end
