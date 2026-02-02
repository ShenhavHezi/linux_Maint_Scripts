#!/bin/bash
# distributed_disk_monitor.sh - Disk usage thresholds across multiple servers
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   - Checks mounted filesystems on one or many Linux hosts.
#   - Applies per-mount WARN/CRIT thresholds (or global defaults).
#   - Skips pseudo filesystems and optionally excluded mountpoints.
#   - Logs concise lines and emails a single aggregated alert.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[disk_monitor] "
LM_LOGFILE="/var/log/disk_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master toggle for lm_mail

lm_require_singleton "distributed_disk_monitor"

MAIL_SUBJECT_PREFIX='[Disk Monitor]'

# ========================
# Configuration
# ========================
# Per-mount thresholds (CSV): /etc/linux_maint/disk_thresholds.txt
#   mountpoint,warn%,crit%
#   Example:
#     /,80,90
#     /var,85,95
#     *,85,95         # default row
THRESHOLDS_FILE="/etc/linux_maint/disk_thresholds.txt"
EXCLUDE_MOUNTS_FILE="/etc/linux_maint/disk_exclude.txt"   # Optional: list of mountpoints to skip (exact match)

# Global default thresholds (used if no exact or '*' row in THRESHOLDS_FILE)
: "${DEFAULT_WARN:=85}"
: "${DEFAULT_CRIT:=95}"

# Skip these filesystem types (regex)
EXCLUDE_FSTYPES_RE='^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?|debugfs|rpc_pipefs|autofs|devpts|mqueue|hugetlbfs|fuse\..*|binfmt_misc|pstore|nsfs)$'

EMAIL_ON_ALERT="true"   # Send email if any WARN/CRIT detected

# ========================
# Helpers (script-local)
# ========================
mail_if_enabled(){ [ "$EMAIL_ON_ALERT" = "true" ] || return 0; lm_mail "$1" "$2"; }

is_mount_excluded(){
  local mp="$1"
  [ -s "$EXCLUDE_MOUNTS_FILE" ] || return 1
  grep -Fxq "$mp" "$EXCLUDE_MOUNTS_FILE"
}

lookup_thresholds(){
  # Echo: "warn crit" for a mountpoint, from THRESHOLDS_FILE > '*' > defaults
  local mp="$1" w="" c=""
  if [ -s "$THRESHOLDS_FILE" ]; then
    read w c < <(awk -F'[ ,]+' -v M="$mp" '
      $0 ~ /^[[:space:]]*#/ {next}
      NF>=3 && $1==M {print $2, $3; exit}' "$THRESHOLDS_FILE")
    if [ -z "$w" ] || [ -z "$c" ]; then
      read w c < <(awk -F'[ ,]+' '
        $0 ~ /^[[:space:]]*#/ {next}
        NF>=3 && $1=="*" {print $2, $3; exit}' "$THRESHOLDS_FILE")
    fi
  fi
  [ -z "$w" ] && w="$DEFAULT_WARN"
  [ -z "$c" ] && c="$DEFAULT_CRIT"
  echo "$w $c"
}

rate_status(){
  local use="$1" warn="$2" crit="$3"
  if [ "$use" -ge "$crit" ]; then echo "CRIT"; return; fi
  if [ "$use" -ge "$warn" ]; then echo "WARN"; return; fi
  echo "OK"
}

# ---- Remote collector: df -PT; prints "fs|type|size|used|avail|use%|mount"
remote_df_cmd='
LC_ALL=C
if df -PT >/dev/null 2>&1; then
  df -PT 2>/dev/null | awk "NR>1{printf \"%s|%s|%s|%s|%s|%s|%s\n\",\$1,\$2,\$3,\$4,\$5,\$6,\$7}"
else
  # Fallback without type column
  df -P 2>/dev/null | awk "NR>1{printf \"%s|%s|%s|%s|%s|%s|%s\n\",\$1,\"-\",\$2,\$3,\$4,\$5,\$6}"
fi
'

# ========================
# Aggregation
# ========================
ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" disk_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Checking disks on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|?|?|?|?|?|CRIT|ssh_unreachable"
    lm_info "===== Completed $host ====="
    return
  fi

  local lines; lines="$(lm_ssh "$host" bash -lc "$remote_df_cmd")"
  if [ -z "$lines" ]; then
    lm_warn "[$host] no df output"
    lm_info "===== Completed $host ====="
    return
  fi

  while IFS='|' read -r fs fstype size used avail usepct mp; do
    [ -z "$mp" ] && continue
    # Normalize
    local use="${usepct%%%}"
    [ -z "$use" ] && continue

    # Skip excluded filesystem types / mountpoints
    if printf "%s\n" "$fstype" | grep -Eq "$EXCLUDE_FSTYPES_RE"; then
      continue
    fi
    if is_mount_excluded "$mp"; then
      continue
    fi

    read warn crit <<<"$(lookup_thresholds "$mp")"
    st="$(rate_status "$use" "$warn" "$crit")"

    lm_info "[$st] $host $mp fs=$fs type=$fstype use%=$use warn=$warn crit=$crit"

    if [ "$st" != "OK" ]; then
      append_alert "$host|$fs|$fstype|$mp|$use|$warn/$crit|$st|"
    fi
  done <<< "$lines"

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
lm_info "=== Disk Monitor Started (defaults warn=${DEFAULT_WARN}% crit=${DEFAULT_CRIT}%) ==="

lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="Disk usage WARN/CRIT detected"
  body="Defaults: warn=${DEFAULT_WARN}%, crit=${DEFAULT_CRIT}%
(Per-mount overrides: ${THRESHOLDS_FILE})

Host | FS | Type | Mount | Use% | (warn/crit) | Status | Note
-----|----|------|-------|------|-------------|--------|-----
$(echo "$alerts" | awk -F'|' '{printf "%s | %s | %s | %s | %s | %s | %s | %s\n",$1,$2,$3,$4,$5,$6,$7,(NF>=8?$8:"")}')

This is an automated message from distributed_disk_monitor.sh."
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Disk Monitor Finished ==="
