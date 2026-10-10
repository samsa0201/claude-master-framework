<script setup lang="ts">
import { computed } from 'vue'
import { state } from '../store'
import { route, go } from '../route'
import { tasksOf, workersOf } from '../model'
import WorkerCard from './WorkerCard.vue'
import TaskList from './TaskList.vue'
import TaskDrawer from './TaskDrawer.vue'

const props = defineProps<{ project: string }>()
const workers = computed(() => workersOf(state.value, props.project))
const tasks = computed(() => tasksOf(state.value, props.project))
const open = computed(() => tasks.value.find((t) => t.id === route.arg) ?? null) // drawer state lives in the URL: back closes it
</script>

<template>
  <section aria-labelledby="w">
    <h2 id="w">Workers</h2>
    <div v-if="workers.length" class="grid">
      <WorkerCard v-for="w in workers" :key="w.seat" :worker="w" @terminal="(tag) => go({ project, tab: 'terminal', arg: tag })" />
    </div>
    <div v-else class="empty card">
      No workers yet. Ask Claude to assign a task, or run <code>team assign {{ project }} dev "…"</code>.
    </div>
  </section>

  <section aria-labelledby="t">
    <h2 id="t">Tasks</h2>
    <TaskList :tasks="tasks" @open="(id) => go({ project, arg: id })" />
  </section>

  <TaskDrawer v-if="open" :task="open" @close="go({ project })" />
</template>

<style scoped>
section + section { margin-top: 30px; }
h2 { margin: 0 0 12px; font-size: 12px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
.grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(250px, 1fr)); gap: 12px; }
</style>
