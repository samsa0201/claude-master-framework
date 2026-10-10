import { expect, test } from 'bun:test'
import type { StudioState, Task } from './api'
import { projectSummaries, statsOf, workersOf } from './model'

const task = (o: Partial<Task>): Task => ({
  id: 'x', proj: 'p', title: 't', summary: '', start: 100, end: null, role: 'dev', seat: 'dev', worker: null, status: 'stale', verify: null, log: false, ...o,
})
const st = (o: Partial<StudioState>): StudioState => ({ tasks: [], live: [], panes: [], projects: [], ...o })

test('worker states: working / stale / idle / offline', () => {
  const s = st({
    tasks: [
      task({ id: 'a', seat: 'dev', status: 'working', worker: 'p-dev' }),
      task({ id: 'b', seat: 'qa', status: 'stale' }),
      task({ id: 'c', seat: 'qc', status: 'done', end: 150 }),
      task({ id: 'd', seat: 'docs', status: 'done', end: 150 }),
      task({ id: 'e', proj: 'other', seat: 'zzz' }),
    ],
    panes: ['p-dev', 'p-qc', 'other-zzz'],
  })
  const by = Object.fromEntries(workersOf(s, 'p').map((w) => [w.seat, w.state]))
  expect(by).toEqual({ dev: 'working', qa: 'stale', qc: 'idle', docs: 'offline' })
})

test('latest task per seat wins; seats are sorted; panes without tasks still show', () => {
  const s = st({
    tasks: [task({ id: 'a', seat: 'dev', status: 'done', end: 120 }), task({ id: 'b', seat: 'dev', start: 200, status: 'working' })],
    panes: ['p-dev', 'p-ux', 'p-dev-2'],
  })
  const ws = workersOf(s, 'p')
  expect(ws.map((w) => w.seat)).toEqual(['dev', 'dev-2', 'ux'])
  expect(ws[0]!.task!.id).toBe('b')
  expect(ws[0]!.taskCount).toBe(2)
  expect(ws[1]!.task).toBeNull()
  expect(ws[1]!.state).toBe('idle')
})

test('a project name that prefixes another does not leak its panes', () => {
  const s = st({ panes: ['web-dev', 'web-app-dev'] })
  expect(workersOf(s, 'web').map((w) => w.tag)).toEqual(['web-app-dev', 'web-dev'])
  expect(workersOf(s, 'web-app').map((w) => w.seat)).toEqual(['dev'])
})

test('statsOf', () => {
  const ts = [task({ status: 'done' }), task({ status: 'working' }), task({ status: 'working' }), task({ status: 'stale' })]
  expect(statsOf(ts)).toEqual({ total: 4, done: 1, active: 2, stale: 1, failed: 0 })
  const failing = task({ status: 'done', verify: { status: 'fail', summary: 'tests failed', details: '' } })
  expect(statsOf([...ts, failing, task({ status: 'done', verify: { status: 'ok', summary: '', details: '' } })]).failed).toBe(1)
})

test('projectSummaries: recent first, task-less projects last by name', () => {
  const s = st({
    projects: ['zeta', 'old', 'new', 'alpha'],
    tasks: [task({ proj: 'old', start: 10, end: 20, status: 'done' }), task({ proj: 'new', start: 500, status: 'working' })],
  })
  expect(projectSummaries(s).map((p) => p.name)).toEqual(['new', 'old', 'alpha', 'zeta'])
  expect(projectSummaries(s)[0]).toMatchObject({ active: 1, total: 1 })
})
