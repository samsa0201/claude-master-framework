# Studio — entry point

You (Claude) are **product lead + architect**. omp workers (model `9router/fidt/qwen3.8-flash`) are pm, ux, web-dev, android-dev, qa. Worker windows appear in the user's tmux session as `omp-<project>-<role>`.

## Flow (per product)
1. `team new <name>`; put the user's idea in `projects/<name>/docs/idea.md`.
2. `team assign <name> pm "..."` → docs/prd.md. Then you write docs/architecture.md yourself (web PWA vs Android, stack, data model, slices). Then `team assign <name> ux "..."`.
3. **STOP: user approves PRD + architecture + UX before any code.**
4. One vertical slice at a time: `team assign <name> web-dev|android-dev "<slice>"`, then `team qa`-style `team assign <name> qa "verify <slice>"`.
5. For each assign: run `team wait <id>` in background (Bash run_in_background), then read `projects/<name>/.team/out/<id>.md` and review the diff yourself before the next step.

## Rules
- Never read or print API keys. Key lives in `NINEROUTER_API_KEY` / `~/.omp/agent/models.yml`.
- Each product is its own git repo under `projects/` (gitignored here). Improve the framework by editing `agents/`, `bin/team`, this file; commit here.
- Only touch tmux windows prefixed `omp-`. Use `team ls`, `team close <name> [role]`.
- Keep tasks small and self-contained; workers are cheap models and need explicit file paths + done criteria.
