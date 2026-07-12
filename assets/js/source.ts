export function sliceLines(linesHtml: string[], startLine: number, endLine: number): string[] {
  const start = Math.max(startLine - 1, 0)
  const end = Math.max(endLine, start + 1)
  return linesHtml.slice(start, end)
}

export function lineText(html: string): string {
  const el = document.createElement("div")
  el.innerHTML = html
  return el.textContent ?? ""
}

export function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
}

export function dedentHtmlLines(lines: string[]): string[] {
  const texts = lines.map(lineText)
  const indents = texts.filter((t) => t.trim() !== "").map((t) => t.length - t.trimStart().length)
  const min = indents.length ? Math.min(...indents) : 0
  if (min === 0) return lines
  return lines.map((line) => stripLeadingChars(line, min))
}

function stripLeadingChars(html: string, count: number): string {
  const el = document.createElement("div")
  el.innerHTML = html
  let remaining = count

  const strip = (node: Node): boolean => {
    if (node.nodeType === Node.TEXT_NODE) {
      const text = node.textContent ?? ""
      const leading = text.length - text.trimStart().length
      const take = Math.min(remaining, leading)
      node.textContent = text.slice(take)
      remaining -= take
      return remaining <= 0 || text.trim() !== ""
    }
    for (const child of Array.from(node.childNodes)) {
      if (strip(child)) return true
    }
    return false
  }

  strip(el)
  return el.innerHTML
}
