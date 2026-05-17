defmodule Reach.Plugins.Phoenix.Smells.RawHTML do
  @moduledoc "Detects raw/1 with dynamic content."

  use Reach.Smell.PatternCheck

  smell(
    from(~p[raw(content)]) |> where(not is_binary(^content)),
    :phoenix_raw_html,
    "raw/1 bypasses HTML escaping for dynamic content; sanitize or render trusted content only"
  )
end
