<script setup lang="ts">
import { computed } from 'vue'
import { state } from '../store'
import { route, go } from '../route'
import { theme, cycleTheme } from '../theme'
import type { ProjectSummary } from '../model'
import Icon from './Icon.vue'

const props = defineProps<{ projects: ProjectSummary[] }>()
const themeIcon = computed(() => ({ system: 'monitor', light: 'sun', dark: 'moon' } as const)[theme.value])
const online = computed(() => state.value.panes.length)
const working = computed(() => state.value.tasks.filter((t) => t.status === 'working').length)
const pick = (e: Event) => go({ project: (e.target as HTMLSelectElement).value })
</script>

<template>
  <aside class="side">
    <div class="brand"><span class="logo" aria-hidden="true">&gt;_</span> Studio</div>

    <nav class="projects" aria-label="Projects">
      <div class="label">Projects</div>
      <a v-for="p in props.projects" :key="p.name" class="proj" :class="{ on: p.name === route.project }"
         :href="'#/' + encodeURIComponent(p.name)" :aria-current="p.name === route.project ? 'page' : undefined">
        <span class="dot" :class="{ live: p.active > 0, warn: !p.active && p.stale > 0 }" aria-hidden="true" />
        <span class="pname">{{ p.name }}</span>
        <span v-if="p.active" class="count">{{ p.active }} active</span>
        <span v-else-if="p.stale" class="count warn">{{ p.stale }} stale</span>
      </a>
      <div v-if="!props.projects.length" class="muted none">No projects yet</div>
    </nav>

    <div class="foot">
      <div class="muted" :title="`${working} of ${online} worker panes are on a task`">
        <Icon name="bot" :size="14" /> {{ online }} worker{{ online === 1 ? '' : 's' }} online
      </div>
      <button class="btn" :title="`Theme: ${theme} (click to change)`" @click="cycleTheme">
        <Icon :name="themeIcon" /> <span class="cap">{{ theme }}</span>
      </button>
    </div>
  </aside>

  <header class="topbar">
    <span class="logo" aria-hidden="true">&gt;_</span>
    <select :value="route.project" aria-label="Project" @change="pick">
      <option v-for="p in props.projects" :key="p.name" :value="p.name">{{ p.name }}{{ p.active ? ` (${p.active} active)` : '' }}</option>
    </select>
    <button class="btn" :title="`Theme: ${theme}`" :aria-label="`Theme: ${theme}`" @click="cycleTheme"><Icon :name="themeIcon" /></button>
  </header>
</template>

<style scoped>
.side { display: flex; flex-direction: column; gap: 18px; padding: 16px 12px; background: var(--surface); border-right: 1px solid var(--border); min-height: 0; }
.brand { display: flex; align-items: center; gap: 10px; padding: 0 8px; font-weight: 650; font-size: 15px; letter-spacing: 0.01em; }
.logo { display: inline-grid; place-items: center; width: 26px; height: 26px; border-radius: 7px; background: var(--accent); color: var(--on-accent); font: 700 12px var(--mono); }
.label { padding: 0 8px 6px; font-size: 11px; font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; color: var(--muted); }
.projects { flex: 1; min-height: 0; overflow: auto; scrollbar-width: thin; }
.proj { display: flex; align-items: center; gap: 9px; padding: 7px 8px; border-radius: 8px; color: var(--text); }
.proj:hover { background: var(--surface-2); text-decoration: none; }
.proj.on { background: var(--accent-soft); color: var(--accent); font-weight: 600; }
.pname { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.dot { width: 8px; height: 8px; border-radius: 50%; background: var(--border-strong); flex: none; }
.dot.live { background: var(--accent); animation: pulse 1.4s ease-in-out infinite; }
.dot.warn { background: var(--warn); }
.count { font-size: 11px; font-weight: 500; color: var(--accent); }
.count.warn { color: var(--warn); }
.none { padding: 8px; }
.foot { display: flex; flex-direction: column; gap: 10px; padding: 0 4px; }
.foot .muted { display: flex; align-items: center; gap: 6px; padding: 0 4px; font-size: 12.5px; }
.cap { text-transform: capitalize; }
.topbar { display: none; }

@media (max-width: 860px) {
  .side { display: none; }
  .topbar { display: flex; align-items: center; gap: 10px; padding: 10px 16px; background: var(--surface); border-bottom: 1px solid var(--border); }
  .topbar select { flex: 1; min-width: 0; padding: 6px 8px; background: var(--surface); border: 1px solid var(--border-strong); border-radius: 8px; }
}
</style>
