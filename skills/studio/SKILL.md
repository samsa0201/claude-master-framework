---
name: studio
description: Run the studio multi-agent workflow (Claude as product lead/architect, coding-agent workers (opencode via adapters) in tmux panes via the `team` CLI) to build a new product or add a feature to an existing repo. Use when the user wants to start a product, assign pm/ux/dev/qa workers, or attach a worktree to a repo.
---
# Studio — entry point

Studio root = `dirname $(dirname $(readlink -f $(which team)))` (call it $STUDIO_ROOT). Paths below like `agents/`, `projects/` are relative to it; run `team` from anywhere inside tmux.

You (Claude) are **product lead + architect**; the user only talks to you. Workers are coding-agent CLIs (runtime adapter `agents/runtime/<R>.sh`, default `opencode`, fallback `goose`) running custom models via 9router, as tmux PANES next to this one (tag `@team=<project>-<role>`) so the user watches live (`Ctrl-b z` zooms one). Treat them like sub-agents: small self-contained task in, result file out, then YOU verify (diff + tests) — never trust a worker's "done".
Roles (`agents/<role>.md`, base prompt + defaults): `pm`, `ux`, `dev` (TDD), `qa` (runs things, drives a real browser), `qc` (reviews diff, no edits), `docs` (no code edits). Any role name works; base = longest matching prefix (`dev-fe` → `dev.md`), else `_base.md`.
**Flex:** when a project starts (or after `team attach`), write `projects/<name>/.team/roles/<role-name>.md` per worker you will use: stack, build/test/lint commands, conventions, key files, specialty. Optional frontmatter `runtime:`, `model:`, `browser:`, `timeout:` overrides the base. Example `dev-fe.md` with `model: fidt/kCode`.

## Flow (per product)
1. `team new <name>`; put the user's idea in `projects/<name>/docs/idea.md`.
2. `team assign <name> pm "..."` → docs/prd.md. Then you write docs/architecture.md yourself (web PWA vs Android, stack, data model, slices). Then `team assign <name> ux "..."`.
3. **STOP: user approves PRD + architecture + UX before any code.**
4. One vertical slice at a time: `team assign <name> dev-<x> "<slice>"`, then `team assign <name> qc "review <slice>"`, then `team assign <name> qa "verify <slice>"`.
5. For each assign: run `team wait <id>` in background (Bash run_in_background; default timeout = role/model timeout). Output `done` → read `projects/<name>/.team/out/<id>.md` and review the diff yourself; `timeout` → `tmux capture-pane` the worker, then nudge it, `team close` + reassign, or switch `--runtime/--model`; `dead` → the worker exited or its pane is gone, read its pane and reassign.

## Flow (feature in an existing repo)
1. `team attach <name> <repo-path> [branch]` → worktree `projects/<name>` on branch `feat/<name>`; the user's checkout stays untouched. Run install/setup (deps, .env) there.
2. You explore the code yourself (graphify if available) and write `docs/feature.md`: goal, files/modules to touch, conventions to follow, done criteria. No pm/prd for small features; use pm/ux only if the feature is big or UI-heavy.
3. **STOP: user approves docs/feature.md.**
4. Slices as in the main flow (tasks name exact existing files; tell workers to match surrounding style and not refactor). Review each diff with `git -C projects/<name> diff`; QA runs the repo's existing tests.
5. Finish: user decides merge/PR; then `git worktree remove projects/<name>`.

## Choosing runtime / model / parallel workers (you decide; ask the user only if cost is unclear)
`team assign <name> <role> "<task>" [--runtime opencode|goose] [--model <id>] [--new]`
- Models (9router ids): `fidt/qwen3.8-flash` (default; logic, backend, docs, review), `fidt/kCode` (UI/frontend; upstream is slow, default timeout 30 min). Put per-worker defaults in the flex file instead of repeating flags.
- Runtime: `opencode` (default; only one with browser support). `goose` as fallback when opencode misbehaves on a task; it runs one task per process (pane respawned per task, no context kept; assigning to a busy goose worker is refused, use `--new`). Why: README "Worker runtime".
- Reusing a live worker with a different `--runtime/--model` is refused: use `--new` or `team close`. A worker whose process exited is respawned automatically.
- `--new` spawns an extra parallel worker (`<role>-2`, ...). Reuse (default) keeps context.
- Preflight: `team assign` refuses if `NINEROUTER_API_KEY` is unset in your shell or 9router is down.
- New runtime/model? Run `tests/runtime-accept.sh <runtime> <model>` first.

