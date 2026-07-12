import ReachGraph from "@reach/components/ReachGraph.vue"
import { createApp } from "vue"

createApp(ReachGraph, {
  manifest: (window as Record<string, unknown>).__reachManifest
}).mount("#app")
