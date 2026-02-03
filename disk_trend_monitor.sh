#!/usr/bin/env bash
# disk_trend_monitor.sh - Disk usage trend + days-to-full forecast (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
#
# Behavior:
# - Always-on by default.
# - First run(s) only record state and return OK with note=insufficient_history.
# - Forecast is per mountpoint, excluding pseudo/ephemeral filesystems.
#
# State:
# - /var/lib/linux_maint/disk_trend/<host>.csv
#   columns: epoch,mount,used_pct,used_kb

set -euo pipefail

. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[disk_trend] "
LM_LOGFILE="/var/log/disk_trend_monitor.log"
: "${LM_MAX_PARALLEL:=0}"
: "${LM_EMAIL_ENABLED:=true}"

lm_require_singleton "disk_trend_monitor"

MAIL_SUBJECT_PREFIX='[Disk Trend Monitor]'
EMAIL_ON_ALERT="true"

STATE_BASE="/var/lib/linux_maint/disk_trend"

# Trend thresholds (days until projected 100%)
WARN_DAYS=14
CRIT_DAYS=7

# Hard thresholds (absolute used%)
HARD_WARN_PCT=90
HARD_CRIT_PCT=95

# Minimum history points per mount to compute slope
MIN_POINTS=2

# Exclude filesystem types (regex)
EXCLUDE_FSTYPES_RE='^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?|debugfs|rpc_pipefs|autofs|devpts|mqueue|hugetlbfs|fuse\..*|binfmt_misc|pstore|nsfs)$'

# Optional exclude mountpoints file
EXCLUDE_MOUNTS_FILE="/etc/linux_maint/disk_trend_exclude_mounts.txt"

ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" disk_trend_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }
mail_if_enabled(){ [ "$EMAIL_ON_ALERT" = "true" ] || return 0; lm_mail "$1" "$2"; }

ensure_dirs(){
  mkdir -p "$(dirname "$LM_LOGFILE")" "$STATE_BASE"
  chmod 0755 "${STATE_BASE%/*}" 2>/dev/null || true
}

is_mount_excluded(){
  local mp="$1"
  [ -f "$EXCLUDE_MOUNTS_FILE" ] || return 1
  grep -Fxq "$mp" "$EXCLUDE_MOUNTS_FILE"
}

remote_collect_cmd() {
  cat <<'EOF'
set -euo pipefail

# Output: mount|fstype|used_pct|used_kb
# Use df -PT for fstype. Use 1K blocks so we can compute deltas.
df -PT -k 2>/dev/null | awk 'NR>1{gsub(/%/,"",$6); print $7"|"$2"|"$6"|"$4}'
EOF
}

append_state(){
  local host="$1" mount="$2" used_pct="$3" used_kb="$4"
  local f="$STATE_BASE/${host}.csv"
  printf "%s,%s,%s,%s\n" "$(date +%s)" "$mount" "$used_pct" "$used_kb" >> "$f"
}

# Compute forecast from history of used_kb for a mount.
# Returns: days_to_full (or NA) and slope_kb_per_day.
forecast_mount(){
  local host="$1" mount="$2"
  local f="$STATE_BASE/${host}.csv"
  [ -f "$f" ] || { echo "NA NA"; return; }

  # Use last 30 points for stability.
  # We do linear slope using oldest and newest points.
  local rows
  rows=$(awk -F',' -v M="$mount" '$2==M{print $0}' "$f" | tail -n 30)
  local n; n=$(printf "%s\n" "$rows" | sed '/^$/d' | wc -l | awk '{print $1}')
  [ "$n" -lt "$MIN_POINTS" ] && { echo "NA NA"; return; }

  local first last
  first=$(printf "%s\n" "$rows" | head -n 1)
  last=$(printf "%s\n" "$rows" | tail -n 1)

  local t1 u1 t2 u2
  t1=$(echo "$first" | awk -F',' '{print $1}')
  u1=$(echo "$first" | awk -F',' '{print $4}')
  t2=$(echo "$last" | awk -F',' '{print $1}')
  u2=$(echo "$last" | awk -F',' '{print $4}')

  # guard
  [[ "$t1" =~ ^[0-9]+$ ]] || { echo "NA NA"; return; }
  [[ "$t2" =~ ^[0-9]+$ ]] || { echo "NA NA"; return; }
  [[ "$u1" =~ ^[0-9]+$ ]] || { echo "NA NA"; return; }
  [[ "$u2" =~ ^[0-9]+$ ]] || { echo "NA NA"; return; }

  local dt=$((t2-t1))
  [ "$dt" -le 0 ] && { echo "NA NA"; return; }
  local du=$((u2-u1))

  # if not growing, no forecast
  [ "$du" -le 0 ] && { echo "INF 0"; return; }

  # slope per day
  local slope_kb_per_day=$(( du * 86400 / dt ))
  [ "$slope_kb_per_day" -le 0 ] && { echo "NA NA"; return; }

  # Need current filesystem size to compute remaining. We approximate size_kb from last point and used_pct:
  local used_pct
  used_pct=$(echo "$last" | awk -F',' '{print $3}')
  [[ "$used_pct" =~ ^[0-9]+$ ]] || { echo "NA NA"; return; }
  [ "$used_pct" -le 0 ] && { echo "NA NA"; return; }

  # size_kb ~= used_kb * 100 / used_pct
  local size_kb=$(( u2 * 100 / used_pct ))
  local remaining_kb=$(( size_kb - u2 ))
  [ "$remaining_kb" -le 0 ] && { echo "0 $slope_kb_per_day"; return; }

  local days=$(( remaining_kb / slope_kb_per_day ))
  echo "$days $slope_kb_per_day"
}

