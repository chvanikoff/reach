defmodule Reach.AST do
  @moduledoc "Shared helpers for working with Elixir AST."

  @doc "Returns real `defmodule` AST nodes from a quoted source tree."
  def modules_in_file(ast) do
    {_ast, modules} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [_name, body]} = module, modules when is_list(body) ->
          {module, [module | modules]}

        node, modules ->
          {node, modules}
      end)

    Enum.reverse(modules)
  end
end
