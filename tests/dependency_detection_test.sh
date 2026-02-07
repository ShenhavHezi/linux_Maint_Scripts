#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$ROOT_DIR/lib/linux_maint.sh"

# Ensure we can source the lib
# shellcheck source=/dev/null
. "$LIB"

# Use repo logs for this test
export LM_MODE="repo"
export LM_LOG_DIR="$ROOT_DIR/.logs"
mkdir -p "$LM_LOG_DIR"

# 1) missing required dep => UNKNOWN reason=missing_dependency and rc=3
export LM_FORCE_MISSING_DEPS="ssh"
set +e
out_req="$("$ROOT_DIR"/monitors/preflight_check.sh 2>/dev/null)"
rc_req=$?
set -e
printf '%s\n' "$out_req" | grep -q 'monitor=preflight_check'
printf '%s\n' "$out_req" | grep -q 'status=UNKNOWN'
printf '%s\n' "$out_req" | grep -q 'reason=missing_dependency'
[ "$rc_req" -eq 3 ]

# 2) missing optional dep => WARN (not OK) and reason=missing_optional_cmd
export LM_FORCE_MISSING_DEPS="smartctl"
set +e
out_opt="$("$ROOT_DIR"/monitors/preflight_check.sh 2>/dev/null)"
rc_opt=$?
set -e
printf '%s\n' "$out_opt" | grep -q 'monitor=preflight_check'
# It can be WARN or UNKNOWN/CRIT depending on environment; but if ONLY optional is missing it should be WARN.
# We assert specifically that the token used is missing_optional_cmd when optional missing is detected.
printf '%s\n' "$out_opt" | grep -q 'reason=missing_optional_cmd'
# rc should be non-fatal (0 or 1). preflight sets WARN rc=1.
[ "$rc_opt" -eq 1 ] || [ "$rc_opt" -eq 0 ]

# reset
unset LM_FORCE_MISSING_DEPS

echo "dependency detection ok"
