#!/bin/bash
# ntp_drift_monitor.sh - Monitor NTP/chrony/timesyncd sync state & clock drift
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Checks one or many Linux servers for time-sync health:
#     - current offset/drift from NTP (ms)
#     - selected time source & stratum
#     - sync status (OK / WARN / CRIT)
#   Supports chrony, ntpd, and systemd-timesyncd.
#   Logs a concise report and can email alerts when drift exceeds thresholds
#   or when a host is not synchronized.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"     # One host per line
EXCLUDED="/etc/linux_maint/excluded.txt"      # Optional: hosts to skip
ALERT_EMAILS="/etc/linux_maint/emails.txt"    # Optional: recipients (one per line)
LOGFILE="/var/log/ntp_drift_monitor.log"      # Log file
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no"

# Thresholds (milliseconds)
OFFSET_WARN_MS=100
OFFSET_CRIT_MS=500

MAIL_SUBJECT_PREFIX='[NTP Drift Monitor]'
EMAIL_ON_ISSUE="true"   # Send email on WARN/CRIT

# ========================
# Helpers
# ========================

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"; }

is_excluded() {
  local host="$1"
  [ -f "$EXCLUDED" ] || return 1
  grep -Fxq "$host" "$EXCLUDED"
}

ssh_do() {
  local host="$1"; shift
  ssh $SSH_OPTS "$host" "$@" 2>/dev/null
}

send_mail() {
  local subject="$1" body="$2"
  [ "$EMAIL_ON_ISSUE" = "true" ] || return 0
  [ -s "$ALERT_EMAILS" ] || return 0
  command -v mail >/dev/null || return 0
  while IFS= read -r to; do
    [ -n "$to" ] && printf "%s\n" "$body" | mail -s "$MAIL_SUBJECT_PREFIX $subject" "$to"
  done < "$ALERT_EMAILS"
}

impl_detect() {
  # Echo one of: chrony | ntpd | timesyncd | unknown
  local host="$1"
  if ssh_do "$host" "command -v chronyc >/dev/null"; then echo chrony; return; fi
  if ssh_do "$host" "command -v ntpq >/dev/null";     then echo ntpd; return; fi
  if ssh_do "$host" "command -v timedatectl >/dev/null && timedatectl show-timesync >/dev/null 2>&1"; then echo timesyncd; return; fi
  echo unknown
}

# ---- Parsers for each implementation. Each should echo:
# impl|offset_ms|stratum|source|synced|note
# where synced is yes/no/unknown
probe_chrony() {
  local host="$1"
  local track; track=$(ssh_do "$host" "chronyc tracking") || track=""
  [ -z "$track" ] && { echo "chrony|?|?|?|no|no_output"; return; }

  # System time: "X seconds fast/slow of NTP time"
  local sysline; sysline=$(printf "%s\n" "$track" | awk -F': ' '/^System time/{print $2}')
  local sec; sec=$(printf "%s\n" "$sysline" | awk '{print $1}')
  local offset_ms; offset_ms=$(awk -v s="$sec" 'BEGIN{if(s=="")print "?"; else printf("%.0f", s*1000>=0?s*1000:-s*1000)}')

  local stratum; stratum=$(printf "%s\n" "$track" | awk -F': ' '/^Stratum/{print $2}')
  [ -z "$stratum" ] && stratum="?"
  # Reference ID / Name appears on "Reference ID"
  local source; source=$(printf "%s\n" "$track" | awk -F': ' '/^Reference ID/{print $2}')
  [ -z "$source" ] && source="?"

  local leap; leap=$(printf "%s\n" "$track" | awk -F': ' '/^Leap status/{print $2}')
  local synced="yes"; [ "$leap" = "Not synchronised" ] && synced="no"

  echo "chrony|$offset_ms|$stratum|$source|$synced|leap:$leap"
}

probe_ntpd() {
  local host="$1"
  local line; line=$(ssh_do "$host" "ntpq -pn | awk '/^\\*/{print \$0}'") || line=""
  if [ -z "$line" ]; then
    # Maybe not synced; still try to get best candidate ('+' or first line)
    line=$(ssh_do "$host" "ntpq -pn | awk '/^\\+/{print \$0; exit} NR==3{print \$0}'")
  fi
  [ -z "$line" ] && { echo "ntpd|?|?|?|no|no_peers"; return; }

  # Columns: remote refid st t when poll reach delay offset jitter
  local source; source=$(echo "$line" | awk '{print $1}')
  local stratum; stratum=$(echo "$line" | awk '{print $3}')
  local offset_ms; offset_ms=$(echo "$line" | awk '{print $9}')
  local synced="no"; echo "$line" | grep -q '^\*' && synced="yes"

  [ -z "$stratum" ] && stratum="?"
  [ -z "$offset_ms" ] && offset_ms="?"

  echo "ntpd|$offset_ms|$stratum|$source|$synced|peerline"
}

