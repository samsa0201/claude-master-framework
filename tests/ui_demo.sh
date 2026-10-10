#!/usr/bin/env bash
# Sample data for `team ui`: fake projects (tasks, docs, a git repo with uncommitted work) and live-looking worker panes
# on a PRIVATE tmux server and temp dirs. Never touches your tmux or projects/. Ctrl-C cleans up.
# Run: tests/ui_demo.sh [port]      then open http://localhost:<port> (default 7788)
set -euo pipefail
R=$(cd "$(dirname "$0")/.." && pwd)
PORT=${1:-7788}
D=$(mktemp -d)
export TMUX_TMPDIR=$D/tmux TEAM_PROJECTS=$D/projects STUDIO_ROOT=$R
mkdir -p "$TMUX_TMPDIR" "$TEAM_PROJECTS"
unset TMUX
cleanup() { tmux kill-server 2>/dev/null || true; kill "${SRV:-0}" 2>/dev/null || true; rm -rf "$D"; }
trap cleanup EXIT INT TERM
g() { git -C "$1" -c user.name=Studio -c user.email=studio@example.com -c commit.gpgsign=false "${@:2}"; }

# mk <project> <role> <seat> <mins-ago-started> <mins-ago-done|-> <title> [report]
mk() {
  local p=$TEAM_PROJECTS/$1 id; id="$1-$2-$(date -d "-$4 min" +%H%M%S)"
  printf '# Task %s (role: %s) (worker: %s)\nYou are acting as: %s.\n%s\n\n## When done (in this order)\n1. Write your result summary to .team/out/%s.md\n2. Then run: touch .team/out/%s.done\n' \
    "$id" "$2" "$3" "$2" "$6" "$id" "$id" > "$p/.team/tasks/$id.md"
  touch -d "-$4 min" "$p/.team/tasks/$id.md"
  if [ "$5" != - ]; then
    printf '%s\n\n## Details\n- changed files listed below\n- tests: **all green**\n' "${7:-Done: $6}" > "$p/.team/out/$id.md"
    touch -d "-$4 min" "$p/.team/out/$id.md"; touch -d "-$5 min" "$p/.team/out/$id.done"
  fi
  echo "$id"
}
# pane <project> <seat> <task id> <screen text>: a tagged pane that looks like a running worker
pane() {
  local p; printf '%s' "$4" > "$D/screen-$2.txt"
  p=$(tmux new-window -d -P -F '#{pane_id}' -n "$2" "cat '$D/screen-$2.txt'; sleep 86400")
  tmux set-option -p -t "$p" @team "$1-$2"; tmux set-option -p -t "$p" @tid "$3"
}

tmux new-session -d -s demo -x 200 -y 50

# ── magisk-app: a busy product ──
P=magisk-app; mkdir -p "$TEAM_PROJECTS/$P"/{docs,.team/{tasks,out,roles},src}; git -C "$TEAM_PROJECTS/$P" init -q -b main
printf '.team/\n' >> "$TEAM_PROJECTS/$P/.git/info/exclude"
cat > "$TEAM_PROJECTS/$P/docs/idea.md" <<'EOF'
# Idea: Magisk module manager
A small PWA to browse, install and toggle Magisk modules from a phone.
EOF
cat > "$TEAM_PROJECTS/$P/docs/prd.md" <<'EOF'
# PRD — Magisk module manager

## Goals
1. List installed modules with their enabled state.
2. Toggle a module and show whether a reboot is required.
3. Work offline once loaded (PWA).

## Non-goals
- Flashing modules from the UI.

## Users & stories
| Persona | Story | Priority |
|---|---|---|
| Power user | See what changed after an update | P0 |
| Tinkerer | Disable a broken module quickly | P0 |
| Newcomer | Understand what a module does | P1 |

## Open questions
> Do we need a root check before the first toggle?

```ts
type Module = { id: string; name: string; enabled: boolean; rebootNeeded: boolean }
```

