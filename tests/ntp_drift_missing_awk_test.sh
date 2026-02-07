#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

export LM_MODE=repo
export LM_LOG_DIR="$ROOT_DIR/.logs"
mkdir -p "$LM_LOG_DIR"

export LM_FORCE_MISSING_DEPS="awk"

set +e
out="$("$ROOT_DIR"/monitors/ntp_drift_monitor.sh 2>/dev/null)"
rc=$?
set -e

printf "%s\n" "$out" | grep -q "monitor=ntp_drift_monitor"
printf "%s\n" "$out" | grep -q "status=UNKNOWN"
printf "%s\n" "$out" | grep -q "reason=missing_dependency"
[ "$rc" -eq 3 ]

unset LM_FORCE_MISSING_DEPS
echo "ntp drift missing awk ok"
