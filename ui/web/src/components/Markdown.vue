<script setup lang="ts">
// Documents are written by worker models: raw HTML is disabled (markdown-it escapes it) and markdown-it drops javascript: links.
import { computed } from 'vue'
import MarkdownIt from 'markdown-it'

const md = new MarkdownIt({ html: false, linkify: true })
const openLink = md.renderer.rules.link_open ?? ((tokens, i, opts, _env, self) => self.renderToken(tokens, i, opts))
md.renderer.rules.link_open = (tokens, i, opts, env, self) => {
  tokens[i]!.attrSet('target', '_blank')
  tokens[i]!.attrSet('rel', 'noopener noreferrer')
  return openLink(tokens, i, opts, env, self)
}

const props = defineProps<{ source: string }>()
const html = computed(() => md.render(props.source))
</script>

<template>
  <!-- eslint-disable-next-line vue/no-v-html -->
  <div class="md" v-html="html" />
</template>

<style>
.md { line-height: 1.65; overflow-wrap: anywhere; }
.md > :first-child { margin-top: 0; }
.md > :last-child { margin-bottom: 0; }
.md h1, .md h2, .md h3, .md h4 { line-height: 1.3; margin: 1.5em 0 0.5em; }
.md h1 { font-size: 1.6em; padding-bottom: 0.3em; border-bottom: 1px solid var(--border); }
.md h2 { font-size: 1.3em; padding-bottom: 0.25em; border-bottom: 1px solid var(--border); }
.md h3 { font-size: 1.1em; }
.md h4 { font-size: 1em; color: var(--muted); }
.md p, .md ul, .md ol, .md blockquote, .md pre, .md table { margin: 0.7em 0; }
.md ul, .md ol { padding-left: 1.5em; }
.md li + li { margin-top: 0.2em; }
.md code { background: var(--surface-2); padding: 0.1em 0.35em; border-radius: 5px; font-size: 0.88em; }
.md pre { background: var(--surface-2); border: 1px solid var(--border); border-radius: 8px; padding: 10px 12px; overflow: auto; }
.md pre code { background: none; padding: 0; font-size: 0.85em; }
.md blockquote { margin-left: 0; padding: 0 1em; color: var(--muted); border-left: 3px solid var(--border-strong); }
.md table { border-collapse: collapse; display: block; overflow: auto; max-width: 100%; }
.md th, .md td { border: 1px solid var(--border); padding: 5px 10px; text-align: left; }
.md th { background: var(--surface-2); }
.md hr { border: 0; border-top: 1px solid var(--border); margin: 1.5em 0; }
.md img { max-width: 100%; }
</style>
