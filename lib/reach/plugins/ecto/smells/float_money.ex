defmodule Reach.Plugins.Ecto.Smells.FloatMoney do
  @moduledoc "Detects money-like Ecto fields and columns declared as :float."

  use Reach.Smell.PatternCheck

  @money_names [
    :amount,
    :balance,
    :cost,
    :fee,
    :money,
    :payment,
    :price,
    :rate,
    :salary,
    :subtotal,
    :tax,
    :total,
    :unit_price
  ]

  smell(
    from(~p[field(name, :float)]) |> where(^name in @money_names),
    :ecto_float_money,
    "money-like Ecto schema field uses :float; use :decimal or integer cents"
  )

  smell(
    from(~p[add(name, :float)]) |> where(^name in @money_names),
    :ecto_float_money,
    "money-like migration column uses :float; use :decimal or integer cents"
  )
end
