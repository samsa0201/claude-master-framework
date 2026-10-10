<script setup lang="ts">
import { computed } from 'vue'
import { state } from '../store'
import { route, go, TABS, type Tab } from '../route'
import { statsOf, tasksOf } from '../model'
import Icon, { type IconName } from './Icon.vue'
import OverviewTab from './OverviewTab.vue'
import TerminalTab from './TerminalTab.vue'

const props = defineProps<{ project: string }>()

const stats = computed(() => statsOf(tasksOf(state.value, props.project)))
const pct = computed(() => (stats.value.total ? Math.round((stats.value.done / stats.value.total) * 100) : 0))

const TAB_META: Record<Tab, { label: string; icon: IconName }> = {
  overview: { label: 'Overview', icon: 'grid' },
  docs: { label: 'Docs', icon: 'doc' },
  changes: { label: 'Changes', icon: 'diff' },
  terminal: { label: 'Terminal', icon: 'terminal' },
}
const TAB_VIEW: Partial<Record<Tab, unknown>> = { overview: OverviewTab, terminal: TerminalTab }
const tabs = computed(() => TABS.filter((t) => t in TAB_VIEW))
const view = computed(() => TAB_VIEW[route.tab] ?? OverviewTab)
</script>

<template>
  <header class="head">
    <div class="row">
      <h1>{{ project }}</h1>
      <div class="stats">
        <span class="stat"><b>{{ stats.total }}</b> task{{ stats.total === 1 ? '' : 's' }}</span>
        <span class="stat prog" :title="`${stats.done} of ${stats.total} done`">
          <span class="bar" role="img" :aria-label="`${pct}% done`"><i :style="{ width: pct + '%' }" /></span>
          <b>{{ stats.done }}/{{ stats.total }}</b> done
        </span>
        <span v-if="stats.active" class="stat active"><b>{{ stats.active }}</b> active</span>
        <span v-if="stats.stale" class="stat stale"><b>{{ stats.stale }}</b> stale</span>
      </div>
    </div>
    <nav class="tabs" aria-label="Project sections">
      <a v-for="t in tabs" :key="t" class="tab" :class="{ on: route.tab === t }"
         :href="'#/' + encodeURIComponent(project) + (t === 'overview' ? '' : '/' + t)"
         :aria-current="route.tab === t ? 'page' : undefined" @click.prevent="go({ project, tab: t })">
        <Icon :name="TAB_META[t].icon" /> {{ TAB_META[t].label }}
      </a>
    </nav>
  </header>
  <section class="content scroll">
    <component :is="view" :project="project" />
  </section>
</template>

<style scoped>
.head { padding: 18px 28px 0; background: var(--bg); }
.row { display: flex; flex-wrap: wrap; align-items: baseline; gap: 8px 24px; }
h1 { margin: 0; font-size: 22px; font-weight: 650; letter-spacing: -0.01em; }
.stats { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 18px; color: var(--muted); font-size: 13px; }
.stat b { color: var(--text); font-weight: 600; font-variant-numeric: tabular-nums; }
.stat.active b, .stat.active { color: var(--accent); }
.stat.stale b, .stat.stale { color: var(--warn); }
.prog { display: inline-flex; align-items: center; gap: 8px; }
.bar { width: 90px; height: 6px; border-radius: 99px; background: var(--border); overflow: hidden; }
.bar i { display: block; height: 100%; background: var(--ok); border-radius: 99px; transition: width 0.4s; }
.tabs { display: flex; gap: 4px; margin-top: 14px; border-bottom: 1px solid var(--border); overflow-x: auto; scrollbar-width: none; }
.tab { display: inline-flex; align-items: center; gap: 7px; padding: 8px 12px; margin-bottom: -1px; color: var(--muted); border-bottom: 2px solid transparent; white-space: nowrap; font-weight: 500; }
.tab:hover { color: var(--text); text-decoration: none; }
.tab.on { color: var(--accent); border-bottom-color: var(--accent); }
.content { flex: 1; min-height: 0; padding: 22px 28px 40px; }
@media (max-width: 860px) {
  .head { padding: 14px 16px 0; }
  .content { padding: 18px 16px 32px; }
}
</style>
