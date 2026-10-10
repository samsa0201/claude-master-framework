// Unified-diff parser for `git diff` / `git show` output (unit-tested in diff.test.ts).
export type LineKind = 'add' | 'del' | 'ctx' | 'meta'
export interface DiffLine { kind: LineKind; text: string; oldNo: number | null; newNo: number | null }
export interface Hunk { header: string; lines: DiffLine[] }
export type FileStatus = 'modified' | 'added' | 'deleted' | 'renamed' | 'binary'
export interface FileDiff {
  path: string
  oldPath: string | null // differs from path only for renames
  status: FileStatus
  hunks: Hunk[]
  adds: number
  dels: number
  lineCount: number
}

const stripPrefix = (p: string) => p.replace(/^[ab]\//, '')

export function parseDiff(text: string): FileDiff[] {
  const files: FileDiff[] = []
  let file: FileDiff | null = null
  let hunk: Hunk | null = null
  let oldNo = 0
  let newNo = 0

  for (const line of text.split('\n')) {
    if (line.startsWith('diff --git ')) {
      // "diff --git a/x b/x": the two paths are equal unless renamed (fixed up by rename/---/+++ lines below)
      const same = /^diff --git a\/(.*) b\/\1$/.exec(line)
      const m = same ?? /^diff --git a\/(.*) b\/(.*)$/.exec(line)
      file = { path: (same ? same[1] : m?.[2]) ?? line.slice(11), oldPath: null, status: 'modified', hunks: [], adds: 0, dels: 0, lineCount: 0 }
      if (m && !same) file.oldPath = m[1]!
      files.push(file)
      hunk = null
      continue
    }
    if (!file) continue

    if (!hunk) { // still in the file header
      if (line.startsWith('new file mode')) file.status = 'added'
      else if (line.startsWith('deleted file mode')) file.status = 'deleted'
      else if (line.startsWith('rename from ')) { file.status = 'renamed'; file.oldPath = line.slice(12) }
      else if (line.startsWith('rename to ')) file.path = line.slice(10)
      else if (line.startsWith('Binary files ') || line.startsWith('GIT binary patch')) file.status = 'binary'
      else if (line.startsWith('+++ ') && line !== '+++ /dev/null') file.path = stripPrefix(line.slice(4)) // exact even when names contain spaces
    }

    const h = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(line)
    if (h) {
      oldNo = +h[1]!
      newNo = +h[2]!
      hunk = { header: line, lines: [] }
      file.hunks.push(hunk)
      continue
    }
    if (!hunk) continue

    const c = line[0]
    if (c === '+') { hunk.lines.push({ kind: 'add', text: line.slice(1), oldNo: null, newNo: newNo++ }); file.adds++ }
    else if (c === '-') { hunk.lines.push({ kind: 'del', text: line.slice(1), oldNo: oldNo++, newNo: null }); file.dels++ }
    else if (c === ' ') hunk.lines.push({ kind: 'ctx', text: line.slice(1), oldNo: oldNo++, newNo: newNo++ })
    else if (c === '\\') hunk.lines.push({ kind: 'meta', text: line, oldNo: null, newNo: null })
    // anything else (a trailing empty line, the next commit's header) ends nothing: it is simply not a diff line
  }
  for (const f of files) f.lineCount = f.hunks.reduce((n, x) => n + x.lines.length, 0)
  return files
}

export const totals = (files: FileDiff[]) => ({
  files: files.length,
  adds: files.reduce((n, f) => n + f.adds, 0),
  dels: files.reduce((n, f) => n + f.dels, 0),
})
