<script setup>
import { ref, computed, nextTick, onMounted, watch } from "vue"
import { VueFlow, useVueFlow } from "@vue-flow/core"
import { MiniMap } from "@vue-flow/minimap"
import { Controls } from "@vue-flow/controls"
import CodeNode from "@reach/components/CodeNode.vue"
import CompactNode from "@reach/components/CompactNode.vue"
import { computeLayout } from "@reach/layout"
import { loadChunk } from "@reach/chunks"
import { buildModuleGraph } from "@reach/grouping"
import { dedentHtmlLines, escapeHtml, lineText, sliceLines } from "@reach/source"

const props = defineProps({
  manifest: { type: Object, required: true },
})

// ELK layered layout degrades badly beyond a few hundred edges, so ego and
// data-flow graphs are capped to keep interactions on the main thread snappy.
const EGO_EDGE_LIMIT = 300
const DATA_FLOW_EDGE_LIMIT = 300

const nodeTypes = { code: CodeNode, compact: CompactNode }
const mode = ref("call_graph")
const nodes = ref([])
const edges = ref([])
const hint = ref("")
const limitNote = ref("")
const search = ref("")
const selectedModuleId = ref(null)
const selectedFunctionId = ref(null)
const expandedGroups = ref(new Set())
const expandedModules = ref(new Set())
const { fitView } = useVueFlow()

const moduleById = computed(() => new Map(props.manifest.modules.map((m) => [m.id, m])))
const selectedModule = computed(() =>
  selectedModuleId.value ? moduleById.value.get(selectedModuleId.value) : null
)

// ── Layout ──

async function applyLayout(rawNodes, rawEdges, layoutOverrides = {}) {
  // Defensively dedupe by id before sizing/layout: duplicate ids reaching ELK
  // are the classic cause of "Cannot read properties of null" layout crashes.
  const seenIds = new Set()
  rawNodes = rawNodes.filter((n) => {
    if (seenIds.has(n.id)) return false
    seenIds.add(n.id)
    return true
  })

  const nodeSizes = new Map()
  for (const n of rawNodes) nodeSizes.set(n.id, estimateSize(n.data))

  const nodeIdSet = new Set(rawNodes.map((n) => n.id))
  const validEdges = rawEdges.filter((e) => nodeIdSet.has(e.source) && nodeIdSet.has(e.target))

  const positions = await computeLayout(
    rawNodes.map((n) => n.id),
    nodeSizes,
    validEdges.map((e) => ({ id: e.id, source: e.source, target: e.target })),
    layoutOverrides
  )

  for (const n of rawNodes) {
    const pos = positions.get(n.id)
    if (pos) n.position = pos
  }

  nodes.value = rawNodes
  edges.value = validEdges
  await nextTick()
  fitView({ padding: 0.1 })
}

function estimateSize(data) {
  if (data.nodeType === "compact" || data.nodeType === "call" || data.nodeType === "external") {
    const len = (data.label ?? "").length
    return { width: Math.max(100, len * 7.5 + 24), height: 32 }
  }

  const lines = data.lines || []
  const labelLen = (data.label ?? "").length
  const maxCodeLen = Math.max(labelLen, 0, ...lines.map((l) => lineText(l).length))
  return {
    width: Math.min(700, Math.max(180, maxCodeLen * 7.5 + 70)),
    height: Math.max(36, lines.length * 18 + (data.label ? 26 : 8)),
  }
}

// ── Call Graph: module landing + per-module ego graph ──

async function buildCallGraph() {
  hint.value = ""
  limitNote.value = ""
  if (selectedModule.value) return buildModuleEgoGraph(selectedModule.value)

  const graph = buildModuleGraph(
    props.manifest.modules,
    props.manifest.call_graph.edges,
    expandedGroups.value
  )

  const rawNodes = graph.nodes.map((n) => ({
    id: n.id,
    type: "compact",
    position: { x: 0, y: 0 },
    data: {
      label: n.kind === "group" ? `${n.label} (${n.size})` : n.label,
      nodeType: "compact",
      kind: n.kind,
    },
  }))

  const rawEdges = graph.edges.map((e) => ({
    id: `mod_${e.source}_${e.target}`,
    source: e.source,
    target: e.target,
    type: "default",
    style: { stroke: "#94a3b8", strokeWidth: Math.min(1 + Math.log2(1 + e.count) * 0.5, 4) },
  }))

  await applyLayout(rawNodes, rawEdges, {
    "elk.direction": "RIGHT",
    "elk.aspectRatio": "1.5",
  })
}

