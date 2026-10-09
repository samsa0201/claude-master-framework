# opencode runtime (default). Base config: runtime-home/opencode.json (9router provider, permissions).
# Per-pane config via OPENCODE_CONFIG_CONTENT: role prompt as instructions (+ Playwright MCP for browser roles, Task 5).
OC=${TEAM_OPENCODE:-$ROOT/.runtime/opencode/node_modules/.bin/opencode}
NR=${NINEROUTER_URL:-http://localhost:20128/v1}
rt_preflight() {   # key check first: it is the most common failure and needs no install
  [ -n "${NINEROUTER_API_KEY:-}" ] || die "NINEROUTER_API_KEY not set in this shell"
  [ -x "$OC" ] || die "opencode not installed: run ./install.sh"
  curl -sf -m 5 -o /dev/null -H "Authorization: Bearer $NINEROUTER_API_KEY" "$NR/models" || die "9router unreachable or key rejected: $NR"
}
pw_chrome() { ls -d ~/.cache/ms-playwright/chromium-*/chrome-linux64/chrome 2>/dev/null | sort -V | tail -1; }
rt_env() {
  echo "OPENCODE_CONFIG=$ROOT/runtime-home/opencode.json"
  echo "NINEROUTER_API_KEY=$NINEROUTER_API_KEY"
  echo "NINEROUTER_URL=$NR"
  echo "XDG_CONFIG_HOME=$ROOT/runtime-home/xdg"
  echo "XDG_DATA_HOME=$ROOT/.runtime/data"
  local mcp='' chrome st=''
  if [ "$browser" != none ]; then
    chrome=$(pw_chrome); [ -n "$chrome" ] || die "no Playwright chromium in ~/.cache/ms-playwright (ask the user before downloading)"
    [ -f "$d/.team/auth.json" ] && st=",\"--storage-state\",\"$d/.team/auth.json\""   # login state placed by lead (SKILL.md SSH flow)
    mcp=",\"mcp\":{\"playwright\":{\"type\":\"local\",\"enabled\":true,\"environment\":{\"DISPLAY\":\"$TEAM_DISPLAY\"},\"command\":[\"npx\",\"-y\",\"@playwright/mcp@0.0.83\",\"--executable-path\",\"$chrome\",\"--viewport-size\",\"1440,900\",\"--output-dir\",\"$d/.team/out/browser\",\"--save-session\",\"--no-sandbox\"$st]}}"
  fi
  echo "OPENCODE_CONFIG_CONTENT={\"instructions\":[\"$d/.team/role-$role.md\"]$mcp}"
}
rt_cmd() { echo "$OC -m 9r/$model --prompt '$msg'"; }
