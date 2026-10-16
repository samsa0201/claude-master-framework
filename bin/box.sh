# Project box: one Docker container + network per project (docs/superpowers/specs/2026-10-12-project-box-design.md).
# Sourced by bin/team (needs ROOT, PROJ, P, die). Workers and lead-started apps run here as the host uid, no caps.
DOCKER=${TEAM_DOCKER:-docker}
BOX_PREFIX=${TEAM_BOX_PREFIX:-studio}
BOX_UID=$(id -u); BOX_GID=$(id -g)
box_image() {   # build studio-box:<hash of Dockerfile + uid/gid> once; prints the tag
  local t; t="studio-box:$( { cat "$ROOT/box/Dockerfile"; echo "$BOX_UID:$BOX_GID"; } | sha256sum | cut -c1-12)"
  $DOCKER image inspect "$t" >/dev/null 2>&1 ||
    $DOCKER build -q --build-arg UID="$BOX_UID" --build-arg GID="$BOX_GID" -t "$t" "$ROOT/box" >/dev/null ||
    die "box image build failed (docker build $ROOT/box)"
  echo "$t"
}
bx() { echo "$BOX_PREFIX-$1"; }
box_ok() { command -v "$DOCKER" >/dev/null 2>&1 && $DOCKER info >/dev/null 2>&1; }
box_running() { [ "$($DOCKER inspect -f '{{.State.Running}}' "$(bx "$1")" 2>/dev/null)" = true ]; }
node_prefix() {   # prints node's install prefix, or nothing for system prefixes (/, /usr, /usr/local: the image has those)
  local x; x=$(node -p process.execPath 2>/dev/null) || return 0
  x=$(dirname "$(dirname "$x")"); x=${x%%/Cellar/*}   # Homebrew node needs the prefix's ld.so and lib/, opt/ deps, not just its Cellar dir
  case $x in /|/usr|/usr/local) ;; *) echo "$x" ;; esac
}
box_mounts() {   # <proj dir>: one docker --volume=... per line; host paths keep their path inside the box
  local d=$1 g gd x
  g=$d/.git gd=$d/.git   # plain repo: never ask git, it follows a box-planted .git/commondir to any host repo
  [ -f "$d/.git" ] && { g=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir); gd=$(git -C "$d" rev-parse --path-format=absolute --git-dir); }
  echo "--volume=$d:$d"
  mkdir -p "$d/.team/out" "$d/.team/logs" "$d/.team/run"   # .team is read by the HOST (roles, tasks, role prompts): ro, worker output dirs rw
  echo "--volume=$d/.team:$d/.team:ro"; for x in out logs run; do echo "--volume=$d/.team/$x:$d/.team/$x"; done
  if [ -f "$d/.git" ]; then   # attached worktree: commits write the main repo's objects/refs; pointers stay fixed
    for x in objects refs logs info; do mkdir -p "$g/$x"; done
    for x in objects refs logs; do echo "--volume=$g/$x:$g/$x"; done   # skeleton, not the whole git dir: the box can't add root files like commondir
    echo "--volume=$gd:$gd"; echo "--volume=$d/.git:$d/.git:ro"
    for x in HEAD info packed-refs; do [ -e "$g/$x" ] && echo "--volume=$g/$x:$g/$x:ro"; done
    echo "--volume=$gd/commondir:$gd/commondir:ro"; echo "--volume=$gd/gitdir:$gd/gitdir:ro"
  else echo "--volume=$d/.git:$d/.git"; fi   # a mountpoint can't be renamed: the worker can't swap in a repo with its own config
  mkdir -p "$g/hooks"   # a missing hooks dir would be writable
  # repo config and hooks run code on the HOST when the lead, the dashboard or the user run git (fsmonitor, filters, hooks)
  echo "--volume=$g/config:$g/config:ro"; echo "--volume=$g/hooks:$g/hooks:ro"
  [ -e "$gd/config.worktree" ] || : > "$gd/config.worktree"   # read when extensions.worktreeConfig is on (git sparse-checkout): same host-code risk as config
  echo "--volume=$gd/config.worktree:$gd/config.worktree:ro"
  for x in "$ROOT/.runtime/opencode" "$ROOT/.runtime/goose" "$ROOT/runtime-home"; do [ -e "$x" ] && echo "--volume=$x:$x:ro"; done
  x=$(node_prefix); [ -n "$x" ] && echo "--volume=$x:$x:ro"
  [ -x "$HOME/.bun/bin/bun" ] && echo "--volume=$HOME/.bun/bin/bun:$HOME/.bun/bin/bun:ro"   # not the rest of ~/.bun (9router lives there)
  x=${TEAM_PW_CACHE:-$HOME/.cache/ms-playwright}; [ -d "$x" ] && echo "--volume=$x:$x:ro"
  [ -d /tmp/.X11-unix ] && echo "--volume=/tmp/.X11-unix:/tmp/.X11-unix"   # QA browser draws on the shared Xvfb display
  for x in ${TEAM_BOX_EXTRA_RO:-}; do echo "--volume=$x:$x:ro"; done   # tests only (fake worker script)
  return 0
}
box_up() {   # <proj>: make sure the box runs; fail-closed (dies, never falls back to the host)
  local p=$1 d n img x path mv lk
  d=$(readlink -f "$(P "$p")"); n=$(bx "$p")
  mkdir -p "$PROJ/.box"; exec {lk}>"$PROJ/.box/$p.lock"; flock "$lk"   # one box_up per project: a racing one could rm -f a firewalled box
  box_ok || die "docker unavailable: workers need a box (TEAM_SANDBOX=none runs them unsandboxed)"
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || die "box needs a git repo: $d"
  if ! box_running "$p"; then
    for x in .git .git/config .git/hooks .team .team/out .team/logs .team/run; do   # links an older (rw .team) box may have planted
      [ -L "$d/$x" ] && die "refusing box: $d/$x is a symlink (remove it, a mount would follow it to the host)"
    done
    $DOCKER rm -f "$n" "$n-ts" >/dev/null 2>&1 || true
    img=$(box_image) || exit 1
    $DOCKER network inspect "$n" >/dev/null 2>&1 || $DOCKER network create --ipv6=false "$n" >/dev/null || die "docker network create $n failed"
    mapfile -t mv < <(box_mounts "$d")
    path=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    [ -x "$HOME/.bun/bin/bun" ] && path="$HOME/.bun/bin:$path"
    x=$(node_prefix); [ -n "$x" ] && path="$x/bin:$path"
    $DOCKER run -d --name "$n" --network "$n" --hostname "$p" --init \
      --user "$BOX_UID:$BOX_GID" --cap-drop ALL --security-opt no-new-privileges \
      --volume "$n-home:/box/home" "${mv[@]}" -e HOME=/box/home -e PATH="$path" \
      "$img" sleep infinity >/dev/null || die "box start failed: $n"
    for x in user.name user.email; do   # identity only, no credentials: commit yes, push no
      git config --global "$x" >/dev/null && $DOCKER exec "$n" git config --global "$x" "$(git config --global "$x")"
    done
    box_ts "$p"
  fi
  box_fw "$p" || { $DOCKER rm -f "$n" "$n-ts" >/dev/null 2>&1; die "egress rules failed: box $n removed (fail-closed)"; }
  box_fwd "$p"
  exec {lk}>&-
}
box_down() {   # <proj>: remove box, sidecar, network and home volume (best effort, quiet). The tailscale state volume
              # <box>-ts stays: a later box of this name rejoins as the same node instead of <name>-1 (logout races containerboot)
  local n; n=$(bx "$1"); rm -f "$(P "$1")"/.team/run/*.pid; box_ok || return 0   # app pid files die with the box
  $DOCKER rm -f "$n" "$n-ts" >/dev/null 2>&1 || true
  $DOCKER network rm "$n" >/dev/null 2>&1 || true
  $DOCKER volume rm "$n-home" >/dev/null 2>&1 || true
}
EGRESS_DEFAULT=(registry.npmjs.org registry.yarnpkg.com pypi.org files.pythonhosted.org)
nr_port() { local u=${NINEROUTER_URL:-http://localhost:20128/v1} d=80; [[ $u == https:* ]] && d=443; u=${u#*://}; u=${u%%/*}; [[ $u == *:* ]] && echo "${u##*:}" || echo $d; }
box_gw() { $DOCKER network inspect -f '{{(index .IPAM.Config 0).Gateway}}' "$(bx "$1")"; }
box_egress() { local f="$PROJ/.box/$1.egress"; [ -f "$f" ] && awk '!/^[[:space:]]*(#|$)/{print $1}' "$f"; return 0; }   # outside every mount: workers can't edit it
box_fw() {   # <proj> [--count]: (re)load egress rules from a short-lived root helper with NET_ADMIN; the box itself has no caps
  local p=$1; shift; local img eg; img=$(box_image) || return 1; mapfile -t eg < <(box_egress "$p")   # array: entries like *.x must not glob
  if [ "${1:-}" = --count ]; then
    $DOCKER run --rm -i --user 0 --network "container:$(bx "$p")" --cap-add NET_ADMIN "$img" bash -s -- --count < "$ROOT/box/fw.sh"
  else
    $DOCKER run --rm -i --user 0 --network "container:$(bx "$p")" --cap-add NET_ADMIN "$img" \
      bash -s -- "$BOX_UID" "$(box_gw "$p")" "$(nr_port)" "${EGRESS_DEFAULT[@]}" "${eg[@]}" < "$ROOT/box/fw.sh"
  fi
}
box_fwd() {   # <proj>: 127.0.0.1:<9router port> in the box -> 9router on the host; adapters keep NINEROUTER_URL=localhost (goose can't change it)
  local n port; n=$(bx "$1"); port=$(nr_port)
  $DOCKER exec "$n" bash -c "exec 3<>/dev/tcp/127.0.0.1/$port" 2>/dev/null && return 0
  $DOCKER exec -d "$n" socat "TCP-LISTEN:$port,bind=127.0.0.1,fork,reuseaddr" "TCP:$(box_gw "$1"):$port"
  sleep 0.3
}
box_env() {   # rt_env lines -> lines for the box: data/state dirs move into the box home ($ROOT/.runtime/data is not mounted)
  sed -e 's|^XDG_DATA_HOME=.*|XDG_DATA_HOME=/box/home/.local/share|' -e 's|^XDG_STATE_HOME=.*|XDG_STATE_HOME=/box/home/.local/state|'
}
box_cmd() {   # <proj> <dir> <cmd> <env names...>: docker exec line (bash syntax); values come from the pane env, never the command line
  local p=$1 d=$2 c=$3 k s; shift 3
  s="$DOCKER exec -it -u $BOX_UID:$BOX_GID -w $(printf %q "$d")"
  for k in "$@"; do s+=" -e $k"; done
  echo "$s $(printf %q "$(bx "$p")") bash -c $(printf %q "$c")"
}
box_pid() {   # <pid file>: its pid; fails on links, non-files, non-numbers (run/ is box-writable: never read host files through it)
  local x; [ ! -L "$1" ] && [ -f "$1" ] || return 1; read -r x < "$1" || true; [[ $x =~ ^[0-9]+$ ]] && echo "$x"
}
box_ps() {   # <proj> <dir>: "<name> running|stopped" per app started with team run
  local f n x; for f in "$2"/.team/run/*.pid; do
    [ -e "$f" ] || [ -L "$f" ] || continue; n=$(basename "$f" .pid)
    if x=$(box_pid "$f") && box_running "$1" && $DOCKER exec "$(bx "$1")" kill -0 -- "-$x" 2>/dev/null; then echo "$n running"; else echo "$n stopped"; fi
  done
}

TS_IMAGE=tailscale/tailscale:v1.102.3
TS_KEY=${TEAM_TS_KEY:-$HOME/.config/studio/ts-authkey}
box_ts() {   # <proj>: tailscale sidecar in the box netns (root there, so not egress-filtered); no key -> warn only, not a security boundary
  local p=$1 n; n=$(bx "$p")
  [ -s "$TS_KEY" ] || { echo "warning: no $TS_KEY: $p is not on tailnet (team url $p shows the ssh -L fallback)" >&2; return 0; }
  # key: env of the sidecar only (separate pid namespace from the box), passed by name, never on the command line
  # state on a volume: a recreated box comes back as the same node (same name), not <name>-1 next to its offline ghost
  TS_AUTHKEY=$(cat "$TS_KEY") $DOCKER run -d --name "$n-ts" --network "container:$n" --volume "$n-ts:/var/lib/tailscale" \
    -e TS_AUTHKEY -e TS_HOSTNAME="$p" -e TS_USERSPACE=true -e TS_STATE_DIR=/var/lib/tailscale "$TS_IMAGE" >/dev/null ||
    echo "warning: tailscale sidecar failed for $p (docker logs $n-ts)" >&2
}
box_ts_name() {   # <proj>: the sidecar's MagicDNS name (may get a -N suffix on collision), empty if none
  $DOCKER exec "$(bx "$1")-ts" tailscale status --json 2>/dev/null |
    python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true
}
