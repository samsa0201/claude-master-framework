# Studio

**A multi-agent development framework for Claude Code.** Claude acts as product lead and architect; coding-agent
workers (PM, UX, dev, QA, QC, docs) run in parallel tmux panes on lower-cost models, each project isolated in its own
sandbox. You talk only to Claude. Claude plans, delegates, and verifies every result itself.

```
                you
                 │
        ┌────────▼────────┐
        │  Claude (lead)  │  spec → architecture → slices → review → verify
        └────────┬────────┘
                 │ team assign / wait / exec
   ┌─────────┬───┴─────┬─────────┬─────────┐
   │   pm    │   ux    │  dev-*  │ qa / qc │   coding-agent workers (opencode, goose)
   └─────────┴─────────┴─────────┴─────────┘   in tmux panes, inside a per-project Docker box
```

## Why

Single-agent coding sessions run out of context, drift from the spec, and report "done" when they are not. Studio
splits the work the way a small product team would and keeps one rule above all: **a worker's report is never
trusted. The lead checks the diff and runs the tests.**

## Features

- **Lead + workers.** Claude writes the architecture and reviews; workers take small, self-contained tasks and write a
  result file. Roles live in `agents/<role>.md` and can be specialised per project (stack, commands, conventions).
- **Spec first.** A PRD, architecture and UX pass need your approval before any code. Then one vertical slice at a time:
  dev → QC review → QA in a real browser.
- **Cheap models where they are enough.** Workers run custom models through an OpenAI-compatible router; the lead picks
  the model per task and switches when a worker stalls.
- **Per-project sandbox.** Each project runs in a Docker box with a filesystem allow-list, egress filtering and its own
  network, so workers cannot read your SSH keys, other projects or the Docker socket. Fail-closed: no box, no run.
- **Existing repos too.** `team attach` puts a feature branch in a git worktree; your checkout stays untouched.
- **Read-only dashboard.** `team ui` shows live workers, tasks, project docs, diffs and worker terminals.

## How runtimes were chosen

Worker runtimes were picked by a scripted benchmark, not by impression: 4 agent CLIs × 2 models × 3 tasks (add a
function with tests, edit UI, follow locked-file discipline), graded by script. opencode passed every task with both
models and has real per-tool permissions, so it is the default; goose is the fallback. Details and the commands to
reproduce: [docs/poc/agents-poc.md](docs/poc/agents-poc.md).

## Quick start

Requirements: Linux, tmux, Docker, Node.js/npm, Claude Code, and an API key for the model router.

```sh
git clone https://github.com/samsa0201/claude-master-framework.git studio
cd studio && ./install.sh          # worker runtimes under .runtime/, `team` on PATH, the studio skill
export NINEROUTER_API_KEY=...      # in the shell that runs claude
tmux                               # workers open as panes next to Claude
claude                             # then: "start a new product: <idea>"
```

## Commands

| Command | What it does |
|---|---|
| `team new <proj>` | Create a project and its sandbox |
| `team attach <proj> <repo> [branch]` | Work on an existing repo in a worktree |
| `team assign <proj> <role> "<task>"` | Give a worker a task (`--model`, `--runtime`, `--new` for a parallel worker) |
| `team wait <id>` | Wait for a task: `done`, `timeout`, `dead` or `idle` |
| `team exec <proj> "<cmd>"` | Run tests, builds or git inside the sandbox |
| `team run` / `team stop` | Start or stop the app inside the sandbox |
| `team url` / `team https` | Reach the running app from another machine |
| `team ui [port]` | Open the read-only dashboard |

## In practice

Used on a production feature of a visual page builder: six workers in parallel plus the lead, 27 commits, with
tests, builds and browser QA run inside the sandbox. Lessons from that run are written up in
[docs/operations.vi.md](docs/operations.vi.md) (Vietnamese).

## Repository layout

```
agents/      role prompts and runtime adapters (opencode, goose)
bin/team     the CLI
box/         per-project sandbox (Docker, egress rules)
skills/      the Claude Code skill that drives the workflow
ui/          read-only dashboard (Vue 3 + TypeScript, served by a stdlib Python server)
tests/       CLI, sandbox, runtime acceptance and dashboard tests
docs/        design specs, the runtime POC, operations notes
```

## Tests

```sh
tests/team_test.sh                     # CLI
tests/box_test.sh                      # sandbox (needs Docker)
tests/runtime-accept.sh <runtime> <model>
python3 -m unittest tests/ui_api_test.py && (cd ui/web && bun test)
```

## Limitations

Linux only for now. Egress filtering is IP-based, so hosts that share a CDN with an allowed registry are reachable,
and DNS is not filtered. Use only dev or staging secrets inside a project.
