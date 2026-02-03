#!/usr/bin/env bash
set -euo pipefail

# Repo-portable runner: place this file on a server and install to /usr/local/sbin/
# It expects the repo scripts under /usr/local/libexec/linux_maint by default.

SCRIPTS_DIR="${SCRIPTS_DIR:-/usr/local/libexec/linux_maint}"
LOG_DIR="${LOG_DIR:-/var/log/health}"
STATUS_FILE="$LOG_DIR/last_status_full"

mkdir -p "$LOG_DIR"
chmod 0755 "$LOG_DIR"

logfile="$LOG_DIR/full_health_monitor_$(date +%F_%H%M%S).log"

tmp_report="/tmp/full_health_monitor_report.$$"
trap 'rm -f "$tmp_report"' EXIT

# Minimal config (local mode)
mkdir -p /etc/linux_maint
[ -f /etc/linux_maint/servers.txt ] || echo "localhost" > /etc/linux_maint/servers.txt
[ -f /etc/linux_maint/excluded.txt ] || : > /etc/linux_maint/excluded.txt

# service_monitor requires services.txt; provide safe defaults if missing
if [ ! -s /etc/linux_maint/services.txt ]; then
  cat > /etc/linux_maint/services.txt <<'SVC'
# critical services
sshd
crond
docker
NetworkManager
SVC
  chmod 0644 /etc/linux_maint/services.txt
fi

# Disable email unless explicitly enabled
export LM_EMAIL_ENABLED="${LM_EMAIL_ENABLED:-false}"

# health_monitor already includes: uptime/load/cpu/mem/disk/top processes.
# Avoid overlaps by excluding disk_monitor/process_hog/server_info.

declare -a scripts=(
  "preflight_check.sh"
  "config_validate.sh"
  "health_monitor.sh"
  "inode_monitor.sh"
  "disk_trend_monitor.sh"
  "network_monitor.sh"
  "service_monitor.sh"
  "ntp_drift_monitor.sh"
  "patch_monitor.sh"
  "storage_health_monitor.sh"
  "kernel_events_monitor.sh"
  "cert_monitor.sh"
  "nfs_mount_monitor.sh"
  "ports_baseline_monitor.sh"
  "config_drift_monitor.sh"
  "user_monitor.sh"
  "backup_check.sh"
  "inventory_export.sh"
)

{
  echo "SUMMARY full_health_monitor host=$(hostname -f 2>/dev/null || hostname) started=$(date -Is)"
  echo "SCRIPTS_DIR=$SCRIPTS_DIR"
  echo "LM_EMAIL_ENABLED=$LM_EMAIL_ENABLED"
  echo "SCRIPT_ORDER=${scripts[*]}"
  echo "============================================================"
} > "$tmp_report"

run_one() {
  local s="$1"
  local path="$SCRIPTS_DIR/$s"
  echo "" >> "$tmp_report"
  echo "==== RUN $s @ $(date '+%F %T') ====" >> "$tmp_report"

  # Skip monitors that require config/baselines unless present
  case "$s" in
    cert_monitor.sh)
      [ -s /etc/linux_maint/certs.txt ] || { echo "SKIP: /etc/linux_maint/certs.txt missing" >> "$tmp_report"; return 0; }
      ;;
    ports_baseline_monitor.sh)
      [ -s /etc/linux_maint/ports_baseline.txt ] || { echo "SKIP: /etc/linux_maint/ports_baseline.txt missing" >> "$tmp_report"; return 0; }
      ;;
    config_drift_monitor.sh)
      [ -s /etc/linux_maint/config_paths.txt ] || { echo "SKIP: /etc/linux_maint/config_paths.txt missing" >> "$tmp_report"; return 0; }
      ;;
    user_monitor.sh)
      [ -s /etc/linux_maint/baseline_users.txt ] || { echo "SKIP: /etc/linux_maint/baseline_users.txt missing" >> "$tmp_report"; return 0; }
      [ -s /etc/linux_maint/baseline_sudoers.txt ] || { echo "SKIP: /etc/linux_maint/baseline_sudoers.txt missing" >> "$tmp_report"; return 0; }
      ;;
  esac

  if [ ! -f "$path" ]; then
    echo "MISSING: $path" >> "$tmp_report"
    return 3
  fi

  if [ "$s" = "config_validate.sh" ]; then
    # Validation warnings should not fail the full run; log output but ignore exit code.
    bash "$path" >> "$tmp_report" 2>&1 || true
    return 0
  fi

  bash "$path" >> "$tmp_report" 2>&1
}

worst=0
ok=0; warn=0; crit=0; unk=0

for s in "${scripts[@]}"; do
  set +e
  run_one "$s"
  rc=$?
  set -e

  case "$rc" in
    0) ok=$((ok+1));;
    1) warn=$((warn+1));;
    2) crit=$((crit+1));;
    *) unk=$((unk+1)); rc=3;;
  esac
  [ "$rc" -gt "$worst" ] && worst="$rc"
done

case "$worst" in
  0) overall="OK";;
  1) overall="WARN";;
  2) overall="CRIT";;
  *) overall="UNKNOWN";;
esac

{
  echo "SUMMARY_RESULT overall=$overall ok=$ok warn=$warn crit=$crit unknown=$unk finished=$(date -Is) exit_code=$worst"
  echo "============================================================"
  cat "$tmp_report"
} | awk '{ print strftime("[%F %T]"), $0 }' | tee "$logfile" >/dev/null

ln -sfn "$logfile" "$LOG_DIR/full_health_monitor_latest.log"

{
  echo "timestamp=$(date -Is)"
  echo "host=$(hostname -f 2>/dev/null || hostname)"
  echo "overall=$overall"
  echo "exit_code=$worst"
  echo "logfile=$logfile"
} > "$STATUS_FILE"
chmod 0644 "$STATUS_FILE"

exit "$worst"
