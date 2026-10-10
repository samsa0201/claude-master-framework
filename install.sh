#!/usr/bin/env bash
# Install worker runtimes under .runtime/ (gitignored), put `team` on PATH, install the studio skill.
set -euo pipefail
R=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$R/.runtime" ~/.local/bin
[ -x "$R/.runtime/opencode/node_modules/.bin/opencode" ] || npm i --prefix "$R/.runtime/opencode" opencode-ai@1.18.35
if [ ! -x "$R/.runtime/goose/goose" ]; then   # official release binary, pinned
  mkdir -p "$R/.runtime/goose"
  curl -fsSL https://github.com/block/goose/releases/download/v1.54.0/goose-x86_64-unknown-linux-gnu.tar.bz2 | tar -xj -C "$R/.runtime/goose"
fi
ln -sf "$R/bin/team" ~/.local/bin/team
mkdir -p ~/.claude/skills && ln -sfn "$R/skills/studio" ~/.claude/skills/studio
if command -v bun >/dev/null; then (cd "$R/ui/web" && bun install --frozen-lockfile && bun run build)   # dashboard for `team ui`
else echo "bun not found: for 'team ui' install bun (https://bun.sh), then: cd $R/ui/web && bun install && bun run build"; fi
echo "ok. export NINEROUTER_API_KEY=... (in the shell that runs claude), then: team new <name>"
