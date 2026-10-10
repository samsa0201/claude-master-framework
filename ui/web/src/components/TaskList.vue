<script setup lang="ts">
import { computed, ref } from 'vue'
import { now } from '../store'
import { clock, duration } from '../format'
import type { Task, TaskStatus } from '../api'
import StatusBadge from './StatusBadge.vue'
import VerifyBadge from './VerifyBadge.vue'

const props = defineProps<{ tasks: Task[] }>()
defineEmits<{ open: [id: string] }>()

type Filter = 'all' | TaskStatus
const filter = ref<Filter>('all')
const FILTERS: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' }, { key: 'working', label: 'Active' }, { key: 'done', label: 'Done' }, { key: 'stale', label: 'Stale' },
]
const count = (f: Filter) => (f === 'all' ? props.tasks.length : props.tasks.filter((t) => t.status === f).length)
const rows = computed(() => props.tasks.filter((t) => filter.value === 'all' || t.status === filter.value).slice().reverse())
const took = (t: Task) => (t.end ? duration(t.end - t.start) : t.status === 'working' ? duration(now.value - t.start) : '')
</script>

<template>
  <div class="filters" role="group" aria-label="Filter tasks">
    <button v-for="f in FILTERS" :key="f.key" class="chip" :class="{ on: filter === f.key }" :aria-pressed="filter === f.key" @click="filter = f.key">
      {{ f.label }} <span class="n">{{ count(f.key) }}</span>
    </button>
  </div>
  <ul v-if="rows.length" class="list card">
    <li v-for="t in rows" :key="t.id">
      <button class="row" @click="$emit('open', t.id)">
        <StatusBadge :kind="t.status" class="badge" />
        <span class="seat mono">{{ t.seat }}</span>
        <span class="body">
          <span class="title">{{ t.title || t.id }}</span>
          <span v-if="t.verify" class="vrow"><VerifyBadge :verify="t.verify" /><span v-if="t.verify.status !== 'ok'" class="muted vs">{{ t.verify.summary }}</span></span>
          <span v-if="t.summary && t.status === 'done'" class="sum muted">{{ t.summary }}</span>
        </span>
        <span class="when muted">
          <span>{{ clock(t.end ?? t.start) }}</span>
          <span v-if="took(t)">{{ took(t) }}</span>
        </span>
      </button>
    </li>
  </ul>
  <div v-else class="empty card">No {{ filter === 'all' ? '' : FILTERS.find((f) => f.key === filter)?.label.toLowerCase() + ' ' }}tasks.</div>
</template>

<style scoped>
.filters { display: flex; flex-wrap: wrap; gap: 6px; margin-bottom: 10px; }
.chip { padding: 3px 11px; border: 1px solid var(--border); border-radius: 999px; background: var(--surface); color: var(--muted); font-size: 13px; }
.chip:hover { color: var(--text); border-color: var(--border-strong); }
.chip.on { background: var(--accent-soft); border-color: transparent; color: var(--accent); font-weight: 600; }
.n { font-variant-numeric: tabular-nums; opacity: 0.75; margin-left: 2px; }
.list { list-style: none; margin: 0; padding: 0; overflow: hidden; }
li + li { border-top: 1px solid var(--border); }
.row { display: grid; grid-template-columns: 92px 108px minmax(0, 1fr) auto; align-items: start; gap: 12px; width: 100%; padding: 11px 14px; background: none; border: 0; text-align: left; }
.row:hover { background: var(--surface-2); }
.badge { justify-self: start; }
.seat { font-size: 12.5px; padding-top: 1px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.body { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.title { overflow-wrap: anywhere; }
.vrow { display: flex; flex-wrap: wrap; align-items: center; gap: 4px 8px; margin-top: 2px; }
.vs { font-size: 12.5px; overflow-wrap: anywhere; }
.sum { font-size: 12.5px; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; overflow-wrap: anywhere; }
.when { display: flex; flex-direction: column; align-items: flex-end; font-size: 12.5px; font-variant-numeric: tabular-nums; white-space: nowrap; }
@media (max-width: 720px) {
  .row { grid-template-columns: minmax(0, 1fr) auto; grid-template-areas: 'badge when' 'seat seat' 'body body'; gap: 4px 12px; }
  .badge { grid-area: badge; } .seat { grid-area: seat; } .body { grid-area: body; } .when { grid-area: when; }
}
</style>
