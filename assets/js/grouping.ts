export interface GroupableModule {
  id: string
  name: string
}

export interface ModuleEdge {
  source: string
  target: string
  count: number
}

// The landing call graph is a zoomable namespace map: at every level at
// most this many nodes are shown, keeping ELK layout and panning snappy.
export const MAX_LANDING_NODES = 40
export const LANDING_EDGE_LIMIT = 80

export interface NamespaceNode {
  id: string // display/graph id: group => "<prefix>.*", module => module id
  label: string
  kind: "group" | "module"
  size: number // module count inside (1 for module)
  prefix: string | null // for kind=group: the namespace prefix to zoom into
}

export interface NamespaceLevel {
  nodes: NamespaceNode[]
  edges: ModuleEdge[] // aggregated, sorted by count desc, NOT yet capped
}

export function buildNamespaceLevel(
  modules: GroupableModule[],
  edges: ModuleEdge[],
  scope: string | null
): NamespaceLevel {
  const inScopeModules = scope === null ? modules : modules.filter((m) => isInScope(m.name, scope))
  const inScopeIds = new Set(inScopeModules.map((m) => m.id))

  const baseDepth = scope === null ? 0 : scope.split(".").length
  const contextBuckets = buildContextBuckets(modules, inScopeIds, edges)

  const depth = pickDepth(inScopeModules, baseDepth, contextBuckets.size)
  const inScopeBuckets = bucketByPrefix(inScopeModules, baseDepth + depth)

  const nodes: NamespaceNode[] = []
  const assignment = new Map<string, string>()

  for (const [prefix, members] of inScopeBuckets) {
    if (members.length === 1) {
      const m = members[0]
      assignment.set(m.id, m.id)
      nodes.push({ id: m.id, label: m.name, kind: "module", size: 1, prefix: null })
    } else {
      const groupId = `${prefix}.*`
      for (const m of members) assignment.set(m.id, groupId)
      nodes.push({ id: groupId, label: groupId, kind: "group", size: members.length, prefix })
    }
  }

  for (const [seg, members] of contextBuckets) {
    const groupId = `${seg}.*`
    for (const m of members) assignment.set(m.id, groupId)
    nodes.push({ id: groupId, label: groupId, kind: "group", size: members.length, prefix: seg })
  }

  return { nodes, edges: aggregate(edges, assignment, inScopeIds) }
}

function isInScope(name: string, scope: string): boolean {
  return name === scope || name.startsWith(`${scope}.`)
}

// Groups in-scope modules by their first `segCount` dot-segments. A module
// with fewer segments than `segCount` falls into its own bucket keyed by
// its full name (it can't be grouped any deeper).
function bucketByPrefix(
  modules: GroupableModule[],
  segCount: number
): Map<string, GroupableModule[]> {
  const map = new Map<string, GroupableModule[]>()
  for (const m of modules) {
    const prefix = m.name.split(".").slice(0, segCount).join(".")
    const list = map.get(prefix) ?? []
    list.push(m)
    map.set(prefix, list)
  }
  return map
}

function countPrefixes(modules: GroupableModule[], segCount: number): number {
  const set = new Set<string>()
  for (const m of modules) set.add(m.name.split(".").slice(0, segCount).join("."))
  return set.size
}

// Finds the deepest namespace depth `d` (starting at 1, capped at 6) whose
// resulting node count - in-scope buckets plus fixed out-of-scope context
// groups - stays within MAX_LANDING_NODES. Falls back to d=1 if even that
// exceeds the budget (bounded by the namespace's natural fan-out then).
function pickDepth(
  inScopeModules: GroupableModule[],
  baseDepth: number,
  contextNodeCount: number
): number {
  let bestD = 1
  for (let d = 1; d <= 6; d++) {
    const nodeCount = countPrefixes(inScopeModules, baseDepth + d) + contextNodeCount
    if (nodeCount > MAX_LANDING_NODES) break
    bestD = d
  }
  return bestD
}

// Buckets out-of-scope modules into depth-1 groups (first dot-segment),
// keeping only the buckets that have at least one edge to/from an
// in-scope module - no isolated context clutter.
function buildContextBuckets(
  modules: GroupableModule[],
  inScopeIds: Set<string>,
  edges: ModuleEdge[]
): Map<string, GroupableModule[]> {
  const outScopeModules = modules.filter((m) => !inScopeIds.has(m.id))
  if (outScopeModules.length === 0) return new Map()

  const segByModuleId = new Map<string, string>()
  const byFirstSeg = new Map<string, GroupableModule[]>()
  for (const m of outScopeModules) {
    const seg = m.name.split(".")[0]
    segByModuleId.set(m.id, seg)
    const list = byFirstSeg.get(seg) ?? []
    list.push(m)
    byFirstSeg.set(seg, list)
  }

  const usedSegs = new Set<string>()
  for (const e of edges) {
    const srcIn = inScopeIds.has(e.source)
    const tgtIn = inScopeIds.has(e.target)
    if (srcIn === tgtIn) continue // both in-scope or both out-of-scope: irrelevant here

    const seg = segByModuleId.get(srcIn ? e.target : e.source)
    if (seg) usedSegs.add(seg)
  }

  const result = new Map<string, GroupableModule[]>()
  for (const seg of usedSegs) {
    const members = byFirstSeg.get(seg)
    if (members) result.set(seg, members)
  }
  return result
}

function aggregate(
  edges: ModuleEdge[],
  assignment: Map<string, string>,
  inScopeIds: Set<string>
): ModuleEdge[] {
  const merged = new Map<string, ModuleEdge>()
  for (const e of edges) {
    if (!inScopeIds.has(e.source) && !inScopeIds.has(e.target)) continue // both out of scope

    const source = assignment.get(e.source)
    const target = assignment.get(e.target)
    if (!source || !target || source === target) continue

    const key = `${source}->${target}`
    const existing = merged.get(key)
    if (existing) existing.count += e.count
    else merged.set(key, { source, target, count: e.count })
  }
  return [...merged.values()].sort((a, b) => b.count - a.count)
}