## Rules
- Never read or print API keys. Key lives only in the `NINEROUTER_API_KEY` env var of the shell running claude (passed into worker panes by `team`).
- Each product is its own git repo under `projects/` (gitignored here). Improve the framework by editing `agents/`, `bin/team`, this file; commit here.
- Only touch tmux panes tagged `@team`. Use `team ls`, `team close <name> [role]`.
- Keep tasks small and self-contained; workers run cheap models and need explicit file paths + done criteria.
- **Ports are per project.** `team new/attach` reserves a fixed block of 20 ports (default from 20000, `TEAM_PORT_BASE`) in `projects/<name>/.team/ports.env` (`PORT_WEB`, `PORT_API`, `PORT_DB`, `PORT_CACHE`, `PORT_AUX1/2`, `COMPOSE_PROJECT_NAME`); every worker pane gets them as env and every task file lists them. Tell workers to bind servers to `$PORT_*` in strict mode and to override hardcoded ports (vite `--port $PORT_WEB --strictPort`, `.env.local`, compose `${PORT_DB}`). `team ports <name>` shows state + the `ssh -L` line for the user's Mac; `team ports <name> kill` and `team close <name>` stop leftover listeners whose cwd is inside the project (others are left alone).
- Framework tests: `tests/team_test.sh` (no model, private tmux server) after editing `bin/team` or adapters.
- `team ui [port]` (default 7777): read-only dashboard (workers and tasks live, docs viewer, uncommitted diff and commits, worker terminals; light/dark). It builds itself on first run and after `ui/web` changes (`ui/build.sh`: pinned bun under `.runtime/bun`, needs node/npm); nothing built is committed. Suggest it to the user when work starts; they open it over `ssh -L <port>:localhost:<port>`.

## QA in a real browser the user can watch
Roles with `browser: qa` (default for `qa`) get Playwright MCP driving Chromium on a shared virtual display. `team assign` starts it and prints the URL; tell the user: `ssh -L 6080:localhost:6080 <linux-host>`, open `http://localhost:6080/vnc.html`, Connect. One browser worker at a time (assign refuses while one is busy). Evidence (screenshots, session) lands in `projects/<name>/.team/out/browser/`. Login: put the storageState file at `projects/<name>/.team/auth.json` (flow below) and the QA browser starts logged in. `team display stop` when done. Browser tasks must say "use the playwright browser tools" (qwen only uses MCP when told).

## Browser login over SSH (user works from a Mac via SSH, no display on this Linux box)
Headed browsers (e.g. `bun run test:e2e:login`) are invisible to the user. Instead:
1. User on Mac: `ssh -L <port>:localhost:<port> <linux-host>` (e.g. 5173 for the magisk dev server).
2. User logs in at `http://localhost:<port>` in the Mac browser (OAuth callback stays localhost:<port>).
3. DevTools console: `copy(JSON.stringify({cookies:[],origins:[{origin:location.origin,localStorage:Object.entries(localStorage).map(([name,value])=>({name,value}))}]}))`
4. In a NEW local Mac terminal (not `!` in chat, keeps tokens out of the transcript): `pbpaste | ssh <linux-host> 'cat > <repo>/tests/e2e/.auth/user.json'`. Do NOT paste into `cat >` over SSH: the tty cuts lines at 4095 chars and corrupts the JSON.
Then use it only through the repo's Playwright config (`storageState`), never copy/print the token. A worktree can reach it via a gitignored symlink `tests/e2e/.auth -> <main checkout>/tests/e2e/.auth`. Ask before downloading Playwright browsers.
