defmodule Reach.Visualize.Chunks do
  @moduledoc """
  Builds the chunked HTML report payload: a manifest with the module tree and
  a module-level call graph, plus one lazily-loaded data chunk per module.

  One chunk per module is the deliberate unit of future incremental caching
  and of a future `Reach.Plug` serving the report directory.
  """

  alias Reach.Visualize
  alias Reach.Visualize.{ControlFlow, Source}

  @top_level_id "_top_level"

  @type output :: %{manifest: map(), chunks: [{String.t(), map()}]}

  @spec build(Reach.Project.t(), keyword()) :: output()
  def build(%Reach.Project{} = project, opts \\ []) do
    all_nodes = Reach.nodes(project)

    module_entries = build_module_entries(all_nodes)
    %{raw_edges: raw_edges, internal_modules: internal} = Visualize.call_graph(project)
    data_flow = Visualize.data_flow(project, opts)

    node_owner = node_owner_map(project)
    df_by_chunk = partition_data_flow(data_flow, node_owner)

    chunks =
      Enum.map(module_entries, fn {mod_atom, module_map, lines_html} ->
        id = chunk_id(mod_atom)

        {id,
         %{
           module: id,
           source: %{file: module_map.file, lines_html: lines_html},
           functions: module_map.functions,
           calls: calls_for(raw_edges, mod_atom, internal),
           data_flow: Map.get(df_by_chunk, id, %{functions: [], edges: []})
         }}
      end)

    manifest = %{
      project: to_string(Keyword.get(opts, :project, "project")),
      generated_at:
        Keyword.get_lazy(opts, :generated_at, fn ->
          DateTime.utc_now() |> DateTime.to_iso8601()
        end),
      modules: manifest_modules(module_entries),
      call_graph: %{edges: module_level_edges(raw_edges, internal)},
      counts: %{
        modules: length(module_entries),
        functions:
          module_entries |> Enum.map(fn {_, map, _} -> length(map.functions) end) |> Enum.sum()
      }
    }

    %{manifest: manifest, chunks: chunks}
  end

  # --- Module entries (parallel CFG build + once-per-file highlighting) ---

  defp build_module_entries(all_nodes) do
    entries =
      all_nodes
      |> Enum.filter(&(&1.type == :module_def))
      |> Task.async_stream(
        fn mod ->
          module_map = ControlFlow.build_module(mod)
          # Highlight in the same process: build_function/2 may have injected
          # embedded (JS) sources into this process's file-line cache.
          {mod.meta[:name], module_map, Source.highlight_file_lines(module_map.file)}
        end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, entry} -> entry end)

    module_maps = Enum.map(entries, fn {_mod, map, _lines} -> map end)

    case ControlFlow.build_top_level(all_nodes, module_maps) do
      nil -> entries
      top -> entries ++ [{nil, top, Source.highlight_file_lines(top.file)}]
    end
  end

  defp manifest_modules(entries) do
    Enum.map(entries, fn {mod_atom, module_map, _lines} ->
      id = chunk_id(mod_atom)

      %{
        id: id,
        name: module_map.module || "(top-level)",
        file: module_map.file,
        chunk: "chunks/#{id}.js",
        functions: Enum.map(module_map.functions, &%{id: &1.id, name: &1.name, arity: &1.arity})
      }
    end)
  end

  defp chunk_id(nil), do: @top_level_id

  defp chunk_id(mod_atom) do
    mod_atom
    |> Visualize.safe_module_name()
    |> String.replace(~r/[^A-Za-z0-9._-]/, "_")
  end

  # --- Call graph slices ---

  defp module_level_edges(raw_edges, internal) do
    raw_edges
    |> Enum.filter(fn {{sm, _, _}, {tm, _, _}} ->
      sm != tm and sm in internal and tm in internal
    end)
    |> Enum.frequencies_by(fn {{sm, _, _}, {tm, _, _}} -> {sm, tm} end)
    |> Enum.map(fn {{sm, tm}, count} ->
      %{
        source: Visualize.safe_module_name(sm),
        target: Visualize.safe_module_name(tm),
        count: count
      }
    end)
  end

  defp calls_for(raw_edges, mod_atom, internal) do
    edges =
      Enum.filter(raw_edges, fn {{sm, _, _}, {tm, _, _}} ->
        sm == mod_atom or tm == mod_atom
      end)

    functions =
      edges
      |> Enum.flat_map(fn {src, tgt} -> [src, tgt] end)
      |> Enum.uniq()
      |> Enum.map(fn {m, f, a} ->
        %{
          id: Visualize.call_id(m, f, a),
          name: "#{f}/#{a}",
          module: Visualize.safe_module_name(m),
          external: m not in internal
        }
      end)

    edge_maps =
      edges
      |> Enum.map(fn {{sm, sf, sa}, {tm, tf, ta}} ->
        source = Visualize.call_id(sm, sf, sa)
        target = Visualize.call_id(tm, tf, ta)

        %{
          id: "call_#{source}_#{target}",
          source: source,
          target: target,
          color: call_edge_color(sm, tm, mod_atom)
        }
      end)
      |> Enum.uniq_by(& &1.id)

    %{functions: functions, edges: edge_maps}
  end

  defp call_edge_color(sm, tm, mod_atom) do
    cond do
      sm == :"<javascript>" or tm == :"<javascript>" -> "#f97316"
      tm == mod_atom -> "#7c3aed"
      true -> "#94a3b8"
    end
  end

  # --- Data flow partitioning ---

  defp node_owner_map(%Reach.Project{modules: modules}) do
    for {mod, sdg} <- modules, {id, _node} <- sdg.nodes, into: %{}, do: {id, mod}
  end

  defp partition_data_flow(%{functions: functions, edges: edges}, node_owner) do
    fn_by_id = Map.new(functions, &{&1.id, &1})
    owner = fn id -> id |> owner_module(node_owner) |> chunk_id() end

    base =
      Enum.reduce(functions, %{}, fn f, acc ->
        Map.update(acc, owner.(f.id), %{functions: [f], edges: []}, fn cur ->
          %{cur | functions: [f | cur.functions]}
        end)
      end)

    edges
    |> Enum.group_by(&owner.(&1.source))
    |> Enum.reduce(base, fn {cid, chunk_edges}, acc ->
      endpoint_fns =
        chunk_edges
        |> Enum.flat_map(&[&1.source, &1.target])
        |> Enum.uniq()
        |> Enum.map(&Map.get(fn_by_id, &1))
        |> Enum.reject(&is_nil/1)

      Map.update(acc, cid, %{functions: endpoint_fns, edges: chunk_edges}, fn cur ->
        %{
          functions: Enum.uniq_by(cur.functions ++ endpoint_fns, & &1.id),
          edges: chunk_edges
        }
      end)
    end)
    |> Map.new(fn {cid, %{functions: fns, edges: es}} ->
      {cid,
       %{
         functions: fns |> Enum.uniq_by(& &1.id) |> Enum.sort_by(& &1.start_line),
         edges: es
       }}
    end)
  end

  defp owner_module(id_string, node_owner) do
    case Integer.parse(id_string) do
      {int, ""} -> Map.get(node_owner, int)
      _ -> nil
    end
  end
end
