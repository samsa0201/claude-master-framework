// Hash routing: #/<project>/<tab>/<arg>. No router dependency; the server only ever serves index.html.
import { reactive } from 'vue'

export const TABS = ['overview', 'docs', 'changes', 'terminal'] as const
export type Tab = (typeof TABS)[number]
export interface Route { project: string; tab: Tab; arg: string }

const dec = (s: string): string => {
  try { return decodeURIComponent(s) } catch { return s }
}

export function parseHash(hash: string): Route {
  const [project = '', tab = '', ...rest] = hash.replace(/^#\/?/, '').split('/')
  return {
    project: dec(project),
    tab: (TABS as readonly string[]).includes(tab) ? (tab as Tab) : 'overview',
    arg: dec(rest.join('/')),
  }
}

export function buildHash(r: Partial<Route> & { project: string }): string {
  const tab = r.tab ?? 'overview'
  return '#/' + [r.project, ...(tab === 'overview' && !r.arg ? [] : [tab]), ...(r.arg ? [r.arg] : [])].map(encodeURIComponent).join('/')
}

export const route = reactive<Route>(parseHash(location.hash))

addEventListener('hashchange', () => Object.assign(route, parseHash(location.hash)))

export function go(r: Partial<Route> & { project: string }, replace = false): void {
  const h = buildHash(r)
  if (replace) history.replaceState(null, '', h)
  else location.hash = h
  Object.assign(route, parseHash(h)) // replaceState fires no hashchange
}
