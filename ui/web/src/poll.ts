// Run `fn` now and then every `ms` while the component is mounted and the browser tab is visible.
// Never overlaps itself: the next run is scheduled after the previous one settles. Errors are left to `fn`.
import { onBeforeUnmount, onMounted } from 'vue'

export function usePoll(fn: () => Promise<void>, ms: number): { refresh: () => Promise<void> } {
  let timer: ReturnType<typeof setTimeout> | undefined
  let alive = false

  const refresh = async (): Promise<void> => {
    clearTimeout(timer)
    if (!document.hidden) {
      try { await fn() } catch { /* fn reports its own errors; polling just keeps going */ }
    }
    if (alive) timer = setTimeout(refresh, ms)
  }
  const onVisible = () => { if (!document.hidden && alive) void refresh() }

  onMounted(() => { alive = true; document.addEventListener('visibilitychange', onVisible); void refresh() })
  onBeforeUnmount(() => { alive = false; clearTimeout(timer); document.removeEventListener('visibilitychange', onVisible) })
  return { refresh }
}