run_for_host(){
  local host="$1"
  ensure_dirs

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    echo "disk_trend_monitor host=$host status=CRIT mounts=0 note=ssh_unreachable"
    WORST_RC=2
    return 2
  fi

  local cmd out
  cmd="$(remote_collect_cmd)"
  out="$(lm_ssh "$host" bash -lc "$cmd" 2>/dev/null || true)"
  [ -z "$out" ] && { echo "disk_trend_monitor host=$host status=UNKNOWN mounts=0 note=no_df"; WORST_RC=3; return 3; }

  local mounts=0
  local warn=0
  local crit=0
  local insufficient=0

  while IFS='|' read -r mp fstype used_pct used_kb; do
    [ -z "$mp" ] && continue
    mounts=$((mounts+1))

    # exclude types/mounts
    if echo "$fstype" | grep -Eq "$EXCLUDE_FSTYPES_RE"; then
      continue
    fi
    if is_mount_excluded "$mp"; then
      continue
    fi

    # record state
    append_state "$host" "$mp" "$used_pct" "$used_kb"

    # hard thresholds
    if [[ "$used_pct" =~ ^[0-9]+$ ]]; then
      if [ "$used_pct" -ge "$HARD_CRIT_PCT" ]; then
        crit=$((crit+1))
        append_alert "$host|disk_hard_crit|mount=$mp used_pct=$used_pct"
        continue
      elif [ "$used_pct" -ge "$HARD_WARN_PCT" ]; then
        warn=$((warn+1))
        append_alert "$host|disk_hard_warn|mount=$mp used_pct=$used_pct"
        # still compute forecast below
      fi
    fi

    # forecast
    read -r days slope < <(forecast_mount "$host" "$mp")
    if [ "$days" = "NA" ]; then
      insufficient=$((insufficient+1))
      continue
    fi
    if [ "$days" = "INF" ]; then
      continue
    fi
    if [[ "$days" =~ ^[0-9]+$ ]]; then
      if [ "$days" -le "$CRIT_DAYS" ]; then
        crit=$((crit+1))
        append_alert "$host|disk_trend_crit|mount=$mp days_to_full=$days slope_kb_per_day=$slope"
      elif [ "$days" -le "$WARN_DAYS" ]; then
        warn=$((warn+1))
        append_alert "$host|disk_trend_warn|mount=$mp days_to_full=$days slope_kb_per_day=$slope"
      fi
    fi
  done <<< "$out"

  local status rc note
  status="OK"; rc=0; note=""
  if [ "$crit" -gt 0 ]; then status="CRIT"; rc=2
  elif [ "$warn" -gt 0 ]; then status="WARN"; rc=1
  else
    if [ "$insufficient" -gt 0 ]; then
      note="insufficient_history"
    fi
  fi

  echo "disk_trend_monitor host=$host status=$status mounts=$mounts warn=$warn crit=$crit note=${note:-none}"
  [ "$rc" -gt "$WORST_RC" ] && WORST_RC="$rc"
  return "$rc"
}

main(){
  : > "$ALERTS_FILE"
  WORST_RC=0

  lm_for_each_host run_for_host

  if [ -s "$ALERTS_FILE" ]; then
    mail_if_enabled "$MAIL_SUBJECT_PREFIX Disk growth/days-to-full alerts" "$(cat "$ALERTS_FILE")"
  fi

  exit "$WORST_RC"
}

main "$@"
