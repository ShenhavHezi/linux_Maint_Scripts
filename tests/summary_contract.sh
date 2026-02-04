#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run a monitor in a minimal local environment and check it emits at least one summary line.
# Some monitors are intentionally SKIP depending on config; those should still not break.

monitors=(
  preflight_check.sh
  config_validate.sh
  health_monitor.sh
  inode_monitor.sh
  disk_trend_monitor.sh
  network_monitor.sh
  service_monitor.sh
  ntp_drift_monitor.sh
  patch_monitor.sh
  storage_health_monitor.sh
  kernel_events_monitor.sh
  cert_monitor.sh
  nfs_mount_monitor.sh
  ports_baseline_monitor.sh
  config_drift_monitor.sh
  user_monitor.sh
  backup_check.sh
  inventory_export.sh
)

export LINUX_MAINT_LIB="$ROOT_DIR/lib/linux_maint.sh"
export LM_LOCKDIR="/tmp"
export LM_LOGFILE="/tmp/linux_maint_contract_test.log"
export LM_EMAIL_ENABLED="false"

fail=0
for m in "${monitors[@]}"; do
  path="$ROOT_DIR/monitors/$m"
  if [[ ! -f "$path" ]]; then
    echo "MISSING monitor file: $m" >&2
    fail=1
    continue
  fi

  out="$(mktemp)"
  # run best-effort; monitor may exit nonzero due to real system state
  set +e
  bash "$path" >"$out" 2>&1
  rc=$?
  set -e

  # Contract: if it ran, it should emit at least one monitor= line OR explicitly SKIP inside output.
  if ! grep -q '^monitor=' "$out"; then
    if grep -q '^SKIP:' "$out"; then
      echo "OK (skipped): $m"
    else
      echo "FAIL: $m produced no '^monitor=' summary line" >&2
      echo "--- output ---" >&2
      tail -n 60 "$out" >&2 || true
      echo "-------------" >&2
      fail=1
    fi
  else
    # Warn if too many summary lines (helps keep standardization tight)
    c="$(grep -c '^monitor=' "$out" || true)"
    if [[ "$c" -gt 5 ]]; then
      echo "WARN: $m produced $c monitor= lines (expected usually 1 or per-host)." >&2
    else
      echo "OK: $m ($c summary lines, rc=$rc)"
    fi
  fi

  rm -f "$out"
done

exit "$fail"
