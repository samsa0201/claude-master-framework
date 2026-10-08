---
name: studio
description: Run the studio multi-agent workflow (Claude as product lead/architect, omp workers in tmux panes via the `team` CLI) to build a new product or add a feature to an existing repo. Use when the user wants to start a product, assign pm/ux/dev/qa workers, or attach a worktree to a repo.
---
# Studio — entry point

Studio root = `dirname $(dirname $(readlink -f $(which team)))` (call it $STUDIO_ROOT). Paths below like `agents/`, `projects/` are relative to it; run `team` from anywhere inside tmux.

You (Claude) are **product lead + architect**. omp workers (model `9router/fidt/qwen3.8-flash`) default to pm, ux, web-dev, android-dev, qa (`agents/<role>.md`). Roles are flexible: you may assign ANY role name (e.g. backend-dev, security, docs); without an agent file it uses `agents/_base.md`, so put the role's responsibility, files and done criteria in the task. Role names: lowercase-with-dashes (enforced by `team assign`). Add an `agents/<role>.md` only when a role recurs. Workers run as tmux PANES next to this one (tag `@team=<project>-<role>`), so the user watches live (`Ctrl-b z` zooms one).

## Flow (per product)
1. `team new <name>`; put the user's idea in `projects/<name>/docs/idea.md`.
2. `team assign <name> pm "..."` → docs/prd.md. Then you write docs/architecture.md yourself (web PWA vs Android, stack, data model, slices). Then `team assign <name> ux "..."`.
3. **STOP: user approves PRD + architecture + UX before any code.**
4. One vertical slice at a time: `team assign <name> web-dev|android-dev "<slice>"`, then `team qa`-style `team assign <name> qa "verify <slice>"`.
5. For each assign: run `team wait <id> [secs]` in background (polls a .done file; safe to repeat) (Bash run_in_background), then read `projects/<name>/.team/out/<id>.md` and review the diff yourself before the next step.

## Flow (feature in an existing repo)
1. `team attach <name> <repo-path> [branch]` → worktree `projects/<name>` on branch `feat/<name>`; the user's checkout stays untouched. Run install/setup (deps, .env) there.
2. You explore the code yourself (graphify if available) and write `docs/feature.md`: goal, files/modules to touch, conventions to follow, done criteria. No pm/prd for small features; use pm/ux only if the feature is big or UI-heavy.
3. **STOP: user approves docs/feature.md.**
4. Slices as in the main flow (tasks name exact existing files; tell workers to match surrounding style and not refactor). Review each diff with `git -C projects/<name> diff`; QA runs the repo's existing tests.
5. Finish: user decides merge/PR; then `git worktree remove projects/<name>`.

## Choosing model / parallel workers (you decide; ask the user only if cost is unclear)
`team assign <name> <role> "<task>" [--model <id>] [--new]`
- Default `9router/fidt/qwen3.8-flash` (cheap, routine slices). `--model 9router/fidt/deepseek-v4.1-flash` for harder reasoning (architecture-heavy, security, tricky debugging). `--model 9router/fidt/kCode` for coding-heavy slices (web-dev/android-dev/backend). Models available: `~/.omp/agent/models.yml`.
- `--new` spawns an extra parallel worker (`<role>-2`, ...) instead of reusing the live pane. Reuse (default) keeps context; use `--new` for independent work or a fresh context.

## Rules
- Never read or print API keys. Key lives in `NINEROUTER_API_KEY` / `~/.omp/agent/models.yml`.
- Each product is its own git repo under `projects/` (gitignored here). Improve the framework by editing `agents/`, `bin/team`, this file; commit here.
- Only touch tmux panes tagged `@team`. Use `team ls`, `team close <name> [role]`.
- Keep tasks small and self-contained; workers are cheap models and need explicit file paths + done criteria.
- `team ui [port]` (default 7777): cute live "office" view (bots walk to you for tasks, type, cheer when done). Suggest it to the user when work starts.

## Browser login over SSH (user works from a Mac via SSH, no display on this Linux box)
Headed browsers (e.g. `bun run test:e2e:login`) are invisible to the user. Instead:
1. User on Mac: `ssh -L <port>:localhost:<port> <linux-host>` (e.g. 5173 for the magisk dev server).
2. User logs in at `http://localhost:<port>` in the Mac browser (OAuth callback stays localhost:<port>).
3. DevTools console: `copy(JSON.stringify({cookies:[],origins:[{origin:location.origin,localStorage:Object.entries(localStorage).map(([name,value])=>({name,value}))}]}))`
4. In a NEW local Mac terminal (not `!` in chat, keeps tokens out of the transcript): `pbpaste | ssh <linux-host> 'cat > <repo>/tests/e2e/.auth/user.json'`. Do NOT paste into `cat >` over SSH: the tty cuts lines at 4095 chars and corrupts the JSON.
Then use it only through the repo's Playwright config (`storageState`), never copy/print the token. A worktree can reach it via a gitignored symlink `tests/e2e/.auth -> <main checkout>/tests/e2e/.auth`. Ask before downloading Playwright browsers.
