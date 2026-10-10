<script setup lang="ts">
// Side panel with a task's check results, the worker's report (.team/out/<id>.md), its brief (.team/tasks/<id>.md) and a saved copy of its screen.
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { api, ApiError, type Task } from '../api'
import Icon from './Icon.vue'
import Markdown from './Markdown.vue'
import StatusBadge from './StatusBadge.vue'
import VerifyBadge from './VerifyBadge.vue'

const props = defineProps<{ task: Task }>()
const emit = defineEmits<{ close: [] }>()

const brief = ref<string | null>(null)
const report = ref<string | null>(null)
const screen = ref<string | null>(null)
const screenWhen = computed(() => screen.value?.match(/^# Worker screen of \S+ (\(.*\))/)?.[1] ?? '') // "(done, 2026-…)"
const screenBody = computed(() => screen.value?.replace(/^# .*\n+/, '') ?? '')
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
    const [b, r, sc] = await Promise.all([text(`.team/tasks/${id}.md`), hasReport ? text(`.team/out/${id}.md`) : null,
      props.task.log ? text(`.team/logs/${id}.md`) : null])
    if (props.task.id === id) [brief.value, report.value, screen.value] = [b, r, sc]
  } catch {
    brief.value = report.value = screen.value = null
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
watch(() => [props.task.status, props.task.summary, props.task.verify?.status, props.task.log], load)
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
        <template v-if="task.verify">
          <h2>Checks</h2>
          <p class="vsum"><VerifyBadge :verify="task.verify" /> {{ task.verify.summary }}</p>
          <pre v-if="task.verify.details" class="vdet">{{ task.verify.details }}</pre>
        </template>
        <h2>Report</h2>
        <Markdown v-if="report" :source="report" />
        <p v-else class="muted">{{ task.status === 'working' ? 'The worker has not reported yet.' : 'No report was written.' }}</p>
        <h2>Task brief</h2>
        <Markdown v-if="brief" :source="brief" />
        <p v-else class="muted">The task file is gone.</p>
        <template v-if="screen">
          <h2>Worker screen <span class="when">{{ screenWhen }}</span></h2>
          <Markdown :source="screenBody" />
        </template>
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
h2 .when { text-transform: none; letter-spacing: 0; font-weight: 400; }
.vsum { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 10px; margin: 0 0 8px; overflow-wrap: anywhere; }
.vdet { margin: 0; padding: 10px 12px; background: var(--surface-2); border: 1px solid var(--border); border-radius: 8px; font: 12.5px/1.5 var(--mono); white-space: pre-wrap; overflow-wrap: anywhere; }
h2 { margin: 22px 0 10px; font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
</style>
