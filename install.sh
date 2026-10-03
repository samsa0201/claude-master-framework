#!/usr/bin/env bash
# Symlink agents into omp, seed models.yml (never overwrites), put `team` on PATH.
set -euo pipefail
R=$(cd "$(dirname "$0")" && pwd); D=~/.omp/agent
mkdir -p "$D/agents" ~/.local/bin
for f in "$R"/agents/*.md; do ln -sf "$f" "$D/agents/$(basename "$f")"; done
[ -e "$D/models.yml" ] || cp "$R/models.example.yml" "$D/models.yml"
ln -sf "$R/bin/team" ~/.local/bin/team
echo "ok. export NINEROUTER_API_KEY=... then: team new <name>"
