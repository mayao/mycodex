#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_ENTRY="$APP_DIR/app.py"
OUTPUT_DIR="$APP_DIR/output"
PID_FILE="$OUTPUT_DIR/invest-backend.pid"
STDOUT_LOG="$OUTPUT_DIR/invest-backend.stdout.log"
STDERR_LOG="$OUTPUT_DIR/invest-backend.stderr.log"
PORT="${PORT:-8008}"
PYTHON_BIN="${PYTHON_BIN:-$(python3 -c 'import sys; print(sys.executable)')}"

detect_lan_ip() {
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

stop_existing() {
  if [[ -f "$PID_FILE" ]]; then
    local existing_pid
    existing_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [[ -n "$existing_pid" ]] && kill -0 "$existing_pid" >/dev/null 2>&1; then
      kill "$existing_pid" >/dev/null 2>&1 || true
      sleep 1
      if kill -0 "$existing_pid" >/dev/null 2>&1; then
        kill -9 "$existing_pid" >/dev/null 2>&1 || true
      fi
    fi
    rm -f "$PID_FILE"
  fi

  local listeners
  listeners="$(lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true)"
  if [[ -n "$listeners" ]]; then
    while IFS= read -r pid; do
      [[ -n "$pid" ]] || continue
      kill "$pid" >/dev/null 2>&1 || true
    done <<<"$listeners"
    sleep 1
  fi
}

mkdir -p "$OUTPUT_DIR"
touch "$STDOUT_LOG" "$STDERR_LOG"

if [[ ! -r "$APP_ENTRY" ]]; then
  echo "Backend entry is not readable: $APP_ENTRY" >&2
  exit 1
fi

stop_existing

cd "$APP_DIR"
export PYTHONUNBUFFERED=1
nohup "$PYTHON_BIN" "$APP_ENTRY" --public --port "$PORT" >>"$STDOUT_LOG" 2>>"$STDERR_LOG" </dev/null &
SERVER_PID="$!"
echo "$SERVER_PID" > "$PID_FILE"

sleep 2
if ! kill -0 "$SERVER_PID" >/dev/null 2>&1; then
  echo "Invest backend failed to stay alive. Check $STDERR_LOG" >&2
  exit 1
fi

LAN_IP="$(detect_lan_ip || true)"
echo "Invest backend is running in background."
echo "PID: $SERVER_PID"
echo "Python: $PYTHON_BIN"
echo "Local: http://127.0.0.1:$PORT/"
if [[ -n "$LAN_IP" ]]; then
  echo "LAN: http://$LAN_IP:$PORT/"
fi
echo "Logs:"
echo "  stdout: $STDOUT_LOG"
echo "  stderr: $STDERR_LOG"
