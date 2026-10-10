// Polls /api/state; pauses while the browser tab is hidden. `now` ticks once a second for live durations.
import { ref } from 'vue'
import { api, type StudioState } from './api'

export const state = ref<StudioState>({ tasks: [], live: [], panes: [], projects: [] })
export const loaded = ref(false)
export const linkDown = ref(false)
export const now = ref(Date.now() / 1000)

let timer: ReturnType<typeof setTimeout> | undefined

async function tick(): Promise<void> {
  clearTimeout(timer)
  try {
    state.value = await api.state(AbortSignal.timeout(5000))
    linkDown.value = false
    loaded.value = true
  } catch {
    linkDown.value = true
  }
  if (!document.hidden) timer = setTimeout(tick, linkDown.value ? 4000 : 2000)
}

export function startPolling(): void {
  void tick()
  document.addEventListener('visibilitychange', () => { if (!document.hidden) void tick() })
  setInterval(() => { now.value = Date.now() / 1000 }, 1000)
}
