# dsh runtime (DeepSeek Harness, headless profile; trial). Config overlay: runtime-home/dsh/9router.patch.yml. No browser support.
# DSH_HOME stays the default (~/.dsh = the box home volume): sessions and profile live per project, never on the host.
RT_ONESHOT=1   # `dsh --profile headless` runs one task and exits: assign always respawns
DSH=${TEAM_DSH:-$ROOT/.runtime/dsh/node_modules/@deepseek-ai/dsh/lib/bin.js}
NR=${NINEROUTER_URL:-http://127.0.0.1:20128/v1}
rt_preflight() {
  [ "$browser" = none ] || die "dsh runtime: no browser support (use --runtime opencode for $role)"
  [ -n "${NINEROUTER_API_KEY:-}" ] || die "NINEROUTER_API_KEY not set in this shell"
  [ -f "$DSH" ] || die "dsh not installed: npm i --ignore-scripts --prefix $ROOT/.runtime/dsh @deepseek-ai/dsh@0.2.1-rc.5 (with node >= 24)"
  [ "$("$(dsh_node)" -p 'process.versions.node.split(".")[0] >= 24' 2>/dev/null)" = true ] || die "dsh needs node >= 24: set TEAM_DSH_NODE (now $(dsh_node))"
  curl -sf -m 20 -o /dev/null -H "Authorization: Bearer $NINEROUTER_API_KEY" "$NR/models" || die "9router unreachable or key rejected: $NR"
}
rt_env() {
  echo "NINEROUTER_API_KEY=$NINEROUTER_API_KEY"; echo "NINEROUTER_URL=$NR"; echo "DSH_MODEL=$model"
  echo "DSH_TELEMETRY_DISABLED=1"            # base profile otherwise exports feedback telemetry to deepseeksvc.com
  echo "DSH_PERMISSION_MODE=danger-full-access"   # the box is the sandbox; dsh's own one asks for approvals nobody answers headless
}
# role prompt + task pointer on stdin (headless has no system-prompt flag); reasoning streams to stderr, answer to stdout
rt_cmd() { echo "{ cat '$d/.team/role-$role.md'; printf '\n%s\n' '$msg'; } | '$(dsh_node)' '$DSH' --profile headless --patch '$ROOT/runtime-home/dsh/9router.patch.yml' -"; }