probe_timesyncd() {
  local host="$1"
  local out; out=$(ssh_do "$host" "timedatectl show-timesync --all") || out=""
  [ -z "$out" ] && { echo "timesyncd|?|?|?|unknown|no_output"; return; }

  # LastOffsetNSec may be negative; convert to absolute ms
  local ns; ns=$(printf "%s\n" "$out" | awk -F'=' '/^LastOffsetNSec/{print $2}')
  local offset_ms="?"
  if [ -n "$ns" ] && [ "$ns" != "n/a" ]; then
    offset_ms=$(awk -v n="$ns" 'BEGIN{m=n/1000000.0; if(m<0)m=-m; printf("%.0f", m)}')
  fi
  local stratum; stratum=$(printf "%s\n" "$out" | awk -F'=' '/^Stratum/{print $2}')
  [ -z "$stratum" ] && stratum="?"
  local server; server=$(printf "%s\n" "$out" | awk -F'=' '/^ServerName/{print $2}')
  [ -z "$server" ] && server=$(printf "%s\n" "$out" | awk -F'=' '/^ServerAddress/{print $2}')
  [ -z "$server" ] && server="?"

  # Sync flag from timedatectl show
  local synced="unknown"
  if ssh_do "$host" "timedatectl show -p SystemClockSync --value" | grep -q '^yes$'; then
    synced="yes"
  else
    synced="no"
  fi

  echo "timesyncd|$offset_ms|$stratum|$server|$synced|timesync"
}

rate_status() {
  # Decide OK/WARN/CRIT based on offset, sync flag
  local offset_ms="$1" synced="$2"
  if [ "$synced" = "no" ]; then echo "CRIT"; return; fi
  if [ "$offset_ms" = "?" ]; then echo "WARN"; return; fi
  # numeric compare
  if [ "$offset_ms" -ge "$OFFSET_CRIT_MS" ]; then echo "CRIT"; return; fi
  if [ "$offset_ms" -ge "$OFFSET_WARN_MS" ]; then echo "WARN"; return; fi
  echo "OK"
}

check_host() {
  local host="$1"
  log "===== Checking time sync on $host ====="

  if ! ssh_do "$host" "echo ok" | grep -q ok; then
    log "[$host] ERROR: SSH unreachable."
    echo "ALERT:$host:unreachable"
    return
  fi

  local impl; impl=$(impl_detect "$host")
  local line
  case "$impl" in
    chrony)     line=$(probe_chrony "$host") ;;
    ntpd)       line=$(probe_ntpd "$host") ;;
    timesyncd)  line=$(probe_timesyncd "$host") ;;
    *)          log "[$host] WARNING: No known time-sync tool found."; echo "INFO:$host:unknown"; return ;;
  esac

  # impl|offset_ms|stratum|source|synced|note
  IFS='|' read -r impl offset_ms stratum source synced note <<<"$line"

  local status; status=$(rate_status "${offset_ms/\?/-1}" "$synced")
  log "[$status] $host impl=$impl offset_ms=$offset_ms stratum=$stratum source=$source synced=$synced ${note:+note=$note}"

  if [ "$status" != "OK" ]; then
    echo "ALERT:$host:$impl:$offset_ms:$stratum:$source:$synced"
  fi
}

# ========================
# Main
# ========================
log "=== NTP Drift Monitor Started (warn=${OFFSET_WARN_MS}ms, crit=${OFFSET_CRIT_MS}ms) ==="

alerts=""
if [ -f "$SERVERLIST" ]; then
  while IFS= read -r HOST; do
    [ -z "$HOST" ] && continue
    is_excluded "$HOST" && { log "Skipping $HOST (excluded)"; continue; }
    res=$(check_host "$HOST")
    case "$res" in
      ALERT:*) alerts+="${res#ALERT:}"$'\n' ;;
      *) : ;;
    esac
  done < "$SERVERLIST"
else
  res=$(check_host "localhost")
  case "$res" in
    ALERT:*) alerts+="${res#ALERT:}"$'\n' ;;
  esac
fi

if [ -n "$alerts" ]; then
  subject="Hosts with NTP drift or unsynced clocks"
  body="Thresholds: WARN=${OFFSET_WARN_MS}ms, CRIT=${OFFSET_CRIT_MS}ms

Host | Impl | Offset(ms) | Stratum | Source | Synced
----------------------------------------------------
$(echo "$alerts" | awk -F: 'NF>=6{printf "%s | %s | %s | %s | %s | %s\n",$1,$2,$3,$4,$5,$6}') 

This is an automated message from ntp_drift_monitor.sh."
  send_mail "$subject" "$body"
fi

log "=== NTP Drift Monitor Finished ==="
