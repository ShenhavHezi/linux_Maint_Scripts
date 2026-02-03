#!/usr/bin/env bash
# kernel_events_monitor.sh - Scan kernel logs for critical events (OOM, I/O errors, FS errors, hung tasks) (distributed)
# Author: Shenhav_Hezi
# Version: 1.0

set -euo pipefail

. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[kernel_events] "
LM_LOGFILE="/var/log/kernel_events_monitor.log"
: "${LM_MAX_PARALLEL:=0}"
: "${LM_EMAIL_ENABLED:=true}"

lm_require_singleton "kernel_events_monitor"

MAIL_SUBJECT_PREFIX='[Kernel Events Monitor]'
EMAIL_ON_ALERT="true"

: "${KERNEL_WINDOW_HOURS:=24}"
WARN_COUNT=1
CRIT_COUNT=5
PATTERNS='oom-killer|out of memory|killed process|soft lockup|hard lockup|hung task|blocked for more than|I/O error|blk_update_request|Buffer I/O error|EXT4-fs error|XFS \(|btrfs: error|nvme.*timeout|resetting link|ata[0-9].*failed|mce:|machine check'

ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" kernel_events_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }
mail_if_enabled(){ [ "$EMAIL_ON_ALERT" = "true" ] || return 0; lm_mail "$1" "$2"; }

ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")"; }

remote_scan_cmd() {
  cat <<'EOF'
set -euo pipefail
hrs="$1"
pat="$2"

have(){ command -v "$1" >/dev/null 2>&1; }

if have journalctl; then
  out=$(journalctl -k -S "-${hrs}h" 2>/dev/null || true)
else
  out=""
  for f in /var/log/kern.log /var/log/messages /var/log/syslog; do
    [ -r "$f" ] || continue
    out="$out\n$(tail -n 5000 "$f" 2>/dev/null || true)"
  done
fi

count=$(printf "%b" "$out" | grep -Eai "$pat" | wc -l | awk '{print $1}')
sample=$(printf "%b" "$out" | grep -Eai "$pat" | head -n 3 | tr '\n' ';' | sed 's/[[:space:]]\+/ /g')

printf "count=%s sample=%s\n" "$count" "${sample:-}"
EOF
}

run_for_host(){
  local host="$1"
  ensure_dirs

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    echo "kernel_events_monitor host=$host status=CRIT matches=?"
    return 2
  fi

  local cmd out
  cmd="$(remote_scan_cmd)"
  out="$(lm_ssh "$host" bash -lc "$cmd" _ "$KERNEL_WINDOW_HOURS" "$PATTERNS" 2>/dev/null || true)"
  if [ -z "$out" ]; then
    lm_warn "[$host] unable to read kernel logs (permissions/tools)"
    echo "kernel_events_monitor host=$host status=UNKNOWN matches=?"
    return 3
  fi

  local count sample
  count=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="count") print $(i+1)}')
  sample=$(echo "$out" | sed -n 's/^.*sample=//p')
  [ -z "$count" ] && count=0

  local status rc
  status="OK"; rc=0
  if [ "$count" -ge "$CRIT_COUNT" ]; then status="CRIT"; rc=2
  elif [ "$count" -ge "$WARN_COUNT" ]; then status="WARN"; rc=1
  fi

  if [ "$rc" -ge 1 ]; then
    append_alert "$host|kernel_events|matches=$count|sample=${sample:0:300}"
  fi

  echo "kernel_events_monitor host=$host status=$status matches=$count window_h=$KERNEL_WINDOW_HOURS"
  return "$rc"
}

main(){
  : > "$ALERTS_FILE"

  local worst=0
  lm_for_each_host run_for_host


  if [ -s "$ALERTS_FILE" ]; then
    mail_if_enabled "$MAIL_SUBJECT_PREFIX Kernel events detected" "$(cat "$ALERTS_FILE")"
  fi

  exit "$worst"
}

main "$@"
