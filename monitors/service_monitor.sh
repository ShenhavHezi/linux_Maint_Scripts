#!/bin/bash
# service_monitor.sh - Monitor critical services across multiple servers
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Checks status of system services (sshd, cron, nginx, etc.) across servers.
#   Logs results and alerts if any service is inactive/failed. Optional auto-restart.

# ===== Shared helpers =====
. "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" || { echo "Missing ${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}"; exit 1; }
LM_PREFIX="[service_monitor] "
LM_LOGFILE="/var/log/service_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0 = sequential hosts; set >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master toggle for lm_mail

lm_require_singleton "service_monitor"

# ========================
# Script configuration
# ========================
SERVICES="/etc/linux_maint/services.txt"     # One service per line (unit name). Comments (#…) and blanks allowed.
AUTO_RESTART="false"                          # "true" to attempt restart on failure (requires root or sudo NOPASSWD)
MAIL_SUBJECT_PREFIX='[Service Monitor]'
EMAIL_ON_ALERT="false"                        # "true" to email when any service is not active

# ========================
# Helpers (script-local)
# ========================
ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" service_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

list_services(){
  [ -s "$SERVICES" ] || { lm_err "Services file not found or empty: $SERVICES"; echo ""; return 1; }
  grep -v '^[[:space:]]*#' "$SERVICES" | sed '/^[[:space:]]*$/d'
}

mail_if_enabled(){
  [ "$EMAIL_ON_ALERT" = "true" ] || return 0
  lm_mail "$1" "$2"
}

# Returns "status|enabled", where status is one of: active,running,inactive,failed,unknown
query_service_status(){
  local host="$1" svc="$2"
  lm_ssh "$host" bash -lc "
set -o pipefail
if command -v systemctl >/dev/null 2>&1; then
  st=\$(systemctl is-active '$svc' 2>/dev/null || true)
  en=\$(systemctl is-enabled '$svc' 2>/dev/null || echo '?')
  echo \"\${st:-unknown}|\${en}\"
elif command -v service >/dev/null 2>&1; then
  out=\$(service '$svc' status 2>/dev/null || true)
  if echo \"\$out\" | grep -qi 'running'; then echo 'running|?'; 
  elif echo \"\$out\" | grep -qi 'stopped\\|dead\\|not running'; then echo 'inactive|?';
  else echo 'unknown|?'; fi
else
  echo 'unknown|?'
fi"
}

restart_service(){
  local host="$1" svc="$2"
  lm_ssh "$host" bash -lc "
if command -v systemctl >/dev/null 2>&1; then
  systemctl restart '$svc' 2>/dev/null || sudo -n systemctl restart '$svc' 2>/dev/null || \
  service '$svc' restart 2>/dev/null || sudo -n service '$svc' restart 2>/dev/null
else
  service '$svc' restart 2>/dev/null || sudo -n service '$svc' restart 2>/dev/null
fi"
}

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Starting service checks on $host ====="

  local checked=0
  local fail_count=0

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    lm_info "===== Completed $host ====="
    return
  fi

  local svc
  while IFS= read -r svc; do
    [ -z "$svc" ] && continue

    checked=$((checked+1))

    local st en
    IFS='|' read -r st en <<<"$(query_service_status "$host" "$svc")"

    case "$st" in
      active|running)
        lm_info "[$host] [OK] $svc active (enabled=$en)"
        ;;
      *)
        lm_err  "[$host] [FAIL] $svc status=$st (enabled=$en)"
        append_alert "$host|$svc|$st"
        fail_count=$((fail_count+1))
        if [ "$AUTO_RESTART" = "true" ]; then
          lm_info "[$host] attempting restart: $svc"
          restart_service "$host" "$svc"
          # Re-check
          IFS='|' read -r st en <<<"$(query_service_status "$host" "$svc")"
          if [[ "$st" = "active" || "$st" = "running" ]]; then
            lm_info "[$host] [RECOVERED] $svc is now $st"
          else
            lm_err  "[$host] [STILL DOWN] $svc status=$st after restart attempt"
          fi
        fi
        ;;
    esac
  done < <(list_services)

  lm_info "===== Completed $host ====="

  status=$( [ "$fail_count" -gt 0 ] && echo CRIT || echo OK )
  lm_summary "service_monitor" "$host" "$status" checked=$checked failures=$fail_count
  # legacy:
  # echo "service_monitor host=$host status=$status checked=$checked failures=$fail_count"

}
# ========================
# Main
# ========================
if ! [ -s "$SERVICES" ]; then
  lm_err "Services file missing or empty: $SERVICES"
  exit 1
fi

lm_info "=== Service Monitor Script Started ==="
lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="Service failures detected"
  body="One or more services are not active:

Host | Service | Status
-----------------------
$(echo "$alerts" | awk -F'|' 'NF>=3{printf "%s | %s | %s\n",$1,$2,$3}') 

AUTO_RESTART=${AUTO_RESTART}"
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Service Monitor Script Finished ==="
