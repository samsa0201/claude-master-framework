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

# --- lifecycle, filesystem allowlist, git protection ---
in_box() { docker exec -u "$U" "studiotest-$1" bash -c "$2"; }
bt() { ( ROOT=$R; PROJ=$TEAM_PROJECTS; P() { echo "$PROJ/$1"; }; die() { echo "$*" >&2; exit 1; }; source "$R/bin/box.sh"; "$@" ); }
export -f in_box bt
"$T" new b1 >/dev/null
check "box_up starts the box" bt box_up b1
check "box runs as the host uid with home /box/home" bash -c "[ \"\$(docker exec studiotest-b1 bash -c 'id -u; echo \$HOME' | paste -sd' ')\" = '$U /box/home' ]"
check "project dir is writable, files owned by the host user" bash -c "docker exec studiotest-b1 touch '$TEAM_PROJECTS/b1/w' && [ \$(stat -c %u '$TEAM_PROJECTS/b1/w') = $U ]"
check "host home is hidden (no ~/.ssh, no studio repo, no .env)" in_box b1 "[ ! -e '$HOME/.ssh' ] && [ ! -e '$R/bin/team' ] && [ ! -e '$R/.env' ]"
check "runtime-home is mounted read-only" in_box b1 "[ -d '$R/runtime-home' ] && ! touch '$R/runtime-home/x' 2>/dev/null"
check "no docker socket" in_box b1 "[ ! -e /var/run/docker.sock ]"
check "root in the box has no capabilities" not docker exec -u 0 studiotest-b1 chown 0 "$TEAM_PROJECTS/b1/w"
check "git commit works in the box" in_box b1 "cd '$TEAM_PROJECTS/b1' && git add w && git -c user.name=t -c user.email=t@t commit -qm t"
check "repo config is read-only" not in_box b1 "echo '[core]' >> '$TEAM_PROJECTS/b1/.git/config'"
check "repo hooks are read-only" not in_box b1 "echo x > '$TEAM_PROJECTS/b1/.git/hooks/pre-commit'"
check ".git cannot be swapped for another repo" not in_box b1 "mv '$TEAM_PROJECTS/b1/.git' '$TEAM_PROJECTS/b1/g2'"
check "box_up again keeps the running box" bash -c "c=\$(docker inspect -f '{{.Id}}' studiotest-b1); bt box_up b1 && [ \"\$(docker inspect -f '{{.Id}}' studiotest-b1)\" = \"\$c\" ]"
# attached worktree: commits land in the main repo, whose config/hooks stay read-only
git -C "$M" init -q; git -C "$M" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
git -C "$M" worktree add -q -b feat/a1 "$TEAM_PROJECTS/a1"
check "worktree box starts" bt box_up a1
check "worktree commit writes the main repo" bash -c "in_box a1 \"cd '$TEAM_PROJECTS/a1' && git -c user.name=t -c user.email=t@t commit -q --allow-empty -m w\" && git -C '$M' log --format=%s feat/a1 | grep -qx w"
check "main repo config is read-only" not in_box a1 "echo x >> '$M/.git/config'"
check "main repo hooks are read-only" not in_box a1 "touch '$M/.git/hooks/post-checkout'"
check "worktree .git pointer is read-only" not in_box a1 "echo 'gitdir: /tmp/x' > '$TEAM_PROJECTS/a1/.git'"
check "worktree commondir is read-only" not in_box a1 "echo /tmp > '$M/.git/worktrees/a1/commondir'"
check "box cannot plant commondir in the main repo" not in_box a1 "echo /tmp > '$M/.git/commondir'"
check "box cannot add files at the main git dir root" not in_box a1 "touch '$M/.git/x'"
check "worktree can create a new branch" in_box a1 "cd '$TEAM_PROJECTS/a1' && git switch -q -c feat/a1-2"
mkdir -p "$H/stub"; printf '#!/bin/sh\necho /usr/bin/node\n' > "$H/stub/node"; chmod +x "$H/stub/node"
check "distro node (/usr/bin) does not mount /usr" bash -c "! PATH='$H/stub':\$PATH bt box_mounts '$TEAM_PROJECTS/b1' | grep -q -- '--volume=/usr:'"
check "real node prefix is mounted" bash -c "x=\$(dirname \$(dirname \$(node -p process.execPath))); case \$x in /|/usr|/usr/local) exit 0;; esac; bt box_mounts '$TEAM_PROJECTS/b1' | grep -qx -- \"--volume=\$x:\$x:ro\""
check "not a git repo -> refused" bash -c "mkdir -p '$TEAM_PROJECTS/ng'; ! bt box_up ng"
bt box_down a1
check "box_down removes container, network, volume" bash -c "! docker ps -a --format '{{.Names}}' | grep -qx studiotest-a1 && ! docker network ls --format '{{.Name}}' | grep -qx studiotest-a1 && ! docker volume ls -q | grep -qx studiotest-a1-home"

