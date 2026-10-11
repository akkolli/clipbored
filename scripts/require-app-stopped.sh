#!/usr/bin/env bash
set -euo pipefail
if pgrep -x Goldfish >/dev/null; then
  echo "FAIL: quit Goldfish before tests or installation" >&2
  exit 1
else
  result=$?
  if [[ "$result" != 1 ]]; then
    echo "FAIL: cannot inspect running apps (process query returned $result); refusing to continue" >&2
    exit 1
  fi
fi
