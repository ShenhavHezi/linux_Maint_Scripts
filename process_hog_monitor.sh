#!/bin/bash
# process_hog_monitor.sh - Alert on sustained high CPU / memory processes (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Samples processes on one or many Linux servers and alerts only when a process
#   stays above CPU and/or MEM thresholds for a configured duration (to avoid
#   one-off spikes). Tracks state per-host between runs.
#
#   Uses ps + /proc/PID/stat (start jiffies) to identify processes robustly
#   across PID reuse. Logs concise lines and can email alerts.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"            # One host per line; if missing → local mode
EXCLUDED="/etc/linux_maint/excluded.txt"             # Optional: hosts to skip
ALERT_EMAILS="/etc/linux_maint/emails.txt"           # Optional: recipients (one per line)
IGNORE_FILE="/etc/linux_maint/process_hog_ignore.txt"# Optional: substrings (case-insensitive) to ignore (command names)

LOGFILE="/var/log/process_hog_monitor.log"           # Report log
STATE_DIR="/var/tmp"                                 # Per-host state is kept here
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no"

# Thresholds (percentages; integers are fine; mem = %MEM)
CPU_WARN=70
CPU_CRIT=90
MEM_WARN=30
MEM_CRIT=60

# Durations to be ABOVE threshold before alerting
DURATION_WARN_SEC=120      # 2 minutes
DURATION_CRIT_SEC=300      # 5 minutes

# Sampling behavior
MAX_PROCESSES=0            # 0 = all; otherwise consider only top N by CPU
MAIL_SUBJECT_PREFIX='[Process Hog Monitor]'
EMAIL_ON_ALERT="true"

# ========================
# Helpers
# ========================
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"; }

is_excluded_host(){
  local host="$1"
  [ -f "$EXCLUDED" ] || return 1
  grep -Fxq "$host" "$EXCLUDED"
}

ssh_do(){
  local host="$1"; shift
  if [ "$host" = "localhost" ]; then
    bash -lc "$*" 2>/dev/null
  else
    ssh $SSH_OPTS "$host" "$@" 2>/dev/null
  fi
}

send_mail(){
  local subject="$1" body="$2"
  [ "$EMAIL_ON_ALERT" = "true" ] || return 0
  [ -s "$ALERT_EMAILS" ] || return 0
  command -v mail >/dev/null || return 0
  while IFS= read -r to; do
    [ -n "$to" ] && printf "%s\n" "$body" | mail -s "$MAIL_SUBJECT_PREFIX $subject" "$to"
  done < "$ALERT_EMAILS"
}

is_ignored_cmd(){
  local cmd="$1"
  [ -s "$IGNORE_FILE" ] || return 1
  # case-insensitive substring match
  grep -iFq -- "$cmd" "$IGNORE_FILE"
}

# ========================
# Remote collector
# ========================
# Emits lines: "pid|startjiffies|comm|pcpu|pmem"
remote_collect_cmd='
LC_ALL=C
fmt(){ printf "%s|%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" "$5"; }
# primary list by CPU (desc); include MEM too
ps -eo pid=,comm=,pcpu=,pmem= --sort=-pcpu 2>/dev/null | \
while read -r pid comm pcpu pmem; do
  [ -r "/proc/$pid/stat" ] || continue
  start=$(awk '"'"'{print $22}'"'"' "/proc/$pid/stat" 2>/dev/null)
  fmt "$pid" "$start" "$comm" "$pcpu" "$pmem"
done
'

# ========================
# Core logic
# ========================

