#!/bin/bash
# backup_check.sh - Verify existence, freshness, size & integrity of backups (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Checks one or many Linux servers for recent backups:
#     - finds the latest file matching a configured pattern
#     - validates age (max_age_hours) and minimum size (min_size_mb)
#     - optional integrity test (tar/gzip/custom command)
#   Logs a concise report and can email alerts when checks fail.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"          # One host per line; if missing → local mode
EXCLUDED="/etc/linux_maint/excluded.txt"           # Optional: hosts to skip
TARGETS="/etc/linux_maint/backup_targets.csv"      # host,pattern,min_size_mb,max_age_hours,verify
ALERT_EMAILS="/etc/linux_maint/emails.txt"         # Optional: recipients (one per line)
LOGFILE="/var/log/backup_check.log"                # Report log
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no"

MAIL_SUBJECT_PREFIX='[Backup Check]'
EMAIL_ON_FAILURE="true"

# Integrity verification timeout (seconds)
VERIFY_TIMEOUT=60

# ========================
# Helpers
# ========================
log(){ echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"; }

is_excluded(){
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
  [ "$EMAIL_ON_FAILURE" = "true" ] || return 0
  [ -s "$ALERT_EMAILS" ] || return 0
  command -v mail >/dev/null || return 0
  while IFS= read -r to; do
    [ -n "$to" ] && printf "%s\n" "$body" | mail -s "$MAIL_SUBJECT_PREFIX $subject" "$to"
  done < "$ALERT_EMAILS"
}

# Return "epoch|bytes|path" for latest file matching pattern; empty if none
remote_latest_file(){
  local host="$1" pattern="$2"
  ssh_do "$host" bash -lc "
    p='$pattern'
    d=\$(dirname -- \"\$p\"); g=\$(basename -- \"\$p\")
    [ -d \"\$d\" ] || exit 0
    LC_ALL=C find \"\$d\" -maxdepth 1 -type f -name \"\$g\" -printf '%T@|%s|%p\n' 2>/dev/null | sort -nr | head -1
  "
}

# verify modes: tar | gzip | none | cmd:<shell>
remote_verify(){
  local host="$1" mode="$2" file="$3"
  case "$mode" in
    tar)  ssh_do "$host" "timeout ${VERIFY_TIMEOUT}s tar -tzf '$file' >/dev/null 2>&1" ;;
    gzip) ssh_do "$host" "timeout ${VERIFY_TIMEOUT}s gzip -t '$file' >/dev/null 2>&1" ;;
    cmd:*) local cmd="${mode#cmd:}"; ssh_do "$host" "timeout ${VERIFY_TIMEOUT}s bash -lc \"$cmd '$file'\" >/dev/null 2>&1" ;;
    none|"") return 0 ;;
    *) return 1 ;;
  esac
}

check_target(){
  local host="$1" pattern="$2" min_mb="$3" max_age_h="$4" verify="$5"

  local rec; rec="$(remote_latest_file "$host" "$pattern")"
  if [ -z "$rec" ]; then
    log "[$host] [CRIT] No backup found for pattern: $pattern"
    echo "ALERT:$host:missing:$pattern"
    return
  fi

  IFS='|' read -r epoch bytes path <<<"$rec"
  local now=$(date +%s)
  local age_h=$(awk -v e="$epoch" -v n="$now" 'BEGIN{printf("%.1f",(n-e)/3600.0)}')
  local size_mb=$(awk -v b="$bytes" 'BEGIN{printf("%.1f",b/1048576.0)}')

  local status="OK"; local notes=()

  # Age check
  awk -v a="$age_h" -v m="$max_age_h" 'BEGIN{exit !(a > m)}' && { status="CRIT"; notes+=("too_old:${age_h}h>${max_age_h}h"); }

  # Size check
  awk -v s="$size_mb" -v m="$min_mb" 'BEGIN{exit !(s < m)}' && { status="CRIT"; notes+=("too_small:${size_mb}MB<${min_mb}MB"); }

  # Integrity check
  if ! remote_verify "$host" "$verify" "$path"; then
    status="CRIT"; notes+=("verify_failed:$verify")
  fi

  if [ "$status" = "OK" ]; then
    log "[$host] [OK] $path size=${size_mb}MB age=${age_h}h verify=${verify:-none}"
  else
    log "[$host] [CRIT] $path size=${size_mb}MB age=${age_h}h verify=${verify:-none} notes=${notes[*]}"
    echo "ALERT:$host:$path:${notes[*]}"
  fi
}

check_host(){
  local host="$1"
  log "===== Checking backups on $host ====="

  # reachability (skip localhost)
  if [ "$host" != "localhost" ]; then
    if ! ssh_do "$host" "echo ok" | grep -q ok; then
      log "[$host] ERROR: SSH unreachable."
      echo "ALERT:$host:ssh_unreachable"
      return
    fi
  fi

  [ -s "$TARGETS" ] || { log "[$host] ERROR: targets file $TARGETS missing/empty."; return; }

  # iterate CSV lines matching this host or wildcard "*"
  awk -F',' -v H="$host" '
    BEGIN{IGNORECASE=0}
    /^[[:space:]]*#/ {next}
    NF>=5 {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
      if($1==H || $1=="*"){print $0}
    }' "$TARGETS" |
  while IFS=',' read -r h pattern min_mb max_age_h verify; do
    # trim
    pattern="$(echo "$pattern"   | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
    min_mb="$(echo "$min_mb"     | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
    max_age_h="$(echo "$max_age_h" | sed "s/^[[:space:]]*//;s/[[:space:]]*$//")"
    verify="$(echo "$verify"     | sed "s/^[[:spa]()]()
