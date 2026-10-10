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

"$T" new p2 >/dev/null
mkdir -p "$TEAM_PROJECTS/p2/.team/roles"
printf -- '---\nmodel: fidt/kCode\n---\nFLEX-FE: React + Vite, test with npm test\n' > "$TEAM_PROJECTS/p2/.team/roles/dev-fe.md"
id=$("$T" assign p2 dev-fe "x" --runtime fake); waits "$id" >/dev/null
check "suffix role uses base dev.md" grep -q "TDD" "$TEAM_PROJECTS/p2/.team/out/$id.md"
check "flex body appended" grep -q "FLEX-FE" "$TEAM_PROJECTS/p2/.team/out/$id.md"
check "flex model overrides base" grep -q "model=fidt/kCode" "$TEAM_PROJECTS/p2/.team/out/$id.md"
id=$("$T" assign p2 dev-be "x" --runtime fake); waits "$id" >/dev/null
check "base default model" grep -q "model=fidt/qwen3.8-flash" "$TEAM_PROJECTS/p2/.team/out/$id.md"
id=$("$T" assign p2 dev-fe "y" --runtime fake --model fidt/other --new); waits "$id" >/dev/null
check "--model beats flex" grep -q "model=fidt/other" "$TEAM_PROJECTS/p2/.team/out/$id.md"
id=$("$T" assign p2 writer "x" --runtime fake); waits "$id" >/dev/null
check "unknown role -> _base" grep -q "described in the task file" "$TEAM_PROJECTS/p2/.team/out/$id.md"
check "no frontmatter leaks into prompt" bash -c "! grep -q '^model:' '$TEAM_PROJECTS/p2/.team/out/$id.md'"
check "flex without frontmatter is whole body" bash -c "printf 'PLAIN-FLEX\n' > '$TEAM_PROJECTS/p2/.team/roles/docs.md'; i=\$('$T' assign p2 docs x --runtime fake); '$T' wait \$i 20 >/dev/null; grep -q PLAIN-FLEX '$TEAM_PROJECTS/p2/.team/out/'\$i.md"
"$T" new p3 >/dev/null
id=$("$T" assign p3 dev "FAKE_DIE" --runtime fake)
r=$("$T" wait "$id" 20); rc=$?
check "crashed worker -> dead" test "$r/$rc" = "dead/2"
id=$("$T" assign p3 qc "FAKE_HANG" --runtime fake)
r=$("$T" wait "$id" 2); rc=$?
check "hung worker -> timeout" test "$r/$rc" = "timeout/1"
pn=$(tmux list-panes -a -F '#{pane_id} #{@tid}' | awk -v i="$id" '$2==i{print $1}')
check "qwen default timeout 900" test "$(tmux show-option -pqv -t "$pn" @timeout)" = 900
id=$("$T" assign p3 docs "FAKE_HANG" --runtime fake --model fidt/kCode)
pn=$(tmux list-panes -a -F '#{pane_id} #{@tid}' | awk -v i="$id" '$2==i{print $1}')
check "kCode default timeout 1800" test "$(tmux show-option -pqv -t "$pn" @timeout)" = 1800
id=$("$T" assign p3 dev-x "a" --runtime fake); waits "$id" >/dev/null
nt=$(ls "$TEAM_PROJECTS/p3/.team/tasks" | wc -l)
msg=$("$T" assign p3 dev-x "b" --runtime fake --model fidt/other 2>&1)
check "reuse with different model refused" bash -c '[[ "$1" == *"use --new or"* ]]' _ "$msg"
check "refused assign wrote no task" test "$(ls "$TEAM_PROJECTS/p3/.team/tasks" | wc -l)" = "$nt"
id=$("$T" assign p3 dev-x "b" --runtime fake --model fidt/other --new)
check "--new allows other model" test "$(waits "$id")" = done
printf 'notes\n---\nmodel: fidt/bad\n' > "$TEAM_PROJECTS/p3/.team/roles/qd.md"
id=$("$T" assign p3 qd "x" --runtime fake); waits "$id" >/dev/null
check "fm ignores non-frontmatter ---" bash -c "! grep -q 'model=fidt/bad' '$TEAM_PROJECTS/p3/.team/out/$id.md'"
check "opencode preflight needs key" bash -c "env -u NINEROUTER_API_KEY '$T' assign p1 dev x --runtime opencode 2>&1 | grep -q NINEROUTER_API_KEY"
check "preflight failure opens no pane" bash -c "! '$T' ls | grep -q ' p1-dev$'"
check "opencode env is valid JSON with role instructions" bash -c "
  ROOT='$R' d=/tmp/p role=dev model=fidt/qwen3.8-flash browser=none msg=m NINEROUTER_API_KEY=k
  source '$R/agents/runtime/opencode.sh'
  rt_env | sed -n 's/^OPENCODE_CONFIG_CONTENT=//p' | python3 -c 'import json,sys; c=json.load(sys.stdin); assert c[\"instructions\"]==[\"/tmp/p/.team/role-dev.md\"]'"
