// Pure derivations over the server state (unit-tested in model.test.ts).
import type { StudioState, Task } from './api'

export type WorkerState = 'working' | 'idle' | 'offline' | 'stale'

export interface Worker {
  seat: string
  tag: string // tmux pane tag: <project>-<seat>
  state: WorkerState
  online: boolean // its pane is still open
  task: Task | null // latest task given to this seat
  taskCount: number
}

export interface Stats { total: number; done: number; active: number; stale: number; failed: number }
export interface ProjectSummary { name: string; active: number; stale: number; total: number; last: number }

export const statsOf = (tasks: Task[]): Stats => ({
  total: tasks.length,
  done: tasks.filter((t) => t.status === 'done').length,
  active: tasks.filter((t) => t.status === 'working').length,
  stale: tasks.filter((t) => t.status === 'stale').length,
  failed: tasks.filter((t) => t.verify?.status === 'fail').length, // finished, but its checks failed
})

export const tasksOf = (s: StudioState, project: string): Task[] => s.tasks.filter((t) => t.proj === project)

export function workersOf(s: StudioState, project: string): Worker[] {
  const prefix = project + '-'
  const latest = new Map<string, Task>()
  const counts = new Map<string, number>()
  for (const t of tasksOf(s, project)) { // server sorts by start, so the last one per seat is the latest
    latest.set(t.seat, t)
    counts.set(t.seat, (counts.get(t.seat) ?? 0) + 1)
  }
  const seats = new Set(latest.keys())
  for (const tag of s.panes) if (tag.startsWith(prefix)) seats.add(tag.slice(prefix.length))
  return [...seats].sort().map((seat) => {
    const task = latest.get(seat) ?? null
    const online = s.panes.includes(prefix + seat)
    const state: WorkerState =
      task?.status === 'working' ? 'working' : task?.status === 'stale' ? 'stale' : online ? 'idle' : 'offline'
    return { seat, tag: prefix + seat, state, online, task, taskCount: counts.get(seat) ?? 0 }
  })
}

// most recently active project first; projects that never had a task (just created) go last, alphabetically
export function projectSummaries(s: StudioState): ProjectSummary[] {
  const names = new Set([...s.projects, ...s.tasks.map((t) => t.proj)])
  return [...names]
    .map((name) => {
      const ts = tasksOf(s, name)
      const st = statsOf(ts)
      return { name, active: st.active, stale: st.stale, total: st.total, last: Math.max(0, ...ts.map((t) => t.end ?? t.start)) }
    })
    .sort((a, b) => b.last - a.last || a.name.localeCompare(b.name))
}
