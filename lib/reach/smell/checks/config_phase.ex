defmodule Reach.Smell.Checks.ConfigPhase do
  @moduledoc "Detects compile-time/runtime config phase mismatches."

  use Reach.Smell.Check.AST

  alias Reach.Smell.Finding

  @compile_time_config_calls [get_env: 2, fetch_env: 2, fetch_env!: 2]
  @runtime_config_calls [compile_env: 2, compile_env: 3, compile_env!: 2, compile_env!: 3]

  @impl true
  def kinds, do: [:config_phase]

  defp scan_ast(ast, file) do
    {_ast, findings} =
      Macro.prewalk(ast, [], fn node, findings ->
        {node, config_phase_findings(node, file) ++ findings}
      end)

    Enum.reverse(findings)
  end

  defp config_phase_findings({:@, _meta, [{_attribute, _, [value]}]}, file) do
    case application_call(value, @compile_time_config_calls) do
      {:ok, function, meta} ->
        [
          finding(
            file,
            meta,
            "module attribute calls Application.#{function} at compile time; use Application.compile_env or read at runtime"
          )
        ]

      :error ->
        []
    end
  end

  defp config_phase_findings({:def, _meta, _args} = node, file), do: function_findings(node, file)

  defp config_phase_findings({:defp, _meta, _args} = node, file),
    do: function_findings(node, file)

  defp config_phase_findings({:defmacro, _meta, _args} = node, file),
    do: function_findings(node, file)

  defp config_phase_findings({:defmacrop, _meta, _args} = node, file),
    do: function_findings(node, file)

  defp config_phase_findings(_node, _file), do: []

  defp function_findings(node, file) do
    {_node, findings} =
      Macro.prewalk(node, [], fn
        {{:., meta, [{:__aliases__, _, [:Application]}, function]}, _, args} = call, findings
        when is_atom(function) ->
          if {function, length(args)} in @runtime_config_calls do
            message =
              "Application.#{function} inside a function is still compile-time; use #{runtime_config_replacement(function)} for runtime config"

            {call, [finding(file, meta, message) | findings]}
          else
            {call, findings}
          end

        child, findings ->
          {child, findings}
      end)

    findings
  end

  defp application_call(
         {{:., meta, [{:__aliases__, _, [:Application]}, function]}, _, args},
         allowed
       )
       when is_atom(function) do
    if {function, length(args)} in allowed, do: {:ok, function, meta}, else: :error
  end

  defp application_call(_node, _allowed), do: :error

  defp runtime_config_replacement(:compile_env), do: "Application.get_env"
  defp runtime_config_replacement(:compile_env!), do: "Application.fetch_env!"

  defp finding(file, meta, message) do
    Finding.new(kind: :config_phase, message: message, location: "#{file}:#{meta[:line] || 0}")
  end
end
