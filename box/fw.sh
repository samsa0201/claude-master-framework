#!/usr/bin/env bash
# Egress rules for one box. Runs as root with NET_ADMIN in the box's netns (bin/box.sh box_fw), never in the box itself.
# Usage: fw.sh --count | fw.sh <uid> <gateway> <9router port> <host[:port]>...
# Only <uid> (workers and lead-started apps) is filtered; root in the netns (tailscale sidecar, Docker's DNS) is not.
set -euo pipefail
if [ "${1:-}" = --count ]; then iptables -L STUDIO -v -n -x | awk '$3=="REJECT"{print $1}'; exit 0; fi
uid=$1 gw=$2 nr=$3; shift 3
r=$'*filter\n:STUDIO - [0:0]\n'   # declaring the chain flushes it; iptables-restore swaps the whole chain atomically
r+=$'-A STUDIO -o lo -j ACCEPT\n'   # loopback, incl. Docker's DNS at 127.0.0.11 (no direct :53 to outside resolvers)
r+=$'-A STUDIO -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT\n'
r+="-A STUDIO -d $gw -p tcp --dport $nr -j ACCEPT"$'\n'   # 9router on the host
for hp in "$@"; do
  h=${hp%%:*}; p=443; [[ $hp == *:* ]] && p=${hp##*:}
  ips=$(getent ahostsv4 "$h" | awk '{print $1}' | sort -u) || true
  [ -n "$ips" ] || { echo "egress: cannot resolve $h (skipped)" >&2; continue; }
  for ip in $ips; do r+="-A STUDIO -d $ip -p tcp --dport $p -j ACCEPT"$'\n'; done
done
r+=$'-A STUDIO -j REJECT\nCOMMIT\n'
iptables-restore --noflush <<<"$r"
iptables -C OUTPUT -m owner --uid-owner "$uid" -j STUDIO 2>/dev/null || iptables -I OUTPUT 1 -m owner --uid-owner "$uid" -j STUDIO
