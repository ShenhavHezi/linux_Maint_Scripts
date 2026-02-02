#!/bin/bash
# process_hog_monitor.sh - Alert on sustained high CPU / memory processes (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[process_hog] "
LM_LOGFILE="/var/log/process_hog_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; set >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle

lm_require_singleton "process_hog_monitor"

# ========================
# Script configuration
# ========================
ALERT_EMAILS="${LM_EMAILS:-/etc/linux_maint/emails.txt}"           # (handled by lib)
IGNORE_FILE="/etc/linux_maint/process_hog_ignore.txt"               # optional

STATE_DIR="${LM_STATE_DIR:-/var/tmp}"                               # per-host state

# Thresholds (percentages; mem = %MEM)
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

# ========================
# Helpers (script-local)
# ========================
ALERTS_FILE="$(mktemp -p "${STATE_DIR}" process_hog.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

is_ignored_cmd(){
  local cmd="$1"
  [ -s "$IGNORE_FILE" ] || return 1
  grep -iFq -- "$cmd" "$IGNORE_FILE"
}

# ========================
# Remote collector
# ========================
# Emits lines: "pid|startjiffies|comm|pcpu|pmem"
remote_collect_cmd='
LC_ALL=C
fmt(){ printf "%s|%s|%s|%s|%s\n" "$1" "$2" "$3" "$4" "$5"; }
ps -eo pid=,comm=,pcpu=,pmem= --sort=-pcpu 2>/dev/null | \
while read -r pid comm pcpu pmem; do
  [ -r "/proc/$pid/stat" ] || continue
  start=$(awk '"'"'{print $22}'"'"' "/proc/$pid/stat" 2>/dev/null)
  fmt "$pid" "$start" "$comm" "$pcpu" "$pmem"
done
'

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Checking process hogs on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    return
  fi

  local now; now=$(date +%s)
  local state="$STATE_DIR/process_hog_monitor.${host}.state"
  local prev="$STATE_DIR/process_hog_monitor.${host}.prev"
  [ -f "$state" ] || : > "$state"
  cp -f "$state" "$prev" 2>/dev/null || :

  # Collect current snapshot
  local lines; lines="$(lm_ssh "$host" bash -lc "'$remote_collect_cmd'")"
  [ -z "$lines" ] && { lm_warn "[$host] no processes collected"; rm -f "$prev"; return; }

  # Optionally limit to top N by CPU
  if [ "$MAX_PROCESSES" -gt 0 ]; then
    lines="$(printf "%s\n" "$lines" | head -n "$MAX_PROCESSES")"
  fi

  # Fresh state
  : > "$state"

  # Iterate processes
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

    lm_info "[$host] [$status] pid=$pid start=$startj cmd=$comm cpu=${cpu_int}% mem=${mem_int}% warn_t=${warn_elapsed}s crit_t=${crit_elapsed}s"

    if [ "$status" != "OK" ]; then
      append_alert "$host|$pid|$comm|cpu=${cpu_int}%|mem=${mem_int}%|${note}"
    fi

    # write updated state
    printf "%s|%s|%s|%s|%s|%s|%s|%s\n" \
      "$pid" "$startj" "$comm" \
      "${first_warn:-}" "${first_crit:-}" "$now" "$cpu_int" "$mem_int" >> "$state"
  done <<< "$lines"

  # Cleanup previous snapshot
  rm -f "$prev" 2>/dev/null || :

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
lm_info "=== Process Hog Monitor Started (CPU warn/crit=${CPU_WARN}/${CPU_CRIT}%, MEM warn/crit=${MEM_WARN}/${MEM_CRIT}%, durations warn/crit=${DURATION_WARN_SEC}/${DURATION_CRIT_SEC}s) ==="

lm_for_each_host run_for_host

alerts_all="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts_all" ]; then
  subject="Sustained CPU/MEM hogs detected"
  body="Host | PID | CMD | CPU | MEM | Note
-----|-----|-----|-----|-----|-----
$alerts_all

Thresholds: CPU ${CPU_WARN}/${CPU_CRIT}% (warn/crit), MEM ${MEM_WARN}/${MEM_CRIT}% (warn/crit),
Durations: ${DURATION_WARN_SEC}/${DURATION_CRIT_SEC}s (warn/crit).
This is an automated message from process_hog_monitor.sh."
  lm_mail "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Process Hog Monitor Finished ==="
