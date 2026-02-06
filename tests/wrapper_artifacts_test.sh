#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Run wrapper in repo mode (writes to ./.logs)
# This test is best-effort; it should not hang.
mkdir -p "$ROOT_DIR/.logs"

# Run with a timeout if available
if command -v timeout >/dev/null 2>&1; then
  timeout 120s sudo -n bash "$ROOT_DIR/run_full_health_monitor.sh" >/dev/null 2>&1 || true
else
  sudo -n bash "$ROOT_DIR/run_full_health_monitor.sh" >/dev/null 2>&1 || true
fi

# Required artifacts (repo mode)
req=(
  "$ROOT_DIR/.logs/full_health_monitor_latest.log"
  "$ROOT_DIR/.logs/full_health_monitor_summary_latest.log"
  "$ROOT_DIR/.logs/full_health_monitor_summary_latest.json"
  "$ROOT_DIR/.logs/last_status_full"
)

missing=0
for f in "${req[@]}"; do
  if [ ! -e "$f" ]; then
    echo "MISSING artifact: $f" >&2
    missing=1
  fi
  # basic non-empty for log/summary/status
  case "$f" in
    *.log|*/last_status_full)
      if [ -e "$f" ] && [ ! -s "$f" ]; then
        echo "EMPTY artifact: $f" >&2
        missing=1
      fi
      ;;
  esac
  # symlink check for latest logs (nice-to-have)
  if [[ "$f" == *latest.log || "$f" == *latest.json ]]; then
    if [ -e "$f" ] && [ ! -L "$f" ]; then
      echo "WARN: expected symlink for $f" >&2
    fi
  fi
done

[ "$missing" -eq 0 ] || exit 1

echo "wrapper artifacts ok"
