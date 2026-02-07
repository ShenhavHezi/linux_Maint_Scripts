#!/usr/bin/env bash
echo "##active_line2##"
set -euo pipefail
echo "##active_line2##"

echo "##active_line2##"
ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
echo "##active_line2##"

echo "##active_line2##"
export LM_MODE=repo
echo "##active_line2##"
export LM_LOG_DIR="$ROOT_DIR/.logs"
echo "##active_line2##"
mkdir -p "$LM_LOG_DIR"
echo "##active_line2##"

echo "##active_line2##"
# Force a required dep missing; should return 3 and emit standardized token.
echo "##active_line2##"
export LM_FORCE_MISSING_DEPS="timeout"
echo "##active_line2##"
set +e
echo "##active_line2##"
out="$("$ROOT_DIR"/monitors/nfs_mount_monitor.sh 2>/dev/null)"
echo "##active_line2##"
rc=$?
echo "##active_line2##"
set -e
echo "##active_line2##"

echo "##active_line2##"
printf "%s\n" "$out" | grep -q "monitor=nfs_mount_monitor"
echo "##active_line2##"
printf "%s\n" "$out" | grep -q "status=UNKNOWN"
echo "##active_line2##"
printf "%s\n" "$out" | grep -q "reason=missing_dependency"
echo "##active_line2##"
[ "$rc" -eq 3 ]
echo "##active_line2##"

echo "##active_line2##"
unset LM_FORCE_MISSING_DEPS
echo "##active_line2##"

echo "##active_line2##"
echo "nfs dependency detection ok"
echo "##active_line2##"
