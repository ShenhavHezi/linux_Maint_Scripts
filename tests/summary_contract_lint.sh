#!/usr/bin/env bash
set -euo pipefail

# Run wrapper once (best-effort) to produce a repo log, then lint latest.
# This test is intentionally tolerant: wrapper may return non-zero.

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/.logs}"
LOG="$LOG_DIR/full_health_monitor_latest.log"

mkdir -p "$LOG_DIR" || true

# best effort
(LOG_DIR="$LOG_DIR" "$REPO_ROOT/run_full_health_monitor.sh" >/dev/null 2>&1 || true)

if [[ ! -f "$LOG" ]]; then
  echo "ERROR: wrapper log not found: $LOG" >&2
  exit 2
fi

exec python3 "$REPO_ROOT/tests/summary_contract_lint.py" "$LOG"
