<script setup lang="ts">
// Live view of a worker's tmux pane: polls /api/term once a second while this tab is open and visible.
import { computed, nextTick, ref, watch } from 'vue'
import { api } from '../api'
import { state } from '../store'
import { route, go } from '../route'
import { usePoll } from '../poll'

const props = defineProps<{ project: string }>()

const tags = computed(() => state.value.panes.filter((t) => t.startsWith(props.project + '-')))
const tag = computed(() => route.arg || tags.value[0] || '')
const text = ref<string | null>(null)
const failed = ref(false)
const screen = ref<HTMLElement>()

const { refresh } = usePoll(async () => {
  const want = tag.value
  if (!want) return
  try {
    const r = await api.term(want, AbortSignal.timeout(4000))
    if (want !== tag.value) return // the user switched worker while this was in flight
    const el = screen.value
    const stick = !el || el.scrollTop + el.clientHeight >= el.scrollHeight - 30 // follow output unless the user scrolled up
    text.value = r.text
    failed.value = false
    if (stick) await nextTick(() => { if (screen.value) screen.value.scrollTop = screen.value.scrollHeight })
  } catch {
    failed.value = true
  }
}, 1000)

watch(tag, () => { text.value = null; void refresh() })
</script>

<template>
  <div class="bar">
    <label for="pane" class="muted">Worker</label>
    <select id="pane" class="sel" :value="tag" :disabled="!tags.length" @change="go({ project, tab: 'terminal', arg: ($event.target as HTMLSelectElement).value })">
      <option v-if="tag && !tags.includes(tag)" :value="tag">{{ tag }} (closed)</option>
      <option v-for="t in tags" :key="t" :value="t">{{ t }}</option>
      <option v-if="!tags.length" value="">No workers</option>
    </select>
    <span v-if="failed" class="err">connection lost</span>
  </div>
  <pre ref="screen" class="screen scroll" tabindex="0" aria-label="Worker terminal output">{{
    !tag ? 'No worker panes are open for this project.' : text === null ? (failed ? '' : 'Pane is closed or has not started.') : text || '(empty)'
  }}</pre>
</template>

<style scoped>
.bar { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; }
.sel { padding: 5px 8px; background: var(--surface); border: 1px solid var(--border-strong); border-radius: 8px; min-width: 200px; }
.err { color: var(--err); font-size: 13px; }
.screen {
  margin: 0; padding: 14px 16px; height: calc(100% - 44px); min-height: 280px;
  background: var(--term-bg); color: var(--term-text); border: 1px solid var(--border); border-radius: var(--radius);
  font: 12.5px/1.45 var(--mono); white-space: pre-wrap; overflow-wrap: anywhere;
}
</style>
