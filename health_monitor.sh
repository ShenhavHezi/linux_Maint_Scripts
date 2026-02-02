#!/bin/bash
# distributed_health_monitor.sh - Run health checks on multiple Linux servers
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Collects CPU, memory, load average, and disk usage from all servers.
#   Skips excluded hosts, logs to a file, and emails the per-run report.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[health_monitor] "
LM_LOGFILE="/var/log/health_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0 = sequential; >0 runs hosts concurrently
: "${LM_EMAIL_ENABLED:=true}" # master toggle for lm_mail

lm_require_singleton "distributed_health_monitor"

MAIL_SUBJECT_PREFIX='[Health Monitor]'

# ========================
# Report buffer (per run)
# ========================
REPORT_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" health_report.XXXXXX)"
REPORT_LOCK="${REPORT_FILE}.lock"

append_report() {
  # Append stdin to report with a lock (safe under parallelism)
  (
    flock -x 9
    cat >> "$REPORT_FILE"
  ) 9>"$REPORT_LOCK"
}

write_report_header() {
  {
    echo "=============================================="
    echo " Linux Distributed Health Check "
    echo " Date: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "=============================================="
  } | append_report
}

# ========================
# Remote snippet
# ========================
read -r -d '' remote_health_cmd <<'EOS'
echo "--- Hostname: $(hostname)"
echo "--- Uptime:"
uptime || true
echo "--- CPU Load:"
( command -v top >/dev/null 2>&1 && top -bn1 2>/dev/null | grep -E "load average|load:" ) || uptime || true
echo "--- Memory Usage (MB):"
free -m 2>/dev/null || true
echo "--- Disk Usage:"
( df -hT 2>/dev/null | awk 'NR==1 || /^\/dev/' ) || true
echo "--- Top 5 Processes by CPU:"
ps -eo pid,comm,%cpu,%mem --sort=-%cpu 2>/dev/null | head -n 6 || true
echo "--- Top 5 Processes by Memory:"
ps -eo pid,comm,%cpu,%mem --sort=-%mem 2>/dev/null | head -n 6 || true
echo "----------------------------------------------"
EOS

# ========================
# Per-host runner
# ========================
run_for_host() {
  local host="$1"
  lm_info "===== Health check on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable; skipping"
    {
      echo ">>> Health check on $host ($(date '+%Y-%m-%d %H:%M:%S'))"
      echo "--- ERROR: SSH unreachable"
      echo "----------------------------------------------"
    } | append_report
    return
  fi

  # Capture remote output then append to report atomically
  {
    echo ">>> Health check on $host ($(date '+%Y-%m-%d %H:%M:%S'))"
    lm_ssh "$host" bash -lc "$remote_health_cmd"
  } | append_report

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
write_report_header
lm_info "=== Health Monitor Started ==="

# Run checks for each host from LM_SERVERLIST (or localhost if missing)
lm_for_each_host run_for_host

# Persist this run into the log file for history
append_report < /dev/null  # ensure file exists
cat "$REPORT_FILE" >> "$LM_LOGFILE" 2>/dev/null || true

# Email just this run's report (if recipients configured)
if [ -s "${LM_EMAILS:-/etc/linux_maint/emails.txt}" ]; then
  lm_mail "$MAIL_SUBJECT_PREFIX Linux Health Check Report - $(date '+%Y-%m-%d %H:%M:%S')" "$(cat "$REPORT_FILE")"
fi

rm -f "$REPORT_FILE" "$REPORT_LOCK" 2>/dev/null || true
lm_info "=== Health Monitor Finished ==="
