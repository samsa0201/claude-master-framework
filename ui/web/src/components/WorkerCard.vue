<script setup lang="ts">
import { computed } from 'vue'
import { now } from '../store'
import { ago, duration } from '../format'
import type { Worker } from '../model'
import StatusBadge from './StatusBadge.vue'
import Icon from './Icon.vue'
import VerifyBadge from './VerifyBadge.vue'

const props = defineProps<{ worker: Worker }>()
defineEmits<{ terminal: [tag: string] }>()

const task = computed(() => props.worker.task)
const meta = computed(() => {
  const t = task.value
  if (!t) return 'No task yet'
  if (t.status === 'working') return `Running ${duration(now.value - t.start)}`
  if (t.status === 'done' && t.end) return `Finished ${ago(now.value - t.end)}`
  return `Abandoned · started ${ago(now.value - t.start)}`
})
</script>

<template>
  <button class="worker card" :class="worker.state" :disabled="!worker.online" :title="worker.online ? 'Open terminal' : 'Pane is closed'"
          @click="$emit('terminal', worker.tag)">
    <span class="top">
      <span class="name"><Icon name="bot" :size="15" /> {{ worker.seat }}</span>
      <StatusBadge :kind="worker.state" />
    </span>
    <span class="title" :class="{ muted: !task }">{{ task ? task.title || task.summary || task.id : 'Standing by' }}</span>
    <VerifyBadge v-if="task?.verify" :verify="task.verify" class="vbadge" />
    <span class="meta muted">
      <span>{{ meta }}</span>
      <span v-if="worker.taskCount > 1">{{ worker.taskCount }} tasks</span>
    </span>
  </button>
</template>

<style scoped>
.worker { display: flex; flex-direction: column; gap: 8px; padding: 14px; text-align: left; width: 100%; font: inherit; color: inherit; transition: border-color 0.15s, box-shadow 0.15s; }
.worker:not(:disabled):hover { border-color: var(--accent); box-shadow: var(--shadow); }
.worker:disabled { cursor: default; }
.worker.working { border-color: color-mix(in srgb, var(--accent) 45%, var(--border)); }
.worker.stale { border-color: color-mix(in srgb, var(--warn) 45%, var(--border)); }
.top { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
.name { display: inline-flex; align-items: center; gap: 7px; font-weight: 600; }
.title { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; overflow-wrap: anywhere; min-height: 2.9em; }
.vbadge { align-self: flex-start; }
.meta { display: flex; justify-content: space-between; gap: 8px; font-size: 12.5px; }
</style>
