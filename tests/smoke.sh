#!/usr/bin/env bash
set -euo pipefail

# Run a minimal set of commands to ensure the repo can execute without installation.
# This should be safe on GitHub Actions runners.

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export LINUX_MAINT_LIB="$ROOT_DIR/lib/linux_maint.sh"
export LM_LOCKDIR=/tmp
export LM_LOGFILE=/tmp/linux_maint.log
export LM_EMAIL_ENABLED=false

# Basic help/version checks
bash "$ROOT_DIR/bin/linux-maint" help >/dev/null

# Preflight should not hard-fail just because optional tools are missing
LM_LOGFILE=/tmp/preflight_check.log LM_LOCKDIR=/tmp bash "$ROOT_DIR/monitors/preflight_check.sh" >/dev/null || true

# Validate config formats (should succeed even if config files are absent; best-effort)
LM_LOGFILE=/tmp/config_validate.log LM_LOCKDIR=/tmp bash "$ROOT_DIR/monitors/config_validate.sh" >/dev/null || true

# lm_for_each_host_rc aggregation test
bash "$ROOT_DIR/tests/lm_for_each_host_rc_test.sh" >/dev/null

# wrapper artifacts + status output contract + reason lint (requires sudo on environments that support it)
bash "$ROOT_DIR/tests/wrapper_artifacts_test.sh" >/dev/null || true
bash "$ROOT_DIR/tests/status_contract_test.sh" >/dev/null || true
bash "$ROOT_DIR/tests/summary_reason_lint.sh" >/dev/null || true

echo "smoke ok"