check "opencode cmd uses 9r provider + prompt" bash -c "
  ROOT='$R' d=/tmp/p role=dev model=fidt/kCode browser=none msg=m
  source '$R/agents/runtime/opencode.sh'; rt_cmd | grep -q -- \"-m 9r/fidt/kCode --prompt 'm'\""
check "opencode.json is valid JSON" python3 -c "import json; json.load(open('$R/runtime-home/opencode.json'))"
check "opencode env isolates XDG dirs" bash -c "
  ROOT='$R' d=/tmp/p role=dev model=m browser=none msg=m NINEROUTER_API_KEY=k
  source '$R/agents/runtime/opencode.sh'; e=\$(rt_env)
  grep -qx \"XDG_CONFIG_HOME=$R/runtime-home/xdg\" <<<\"\$e\" && grep -qx \"XDG_DATA_HOME=$R/.runtime/data\" <<<\"\$e\""
check "opencode env NINEROUTER_URL default + override" bash -c "
  ROOT='$R' d=/tmp/p role=dev model=m browser=none msg=m NINEROUTER_API_KEY=k
  source '$R/agents/runtime/opencode.sh'; rt_env | grep -qx NINEROUTER_URL=http://localhost:20128/v1
  NINEROUTER_URL=http://x:1/v1; source '$R/agents/runtime/opencode.sh'; rt_env | grep -qx NINEROUTER_URL=http://x:1/v1"
"$T" new p5 >/dev/null
id=$("$T" assign p5 qa "FAKE_HANG" --runtime fake)
check "browser role starts Xvfb on test display" bash -c "pgrep -a -x Xvfb | grep -q ' $TEAM_DISPLAY '"
check "noVNC web port listens on localhost" bash -c "ss -ltn | grep -q '127.0.0.1:$TEAM_WEB_PORT'"
check "second browser worker refused while busy" bash -c "o=\$('$T' assign p5 qa-2 x --runtime fake 2>&1); [ \$? -ne 0 ] && grep -q busy <<<\"\$o\""
check "non-browser role not blocked" bash -c "i=\$('$T' assign p5 pm x --runtime fake) && '$T' wait \$i 20 | grep -q done"
"$T" close p5 qa >/dev/null
check "lock released after close" bash -c "i=\$('$T' assign p5 qa-3 x --runtime fake) && '$T' wait \$i 20 | grep -q done"
"$T" display stop
check "display stop kills Xvfb" bash -c "! pgrep -a -x Xvfb | grep -q ' $TEAM_DISPLAY '"
check "opencode browser env adds playwright MCP on display" bash -c "
  ROOT='$R' d=/tmp/p role=qa model=fidt/qwen3.8-flash browser=qa msg=m NINEROUTER_API_KEY=k TEAM_DISPLAY=:97
  source '$R/agents/runtime/opencode.sh'
  rt_env | sed -n 's/^OPENCODE_CONFIG_CONTENT=//p' | python3 -c 'import json,sys; m=json.load(sys.stdin)[\"mcp\"][\"playwright\"]; assert m[\"environment\"][\"DISPLAY\"]==\":97\" and \"/tmp/p/.team/out/browser\" in m[\"command\"]'"
"$T" new p6 >/dev/null
check "missing chromium aborts browser assign before spawning" bash -c "
  o=\$(TEAM_PW_CACHE=/nonexistent TEAM_OPENCODE=/bin/true NINEROUTER_API_KEY=k '$T' assign p6 qa x 2>&1); rc=\$?
  [ \$rc -ne 0 ] && grep -q 'no Playwright chromium' <<<\"\$o\" && ! '$T' ls | grep -q ' p6-qa\$'"
