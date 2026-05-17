defmodule Reach.Smell.Check.Pattern do
  @moduledoc "Macro DSL for ExAST-backed pattern smell checks."

  defmacro __using__(_opts) do
    quote do
      @behaviour Reach.Smell.Check
      @before_compile Reach.Smell.Check.Pattern

      import ExAST.Sigil
      import ExAST.Query
      import Reach.Smell.Check.Pattern, only: [smell: 3, smell: 4]

      alias Reach.Smell.PatternRunner

      @pattern_check_source __ENV__.file

      Module.register_attribute(__MODULE__, :smell_patterns, accumulate: true)
      Module.register_attribute(__MODULE__, :smell_query_names, accumulate: true)

      @impl true
      def run(project) do
        PatternRunner.run(project, [__MODULE__])
      end
    end
  end

  defmacro smell(pattern, kind, message) do
    build_smell(pattern, kind, message, [], __CALLER__)
  end

  defmacro smell(pattern, kind, message, opts) do
    build_smell(pattern, kind, message, opts, __CALLER__)
  end

  defp build_smell(pattern, kind, message, opts, caller) do
    prefilter = Keyword.get(opts, :prefilter, :auto)

    if selector_ast?(pattern) do
      idx = Module.get_attribute(caller.module, :smell_query_counter) || 0
      Module.put_attribute(caller.module, :smell_query_counter, idx + 1)
      fun_name = :"__smell_query_#{idx}__"

      quote do
        @smell_query_names {unquote(fun_name), unquote(kind), unquote(message),
                            unquote(prefilter)}
        @doc false
        @dialyzer {:nowarn_function, [{unquote(fun_name), 0}]}
        def unquote(fun_name)(), do: unquote(pattern)
      end
    else
      quote do
        @smell_patterns {unquote(pattern), unquote(kind), unquote(message), unquote(prefilter)}
      end
    end
  end

  defp selector_ast?({:|>, _, [left, _]}), do: selector_ast?(left)
  defp selector_ast?({:from, _, _}), do: true
  defp selector_ast?(_), do: false

  defmacro __before_compile__(_env) do
    quote do
      def __reach_pattern_check__ do
        %{
          source: @pattern_check_source,
          patterns: @smell_patterns,
          queries: @smell_query_names
        }
      end
    end
  end
end
