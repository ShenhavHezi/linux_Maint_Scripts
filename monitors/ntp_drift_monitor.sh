#!/bin/bash
# shellcheck disable=SC1090
set -euo pipefail

# Defaults for standalone runs (wrapper sets these)
: "${LM_LOCKDIR:=/tmp}"
: "${LM_LOG_DIR:=.logs}"

# Dependency checks (local runner)
lm_require_cmd "ntp_drift_monitor" "localhost" awk || exit $?
lm_require_cmd "ntp_drift_monitor" "localhost" grep || exit $?
lm_require_cmd "ntp_drift_monitor" "localhost" sed || exit $?
lm_require_cmd "ntp_drift_monitor" "localhost" chronyc --optional || true
lm_require_cmd "ntp_drift_monitor" "localhost" ntpq --optional || true
lm_require_cmd "ntp_drift_monitor" "localhost" timedatectl --optional || true

# ntp_drift_monitor.sh - Monitor NTP/chrony/timesyncd sync state & clock drift
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Checks one or many Linux servers for time-sync health:
#     - current offset/drift from NTP (ms)
#     - selected time source & stratum
#     - sync status (OK/WARN/CRIT)
#   Supports chrony, ntpd, and systemd-timesyncd.
#   Logs a concise report and can email aggregated alerts.

# ===== Shared helpers =====
. "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" || { echo "Missing ${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}"; exit 1; }
LM_PREFIX="[ntp_drift] "
LM_LOGFILE="${LM_LOGFILE:-/var/log/ntp_drift_monitor.log}"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle

lm_require_singleton "ntp_drift_monitor"

MAIL_SUBJECT_PREFIX='[NTP Drift Monitor]'

# ========================
# Configuration
# ========================
# Thresholds (milliseconds)
OFFSET_WARN_MS=100
OFFSET_CRIT_MS=500
EMAIL_ON_ISSUE="true"   # Send email on WARN/CRIT

# ========================
# Helpers (script-local)
# ========================
mail_if_enabled(){ [ "$EMAIL_ON_ISSUE" = "true" ] || return 0; lm_mail "$1" "$2"; }

# Echo one of: chrony | ntpd | timesyncd | unknown
impl_detect() {
  local host="$1"
  if lm_ssh "$host" "command -v chronyc >/dev/null"; then echo chrony; return; fi
  if lm_ssh "$host" "command -v ntpq >/dev/null";     then echo ntpd; return; fi
  if lm_ssh "$host" "command -v timedatectl >/dev/null 2>&1 && timedatectl show-timesync >/dev/null 2>&1"; then
    echo timesyncd; return
  fi
  echo unknown
}

# ---- Parsers for each implementation. Echo:
# impl|offset_ms|stratum|source|synced|note
# where synced is yes/no/unknown
probe_chrony() {
  local host="$1"
  local track; track="$(lm_ssh "$host" "chronyc tracking" 2>/dev/null)" || track=""
  [ -z "$track" ] && { echo "chrony|?|?|?|no|no_output"; return; }

  # System time: "X seconds fast/slow of NTP time"
  local sysline; sysline="$(printf "%s\n" "$track" | awk -F': ' '/^System time/{print $2}')"
  local sec; sec="$(printf "%s\n" "$sysline" | awk '{print $1}')"
  local offset_ms; offset_ms="$(awk -v s="$sec" 'BEGIN{ if(s==""){print "?"} else {m=s*1000; if(m<0)m=-m; printf("%.0f", m)} }')"

  local stratum; stratum="$(printf "%s\n" "$track" | awk -F': ' '/^Stratum/{print $2}')"
  [ -z "$stratum" ] && stratum="?"
  local source; source="$(printf "%s\n" "$track" | awk -F': ' '/^Reference ID/{print $2}')"
  [ -z "$source" ] && source="?"

  local leap; leap="$(printf "%s\n" "$track" | awk -F': ' '/^Leap status/{print $2}')"
  local synced="yes"; [ "$leap" = "Not synchronised" ] && synced="no"

  echo "chrony|$offset_ms|$stratum|$source|$synced|leap:$leap"
}

probe_ntpd() {
  local host="$1"
  local line; line="$(lm_ssh "$host" "ntpq -pn | awk '/^\\*/{print \$0}'" 2>/dev/null)" || line=""
  if [ -z "$line" ]; then
    line="$(lm_ssh "$host" "ntpq -pn | awk '/^\\+/{print \$0; exit} NR==3{print \$0}'" 2>/dev/null)"
  fi
  [ -z "$line" ] && { echo "ntpd|?|?|?|no|no_peers"; return; }

  # Columns: remote refid st t when poll reach delay offset jitter
  local source stratum offset_ms synced="no"
  source="$(echo "$line" | awk '{print $1}')"
  stratum="$(echo "$line" | awk '{print $3}')"
  offset_ms="$(echo "$line" | awk '{print $9}')"
  echo "$line" | grep -q '^\*' && synced="yes"

  [ -z "$stratum" ] && stratum="?"
  [ -z "$offset_ms" ] && offset_ms="?"

  echo "ntpd|$offset_ms|$stratum|$source|$synced|peerline"
}