# --- egress firewall (uid-filtered, loaded by a root helper) ---
can() { in_box "$1" "timeout 4 bash -c '</dev/tcp/$2/$3'"; }
root_can() { docker run --rm --network "container:studiotest-$1" "$I" bash -c "timeout 4 bash -c '</dev/tcp/$2/$3'"; }   # root: not filtered
fwq() { docker run --rm --network "container:studiotest-$1" --cap-add NET_ADMIN "$I" iptables -S "$2"; }
export -f can root_can fwq
(cd "$H" && exec python3 -m http.server 28128 --bind 0.0.0.0 >/dev/null 2>&1) & s1=$!
(cd "$H" && exec python3 -m http.server 28129 --bind 0.0.0.0 >/dev/null 2>&1) & s2=$!
sleep 1; bt box_up b1
GW=$(docker network inspect -f '{{(index .IPAM.Config 0).Gateway}}' studiotest-b1)
check "9router port on the host: allowed" can b1 "$GW" 28128
check "9router forwarder: localhost:28128 inside the box" can b1 127.0.0.1 28128
check "other host port: blocked" not can b1 "$GW" 28129
check "...but open without the firewall (so the block is ours)" root_can b1 "$GW" 28129
LAN=$(ip -4 route get 1.1.1.1 | awk '{for(i=1;i<NF;i++) if($i=="src") print $(i+1)}')
check "host LAN address: blocked" not can b1 "$LAN" 28129
TSIP=$(tailscale ip -4 2>/dev/null | head -1 || true)
[ -n "$TSIP" ] && check "tailnet address: blocked" not can b1 "$TSIP" 28129
check "npm registry: allowed" can b1 registry.npmjs.org 443
check "example.com: blocked" not can b1 example.com 443
check "DNS resolves through Docker's resolver" in_box b1 "getent hosts example.com"
check "direct DNS to an outside resolver: blocked" not can b1 1.1.1.1 53
check "worker cannot flush the rules" not in_box b1 "iptables -F STUDIO"
check "root in the box cannot flush the rules" not docker exec -u 0 studiotest-b1 iptables -F STUDIO
bt box_up b1; bt box_up b1
check "reload is idempotent: one jump, one REJECT" bash -c "[ \$(fwq b1 OUTPUT | grep -c -- '-j STUDIO') = 1 ] && [ \$(fwq b1 STUDIO | grep -c REJECT) = 1 ]"
mkdir -p "$TEAM_PROJECTS/.box"; printf '# test\nexample.com\n' > "$TEAM_PROJECTS/.box/b1.egress"
bt box_up b1
check "allowlist file opens example.com" can b1 example.com 443
check "count reports rejected packets" bash -c "can b1 '$GW' 28129; [ \"\$(bt box_fw b1 --count)\" -ge 1 ]"
check "box network has IPv6 disabled" bash -c "[ \"\$(docker network inspect -f '{{.EnableIPv6}}' studiotest-b1)\" = false ]"
check "no global IPv6 address in the box" in_box b1 "! grep -v '^fe80\|^00000000000000000000000000000001' /proc/net/if_inet6 | grep -q ."
check "nr_port: https without port is 443" bash -c "[ \"\$(NINEROUTER_URL=https://x/v1 bt nr_port)\" = 443 ]"
check "nr_port: http without port is 80" bash -c "[ \"\$(NINEROUTER_URL=http://x/v1 bt nr_port)\" = 80 ]"
check "nr_port: explicit port wins" bash -c "[ \"\$(NINEROUTER_URL=http://localhost:28128/v1 bt nr_port)\" = 28128 ]"
printf '*\n' > "$TEAM_PROJECTS/.box/b1.egress"   # glob char in the allowlist must reach the helper literally
check "allowlist entries are not glob-expanded" bash -c "cd '$H' && [[ \$(bt box_fw b1 2>&1) == *'cannot resolve *'* ]]"
printf '# test\nexample.com\n' > "$TEAM_PROJECTS/.box/b1.egress"; bt box_fw b1
mkdir -p "$TEAM_PROJECTS/b3"; git -C "$TEAM_PROJECTS/b3" init -q
o=$(NINEROUTER_URL=http://localhost:notaport/v1 bt box_up b3 2>&1); rc=$?
export o rc   # $o holds iptables' quotes: pass by env, not through the bash -c string
check "rules fail -> box removed, error says fail-closed" bash -c "[ \$rc -ne 0 ] && [[ \$o == *fail-closed* ]] && ! docker ps -a --format '{{.Names}}' | grep -qx studiotest-b3"

# --- team assign runs the worker inside the box ---
tmux kill-server 2>/dev/null; tmux new-session -d -s t -x 220 -y 60
export TMUX_PANE=$(tmux list-panes -t t -F '#{pane_id}' | head -1)
id=$("$T" assign b1 pm "hello" --runtime fake)
check "fake worker ran inside the box" bash -c "[ \"\$('$T' wait $id 60)\" = done ] && grep -qx 'env home=/box/home' '$TEAM_PROJECTS/b1/.team/out/$id.md'"
check "worker output owned by the host user" test "$(stat -c %u "$TEAM_PROJECTS/b1/.team/out/$id.md")" = "$U"
"$T" close b1
check "team close <proj> removes the box" bash -c "! docker ps -a --format '{{.Names}}' | grep -qx studiotest-b1"
# --- lead commands: run / stop / exec / egress; two boxes on the same port ---
"$T" new b2 >/dev/null; "$T" new b4 >/dev/null
"$T" run b2 web "python3 -m http.server 5173" >/dev/null
"$T" run b4 web "python3 -m http.server 5173" >/dev/null; sleep 1.5
boxip() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "studiotest-$1"; }
check "two boxes serve :5173 at once" bash -c "curl -sf -m 3 http://$(boxip b2):5173/ >/dev/null && curl -sf -m 3 http://$(boxip b4):5173/ >/dev/null"
check "box b2 cannot reach box b4" not can b2 "$(boxip b4)" 5173
check "run lists the app" bash -c "'$T' run b2 | grep -qx 'web running'"
check "app log in .team/logs" test -f "$TEAM_PROJECTS/b2/.team/logs/web.log"
check "same name twice refused" not "$T" run b2 web true
"$T" stop b2 web >/dev/null; sleep 0.5
check "stop kills the app" bash -c "! curl -sf -m 2 http://$(boxip b2):5173/ >/dev/null && '$T' run b2 | grep -qx 'web stopped'"
check "exec runs as the box user" bash -c "[ \"\$('$T' exec b2 'id -u; echo \$HOME' | paste -sd' ')\" = '$U /box/home' ]"
check "exec passes the exit code" bash -c "'$T' exec b2 'exit 3'; [ \$? = 3 ]"
check "exec is firewalled" not "$T" exec b2 "timeout 4 bash -c '</dev/tcp/example.com/443'"
o=$("$T" egress b2)
check "egress prints counter and allowlist path" bash -c '[[ "$1" == *"rejected packets: "* && "$1" == *".box/b2.egress"* ]]' _ "$o"
"$T" close b2; "$T" close b4
# @@MORE_BOX_TESTS@@ (later tasks insert their blocks above this line)
[ $fail = 0 ] && echo "ALL PASS" || { echo "SOME FAILED"; exit 1; }
