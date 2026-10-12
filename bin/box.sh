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
  x=$(dirname "$(dirname "$x")"); case $x in /|/usr|/usr/local) ;; *) echo "$x" ;; esac
}
box_mounts() {   # <proj dir>: one docker --volume=... per line; host paths keep their path inside the box
  local d=$1 g gd x
  g=$(git -C "$d" rev-parse --path-format=absolute --git-common-dir); gd=$(git -C "$d" rev-parse --path-format=absolute --git-dir)
  echo "--volume=$d:$d"
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
  for x in "$ROOT/.runtime/opencode" "$ROOT/.runtime/goose" "$ROOT/runtime-home"; do [ -e "$x" ] && echo "--volume=$x:$x:ro"; done
  x=$(node_prefix); [ -n "$x" ] && echo "--volume=$x:$x:ro"
  [ -x "$HOME/.bun/bin/bun" ] && echo "--volume=$HOME/.bun/bin/bun:$HOME/.bun/bin/bun:ro"   # not the rest of ~/.bun (9router lives there)
  x=${TEAM_PW_CACHE:-$HOME/.cache/ms-playwright}; [ -d "$x" ] && echo "--volume=$x:$x:ro"
  [ -d /tmp/.X11-unix ] && echo "--volume=/tmp/.X11-unix:/tmp/.X11-unix"   # QA browser draws on the shared Xvfb display
  for x in ${TEAM_BOX_EXTRA_RO:-}; do echo "--volume=$x:$x:ro"; done   # tests only (fake worker script)
  return 0
}
box_up() {   # <proj>: make sure the box runs; fail-closed (dies, never falls back to the host)
  local p=$1 d n img x path mv
  d=$(readlink -f "$(P "$p")"); n=$(bx "$p")
  box_ok || die "docker unavailable: workers need a box (TEAM_SANDBOX=none runs them unsandboxed)"
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || die "box needs a git repo: $d"
  if ! box_running "$p"; then
    $DOCKER rm -f "$n" "$n-ts" >/dev/null 2>&1 || true
    img=$(box_image) || exit 1
    $DOCKER network inspect "$n" >/dev/null 2>&1 || $DOCKER network create "$n" >/dev/null || die "docker network create $n failed"
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
  fi
  return 0
}
box_down() {   # <proj>: remove box, sidecar, network and home volume (best effort, quiet)
  local n; n=$(bx "$1"); box_ok || return 0
  $DOCKER rm -f "$n" "$n-ts" >/dev/null 2>&1 || true
  $DOCKER network rm "$n" >/dev/null 2>&1 || true
  $DOCKER volume rm "$n-home" >/dev/null 2>&1 || true
}
