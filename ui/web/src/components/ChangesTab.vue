<script setup lang="ts">
// What the workers changed: the uncommitted working tree (git diff HEAD + untracked files) and recent commits.
import { computed, ref, watch } from 'vue'
import { api, ApiError, type Commit, type CommitDetail, type DiffResult } from '../api'
import { route, go } from '../route'
import { now } from '../store'
import { ago } from '../format'
import { parseDiff, totals } from '../diff'
import { usePoll } from '../poll'
import DiffView from './DiffView.vue'
import Icon from './Icon.vue'

const props = defineProps<{ project: string }>()

const tree = ref<DiffResult | null>(null)
const commits = ref<Commit[]>([])
const problem = ref('') // not a git repo / server error
const sha = computed(() => route.arg) // '' = working tree
const treeFiles = computed(() => parseDiff(tree.value?.diff ?? ''))
const treeTotals = computed(() => totals(treeFiles.value))

const detail = ref<CommitDetail | null>(null)
const detailError = ref('')
const cache = new Map<string, CommitDetail>() // commits are immutable
const detailFiles = computed(() => parseDiff(detail.value?.diff ?? ''))

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b)

const { refresh } = usePoll(async () => {
  try {
    const [d, c] = await Promise.all([api.diff(props.project), api.log(props.project)])
    if (!same(d, tree.value)) tree.value = d // keep the old object when nothing changed: no re-parse, no re-render
    if (!same(c, commits.value)) commits.value = c
    problem.value = ''
  } catch (e) {
    problem.value = e instanceof ApiError && e.status === 404 ? 'This project is not a git repository (yet).' : `Could not load changes: ${(e as Error).message}`
  }
}, 4000)

watch(sha, async (s) => {
  detail.value = null
  detailError.value = ''
  if (!s) return
  try {
    const d = cache.get(s) ?? (await api.commit(props.project, s))
    cache.set(s, d)
    if (sha.value === s) detail.value = d
  } catch (e) {
    if (sha.value === s) detailError.value = (e as Error).message
  }
}, { immediate: true })

const pick = (e: Event) => go({ project: props.project, tab: 'changes', arg: (e.target as HTMLSelectElement).value })
</script>