async function buildModuleEgoGraph(mod) {
  const chunk = await loadChunk(mod.id, mod.chunk)

  let callFunctions = chunk.calls.functions
  let callEdges = chunk.calls.edges

  if (callEdges.length > EGO_EDGE_LIMIT) {
    const total = callEdges.length
    callEdges = callEdges.slice(0, EGO_EDGE_LIMIT)
    const endpointIds = new Set()
    for (const e of callEdges) {
      endpointIds.add(e.source)
      endpointIds.add(e.target)
    }
    callFunctions = callFunctions.filter((f) => endpointIds.has(f.id))
    limitNote.value = `Showing ${EGO_EDGE_LIMIT} of ${total} call edges`
  } else {
    limitNote.value = ""
  }

  const rawNodes = callFunctions.map((f) => ({
    id: f.id,
    type: "compact",
    position: { x: 0, y: 0 },
    data: {
      label: f.module === mod.id ? f.name : f.id,
      nodeType: f.external ? "external" : "call",
      callFunction: f,
    },
  }))

  const rawEdges = callEdges.map((e) => ({
    id: e.id,
    source: e.source,
    target: e.target,
    type: "default",
    style: { stroke: e.color, strokeWidth: 1.5 },
  }))

  await applyLayout(rawNodes, rawEdges, {
    "elk.direction": "RIGHT",
    "elk.aspectRatio": "1.5",
    "elk.edgeRouting": "SPLINES",
  })
}

// ── Control Flow: one function at a time ──

async function buildControlFlow() {
  limitNote.value = ""
  if (!selectedModule.value || !selectedFunctionId.value) {
    nodes.value = []
    edges.value = []
    hint.value = "Select a function from the sidebar"
    return
  }

  hint.value = ""
  const chunk = await loadChunk(selectedModule.value.id, selectedModule.value.chunk)
  const func = chunk.functions.find((f) => f.id === selectedFunctionId.value)
  if (!func) return

  const rawNodes = func.nodes.map((n) => makeCfNode(n, chunk, func))
  const rawEdges = (func.edges || []).map((edge) => ({
    id: edge.id,
    source: edge.source,
    target: edge.target,
    type: edgeStyle(edge.edge_type),
    style: edgeVisualStyle(edge),
    label: edge.label,
    labelStyle: {
      fill: edge.color,
      fontSize: 11,
      fontFamily: "ui-monospace, SFMono-Regular, monospace",
    },
    animated: edge.edge_type === "data",
  }))

  await applyLayout(rawNodes, rawEdges)
}

function makeCfNode(node, chunk, func) {
  let label = node.label
  if (!label && node.type === "entry") label = `${func.name}/${func.arity}`

  return {
    id: node.id,
    type: "code",
    position: { x: 0, y: 0 },
    data: {
      label,
      nodeType: visNodeType(node.type),
      funcId: func.id,
      lines: nodeLines(node, chunk),
      startLine: node.start_line,
    },
  }
}

function nodeLines(node, chunk) {
  if (node.source_text) return node.source_text.split("\n").map(escapeHtml)

  const linesHtml = chunk.source?.lines_html
  if (!linesHtml) return []

  const singleLine = node.type === "entry" || node.type === "exit" || node.type === "branch"
  const endLine = singleLine ? node.start_line : node.end_line
  return dedentHtmlLines(sliceLines(linesHtml, node.start_line, endLine))
}

function visNodeType(type) {
  switch (type) {
    case "entry": return "function"
    case "exit": return "exit"
    case "branch": return "match"
    case "dispatch": return "clause"
    case "clause": return "clause"
    default: return "expression"
  }
}

function edgeStyle(edgeType) {
  switch (edgeType) {
    case "branch": return "smoothstep"
    case "converge": return "smoothstep"
    case "data": return "smoothstep"
    default: return "default"
  }
}

function edgeVisualStyle(edge) {
  const width = edge.edge_type === "sequential" ? 1 : 2
  return { stroke: edge.color, strokeWidth: width }
}

// ── Data Flow: module-scoped ──

async function buildDataFlow() {
  limitNote.value = ""
  if (!selectedModule.value) {
    nodes.value = []
    edges.value = []
    hint.value = "Select a module to see its data flow"
    return
  }

  hint.value = ""
  const chunk = await loadChunk(selectedModule.value.id, selectedModule.value.chunk)

  let dataFunctions = chunk.data_flow.functions
  let dataEdges = chunk.data_flow.edges

  if (dataEdges.length > DATA_FLOW_EDGE_LIMIT) {
    const total = dataEdges.length
    dataEdges = dataEdges.slice(0, DATA_FLOW_EDGE_LIMIT)
    const endpointIds = new Set()
    for (const e of dataEdges) {
      endpointIds.add(e.source)
      endpointIds.add(e.target)
    }
    dataFunctions = dataFunctions.filter((f) => endpointIds.has(f.id))
    limitNote.value = `Showing ${DATA_FLOW_EDGE_LIMIT} of ${total} data flow edges`
  }

  const rawNodes = dataFunctions.map((f) => ({
    id: f.id,
    type: "code",
    position: { x: 0, y: 0 },
    data: { label: f.label, nodeType: "data", lines: [], startLine: f.start_line ?? 1 },
  }))

  const rawEdges = dataEdges.map((e) => ({
    id: e.id,
    source: e.source,
    target: e.target,
    type: "smoothstep",
    style: { stroke: e.color, strokeWidth: 2 },
    label: e.label,
    labelStyle: { fill: "#16a34a", fontSize: 11 },
  }))

  await applyLayout(rawNodes, rawEdges)
}