probe_timesyncd() {
  local host="$1"
  local out; out="$(lm_ssh "$host" "timedatectl show-timesync --all" 2>/dev/null)" || out=""
  [ -z "$out" ] && { echo "timesyncd|?|?|?|unknown|no_output"; return; }

  # LastOffsetNSec may be negative; convert to absolute ms
  local ns; ns="$(printf "%s\n" "$out" | awk -F'=' '/^LastOffsetNSec/{print $2}')"
  local offset_ms="?"
  if [ -n "$ns" ] && [ "$ns" != "n/a" ]; then
    offset_ms="$(awk -v n="$ns" 'BEGIN{m=n/1000000.0; if(m<0)m=-m; printf("%.0f", m)}')"
  fi
  local stratum; stratum="$(printf "%s\n" "$out" | awk -F'=' '/^Stratum/{print $2}')"
  [ -z "$stratum" ] && stratum="?"
  local server; server="$(printf "%s\n" "$out" | awk -F'=' '/^ServerName/{print $2}')"
  [ -z "$server" ] && server="$(printf "%s\n" "$out" | awk -F'=' '/^ServerAddress/{print $2}')"
  [ -z "$server" ] && server="?"

  local synced="unknown"
  if lm_ssh "$host" "timedatectl show -p SystemClockSync --value" | grep -q '^yes$'; then
    synced="yes"
  else
    synced="no"
  fi

  echo "timesyncd|$offset_ms|$stratum|$server|$synced|timesync"
}

rate_status() {
  # Decide OK/WARN/CRIT based on offset and sync flag
  local offset_ms="$1" synced="$2"
  if [ "$synced" = "no" ]; then echo "CRIT"; return; fi
  if [ "$offset_ms" = "?" ]; then echo "WARN"; return; fi
  if [ "$offset_ms" -ge "$OFFSET_CRIT_MS" ]; then echo "CRIT"; return; fi
  if [ "$offset_ms" -ge "$OFFSET_WARN_MS" ]; then echo "WARN"; return; fi
  echo "OK"
}

# ========================
# Aggregation
# ========================
ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" ntp_drift.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

# ========================
# Per-host runner
# ========================
run_for_host() {
  local host="$1"
  lm_info "===== Checking time sync on $host ====="

  local checked=0
  local warn_count=0
  local crit_count=0

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|unreachable|?|?|?|no"
    lm_summary "ntp_drift_monitor" "$host" "CRIT" reason=ssh_unreachable checked=0 warn=0 crit=1
    lm_info "===== Completed $host ====="
    return 2
  fi

  local impl; impl="$(impl_detect "$host")"
  local line
  case "$impl" in
    chrony)     line="$(probe_chrony "$host")" ;;
    ntpd)       line="$(probe_ntpd "$host")" ;;
    timesyncd)  line="$(probe_timesyncd "$host")" ;;
    *)          lm_warn "[$host] No known time-sync tool found"; lm_summary "ntp_drift_monitor" "$host" "SKIP" reason=no_timesync_tool checked=0 warn=0 crit=0; lm_info "===== Completed $host ====="; return 0 ;;
  esac

  checked=1

  # impl|offset_ms|stratum|source|synced|note
  local offset_ms stratum source synced note
  IFS='|' read -r impl offset_ms stratum source synced note <<<"$line"

  # Use -1 sentinel for numeric comparison when offset is "?"
  local off_num="$offset_ms"; [ "$off_num" = "?" ] && off_num="-1"

  local status; status="$(rate_status "$off_num" "$synced")"
  lm_info "[$status] $host impl=$impl offset_ms=$offset_ms stratum=$stratum source=$source synced=$synced ${note:+note=$note}"

  [ "$status" = "WARN" ] && warn_count=$((warn_count+1))
  [ "$status" = "CRIT" ] && crit_count=$((crit_count+1))

  if [ "$status" != "OK" ]; then
    append_alert "$host|$impl|$offset_ms|$stratum|$source|$synced"
  fi

  lm_info "===== Completed $host ====="

  local overall=OK
  if [ "$crit_count" -gt 0 ]; then
    overall=CRIT
  elif [ "$warn_count" -gt 0 ]; then
    overall=WARN
  else
    overall=OK
  fi
  reason=""
  if [ "$overall" = "CRIT" ]; then reason=ntp_drift_high; fi
  if [ "$overall" = "WARN" ]; then reason=ntp_drift_high; fi
  if [ "$overall" = "UNKNOWN" ]; then reason=ntp_not_synced; fi
  if [ "$overall" != "OK" ] && [ -n "$reason" ]; then
    lm_summary "ntp_drift_monitor" "$host" "$overall" reason=$reason checked=$checked warn=$warn_count crit=$crit_count
  else
    lm_summary "ntp_drift_monitor" "$host" "$overall" checked=$checked warn=$warn_count crit=$crit_count
  fi
  # legacy:
  # echo "ntp_drift_monitor host=$host status=$overall checked=$checked warn=$warn_count crit=$crit_count"

}
# ========================
# Main
# ========================
lm_info "=== NTP Drift Monitor Started (warn=${OFFSET_WARN_MS}ms, crit=${OFFSET_CRIT_MS}ms) ==="

lm_for_each_host_rc run_for_host
worst=$?
exit "$worst"

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="Hosts with NTP drift or unsynced clocks"
  body="Thresholds: WARN=${OFFSET_WARN_MS}ms, CRIT=${OFFSET_CRIT_MS}ms

Host | Impl | Offset(ms) | Stratum | Source | Synced
----------------------------------------------------
$(echo "$alerts" | awk -F'|' 'NF>=6{printf "%s | %s | %s | %s | %s | %s\n",$1,$2,$3,$4,$5,$6}') 

This is an automated message from ntp_drift_monitor.sh."
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== NTP Drift Monitor Finished ==="
