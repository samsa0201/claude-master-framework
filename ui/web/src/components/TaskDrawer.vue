<script setup lang="ts">
// Side panel with a task's brief (.team/tasks/<id>.md) and the worker's report (.team/out/<id>.md).
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { api, ApiError, type Task } from '../api'
import Icon from './Icon.vue'
import Markdown from './Markdown.vue'
import StatusBadge from './StatusBadge.vue'

const props = defineProps<{ task: Task }>()
const emit = defineEmits<{ close: [] }>()

const brief = ref<string | null>(null)
const report = ref<string | null>(null)
const loading = ref(true)
const root = ref<HTMLElement>()
const closeBtn = ref<HTMLButtonElement>()
let opener: Element | null = null

async function text(path: string): Promise<string | null> {
  try {
    return (await api.file(props.task.proj, path)).text.replace(/^# Task .*\n+/, '') // the drawer header already says which task
  } catch (e) {
    if (e instanceof ApiError && e.status === 404) return null // the file simply isn't there (yet)
    throw e
  }
}

async function load() {
  loading.value = true
  const id = props.task.id
  try {
    const hasReport = props.task.status === 'done' || !!props.task.summary // avoids a pointless 404 for tasks still running
    const [b, r] = await Promise.all([text(`.team/tasks/${id}.md`), hasReport ? text(`.team/out/${id}.md`) : null])
    if (props.task.id === id) [brief.value, report.value] = [b, r]
  } catch {
    brief.value = report.value = null
  } finally {
    loading.value = false
  }
}

function onKey(e: KeyboardEvent) {
  if (e.key === 'Escape') return emit('close')
  if (e.key !== 'Tab' || !root.value) return // keep focus inside the dialog
  const els = [...root.value.querySelectorAll<HTMLElement>('button, a[href], [tabindex="0"]')]
  const [first, last] = [els[0], els[els.length - 1]]
  if (e.shiftKey && document.activeElement === first) { last?.focus(); e.preventDefault() }
  else if (!e.shiftKey && document.activeElement === last) { first?.focus(); e.preventDefault() }
}

onMounted(async () => {
  opener = document.activeElement
  addEventListener('keydown', onKey)
  void load()
  await nextTick()
  closeBtn.value?.focus()
})
onBeforeUnmount(() => {
  removeEventListener('keydown', onKey)
  if (opener instanceof HTMLElement) opener.focus()
})
watch(() => props.task.id, load)
// a running task's report appears when the worker finishes
watch(() => [props.task.status, props.task.summary], load)
</script>

<template>
  <div class="scrim" @click="emit('close')" />
  <aside ref="root" class="drawer" role="dialog" aria-modal="true" :aria-label="`Task ${task.id}`">
    <header>
      <div class="hd">
        <div class="id mono">{{ task.id }}</div>
        <div class="meta"><StatusBadge :kind="task.status" /> <span class="muted">{{ task.seat }}</span></div>
      </div>
      <button ref="closeBtn" class="btn" aria-label="Close" @click="emit('close')"><Icon name="x" /></button>
    </header>
    <div class="scroll body">
      <div v-if="loading" class="muted">Loading…</div>
      <template v-else>
        <h2>Report</h2>
        <Markdown v-if="report" :source="report" />
        <p v-else class="muted">{{ task.status === 'working' ? 'The worker has not reported yet.' : 'No report was written.' }}</p>
        <h2>Task brief</h2>
        <Markdown v-if="brief" :source="brief" />
        <p v-else class="muted">The task file is gone.</p>
      </template>
    </div>
  </aside>
</template>

<style scoped>
.scrim { position: fixed; inset: 0; background: rgb(0 0 0 / 0.35); z-index: 20; }
.drawer { position: fixed; top: 0; right: 0; bottom: 0; z-index: 21; width: min(640px, 100vw); display: flex; flex-direction: column; background: var(--surface); border-left: 1px solid var(--border); box-shadow: var(--shadow); animation: slide 0.18s ease-out; }
@keyframes slide { from { transform: translateX(24px); opacity: 0; } }
header { display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; padding: 16px 20px; border-bottom: 1px solid var(--border); }
.id { font-size: 13px; overflow-wrap: anywhere; }
.meta { display: flex; align-items: center; gap: 10px; margin-top: 6px; }
.body { flex: 1; padding: 6px 20px 28px; }
h2 { margin: 22px 0 10px; font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
</style>
