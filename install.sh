#!/usr/bin/env bash
# Install worker runtimes under .runtime/ (gitignored), put `team` on PATH, install the studio skill.
set -euo pipefail
R=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$R/.runtime" ~/.local/bin
[ -x "$R/.runtime/opencode/node_modules/.bin/opencode" ] || npm i --prefix "$R/.runtime/opencode" opencode-ai@1.18.35
ln -sf "$R/bin/team" ~/.local/bin/team
mkdir -p ~/.claude/skills && ln -sfn "$R/skills/studio" ~/.claude/skills/studio
echo "ok. export NINEROUTER_API_KEY=... (in the shell that runs claude), then: team new <name>"
