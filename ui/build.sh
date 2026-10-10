#!/usr/bin/env bash
# Build the dashboard (ui/web -> ui/dist, gitignored). Used by install.sh and `team ui`.
# bun: the version pinned in ui/web/package.json ("packageManager"), installed on demand under .runtime/bun (like opencode),
# so the lockfile and the build never depend on whatever bun the machine has. Falls back to bun on PATH if that install fails.
# Skips the build when the sources are unchanged: ui/dist/.stamp holds a hash of their contents (not mtimes, which git checkouts scramble).
set -euo pipefail
R=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
W=$R/ui/web D=$R/ui/dist

want=$(cd "$W" && find . -name node_modules -prune -o -type f -print | LC_ALL=C sort | xargs -r -d '\n' sha256sum | sha256sum | cut -d' ' -f1)
[ -f "$D/index.html" ] && [ "$(cat "$D/.stamp" 2>/dev/null)" = "$want" ] && exit 0

V=$(sed -n 's/.*"packageManager": *"bun@\([^"]*\)".*/\1/p' "$W/package.json")
BUN=$R/.runtime/bun/node_modules/.bin/bun
if [ ! -x "$BUN" ] || { [ -n "$V" ] && [ "$("$BUN" --version 2>/dev/null)" != "$V" ]; }; then
  BUN=
  if [ -n "$V" ] && command -v npm >/dev/null; then
    echo "installing bun $V under .runtime/bun..." >&2
    npm i --prefix "$R/.runtime/bun" "bun@$V" >&2 && BUN=$R/.runtime/bun/node_modules/.bin/bun
  fi
  [ -x "$BUN" ] || BUN=$(command -v bun || true)
fi
[ -n "$BUN" ] || { echo "no bun available: install node/npm (the pinned bun is fetched with npm) or bun itself (https://bun.sh)" >&2; exit 1; }

echo "building the dashboard (ui/web) with bun $("$BUN" --version)..." >&2
(cd "$W" && "$BUN" install --frozen-lockfile && "$BUN" run build) >&2
echo "$want" > "$D/.stamp"
