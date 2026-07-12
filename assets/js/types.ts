export interface ManifestFunction {
  id: string
  name: string
  arity: number
}

export interface ManifestModule {
  id: string
  name: string
  file: string | null
  chunk: string
  functions: ManifestFunction[]
}

export interface ModuleEdge {
  source: string
  target: string
  count: number
}

export interface Manifest {
  project: string
  generated_at: string
  modules: ManifestModule[]
  call_graph: { edges: ModuleEdge[] }
  counts: { modules: number; functions: number }
}

export interface CfNode {
  id: string
  type: string
  label: string | null
  start_line: number
  end_line: number
  source_text: string | null
  parent_id: string | null
}

export interface CfEdge {
  id: string
  source: string
  target: string
  label: string
  edge_type: string
  color: string
}

export interface ChunkFunction {
  id: string
  name: string
  arity: number
  nodes: CfNode[]
  edges: CfEdge[]
}

export interface CallFunction {
  id: string
  name: string
  module: string
  external: boolean
}

export interface CallEdge {
  id: string
  source: string
  target: string
  color: string
}

export interface DataFlowFunction {
  id: string
  label: string
  start_line: number | null
}

export interface DataFlowEdge {
  id: string
  source: string
  target: string
  label: string
  color: string
}

export interface Chunk {
  module: string
  source: { file: string | null; lines_html: string[] | null }
  functions: ChunkFunction[]
  calls: { functions: CallFunction[]; edges: CallEdge[] }
  data_flow: { functions: DataFlowFunction[]; edges: DataFlowEdge[] }
}
