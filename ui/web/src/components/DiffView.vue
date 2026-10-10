<script setup lang="ts">
// Renders parsed unified-diff files. Big files start collapsed; the user's expand/collapse choices survive refreshes.
import { reactive } from 'vue'
import type { FileDiff, FileStatus } from '../diff'
import Icon from './Icon.vue'

defineProps<{ files: FileDiff[] }>()

const AUTO_OPEN_MAX = 400 // lines
const forced = reactive(new Map<string, boolean>())
const isOpen = (f: FileDiff) => forced.get(f.path) ?? (f.lineCount <= AUTO_OPEN_MAX && f.status !== 'binary')
const toggle = (f: FileDiff) => forced.set(f.path, !isOpen(f))

const LABEL: Record<FileStatus, string> = { modified: 'Modified', added: 'Added', deleted: 'Deleted', renamed: 'Renamed', binary: 'Binary' }
</script>

<template>
  <div class="files">
    <section v-for="f in files" :key="f.path" class="file card">
      <button class="head" :aria-expanded="isOpen(f)" @click="toggle(f)">
        <Icon name="doc" :size="15" class="ico" />
        <span class="path mono">
          <template v-if="f.oldPath"><span class="muted">{{ f.oldPath }}</span> → </template>{{ f.path }}
        </span>
        <span class="tag" :class="f.status">{{ LABEL[f.status] }}</span>
        <span class="nums mono"><b class="n-add">+{{ f.adds }}</b> <b class="n-del">−{{ f.dels }}</b></span>
        <span class="chev" :class="{ open: isOpen(f) }" aria-hidden="true">▸</span>
      </button>
      <div v-if="isOpen(f)" class="scroll body">
        <p v-if="f.status === 'binary'" class="note muted">Binary file not shown.</p>
        <p v-else-if="!f.hunks.length" class="note muted">No content changes (mode or rename only).</p>
        <table v-else class="diff mono">
          <template v-for="(h, hi) in f.hunks" :key="hi">
            <tbody>
              <tr class="hunk"><td colspan="3">{{ h.header }}</td></tr>
              <tr v-for="(l, li) in h.lines" :key="li" :class="l.kind">
                <td class="no">{{ l.oldNo ?? '' }}</td>
                <td class="no">{{ l.newNo ?? '' }}</td>
                <td class="code"><span class="sign" aria-hidden="true">{{ l.kind === 'add' ? '+' : l.kind === 'del' ? '−' : ' ' }}</span>{{ l.text }}<span v-if="l.kind === 'add' || l.kind === 'del'" class="sr-only">{{ l.kind === 'add' ? ' (added)' : ' (removed)' }}</span></td>
              </tr>
            </tbody>
          </template>
        </table>
      </div>
      <p v-else-if="f.status !== 'binary'" class="note muted">{{ f.lineCount }} lines hidden — click the file name to show them.</p>
    </section>
  </div>
</template>

<style scoped>
.files { display: flex; flex-direction: column; gap: 12px; }
.file { overflow: hidden; }
.head { display: flex; align-items: center; gap: 10px; width: 100%; padding: 9px 12px; background: var(--surface-2); border: 0; text-align: left; }
.head:hover { background: color-mix(in srgb, var(--surface-2) 70%, var(--border)); }
.ico { color: var(--muted); flex: none; }
.path { flex: 1; min-width: 0; font-size: 12.5px; overflow-wrap: anywhere; }
.tag { padding: 0 7px; border-radius: 999px; font-size: 11.5px; font-weight: 600; background: var(--surface); border: 1px solid var(--border); color: var(--muted); }
.tag.added { color: var(--ok); } .tag.deleted { color: var(--err); } .tag.renamed { color: var(--accent); }
.nums { font-size: 12px; white-space: nowrap; }
.n-add { color: var(--ok); font-weight: 600; } .n-del { color: var(--err); font-weight: 600; }
.chev { color: var(--muted); transition: transform 0.15s; } .chev.open { transform: rotate(90deg); }
.body { max-height: 70vh; border-top: 1px solid var(--border); }
.note { margin: 0; padding: 12px 14px; font-size: 13px; }
.diff { border-collapse: collapse; width: 100%; font-size: 12.5px; line-height: 1.5; }
.diff td { padding: 0 10px; vertical-align: top; }
.no { width: 1%; min-width: 44px; padding: 0 8px !important; text-align: right; color: var(--muted); user-select: none; white-space: nowrap; font-variant-numeric: tabular-nums; }
.code { white-space: pre; }
.sign { display: inline-block; width: 1.4ch; user-select: none; color: var(--muted); }
.add > .code, .add > .no { background: var(--add-bg); }
.del > .code, .del > .no { background: var(--del-bg); }
.add .sign { color: var(--ok); } .del .sign { color: var(--err); }
.hunk td { padding: 3px 10px; background: var(--accent-soft); color: var(--accent); font-size: 12px; }
.meta .code { color: var(--muted); font-style: italic; }
</style>
