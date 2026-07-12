interface ElkNode {
  id: string
  width: number
  height: number
}

interface ElkEdge {
  id: string
  sources: string[]
  targets: string[]
}

interface ElkGraph {
  id: string
  layoutOptions: Record<string, string>
  children: ElkNode[]
  edges: ElkEdge[]
}

interface ElkResult {
  children?: { id: string; x?: number; y?: number }[]
}

declare global {
  interface Window {
    ELK: new () => { layout: (graph: ElkGraph) => Promise<ElkResult> }
  }
}

const DEFAULT_OPTIONS: Record<string, string> = {
  "elk.algorithm": "layered",
  "elk.direction": "DOWN",
  "elk.layered.spacing.nodeNodeBetweenLayers": "40",
  "elk.spacing.nodeNode": "20",
  "elk.spacing.componentComponent": "30",
  "elk.layered.crossingMinimization.strategy": "LAYER_SWEEP",
  "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
  "elk.separateConnectedComponents": "true",
  "elk.layered.compaction.connectedComponents": "true",
  "elk.layered.considerModelOrder.strategy": "NODES_AND_EDGES",
  "elk.layered.compaction.postCompaction.strategy": "EDGE_LENGTH",
  "elk.edgeRouting": "ORTHOGONAL",
  "elk.aspectRatio": "0.3",
  "elk.layered.wrapping.strategy": "MULTI_EDGE",
  "elk.layered.wrapping.additionalEdgeSpacing": "20"
}

// ELK's layered algorithm has internal bugs that certain graph shapes trigger
// with the fancier options above (e.g. "Invalid hitboxes for scanline
// constraint calculation" from the wrapping/model-order machinery). When the
// full option set fails, retry with this minimal, robust subset.
const SAFE_OPTIONS: Record<string, string> = {
  "elk.algorithm": "layered",
  "elk.direction": "DOWN",
  "elk.layered.spacing.nodeNodeBetweenLayers": "40",
  "elk.spacing.nodeNode": "20",
  "elk.spacing.componentComponent": "30",
  "elk.separateConnectedComponents": "true"
}

// Overrides worth preserving in the safe retry; the exotic per-view options
// (edge routing, wrapping) are dropped along with the defaults that crash.
const SAFE_OVERRIDE_KEYS = ["elk.direction", "elk.aspectRatio"]

export async function computeLayout(
  nodeIds: string[],
  nodeSizes: Map<string, { width: number; height: number }>,
  edges: { source: string; target: string; id: string }[],
  overrides: Record<string, string> = {}
): Promise<Map<string, { x: number; y: number }>> {
  const elk = new window.ELK()

  const children: ElkNode[] = nodeIds.map((id) => {
    const size = nodeSizes.get(id) ?? { width: 200, height: 60 }
    return { id, width: size.width, height: size.height }
  })

  const elkEdges: ElkEdge[] = edges.map((e) => ({
    id: e.id,
    sources: [e.source],
    targets: [e.target]
  }))

  const attempt = async (layoutOptions: Record<string, string>) => {
    // elk.layout mutates its input; give every attempt a fresh copy.
    const graph: ElkGraph = {
      id: "root",
      layoutOptions,
      children: children.map((c) => ({ ...c })),
      edges: elkEdges.map((e) => ({ ...e }))
    }

    const result = await elk.layout(graph)
    const positions = new Map<string, { x: number; y: number }>()

    for (const child of result.children ?? []) {
      positions.set(child.id, { x: child.x ?? 0, y: child.y ?? 0 })
    }

    return positions
  }

  try {
    return await attempt({ ...DEFAULT_OPTIONS, ...overrides })
  } catch (fullError) {
    console.warn("elk layout failed; retrying with safe options:", fullError)
    try {
      const kept: Record<string, string> = {}
      for (const key of SAFE_OVERRIDE_KEYS) {
        if (overrides[key]) kept[key] = overrides[key]
      }
      return await attempt({ ...SAFE_OPTIONS, ...kept })
    } catch (safeError) {
      console.warn("safe elk layout failed; falling back to a grid:", safeError)
      return gridPositions(nodeIds, nodeSizes)
    }
  }
}

// Last-resort layout: a simple grid so the view always renders something.
function gridPositions(
  nodeIds: string[],
  nodeSizes: Map<string, { width: number; height: number }>
): Map<string, { x: number; y: number }> {
  const positions = new Map<string, { x: number; y: number }>()
  const columns = Math.max(1, Math.ceil(Math.sqrt(nodeIds.length)))
  let x = 0
  let y = 0
  let rowHeight = 0
  let column = 0

  for (const id of nodeIds) {
    const size = nodeSizes.get(id) ?? { width: 200, height: 60 }
    positions.set(id, { x, y })
    x += size.width + 24
    rowHeight = Math.max(rowHeight, size.height)
    column += 1

    if (column >= columns) {
      column = 0
      x = 0
      y += rowHeight + 24
      rowHeight = 0
    }
  }

  return positions
}
