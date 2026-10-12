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
