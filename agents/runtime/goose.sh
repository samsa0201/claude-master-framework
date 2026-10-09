# goose runtime (fallback). Config: runtime-home/goose (XDG_CONFIG_HOME). No browser support in MVP.
RT_ONESHOT=1   # process exits after its task (.done lands just before exit): assign always respawns
GO=${TEAM_GOOSE:-$ROOT/.runtime/goose/goose}
NR=${NINEROUTER_URL:-http://localhost:20128/v1}
rt_preflight() {
  [ "$browser" = none ] || die "goose runtime: no browser support (use --runtime opencode for $role)"
  [ -n "${NINEROUTER_API_KEY:-}" ] || die "NINEROUTER_API_KEY not set in this shell"
  [ -x "$GO" ] || die "goose not installed: run ./install.sh"
  curl -sf -m 5 -o /dev/null -H "Authorization: Bearer $NINEROUTER_API_KEY" "$NR/models" || die "9router unreachable or key rejected: $NR"
}
rt_env() {
  echo "XDG_CONFIG_HOME=$ROOT/runtime-home/goose"; echo "XDG_DATA_HOME=$ROOT/.runtime/data"; echo "XDG_STATE_HOME=$ROOT/.runtime/state"
  echo "GOOSE_DISABLE_KEYRING=1"; echo "NINEROUTER_API_KEY=$NINEROUTER_API_KEY"
}
# goose ignores follow-up messages in -s mode (verified), so no -s: each task is a fresh goose process (pane dies, next assign respawns)
rt_cmd() { echo "$GO run --system \"\$(cat '$d/.team/role-$role.md')\" --max-tool-repetitions 5 --model $model -t '$msg'"; }
