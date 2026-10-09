#!/usr/bin/env bash
# Plumbing tests for bin/team with the fake runtime on a private tmux server.
# Never touches the user's tmux server or projects/. Run: tests/team_test.sh
set -uo pipefail
R=$(cd "$(dirname "$0")/.." && pwd)
export TEAM_REAL_TMUX=$(command -v tmux) PATH="$R/tests/shim:$PATH" TEAM_PROJECTS=$(mktemp -d)
export TEAM_DISPLAY=:97 TEAM_VNC_PORT=5997 TEAM_WEB_PORT=6077
unset TMUX
T="$R/bin/team"; fail=0
cleanup() { "$T" display stop >/dev/null 2>&1; tmux kill-server 2>/dev/null; rm -rf "$TEAM_PROJECTS"; }
trap cleanup EXIT
tmux kill-server 2>/dev/null
tmux new-session -d -s t -x 220 -y 60
export TMUX_PANE=$(tmux list-panes -t t -F '#{pane_id}' | head -1)
check() { local name=$1; shift; if "$@" >/dev/null 2>&1; then echo "ok - $name"; else echo "FAIL - $name"; fail=1; fi; }
waits() { "$T" wait "$1" "${2:-20}"; }          # prints done|timeout|dead
out() { cat "$TEAM_PROJECTS/$1/.team/out/$2.md"; }

"$T" new p1 >/dev/null
id=$("$T" assign p1 pm "hello" --runtime fake)
check "assign then wait -> done" test "$(waits "$id")" = done
check "worker wrote out file" grep -q "role=pm" "$TEAM_PROJECTS/p1/.team/out/$id.md"
check "unknown runtime rejected" bash -c "! '$T' assign p1 pm x --runtime nope"
id2=$("$T" assign p1 pm "again" --runtime fake)
check "reused pane gets follow-up" test "$(waits "$id2")" = done
check "still one pm pane" test "$("$T" ls | grep -c ' p1-pm$')" = 1
id3=$("$T" assign p1 pm "parallel" --runtime fake --new)
check "--new spawns pm-2" test "$(waits "$id3")" = done
check "pm-2 pane exists" bash -c "'$T' ls | grep -q ' p1-pm-2$'"

# @@MORE_TESTS@@ (later tasks insert their blocks above this line)
[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