check "goose refuses browser roles" bash -c "NINEROUTER_API_KEY=k '$T' assign p1 qa x --runtime goose 2>&1 | grep -q 'no browser'"
check "goose cmd: interactive, system prompt from role file, anti-loop" bash -c "
  ROOT='$R' d=/tmp/p role=dev model=fidt/qwen3.8-flash browser=none msg=m
  source '$R/agents/runtime/goose.sh'; c=\$(rt_cmd); [[ \$c == *' run --system '*&& \$c != *' -s '* && \$c == *'role-dev.md'* && \$c == *'--max-tool-repetitions 5'* && \$c == *\"-t 'm'\"* ]]"
check "goose env isolates config/data/state" bash -c "
  ROOT='$R' d=/tmp/p role=dev browser=none NINEROUTER_API_KEY=k
  source '$R/agents/runtime/goose.sh'; e=\$(rt_env)
  grep -qx \"XDG_CONFIG_HOME=$R/runtime-home/goose\" <<<\"\$e\" && grep -qx \"XDG_DATA_HOME=$R/.runtime/data\" <<<\"\$e\" && grep -qx \"XDG_STATE_HOME=$R/.runtime/state\" <<<\"\$e\""
"$T" new p7 >/dev/null
id=$("$T" assign p7 dev "FAKE_DIE" --runtime fake)
check "dead worker reported dead" test "$(waits "$id")" = dead
id=$("$T" assign p7 dev "ok" --runtime fake)
check "assign to dead pane respawns -> done" test "$(waits "$id")" = done
check "exactly one p7-dev pane" test "$("$T" ls | grep -c ' p7-dev$')" = 1
"$T" new p8 >/dev/null
id=$(FAKE_ONESHOT=1 "$T" assign p8 dev "FAKE_HANG" --runtime fake)
check "busy one-shot worker refused" bash -c "o=\$(FAKE_ONESHOT=1 '$T' assign p8 dev x --runtime fake 2>&1); [ \$? -ne 0 ] && grep -q busy <<<\"\$o\""
touch "$TEAM_PROJECTS/p8/.team/out/$id.done"
id=$(FAKE_ONESHOT=1 "$T" assign p8 dev "ok" --runtime fake)
check "finished one-shot worker respawned -> done" test "$(waits "$id")" = done
check "exactly one p8-dev pane" test "$("$T" ls | grep -c ' p8-dev$')" = 1
check "opencode env disables ~/.claude + external skills" bash -c "
  ROOT='$R' d=/tmp/p role=dev model=m browser=none msg=m NINEROUTER_API_KEY=k
  source '$R/agents/runtime/opencode.sh'; e=\$(rt_env)
  grep -qx OPENCODE_DISABLE_CLAUDE_CODE=1 <<<\"\$e\" && grep -qx OPENCODE_DISABLE_EXTERNAL_SKILLS=1 <<<\"\$e\""
check "opencode.json denies tmux/team" python3 -c "
import json; b=json.load(open('$R/runtime-home/opencode.json'))['permission']['bash']
assert all(b[k]=='deny' for k in ['tmux*','*tmux *','team *','*bin/team*'])"
"$T" new cx >/dev/null; "$T" new cxy >/dev/null
for r in dev dev-fe; do waits "$("$T" assign cx $r "FAKE_HANG" --runtime fake)" 1 >/dev/null; done
waits "$("$T" assign cx dev "FAKE_HANG" --runtime fake --new)" 1 >/dev/null
waits "$("$T" assign cxy dev "FAKE_HANG" --runtime fake)" 1 >/dev/null
"$T" close cx dev
check "close cx dev: exact + numbered only" bash -c "l=\$('$T' ls); grep -q ' cx-dev-fe\$' <<<\"\$l\" && grep -q ' cxy-dev\$' <<<\"\$l\" && ! grep -qE ' cx-dev(-2)?\$' <<<\"\$l\""
"$T" close cx
check "close cx: all cx-*, not cxy" bash -c "l=\$('$T' ls); ! grep -q ' cx-' <<<\"\$l\" && grep -q ' cxy-dev\$' <<<\"\$l\""
"$T" new gx >/dev/null
check "new excludes .team from git" git -C "$TEAM_PROJECTS/gx" check-ignore -q .team/auth.json
"$T" new w1 >/dev/null
ida=$("$T" assign w1 dev "FAKE_HANG" --runtime fake); sleep 1
idb=$("$T" assign w1 dev "FAKE_HANG" --runtime fake)
check "wait on superseded id in live pane -> timeout" test "$(waits "$ida" 3)" = timeout
# team ui builds the dashboard on demand (ui/build.sh), then serves it. Fake studio root; fake npm installs a fake pinned bun.
U=$(mktemp -d); mkdir -p "$U/ui/web/src" "$U/fakebin"; cp "$R/ui/build.sh" "$U/ui/"
echo 'import sys; print("SERVED", sys.argv[1])' > "$U/ui/serve.py"; echo one > "$U/ui/web/src/a.ts"
echo '{"packageManager": "bun@1.3.14"}' > "$U/ui/web/package.json"
fakebun() { mkdir -p "$(dirname "$1")"; cat > "$1" <<B
#!/usr/bin/env bash
[ "\$1" = --version ] && { echo 1.3.14; exit 0; }
echo "$2 \$*" >> "\$FAKE_LOG"
[ -z "\${FAKE_BUN_FAIL:-}" ] || exit 1
[ "\$1 \$2" = "run build" ] && { mkdir -p ../dist; echo built > ../dist/index.html; }
exit 0
B
  chmod +x "$1"; }
cat > "$U/fakebin/npm" <<B
#!/usr/bin/env bash
echo "NPM \$*" >> "\$FAKE_LOG"
[ -z "\${FAKE_NPM_FAIL:-}" ] || exit 1
B="\$3/node_modules/.bin/bun"; mkdir -p "\$(dirname "\$B")"
cat > "\$B" <<'F'
#!/usr/bin/env bash
[ "\$1" = --version ] && { echo 1.3.14; exit 0; }
echo "PINNED \$*" >> "\$FAKE_LOG"
[ -z "\${FAKE_BUN_FAIL:-}" ] || exit 1
[ "\$1 \$2" = "run build" ] && { mkdir -p ../dist; echo built > ../dist/index.html; }
exit 0
F
chmod +x "\$B"
B
chmod +x "$U/fakebin/npm"; fakebun "$U/fakebin/bun" PATHBUN
uirun() { PATH="$U/fakebin:$PATH" STUDIO_ROOT="$U" FAKE_LOG="$U/log" "$T" ui "$@" 2>&1; }
out=$(uirun 7000)
check "no dist: installs the pinned bun via npm, builds with it, serves" bash -c '[[ "$1" == *"SERVED 7000"* ]] && grep -q "^NPM i --prefix .*/.runtime/bun bun@1.3.14" "$2" && grep -q "^PINNED install --frozen-lockfile" "$2" && grep -q "^PINNED run build" "$2" && ! grep -q PATHBUN "$2"' _ "$out" "$U/log"
rm -f "$U/log"; mkdir -p "$U/ui/web/node_modules"; echo y > "$U/ui/web/node_modules/x"; out=$(uirun 7001)
check "unchanged sources: nothing runs (node_modules ignored)" bash -c '[[ "$1" == *"SERVED 7001"* ]] && [ ! -e "$2" ]' _ "$out" "$U/log"
touch -d '+1 hour' "$U/ui/web/src/a.ts"; out=$(uirun 7002)
check "newer mtime but same content: no build (hash, not mtime)" bash -c '[[ "$1" == *"SERVED 7002"* ]] && [ ! -e "$2" ]' _ "$out" "$U/log"
echo two > "$U/ui/web/src/a.ts"; out=$(uirun 7003)
check "changed content: rebuild with the installed pinned bun, no reinstall" bash -c '[[ "$1" == *"SERVED 7003"* ]] && grep -q "^PINNED run build" "$2" && ! grep -q "^NPM" "$2"' _ "$out" "$U/log"
echo three > "$U/ui/web/src/a.ts"; out=$(FAKE_BUN_FAIL=1 uirun 7004)
check "failed rebuild still serves the previous build" bash -c '[[ "$1" == *"previous build"* && "$1" == *"SERVED 7004"* ]]' _ "$out"
echo four > "$U/ui/web/src/a.ts"; rm -rf "$U/.runtime" "$U/log"; out=$(FAKE_NPM_FAIL=1 uirun 7005)
check "npm fails: falls back to bun on PATH" bash -c '[[ "$1" == *"SERVED 7005"* ]] && grep -q "^PATHBUN run build" "$2"' _ "$out" "$U/log"
echo five > "$U/ui/web/src/a.ts"; rm -rf "$U/ui/dist" "$U/.runtime"; out=$(FAKE_NPM_FAIL=1 FAKE_BUN_FAIL=1 uirun 7006); rc=$?
check "no dist and no working bun -> error, not served" bash -c '[ "$2" -ne 0 ] && [[ "$1" != *SERVED* ]]' _ "$out" "$rc"
rm -rf "$U"
# @@MORE_TESTS@@ (later tasks insert their blocks above this line)
[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
