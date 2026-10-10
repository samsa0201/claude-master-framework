// Shapes returned by ui/serve.py. Read-only: every call is a GET.
export type TaskStatus = 'working' | 'done' | 'stale'

export interface Task {
  id: string
  proj: string
  title: string
  summary: string
  start: number // unix seconds
  end: number | null
  role: string
  seat: string // worker pane name inside the project, e.g. dev-fe-2
  worker: string | null // live pane tag while the pane still holds this task
  status: TaskStatus
}

export interface StudioState {
  tasks: Task[]
  live: string[] // tags of panes working on a task right now
  panes: string[] // every tagged pane: <project>-<seat>
  projects: string[]
}

export interface DocFile { path: string; group: string; name: string; size: number; mtime: number }
export interface DocContent { path: string; text: string; truncated: boolean; mtime: number }
export interface Skipped { path: string; reason: string }
export interface DiffResult {
  diff: string
  untracked: string[]
  skipped: Skipped[]
  truncated: boolean
  head: string | null
  branch: string | null
}
export interface Commit { sha: string; short: string; author: string; time: number; subject: string }
export interface CommitDetail extends Commit { body: string; diff: string; truncated: boolean }
export interface Term { tag: string; text: string | null }

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}

async function get<T>(path: string, signal?: AbortSignal): Promise<T> {
  const res = await fetch(path, { signal, headers: { Accept: 'application/json' } })
  let body: unknown = null
  try {
    body = await res.json()
  } catch {
    /* non-JSON error page */
  }
  if (!res.ok) throw new ApiError(res.status, (body as { error?: string } | null)?.error ?? res.statusText)
  return body as T
}

const enc = encodeURIComponent
const proj = (p: string) => `/api/projects/${enc(p)}`

export const api = {
  state: (signal?: AbortSignal) => get<StudioState>('/api/state', signal),
  term: (tag: string, signal?: AbortSignal) => get<Term>(`/api/term?tag=${enc(tag)}`, signal),
  files: (p: string) => get<{ files: DocFile[] }>(`${proj(p)}/files`).then((r) => r.files),
  file: (p: string, path: string) => get<DocContent>(`${proj(p)}/file?path=${enc(path)}`),
  diff: (p: string) => get<DiffResult>(`${proj(p)}/diff`),
  log: (p: string) => get<{ commits: Commit[] }>(`${proj(p)}/log`).then((r) => r.commits),
  commit: (p: string, sha: string) => get<CommitDetail>(`${proj(p)}/commit?sha=${enc(sha)}`),
}
