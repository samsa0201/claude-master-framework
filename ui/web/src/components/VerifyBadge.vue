<script setup lang="ts">
// Outcome of the checks run when a worker said "done". Icon + words, like StatusBadge.
import type { Verify } from '../api'
import Icon from './Icon.vue'

defineProps<{ verify: Verify }>()
const LABEL = { ok: 'Checks passed', warn: 'Check warning', fail: 'Checks failed' } as const
</script>

<template>
  <span class="vb" :class="verify.status" :title="verify.summary">
    <Icon :name="verify.status === 'ok' ? 'check' : 'alert'" :size="12" /> {{ LABEL[verify.status] }}
  </span>
</template>

<style scoped>
.vb { display: inline-flex; align-items: center; gap: 4px; padding: 0 7px; border-radius: 999px; font-size: 11.5px; font-weight: 600; white-space: nowrap; background: var(--ok-soft); color: var(--ok); }
.warn { background: var(--warn-soft); color: var(--warn); }
.fail { background: var(--err-soft); color: var(--err); }
</style>
