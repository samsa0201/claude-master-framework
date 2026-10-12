#!/usr/bin/env bash
# Real Docker tests for the project box (bin/box.sh, box/). Needs docker and internet (npm registry, example.com).
# Own names (studiotest-*), a private tmux server and temp dirs; cleans up after itself. Run: tests/box_test.sh
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd)
export TEAM_REAL_TMUX=$(command -v tmux) PATH="$R/tests/shim:$PATH" TEAM_PROJECTS=$(mktemp -d)
export TEAM_BOX_PREFIX=studiotest TEAM_TS_KEY=/nonexistent TEAM_BOX_EXTRA_RO="$R/tests"
export NINEROUTER_URL=http://localhost:28128/v1   # fake 9router below
unset TMUX TEAM_SANDBOX
T="$R/bin/team"; fail=0; U=$(id -u); H=$(mktemp -d); M=$(mktemp -d); s1=; s2=
export R U   # helpers below are exported: checks call them through bash -c
cleanup() {
  for p in b1 b2 b3 b4 b5 a1; do "$T" close "$p" >/dev/null 2>&1; done
  docker rm -f $(docker ps -aq --filter name=studiotest-) >/dev/null 2>&1
  [ -n "$s1" ] && kill "$s1" "$s2" 2>/dev/null; tmux kill-server 2>/dev/null; rm -rf "$TEAM_PROJECTS" "$H" "$M"
}
trap cleanup EXIT
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok - $name"; else echo "FAIL - $name"; fail=1; fi; }
not() { ! "$@"; }
img() { ( ROOT=$R; PROJ=$TEAM_PROJECTS; P() { echo "$PROJ/$1"; }; die() { echo "$*" >&2; exit 1; }; source "$R/bin/box.sh"; box_image ); }

# --- image ---
I=$(img); export I
check "image builds and is tagged by content" bash -c "[[ '$I' =~ ^studio-box:[0-9a-f]{12}$ ]] && docker image inspect '$I'"
check "image has git, python3, socat, iptables" docker run --rm "$I" bash -c "command -v git python3 socat iptables-restore"
check "box home is owned by the host user" docker run --rm "$I" bash -c "[ \$(stat -c %u /box/home) = $U ]"
CH=$(ls -d "${TEAM_PW_CACHE:-$HOME/.cache/ms-playwright}"/chromium-*/chrome-linux64 2>/dev/null | sort -V | tail -1)
[ -n "$CH" ] && check "chromium libs all resolve in the image" docker run --rm -v "$CH:$CH:ro" "$I" bash -c "! ldd '$CH/chrome' | grep -q 'not found'"
check "same Dockerfile -> same tag, no rebuild" test "$(img)" = "$I"

# @@MORE_BOX_TESTS@@ (later tasks insert their blocks above this line)
[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
