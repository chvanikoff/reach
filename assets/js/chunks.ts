import type { Chunk } from "@reach/types"

const cache = new Map<string, Promise<Chunk>>()
const resolvers = new Map<string, (chunk: Chunk) => void>()

declare global {
  interface Window {
    __reachChunk: (id: string, data: Chunk) => void
  }
}

window.__reachChunk = (id: string, data: Chunk) => {
  resolvers.get(id)?.(data)
  resolvers.delete(id)
}

export function loadChunk(id: string, chunkPath: string): Promise<Chunk> {
  const cached = cache.get(id)
  if (cached) return cached

  const promise = new Promise<Chunk>((resolve, reject) => {
    resolvers.set(id, resolve)
    const script = document.createElement("script")
    script.src = chunkPath
    script.onerror = () => {
      resolvers.delete(id)
      cache.delete(id)
      reject(new Error(`failed to load chunk: ${chunkPath}`))
    }
    document.head.appendChild(script)
  })

  cache.set(id, promise)
  return promise
}