<template>
  <div v-if="problem" class="empty card">{{ problem }}</div>
  <div v-else class="layout">
    <nav class="list card" aria-label="Changes">
      <a class="item" :class="{ on: !sha }" :href="'#/' + encodeURIComponent(project) + '/changes'" :aria-current="!sha ? 'true' : undefined"
         @click.prevent="go({ project, tab: 'changes' })">
        <span class="t"><Icon name="diff" :size="14" /> Uncommitted changes</span>
        <span class="s muted">{{ tree ? (treeFiles.length || tree.skipped.length ? `${treeFiles.length} file${treeFiles.length === 1 ? '' : 's'}` : 'clean') : '…' }}</span>
      </a>
      <div class="label">Commits</div>
      <a v-for="c in commits" :key="c.sha" class="item" :class="{ on: sha === c.sha }"
         :href="'#/' + encodeURIComponent(project) + '/changes/' + c.sha" :aria-current="sha === c.sha ? 'true' : undefined"
         @click.prevent="go({ project, tab: 'changes', arg: c.sha })">
        <span class="t sub">{{ c.subject }}</span>
        <span class="s muted"><span class="mono">{{ c.short }}</span> · {{ c.author }} · {{ ago(now - c.time) }}</span>
      </a>
      <div v-if="!commits.length" class="none muted">No commits yet</div>
    </nav>

    <select class="pick" aria-label="Changes" :value="sha" @change="pick">
      <option value="">Uncommitted changes</option>
      <option v-for="c in commits" :key="c.sha" :value="c.sha">{{ c.short }} {{ c.subject }}</option>
    </select>

    <div class="main">
      <!-- working tree -->
      <template v-if="!sha">
        <div class="bar">
          <h2>Uncommitted changes</h2>
          <span v-if="tree?.branch" class="muted mono">{{ tree.branch }}</span>
          <span class="nums mono"><b class="add">+{{ treeTotals.adds }}</b> <b class="del">−{{ treeTotals.dels }}</b></span>
          <button class="btn r" title="Refresh now" @click="refresh"><Icon name="refresh" :size="14" /> Refresh</button>
        </div>
        <p v-if="tree?.truncated" class="warn" role="status">Output was cut at the size limit: some changes are not shown.</p>
        <DiffView v-if="treeFiles.length" :files="treeFiles" />
        <div v-else-if="tree" class="empty card"><Icon name="check" /> Working tree clean{{ tree.skipped.length ? ' (apart from the files below)' : '' }}.</div>
        <section v-if="tree?.skipped.length" class="skipped card">
          <h3>Not shown</h3>
          <ul><li v-for="s in tree.skipped" :key="s.path"><span class="mono">{{ s.path }}</span> <span class="muted">— {{ s.reason }}</span></li></ul>
        </section>
      </template>

      <!-- one commit -->
      <template v-else>
        <p v-if="detailError" class="warn" role="alert">{{ detailError }}</p>
        <p v-else-if="!detail" class="muted">Loading…</p>
        <template v-else>
          <div class="bar"><h2>{{ detail.subject }}</h2></div>
          <p class="cmeta muted"><span class="mono">{{ detail.sha.slice(0, 12) }}</span> · {{ detail.author }} · {{ ago(now - detail.time) }}
            · <span class="nums mono"><b class="add">+{{ totals(detailFiles).adds }}</b> <b class="del">−{{ totals(detailFiles).dels }}</b></span></p>
          <pre v-if="detail.body" class="body">{{ detail.body }}</pre>
          <p v-if="detail.truncated" class="warn" role="status">Output was cut at the size limit: some changes are not shown.</p>
          <DiffView :files="detailFiles" />
        </template>
      </template>
    </div>
  </div>
</template>

<style scoped>
.layout { display: grid; grid-template-columns: 270px minmax(0, 1fr); gap: 18px; align-items: start; }
.list { position: sticky; top: 0; max-height: calc(100vh - 190px); overflow: auto; padding: 6px; scrollbar-width: thin; }
.label { padding: 12px 8px 4px; font-size: 11px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
.item { display: flex; flex-direction: column; gap: 2px; padding: 7px 8px; border-radius: 8px; color: var(--text); }
.item:hover { background: var(--surface-2); text-decoration: none; }
.item.on { background: var(--accent-soft); color: var(--accent); }
.t { display: flex; align-items: center; gap: 6px; font-weight: 500; }
.t.sub { display: block; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.s { font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.item.on .s { color: inherit; opacity: 0.8; }
.none { padding: 6px 8px; }
.pick { display: none; width: 100%; padding: 7px 8px; background: var(--surface); border: 1px solid var(--border-strong); border-radius: 8px; }
.bar { display: flex; align-items: center; flex-wrap: wrap; gap: 6px 14px; margin-bottom: 12px; }
.bar h2 { margin: 0; font-size: 16px; }
.r { margin-left: auto; }
.nums { font-size: 12.5px; }
.add { color: var(--ok); font-weight: 600; } .del { color: var(--err); font-weight: 600; }
.cmeta { margin: -6px 0 12px; font-size: 13px; }
.body { margin: 0 0 14px; padding: 10px 12px; background: var(--surface-2); border-radius: 8px; white-space: pre-wrap; font: 12.5px/1.5 var(--mono); }
.warn { padding: 8px 12px; margin: 0 0 12px; border-radius: 8px; background: var(--warn-soft); color: var(--warn); }
.empty { display: flex; align-items: center; justify-content: center; gap: 8px; }
.skipped { margin-top: 14px; padding: 10px 14px; }
.skipped h3 { margin: 0 0 6px; font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
.skipped ul { margin: 0; padding-left: 18px; font-size: 13px; }
@media (max-width: 860px) {
  .layout { grid-template-columns: minmax(0, 1fr); gap: 12px; }
  .list { display: none; }
  .pick { display: block; }
}
</style>