check_host(){
  local host="$1"
  log "===== Checking process hogs on $host ====="

  # reachability (skip for localhost)
  if [ "$host" != "localhost" ]; then
    if ! ssh_do "$host" "echo ok" | grep -q ok; then
      log "[$host] ERROR: SSH unreachable."
      echo "ALERT:$host:ssh_unreachable"
      return
    fi
  fi

  local now; now=$(date +%s)
  local state="$STATE_DIR/process_hog_monitor.${host}.state"
  local prev="$STATE_DIR/process_hog_monitor.${host}.prev"
  [ -f "$state" ] || : > "$state"
  cp -f "$state" "$prev" 2>/dev/null || :

  # Collect current snapshot
  local lines; lines="$(ssh_do "$host" bash -lc "'$remote_collect_cmd'")"
  [ -z "$lines" ] && { log "[$host] WARNING: no processes collected"; return; }

  # Optionally limit to top N by CPU
  if [ "$MAX_PROCESSES" -gt 0 ]; then
    lines="$(printf "%s\n" "$lines" | head -n "$MAX_PROCESSES")"
  fi

  # Fresh state
  : > "$state"

  # Iterate processes
  local alerts=""
  while IFS='|' read -r pid startj comm pcpu pmem; do
    # sanitize numbers
    cpu_int=$(awk -v v="$pcpu" 'BEGIN{if(v=="")v=0; printf("%.0f", v+0)}')
    mem_int=$(awk -v v="$pmem" 'BEGIN{if(v=="")v=0; printf("%.0f", v+0)}')

    # ignore list
    is_ignored_cmd "$comm" && continue

    # hog level
    level=0
    if [ "$cpu_int" -ge "$CPU_CRIT" ] || [ "$mem_int" -ge "$MEM_CRIT" ]; then level=2
    elif [ "$cpu_int" -ge "$CPU_WARN" ] || [ "$mem_int" -ge "$MEM_WARN" ]; then level=1
    fi

    # load previous entry
    prev_line=$(awk -F'|' -v p="$pid" -v s="$startj" '$1==p && $2==s {print; exit}' "$prev")
    if [ -n "$prev_line" ]; then
      IFS='|' read -r _pid _start _cmd first_warn first_crit last_seen last_cpu last_mem <<<"$prev_line"
    else
      first_warn=""; first_crit=""; last_seen=""; last_cpu=""; last_mem=""
    fi

    # update timers
    if [ "$level" -ge 1 ]; then
      [ -z "$first_warn" ] && first_warn="$now"
    else
      first_warn=""
    fi
    if [ "$level" -ge 2 ]; then
      [ -z "$first_crit" ] && first_crit="$now"
    else
      first_crit=""
    fi

    warn_elapsed=0; crit_elapsed=0
    [ -n "$first_warn" ] && warn_elapsed=$(( now - first_warn ))
    [ -n "$first_crit" ] && crit_elapsed=$(( now - first_crit ))

    status="OK"; note=""
    if [ "$level" -ge 2 ] && [ "$crit_elapsed" -ge "$DURATION_CRIT_SEC" ]; then
      status="CRIT"; note="sustained ${crit_elapsed}s (cpu=${cpu_int}% mem=${mem_int}%)"
    elif [ "$level" -ge 1 ] && [ "$warn_elapsed" -ge "$DURATION_WARN_SEC" ]; then
      status="WARN"; note="sustained ${warn_elapsed}s (cpu=${cpu_int}% mem=${mem_int}%)"
    fi

    log "[$host] [$status] pid=$pid start=$startj cmd=$comm cpu=${cpu_int}% mem=${mem_int}% warn_t=${warn_elapsed}s crit_t=${crit_elapsed}s"

    if [ "$status" != "OK" ]; then
      alerts+="$host|$pid|$comm|cpu=${cpu_int}%|mem=${mem_int}%|${note}\n"
    fi

    # write updated state
    printf "%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$pid" "$startj" "$comm" \
      "${first_warn:-}" "${first_crit:-}" "$now" "$cpu_int" "$mem_int" >> "$state"
  done <<< "$lines"

  # Cleanup: report processes that ended (optional info only)
  while IFS='|' read -r opid ostart ocmd _ _ olast _ _; do
    [ "$olast" = "$now" ] && continue
    # ended since last run
    :
  done < "$prev"
  rm -f "$prev" 2>/dev/null || :

  # return alerts for aggregation
  if [ -n "$alerts" ]; then
    # Print as "ALERT:" lines so the caller can aggregate
    while IFS= read -r L; do
      [ -n "$L" ] && echo "ALERT:$L"
    done <<< "$(printf "%b" "$alerts")"
  fi

  log "===== Completed $host ====="
}

# ========================
# Main
# ========================
log "=== Process Hog Monitor Started (CPU warn/crit=${CPU_WARN}/${CPU_CRIT}%, MEM warn/crit=${MEM_WARN}/${MEM_CRIT}%, durations warn/crit=${DURATION_WARN_SEC}/${DURATION_CRIT_SEC}s) ==="

alerts_all=""
if [ -f "$SERVERLIST" ]; then
  while IFS= read -r HOST; do
    [ -z "$HOST" ] && continue
    is_excluded_host "$HOST" && { log "Skipping $HOST (excluded)"; continue; }
    out="$(check_host "$HOST")"
    case "$out" in
      *ALERT:*) alerts_all+=$(printf "%s\n" "$out" | sed 's/^.*ALERT://')$'\n' ;;
    esac
  done < "$SERVERLIST"
else
  out="$(check_host "localhost")"
  case "$out" in
    *ALERT:*) alerts_all+=$(printf "%s\n" "$out" | sed 's/^.*ALERT://')$'\n' ;;
  esac
fi

if [ -n "$alerts_all" ]; then
  subject="Sustained CPU/MEM hogs detected"
  body="Host | PID | CMD | CPU | MEM | Note
-----|-----|-----|-----|-----|-----
$(echo -e "$alerts_all") 

Thresholds: CPU ${CPU_WARN}/${CPU_CRIT}% (warn/crit), MEM ${MEM_WARN}/${MEM_CRIT}% (warn/crit),
Durations: ${DURATION_WARN_SEC}/${DURATION_CRIT_SEC}s (warn/crit).
This is an automated message from process_hog_monitor.sh."
  send_mail "$subject" "$body"
fi

log "=== Process Hog Monitor Finished ==="
