<script setup lang="ts">
// Project documents: docs/*.md plus the studio's own notes (.team/roles, task briefs, worker reports). Read-only.
import { computed, ref, watch } from 'vue'
import { api, ApiError, type DocContent, type DocFile } from '../api'
import { route, go } from '../route'
import { now } from '../store'
import { ago, bytes } from '../format'
import { usePoll } from '../poll'
import Markdown from './Markdown.vue'
import Icon from './Icon.vue'

const props = defineProps<{ project: string }>()

const GROUPS = [
  { key: 'docs', label: 'Docs' },
  { key: '.team/roles', label: 'Role notes' },
  { key: '.team/tasks', label: 'Task briefs' },
  { key: '.team/out', label: 'Reports' },
  { key: '.team/logs', label: 'Worker screens' },
]
const DOC_ORDER = ['idea', 'prd', 'architecture', 'ux', 'feature'] // the usual reading order; everything else alphabetical after

const files = ref<DocFile[]>([])
const listed = ref(false)
const problem = ref('')
const groups = computed(() =>
  GROUPS.map((g) => {
    const fs = files.value.filter((f) => f.group === g.key)
    const rank = (f: DocFile) => { const i = DOC_ORDER.indexOf(f.name.replace(/\.md$/, '')); return i < 0 ? DOC_ORDER.length : i }
    fs.sort(g.key === 'docs' || g.key === '.team/roles' ? (a, b) => rank(a) - rank(b) || a.path.localeCompare(b.path) : (a, b) => b.mtime - a.mtime)
    return { ...g, files: fs }
  }).filter((g) => g.files.length),
)
const rel = (f: DocFile, group: string) => f.path.slice(group.length + 1)

const selected = computed(() => route.arg || (files.value.find((f) => f.path === 'docs/prd.md') ?? groups.value[0]?.files[0])?.path || '')
const current = computed(() => files.value.find((f) => f.path === selected.value))

const doc = ref<DocContent | null>(null)
const docError = ref('')
let loadedAt = '' // path@mtime of what `doc` shows, so unchanged files are not refetched on every list refresh

async function loadDoc(path: string, mtime: number) {
  const id = `${path}@${mtime}`
  if (id === loadedAt) return
  try {
    const d = await api.file(props.project, path)
    if (selected.value !== path) return // user moved on while loading
    doc.value = d
    docError.value = ''
    loadedAt = id
  } catch (e) {
    if (selected.value !== path) return
    doc.value = null
    docError.value = e instanceof ApiError && e.status === 404 ? 'This file no longer exists.' : `Could not load: ${(e as Error).message}`
  }
}

usePoll(async () => {
  try {
    files.value = await api.files(props.project)
    problem.value = ''
  } catch (e) {
    problem.value = `Could not list documents: ${(e as Error).message}`
  }
  listed.value = true
}, 5000)

// reload when the selection changes, or when the worker rewrites the open file (its mtime moves)
watch([selected, () => current.value?.mtime], ([path, mtime]) => {
  if (!path) { doc.value = null; docError.value = ''; loadedAt = ''; return }
  if (path !== doc.value?.path) { doc.value = null; docError.value = ''; loadedAt = '' }
  void loadDoc(path, mtime ?? 0)
}, { immediate: true })

const pick = (e: Event) => go({ project: props.project, tab: 'docs', arg: (e.target as HTMLSelectElement).value })
</script>

<template>
  <div v-if="problem" class="empty card">{{ problem }}</div>
  <div v-else-if="listed && !files.length" class="empty card">
    No documents yet. The lead writes <code>docs/prd.md</code>, <code>docs/architecture.md</code> or <code>docs/feature.md</code> as a project moves along.
  </div>
  <div v-else class="layout">
    <nav class="tree card" aria-label="Documents">
      <details v-for="g in groups" :key="g.key" :open="g.key === 'docs' || g.key === '.team/roles' || selected.startsWith(g.key + '/')">
        <summary>{{ g.label }} <span class="n muted">{{ g.files.length }}</span></summary>
        <a v-for="f in g.files" :key="f.path" class="item" :class="{ on: f.path === selected }" :title="f.path"
           :href="'#/' + encodeURIComponent(project) + '/docs/' + encodeURIComponent(f.path)" :aria-current="f.path === selected ? 'true' : undefined"
           @click.prevent="go({ project, tab: 'docs', arg: f.path })">
          <Icon name="doc" :size="14" /> <span class="nm">{{ rel(f, g.key) }}</span>
        </a>
      </details>
    </nav>

    <select class="pick" aria-label="Document" :value="selected" @change="pick">
      <optgroup v-for="g in groups" :key="g.key" :label="g.label">
        <option v-for="f in g.files" :key="f.path" :value="f.path">{{ rel(f, g.key) }}</option>
      </optgroup>
    </select>

    <article class="doc card">
      <header v-if="current">
        <span class="mono path">{{ current.path }}</span>
        <span class="muted">{{ bytes(current.size) }} · updated {{ ago(now - current.mtime) }}</span>
      </header>
      <div class="content">
        <p v-if="docError" class="muted">{{ docError }}</p>
        <template v-else-if="doc">
          <p v-if="doc.truncated" class="warn" role="status">This document is large; only the first part is shown.</p>
          <Markdown :source="doc.text" />
        </template>
        <p v-else class="muted">{{ selected ? 'Loading…' : 'Select a document.' }}</p>
      </div>
    </article>
  </div>
</template>

<style scoped>
.layout { display: grid; grid-template-columns: 250px minmax(0, 1fr); gap: 18px; align-items: start; }
.tree { position: sticky; top: 0; max-height: calc(100vh - 190px); overflow: auto; padding: 6px; scrollbar-width: thin; }
summary { padding: 8px 8px 4px; font-size: 11px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); cursor: pointer; }
.n { margin-left: 4px; font-variant-numeric: tabular-nums; }
.item { display: flex; align-items: center; gap: 7px; padding: 6px 8px; border-radius: 8px; color: var(--text); }
.item:hover { background: var(--surface-2); text-decoration: none; }
.item.on { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
.item :deep(svg) { flex: none; color: var(--muted); }
.item.on :deep(svg) { color: inherit; }
.nm { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pick { display: none; width: 100%; padding: 7px 8px; background: var(--surface); border: 1px solid var(--border-strong); border-radius: 8px; }
.doc header { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 4px 16px; padding: 10px 18px; border-bottom: 1px solid var(--border); font-size: 12.5px; }
.content { padding: 8px 24px 28px; }
.warn { padding: 8px 12px; border-radius: 8px; background: var(--warn-soft); color: var(--warn); }
@media (max-width: 860px) {
  .layout { grid-template-columns: minmax(0, 1fr); gap: 12px; }
  .tree { display: none; }
  .pick { display: block; }
  .content { padding: 4px 16px 22px; }
}
</style>
