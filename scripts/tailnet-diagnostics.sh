#!/bin/bash
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${SIDESCREEN_PORT:-54321}"

usage() {
    echo "Usage: ./scripts/tailnet-diagnostics.sh"
    echo ""
    echo "Prints the Mac Tailnet host/IP, Android peers, and exact long-run QA commands."
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

if ! command -v tailscale >/dev/null 2>&1; then
    echo "❌ tailscale not found"
    echo "   Install and log in to Tailscale before using Tailnet mode."
    exit 1
fi

STATUS_JSON="$(mktemp)"
trap 'rm -f "$STATUS_JSON"' EXIT

if ! tailscale status --json > "$STATUS_JSON" 2>/tmp/sidescreen-tailnet.out; then
    echo "❌ tailscale status failed"
    sed 's/^/   /' /tmp/sidescreen-tailnet.out | tail -40
    exit 1
fi

python3 - "$STATUS_JSON" "$PORT" "$ROOT_DIR" <<'PY'
import json
import sys

status_path, port, root = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(open(status_path, encoding="utf-8"))
self_node = data.get("Self") or {}

def strip_dot(value):
    return (value or "").rstrip(".")

def ipv4(values):
    for value in values or []:
        if ":" not in value:
            return value
    return ""

mac_dns = strip_dot(self_node.get("DNSName"))
mac_ip = ipv4(data.get("TailscaleIPs")) or ipv4(self_node.get("TailscaleIPs"))
suggested_host = mac_dns or mac_ip
peers = list((data.get("Peer") or {}).values())
android_peers = [peer for peer in peers if (peer.get("OS") or "").lower() == "android"]
online_androids = [peer for peer in android_peers if peer.get("Online")]

print("# Remote Mac Tailnet Diagnostics")
print("")
print(f"Mac Tailnet host: {suggested_host or 'unavailable'}")
print(f"Mac Tailnet DNS:  {mac_dns or 'unavailable'}")
print(f"Mac Tailnet IP:   {mac_ip or 'unavailable'}")
print(f"Remote Mac port: {port}")
print("")

if android_peers:
    print("## Android peers")
    print("| State | Name | DNS | IPv4 |")
    print("|---|---|---|---|")
    for peer in sorted(android_peers, key=lambda item: (not item.get("Online"), item.get("HostName") or "")):
        state = "online" if peer.get("Online") else "offline"
        name = peer.get("HostName") or peer.get("DNSName") or "unknown"
        dns = strip_dot(peer.get("DNSName")) or "unavailable"
        ip = ipv4(peer.get("TailscaleIPs")) or "unavailable"
        print(f"| {state} | {name} | {dns} | {ip} |")
else:
    print("## Android peers")
    print("No Android peer found in this Tailnet.")

print("")
print("## Commands")
if suggested_host:
    print(f"Use this host in the Mac Wireless tab when Endpoint = Tailnet:")
    print(f"  {suggested_host}")
    print("")
    print("For a 30-minute Tailnet run with evidence:")
    print(f"  cd {root}")
    print(f"  ./scripts/collect-qa-evidence.sh --smoke --duration 1800 --expect-stream --tailnet-host {suggested_host}")
    print("")
    print("For a quicker device reachability check:")
    print(f"  ./scripts/android-device-smoke.sh --duration 15 --tailnet-host {suggested_host}")
else:
    print("Mac Tailnet host unavailable. Check Tailscale login/status on this Mac.")

print("")
if not online_androids:
    print("⚠️  No Android peer is online. Tailnet stream validation cannot be trusted yet.")
    raise SystemExit(2)

print("✅ At least one Android peer is online.")
PY
