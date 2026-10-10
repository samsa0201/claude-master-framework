<script setup lang="ts">
import { computed, watchEffect } from 'vue'
import { state, loaded, linkDown } from './store'
import { route, go } from './route'
import { projectSummaries } from './model'
import Sidebar from './components/Sidebar.vue'
import ProjectView from './components/ProjectView.vue'

const projects = computed(() => projectSummaries(state.value))
const known = computed(() => projects.value.some((p) => p.name === route.project))

// no project in the URL (or it no longer exists) → land on the most recently active one
watchEffect(() => {
  const first = projects.value[0]
  if (loaded.value && first && !known.value) go({ project: first.name }, true)
})
</script>

<template>
  <div class="app">
    <Sidebar :projects="projects" />
    <main class="main">
      <div v-if="linkDown" class="banner" role="alert">Can't reach the studio server — retrying…</div>
      <ProjectView v-if="known" :key="route.project" :project="route.project" />
      <div v-else-if="loaded" class="empty">
        <p><strong>No projects yet.</strong></p>
        <p>Ask Claude to start one, or run <code>team new &lt;name&gt;</code> inside tmux.</p>
      </div>
      <div v-else class="empty">Loading…</div>
    </main>
  </div>
</template>

<style scoped>
.app { display: grid; grid-template-columns: 244px minmax(0, 1fr); height: 100%; }
.main { display: flex; flex-direction: column; min-width: 0; min-height: 0; }
.banner { padding: 8px 16px; background: var(--err-soft); color: var(--err); font-weight: 500; text-align: center; }
@media (max-width: 860px) {
  .app { grid-template-columns: minmax(0, 1fr); grid-template-rows: auto minmax(0, 1fr); }
}
</style>
