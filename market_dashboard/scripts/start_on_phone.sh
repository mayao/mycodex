#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PORT="${PORT:-8008}"

detect_lan_ip() {
  if [[ -n "${LAN_IP:-}" ]]; then
    printf '%s\n' "$LAN_IP"
    return 0
  fi

  local iface=""
  local candidate=""

  iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  if [[ "$iface" == utun* ]]; then
    iface=""
  fi
  for candidate in "$iface" en0 en1 en2; do
    [[ -n "$candidate" ]] || continue
    if ipconfig getifaddr "$candidate" >/dev/null 2>&1; then
      ipconfig getifaddr "$candidate"
      return 0
    fi
  done

  ifconfig | awk '/inet / && $2 != "127.0.0.1" && $2 !~ /^169\.254\./ {print $2; exit}'
}

LAN_IP="$(detect_lan_ip || true)"

cd "$APP_DIR"

if [[ -n "$LAN_IP" ]]; then
  echo "Phone overview: http://$LAN_IP:$PORT/"
  echo "Phone share view: http://$LAN_IP:$PORT/share"
else
  echo "LAN IP not detected automatically."
  echo "If needed, set LAN_IP manually before running this script."
fi

exec python3 app.py --public --port "$PORT"
