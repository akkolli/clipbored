#!/usr/bin/env bash
set -euo pipefail

APP_NAME="ClipBored"
DURATION_SECONDS="${1:-900}"

PID="$(pgrep -x "$APP_NAME" | head -n 1 || true)"
if [ -z "$PID" ]; then
  echo "ClipBored is not running. Launch build/ClipBored.app first."
  exit 1
fi

echo "Idle soak for $APP_NAME (pid $PID)"
echo "Duration: ${DURATION_SECONDS}s"
echo "Start:"
ps -o pid,pcpu,pmem,time,command -p "$PID"

sleep "$DURATION_SECONDS"

echo "End:"
ps -o pid,pcpu,pmem,time,command -p "$PID"
echo "Use Instruments or Activity Monitor Energy tab for wakeup/energy validation."