// ── Rebuild / selection ──

async function rebuild() {
  try {
    switch (mode.value) {
      case "call_graph":
        await buildCallGraph()
        break
      case "control_flow":
        await buildControlFlow()
        break
      case "data_flow":
        await buildDataFlow()
        break
    }
  } catch (e) {
    console.error("rebuild error:", e)
  }
}

watch([mode, selectedModuleId, selectedFunctionId], rebuild)
onMounted(rebuild)

function selectModule(id) {
  const next = new Set(expandedModules.value)
  next.add(id)
  expandedModules.value = next

  if (selectedModuleId.value === id) return
  selectedModuleId.value = id
  selectedFunctionId.value = null
}

function selectFunction(moduleId, funcId) {
  selectedModuleId.value = moduleId
  selectedFunctionId.value = funcId
  if (mode.value !== "control_flow") mode.value = "control_flow"
}

function clearSelection() {
  selectedModuleId.value = null
  selectedFunctionId.value = null
}

async function onNodeClick({ node }) {
  if (mode.value !== "call_graph") return

  if (!selectedModuleId.value) {
    if (node.data.kind === "group") {
      const next = new Set(expandedGroups.value)
      if (next.has(node.id)) next.delete(node.id)
      else next.add(node.id)
      expandedGroups.value = next
      await rebuild()
    } else if (moduleById.value.has(node.id)) {
      selectModule(node.id)
    }
    return
  }

  const fn = node.data.callFunction
  if (fn && !fn.external) {
    const mod = moduleById.value.get(fn.module)
    const target = mod?.functions.find((f) => `${f.name}/${f.arity}` === fn.name)
    if (mod && target) selectFunction(mod.id, target.id)
  }
}

// ── Sidebar ──

const filteredModules = computed(() => {
  const q = search.value.trim().toLowerCase()

  if (!q) {
    return props.manifest.modules.map((m) => ({
      ...m,
      functions: expandedModules.value.has(m.id) ? m.functions : [],
    }))
  }

  return props.manifest.modules
    .map((m) => {
      const nameHit = m.name.toLowerCase().includes(q)
      const funcs = m.functions.filter((f) =>
        `${f.name}/${f.arity}`.toLowerCase().includes(q)
      )
      if (!nameHit && funcs.length === 0) return null
      return { ...m, functions: nameHit && funcs.length === 0 ? m.functions : funcs }
    })
    .filter(Boolean)
})
</script>

<template>
  <div class="reach-container">
    <div class="tab-bar">
      <div class="tab-bar-tabs">
        <button class="tab" :class="{ active: mode === 'call_graph' }" @click="mode = 'call_graph'">
          Call Graph
        </button>
        <button class="tab" :class="{ active: mode === 'control_flow' }" @click="mode = 'control_flow'">
          Control Flow
        </button>
        <button class="tab" :class="{ active: mode === 'data_flow' }" @click="mode = 'data_flow'">
          Data Flow
        </button>
      </div>
      <div class="breadcrumb">
        <span>{{ manifest.project }}</span>
        <template v-if="selectedModule">
          <span>·</span>
          <span>{{ selectedModule.name }}</span>
          <button @click="clearSelection">back to overview</button>
        </template>
      </div>
    </div>

    <div class="main-area">
      <div class="sidebar">
        <div class="sidebar-title">Modules</div>
        <div class="sidebar-search">
          <input v-model="search" placeholder="Filter modules and functions…" />
        </div>
        <div v-for="mod in filteredModules" :key="mod.id" class="sidebar-module">
          <button class="sidebar-module-name" @click="selectModule(mod.id)">
            {{ mod.name }}
          </button>
          <button
            v-for="func in mod.functions"
            :key="func.id"
            class="sidebar-func"
            :class="{ active: selectedFunctionId === func.id }"
            @click="selectFunction(mod.id, func.id)"
          >
            {{ func.name }}/{{ func.arity }}
          </button>
        </div>
      </div>

      <div class="reach-flow-wrap">
        <VueFlow
          :nodes="nodes"
          :edges="edges"
          :node-types="nodeTypes"
          :default-edge-options="{ type: 'smoothstep' }"
          :min-zoom="0.1"
          :max-zoom="3"
          :nodes-draggable="false"
          class="reach-flow"
          @node-click="onNodeClick"
        >
          <MiniMap pannable zoomable />
          <Controls />
        </VueFlow>
        <div v-if="hint" class="hint-overlay">{{ hint }}</div>
        <div v-if="limitNote" class="limit-note">{{ limitNote }}</div>
      </div>
    </div>
  </div>
</template>
