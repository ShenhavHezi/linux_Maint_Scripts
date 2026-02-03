#!/usr/bin/env bash
# preflight_check.sh - Validate environment readiness for Linux_Maint_Scripts (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
#
# Always-on by default. Low-noise.
# - OK if core requirements exist
# - WARN if optional tools/configs are missing
# - CRIT if SSH to configured hosts fails

set -euo pipefail

. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[preflight] "
LM_LOGFILE="/var/log/preflight_check.log"
: "${LM_MAX_PARALLEL:=0}"

lm_require_singleton "preflight_check"

# Required commands
REQ_CMDS=(bash awk sed grep df ssh)
# Optional commands that improve coverage
OPT_CMDS=(openssl ss netstat journalctl smartctl nvme mail timeout)

ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")" /var/lib/linux_maint 2>/dev/null || true; }

has(){ command -v "$1" >/dev/null 2>&1; }

main(){
  ensure_dirs

  local missing_req=0 missing_opt=0
  local miss_req_list="" miss_opt_list=""

  for c in "${REQ_CMDS[@]}"; do
    if ! has "$c"; then
      missing_req=$((missing_req+1))
      miss_req_list+="$c,"
    fi
  done

  for c in "${OPT_CMDS[@]}"; do
    if ! has "$c"; then
      missing_opt=$((missing_opt+1))
      miss_opt_list+="$c,"
    fi
  done

  # Check state/log dirs are writable
  local writable_state=1 writable_logs=1
  touch /var/lib/linux_maint/.wtest 2>/dev/null && rm -f /var/lib/linux_maint/.wtest 2>/dev/null || writable_state=0
  mkdir -p /var/log/health 2>/dev/null || true
  touch /var/log/health/.wtest 2>/dev/null && rm -f /var/log/health/.wtest 2>/dev/null || writable_logs=0

  # Check SSH reachability for hosts
  local unreachable=0 total=0
  while read -r h; do
    [ -z "$h" ] && continue
    total=$((total+1))
    lm_is_excluded "$h" && continue
    if ! lm_reachable "$h"; then
      unreachable=$((unreachable+1))
    fi
  done < <(lm_hosts)

  # Check config gates presence (informational)
  local missing_cfg=0
  for f in /etc/linux_maint/certs.txt /etc/linux_maint/config_paths.txt /etc/linux_maint/ports_baseline.txt /etc/linux_maint/network_targets.txt /etc/linux_maint/backup_targets.csv; do
    [ -s "$f" ] || missing_cfg=$((missing_cfg+1))
  done

  local status rc
  status="OK"; rc=0
  if [ "$missing_req" -gt 0 ] || [ "$writable_state" -eq 0 ] || [ "$writable_logs" -eq 0 ]; then
    status="UNKNOWN"; rc=3
  fi
  if [ "$unreachable" -gt 0 ]; then
    status="CRIT"; rc=2
  elif [ "$missing_opt" -gt 0 ] || [ "$missing_cfg" -gt 0 ]; then
    [ "$rc" -lt 1 ] && { status="WARN"; rc=1; }
  fi

  echo "preflight_check status=$status required_missing=$missing_req optional_missing=$missing_opt ssh_unreachable=$unreachable hosts=$total state_writable=$writable_state logs_writable=$writable_logs cfg_missing=$missing_cfg"
  echo "preflight_check details required_missing=[${miss_req_list%,}] optional_missing=[${miss_opt_list%,}]" >> "$LM_LOGFILE"
  exit "$rc"
}

main "$@"
