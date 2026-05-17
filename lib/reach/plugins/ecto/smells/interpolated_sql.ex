defmodule Reach.Plugins.Ecto.Smells.InterpolatedSQL do
  @moduledoc "Detects string interpolation in Ecto SQL fragments and raw queries."

  use Reach.Smell.PatternCheck

  smell(
    from(~p[fragment(sql)]) |> where(match?({:<<>>, _, _}, ^sql)),
    :ecto_interpolated_fragment,
    "SQL fragment uses string interpolation; use fragment placeholders and pinned parameters instead"
  )

  smell(
    from(~p[Repo.query(sql)]) |> where(match?({:<<>>, _, _}, ^sql)),
    :ecto_interpolated_repo_query,
    "Repo.query uses string interpolation; use parameterized queries instead"
  )

  smell(
    from(~p[Repo.query!(sql)]) |> where(match?({:<<>>, _, _}, ^sql)),
    :ecto_interpolated_repo_query,
    "Repo.query! uses string interpolation; use parameterized queries instead"
  )
end