See [Magisk docs](https://topjohnwu.github.io/Magisk/).
EOF
cat > "$TEAM_PROJECTS/$P/docs/architecture.md" <<'EOF'
# Architecture
- **Web PWA**, Vue 3 + Vite, served by the module's own tiny HTTP daemon.
- Data model: `Module { id, name, enabled, rebootNeeded }`.
- Slices: list → toggle → offline cache.
EOF
printf -- '---\nmodel: fidt/kCode\n---\nStack: Vue 3 + Vite. Run `bun test` and `bun run build`.\n' > "$TEAM_PROJECTS/$P/.team/roles/dev-fe.md"
printf 'export const BASE = "/api"\nexport function listModules() {\n  return fetch(BASE + "/modules")\n}\n\nexport function toggle(id: string) {\n  return fetch(BASE + "/toggle/" + id)\n}\n\nexport const VERSION = 1\n' > "$TEAM_PROJECTS/$P/src/api.ts"
printf '# magisk-app\n' > "$TEAM_PROJECTS/$P/README.md"; printf 'old\n' > "$TEAM_PROJECTS/$P/src/legacy.ts"
g "$TEAM_PROJECTS/$P" add -A; g "$TEAM_PROJECTS/$P" commit -q -m "chore: scaffold project"
printf 'export const BASE = "/api"\nexport function listModules() {\n  return fetch(BASE + "/modules")\n}\n\nexport function toggle(id: string) {\n  return fetch(BASE + "/toggle/" + id)\n}\n\nexport const VERSION = 1\n// poll interval\nexport const POLL_MS = 2000\n' > "$TEAM_PROJECTS/$P/src/api.ts"
g "$TEAM_PROJECTS/$P" commit -qam "feat(api): add POLL_MS"
# uncommitted work: edited, deleted, brand-new, plus files that must be skipped
printf 'export const BASE = "/api/v2"\nexport async function listModules(): Promise<Module[]> {\n  const r = await fetch(BASE + "/modules")\n  return r.json()\n}\n\nexport function toggle(id: string) {\n  return fetch(BASE + "/toggle/" + id, { method: "POST" })\n}\n\nexport const VERSION = 2\n// poll interval\nexport const POLL_MS = 2000\n' > "$TEAM_PROJECTS/$P/src/api.ts"
rm "$TEAM_PROJECTS/$P/src/legacy.ts"
printf '<script setup lang="ts">\nimport { ref } from "vue"\nconst modules = ref<string[]>([])\n</script>\n\n<template>\n  <ul><li v-for="m in modules" :key="m">{{ m }}</li></ul>\n</template>\n' > "$TEAM_PROJECTS/$P/src/ModuleList.vue"
printf 'TOKEN=secret\n' > "$TEAM_PROJECTS/$P/.env"

mk $P pm pm 95 90 "Write the PRD for the Magisk module manager" "PRD written: 3 goals, 3 stories." >/dev/null
mk $P ux ux 88 80 "Design the module list and toggle flow" "UX flows for list/toggle drawn in docs/ux.md." >/dev/null
mk $P dev-be dev-be 70 52 "Slice 1: GET /api/modules returns installed modules" "Endpoint implemented with 4 tests." >/dev/null
mk $P dev-fe dev-fe 50 41 "Slice 1: module list view" "ModuleList.vue renders modules; tests green." >/dev/null
mk $P qc qc 40 36 "Review slice 1 diff" "Two nits: rename tmp -> modules, add empty state." >/dev/null
mk $P qa qa 30 - "Verify slice 1 in the browser (use the playwright browser tools)" >/dev/null           # abandoned: no pane, no .done
T1=$(mk $P dev-fe dev-fe 6 - "Slice 2: toggle a module and show the reboot-needed banner. Files: src/ModuleList.vue, src/api.ts")
T2=$(mk $P dev-fe dev-fe-2 3 - "Slice 2b: offline cache with a service worker")
T3=$(mk $P dev-be dev-be 2 - "Slice 2: POST /api/toggle/:id")
pane $P dev-fe "$T1" $'$ opencode\n> Read .team/tasks/'"$T1"$'.md and do it exactly.\n\n● Reading src/ModuleList.vue\n● Editing src/ModuleList.vue (+18 -2)\n● Running: bun test\n  ✓ toggles a module (12ms)\n  ✓ shows reboot banner (8ms)\n\n2 pass, 0 fail\n'
pane $P dev-fe-2 "$T2" $'$ opencode\n● Writing public/sw.js\n● Waiting for upstream model (kCode)...\n'
pane $P dev-be "$T3" $'$ opencode\n● Editing server/toggle.py\n'
pane $P pm "$P-pm-old" $'$ opencode\n(idle - waiting for next task)\n'

# ── todo-pwa: finished work, nothing live ──
P=todo-pwa; mkdir -p "$TEAM_PROJECTS/$P"/{docs,.team/{tasks,out,roles}}; git -C "$TEAM_PROJECTS/$P" init -q -b main
echo "# Idea: todo app" > "$TEAM_PROJECTS/$P/docs/idea.md"
mk $P dev dev 1500 1490 "Add todo list with local storage" "Implemented; 6 tests." >/dev/null
mk $P docs docs 1480 1470 "Write README" "README added." >/dev/null

# ── fresh: just created ──
P=fresh-idea; mkdir -p "$TEAM_PROJECTS/$P"/{docs,.team/{tasks,out,roles}}; git -C "$TEAM_PROJECTS/$P" init -q -b main
echo "# Idea: something new" > "$TEAM_PROJECTS/$P/docs/idea.md"

STUDIO_ROOT=$R python3 "$R/ui/serve.py" "$PORT" &
SRV=$!
echo "demo data in $D; Ctrl-C to stop" >&2
wait "$SRV"
