#!/bin/bash
# inode_monitor.sh - Monitor inode usage per filesystem (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[inode_monitor] "
LM_LOGFILE="/var/log/inode_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; set >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle

lm_require_singleton "inode_monitor"

# ========================
# Script configuration
# ========================
THRESHOLDS="/etc/linux_maint/inode_thresholds.txt"   # CSV: mountpoint,warn%,crit% (supports '*' default)
EXCLUDE_MOUNTS="/etc/linux_maint/inode_exclude.txt"  # Optional: list of mountpoints to skip

# Defaults if not specified per mount / default row (*)
DEFAULT_WARN=80
DEFAULT_CRIT=95

# Skip these filesystem types (regex). Tweak to your taste.
EXCLUDE_FSTYPES_RE='^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?|debugfs|rpc_pipefs|autofs|devpts|mqueue|hugetlbfs|fuse\..*|binfmt_misc|pstore|nsfs)$'

MAIL_SUBJECT_PREFIX='[Inode Monitor]'

# ========================
# Helpers (script-local)
# ========================
ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" inode_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

is_mount_excluded(){
  local mp="$1"
  [ -f "$EXCLUDE_MOUNTS" ] || return 1
  grep -Fxq "$mp" "$EXCLUDE_MOUNTS"
}

# Lookup warn/crit thresholds for a mountpoint from THRESHOLDS file.
# Order of precedence: exact mount row > '*' row > defaults.
lookup_thresholds(){
  local mp="$1"
  local warn crit
  warn=""; crit=""
  if [ -f "$THRESHOLDS" ]; then
    # exact row
    read warn crit < <(awk -F'[ ,]+' -v M="$mp" '
      $0 ~ /^[[:space:]]*#/ {next}
      NF>=3 && $1==M {print $2, $3; exit}
    ' "$THRESHOLDS")
    # star/default row
    if [ -z "$warn" ] || [ -z "$crit" ]; then
      read warn crit < <(awk -F'[ ,]+' '
        $0 ~ /^[[:space:]]*#/ {next}
        NF>=3 && $1=="*" {print $2, $3; exit}
      ' "$THRESHOLDS")
    fi
  fi
  [ -z "$warn" ] && warn="$DEFAULT_WARN"
  [ -z "$crit" ] && crit="$DEFAULT_CRIT"
  echo "$warn $crit"
}

collect_inodes(){
  # Prints: fs|type|inodes|iused|iuse%|mount
  local host="$1"
  local out
  out="$(lm_ssh "$host" "df -PTi 2>/dev/null | awk 'NR>1{printf \"%s|%s|%s|%s|%s|%s\\n\",\$1,\$2,\$3,\$4,\$6,\$7}'")"
  if [ -z "$out" ]; then
    out="$(lm_ssh "$host" "df -Pi 2>/dev/null | awk 'NR>1{printf \"%s|%s|%s|%s|%s|%s\\n\",\$1,\"-\",\$2,\$3,\$5,\$6}'")"
  fi
  printf "%s\n" "$out" | sed '/^$/d'
}

rate_status(){
  local use="$1" warn="$2" crit="$3"
  # guard non-numeric (some df variants may return "-" or empty)
  [[ "$use" =~ ^[0-9]+$ ]] || { echo "OK"; return; }
  if [ "$use" -ge "$crit" ]; then echo "CRIT"; return; fi
  if [ "$use" -ge "$warn" ]; then echo "WARN"; return; fi
  echo "OK"
}

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Checking inode usage on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    return
  fi

  local lines; lines="$(collect_inodes "$host")"
  if [ -z "$lines" ]; then
    lm_warn "[$host] No df output."
    return
  fi

  while IFS='|' read -r fs type inodes iused iusepct mp; do
    # Normalize
    use="${iusepct%%%}"
    [ -z "$use" ] && continue

    # Skip excluded fstype or mountpoint
    if echo "$type" | grep -Eq "$EXCLUDE_FSTYPES_RE"; then
      continue
    fi
    if is_mount_excluded "$mp"; then
      continue
    fi

    read warn crit <<<"$(lookup_thresholds "$mp")"
    st="$(rate_status "$use" "$warn" "$crit")"

    lm_info "[$host] [$st] $mp type=$type inodes=$inodes used=$iused use%=$use warn=$warn crit=$crit"

    if [ "$st" != "OK" ]; then
      append_alert "$host|$mp|$use% (warn=$warn crit=$crit)"
    fi
  done <<< "$lines"

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
lm_info "=== Inode Monitor Started (defaults warn=${DEFAULT_WARN}% crit=${DEFAULT_CRIT}%) ==="

lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="High inode usage detected"
  body="The following filesystems exceeded thresholds:

Host | Mount | Use% (warn/crit)
-------------------------------
$(echo "$alerts" | awk -F'|' 'NF>=3{printf "%s | %s | %s\n",$1,$2,$3}')

This is an automated message from inode_monitor.sh."
  lm_mail "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Inode Monitor Finished ==="
