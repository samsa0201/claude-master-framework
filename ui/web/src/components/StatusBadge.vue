<script setup lang="ts">
// Status is always icon + word, never colour alone.
import Icon, { type IconName } from './Icon.vue'

export type Kind = 'working' | 'idle' | 'done' | 'stale' | 'offline'
defineProps<{ kind: Kind }>()

const META: Record<Kind, { label: string; icon: IconName }> = {
  working: { label: 'Working', icon: 'spinner' },
  idle: { label: 'Idle', icon: 'circle' },
  done: { label: 'Done', icon: 'check' },
  stale: { label: 'Stale', icon: 'alert' },
  offline: { label: 'Offline', icon: 'circle' },
}
</script>

<template>
  <span class="badge" :class="kind">
    <Icon :name="META[kind].icon" :size="13" :class="{ spin: kind === 'working' }" />
    {{ META[kind].label }}
  </span>
</template>

<style scoped>
.badge {
  display: inline-flex; align-items: center; gap: 5px; padding: 1px 8px 1px 6px;
  border-radius: 999px; font-size: 12px; font-weight: 500; white-space: nowrap;
  background: var(--surface-2); color: var(--muted);
}
.working { background: var(--accent-soft); color: var(--accent); }
.done, .idle { background: var(--ok-soft); color: var(--ok); }
.idle { background: var(--surface-2); color: var(--muted); }
.stale { background: var(--warn-soft); color: var(--warn); }
.spin { animation: spin 1.1s linear infinite; }
</style>
