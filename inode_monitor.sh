#!/bin/bash
# inode_monitor.sh - Monitor inode usage per filesystem (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Checks one or many Linux servers for inode pressure:
#     - collects inode usage per mountpoint (df -PTi)
#     - applies per-mount WARN/CRIT thresholds (or global defaults)
#     - skips pseudo filesystems and optional excluded mountpoints
#   Logs a concise report and can email alerts when thresholds are crossed.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"          # One host per line; if missing → local mode
EXCLUDED="/etc/linux_maint/excluded.txt"           # Optional: hosts to skip
THRESHOLDS="/etc/linux_maint/inode_thresholds.txt" # CSV: mountpoint,warn%,crit% (supports '*' default)
EXCLUDE_MOUNTS="/etc/linux_maint/inode_exclude.txt"# Optional: list of mountpoints to skip
ALERT_EMAILS="/etc/linux_maint/emails.txt"         # Optional: recipients (one per line)

LOGFILE="/var/log/inode_monitor.log"               # Report log
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no"

# Default thresholds if not specified per mount / default row (*)
DEFAULT_WARN=80
DEFAULT_CRIT=95

# Skip these filesystem types (regex). Tweak to your taste.
EXCLUDE_FSTYPES_RE='^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?|debugfs|rpc_pipefs|autofs|devpts|mqueue|hugetlbfs|fuse\..*|binfmt_misc|pstore|nsfs)$'

# Email behavior
MAIL_SUBJECT_PREFIX='[Inode Monitor]'
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
  local out=""
  out="$(ssh_do "$host" "df -PTi 2>/dev/null | awk 'NR>1{printf \"%s|%s|%s|%s|%s|%s\\n\",\$1,\$2,\$3,\$4,\$6,\$7}'")"
  if [ -z "$out" ]; then
    out="$(ssh_do "$host" "df -Pi 2>/dev/null | awk 'NR>1{printf \"%s|%s|%s|%s|%s|%s\\n\",\$1,\"-\",\$2,\$3,\$5,\$6}'")"
  fi
  printf "%s\n" "$out" | sed '/^$/d'
}

rate_status(){
  local use="$1" warn="$2" crit="$3"
  if [ "$use" -ge "$crit" ]; then echo "CRIT"; return; fi
  if [ "$use" -ge "$warn" ]; then echo "WARN"; return; fi
  echo "OK"
}

check_host(){
  local host="$1"
  log "===== Checking inode usage on $host ====="

  # reachability (skip for localhost)
  if [ "$host" != "localhost" ]; then
    if ! ssh_do "$host" "echo ok" | grep -q ok; then
      log "[$host] ERROR: SSH unreachable."
      echo "ALERT:$host:ssh_unreachable"
      return
    fi
  fi

  local lines; lines="$(collect_inodes "$host")"
  if [ -z "$lines" ]; then
    log "[$host] WARNING: No df output."
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

    log "[$host] [$st] $mp type=$type inodes=$inodes used=$iused use%=$use warn=$warn crit=$crit"

    if [ "$st" != "OK" ]; then
      echo "ALERT:$host:$mp:$use% (warn=$warn crit=$crit)"
    fi
  done <<< "$lines"

  log "===== Completed $host ====="
}

# ========================
# Main
# ========================
log "=== Inode Monitor Started (defaults warn=${DEFAULT_WARN}% crit=${DEFAULT_CRIT}%) ==="

alerts=""
if [ -f "$SERVERLIST" ]; then
  while IFS= read -r HOST; do
    [ -z "$HOST" ] && continue
    is_excluded_host "$HOST" && { log "Skipping $HOST (excluded)"; continue; }
    res="$(check_host "$HOST")"
    case "$res" in
      *ALERT:*) alerts+=$(printf "%s\n" "$res" | sed 's/^.*ALERT://')$'\n' ;;
    esac
  done < "$SERVERLIST"
else
  res="$(check_host "localhost")"
  case "$res" in
    *ALERT:*) alerts+=$(printf "%s\n" "$res" | sed 's/^.*ALERT://')$'\n' ;;
  esac
fi

if [ -n "$alerts" ]; then
  subject="High inode usage detected"
  body="The following filesystems exceeded thresholds:

Host | Mount | Use% (warn/crit)
-------------------------------
$(echo "$alerts" | awk -F: 'NF>=3{printf "%s | %s | %s\n",$1,$2,$3}') 

This is an automated message from inode_monitor.sh."
  send_mail "$subject" "$body"
fi

log "=== Inode Monitor Finished ==="
