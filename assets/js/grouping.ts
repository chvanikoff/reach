export interface GroupableModule {
  id: string
  name: string
}

export interface ModuleEdge {
  source: string
  target: string
  count: number
}

export interface ModuleGraphNode {
  id: string
  label: string
  kind: "module" | "group"
  size: number
}

export interface ModuleGraph {
  nodes: ModuleGraphNode[]
  edges: ModuleEdge[]
}

// Above this many modules the landing call graph collapses dotted
// namespaces (e.g. "MyApp.Billing.*") into expandable group nodes.
export const GROUP_THRESHOLD = 150

export function buildModuleGraph(
  modules: GroupableModule[],
  edges: ModuleEdge[],
  expanded: Set<string>
): ModuleGraph {
  if (modules.length <= GROUP_THRESHOLD) {
    return { nodes: modules.map(moduleNode), edges: aggregate(edges, identityAssignment(modules)) }
  }

  const byPrefix = new Map<string, GroupableModule[]>()
  for (const m of modules) {
    const prefix = groupPrefix(m.name)
    const list = byPrefix.get(prefix) ?? []
    list.push(m)
    byPrefix.set(prefix, list)
  }

  const assignment = new Map<string, string>()
  const nodes: ModuleGraphNode[] = []

  for (const [prefix, members] of byPrefix) {
    if (members.length === 1 || expanded.has(prefix)) {
      for (const m of members) {
        assignment.set(m.id, m.id)
        nodes.push(moduleNode(m))
      }
    } else {
      for (const m of members) assignment.set(m.id, prefix)
      nodes.push({ id: prefix, label: prefix, kind: "group", size: members.length })
    }
  }

  return { nodes, edges: aggregate(edges, assignment) }
}

function identityAssignment(modules: GroupableModule[]): Map<string, string> {
  return new Map(modules.map((m) => [m.id, m.id]))
}

function aggregate(edges: ModuleEdge[], assignment: Map<string, string>): ModuleEdge[] {
  const merged = new Map<string, ModuleEdge>()
  for (const e of edges) {
    const source = assignment.get(e.source)
    const target = assignment.get(e.target)
    if (!source || !target || source === target) continue
    const key = `${source}->${target}`
    const existing = merged.get(key)
    if (existing) existing.count += e.count
    else merged.set(key, { source, target, count: e.count })
  }
  return [...merged.values()]
}

function moduleNode(m: GroupableModule): ModuleGraphNode {
  return { id: m.id, label: m.name, kind: "module", size: 1 }
}

function groupPrefix(name: string): string {
  const parts = name.split(".")
  return parts.length <= 2 ? name : `${parts.slice(0, 2).join(".")}.*`
}
