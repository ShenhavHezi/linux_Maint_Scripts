#!/bin/bash
# backup_check.sh - Verify existence, freshness, size & integrity of backups (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Checks one or many Linux servers for recent backups:
#     - finds the latest file matching a configured pattern
#     - validates age (max_age_hours) and minimum size (min_size_mb)
#     - optional integrity test (tar/gzip/custom "cmd:<shell>")
#   Logs concise lines and emails a single aggregated alert when checks fail.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[backup_check] "
LM_LOGFILE="/var/log/backup_check.log"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; >0 parallelize hosts
: "${LM_EMAIL_ENABLED:=true}" # master toggle for lm_mail
lm_require_singleton "backup_check"
mkdir -p "$(dirname "$LM_LOGFILE")"

MAIL_SUBJECT_PREFIX='[Backup Check]'
EMAIL_ON_FAILURE="true"

# ========================
# Configuration
# ========================
TARGETS="/etc/linux_maint/backup_targets.csv"  # CSV: host,pattern,min_size_mb,max_age_hours,verify
#  - host can be a concrete hostname or "*" to apply to all
#  - pattern like /backups/db/db_*.tar.gz  (glob in the filename only)
#  - verify: "tar" | "gzip" | "none" | "cmd:<shell that receives file path>"
#            e.g. cmd:tar -tf ; cmd:pigz -t ; cmd:7z t

# Integrity verification timeout (seconds)
: "${VERIFY_TIMEOUT:=60}"

# ========================
# Helpers (script-local)
# ========================
mail_if_enabled(){ [ "$EMAIL_ON_FAILURE" = "true" ] || return 0; lm_mail "$1" "$2"; }

# Return "epoch|bytes|path" for latest file matching "pattern"; empty if none
remote_latest_file(){
  local host="$1" pattern="$2"
  lm_ssh "$host" bash -lc '
    p=$1
    d=$(dirname -- "$p"); g=$(basename -- "$p")
    [ -d "$d" ] || exit 0
    LC_ALL=C find "$d" -maxdepth 1 -type f -name "$g" -printf "%T@|%s|%p\n" 2>/dev/null | sort -nr | head -1
  ' _ "$pattern"
}

# verify modes: tar | gzip | none | cmd:<shell>
remote_verify(){
  local host="$1" mode="$2" file="$3"
  case "$mode" in
    tar)   lm_ssh "$host" "timeout ${VERIFY_TIMEOUT}s tar -tf '$file' >/dev/null 2>&1" ;;
    gzip)  lm_ssh "$host" "timeout ${VERIFY_TIMEOUT}s gzip -t '$file' >/dev/null 2>&1" ;;
    cmd:*) local cmd="${mode#cmd:}"
           # Pass file path as "$1" to keep quoting safe
           lm_ssh "$host" bash -lc "timeout ${VERIFY_TIMEOUT}s $cmd \"\$1\" >/dev/null 2>&1" _ "$file" ;;
    none|"") return 0 ;;
    *)     return 1 ;;
  esac
}

append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Checking backups on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|*|?|?|?|CRIT|ssh_unreachable"
    lm_info "===== Completed $host ====="
    return
  fi

  [ -s "$TARGETS" ] || { lm_err "[$host] targets file missing/empty: $TARGETS"; lm_info "===== Completed $host ====="; return; }

  # Select rows for this host (* or exact)
  awk -F',' -v H="$host" '
    /^[[:space:]]*#/ {next}
    NF>=5 {
      # trim cells
      for(i=1;i<=NF;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
      if($1==H || $1=="*"){ print $0 }
    }' "$TARGETS" |
  while IFS=',' read -r _h pattern min_mb max_age_h verify; do
    [ -z "$pattern" ] && continue

    # Pull latest file
    local rec; rec="$(remote_latest_file "$host" "$pattern")"
    if [ -z "$rec" ]; then
      lm_info "[$host] [CRIT] no backup found for pattern: $pattern"
      append_alert "$host|$pattern|missing|-|$verify|CRIT|no_match"
      continue
    fi

    local epoch bytes path now age_h size_mb
    IFS='|' read -r epoch bytes path <<<"$rec"
    now="$(date +%s)"
    age_h="$(awk -v e="$epoch" -v n="$now" 'BEGIN{printf("%.1f",(n-e)/3600.0)}')"
    size_mb="$(awk -v b="$bytes" 'BEGIN{printf("%.1f",b/1048576.0)}')"

    # Checks
    local status="OK"; local notes=()

    # Age
    if awk -v a="$age_h" -v m="$max_age_h" 'BEGIN{exit !(a > m)}'; then
      status="CRIT"; notes+=("too_old:${age_h}h>${max_age_h}h")
    fi
    # Size
    if awk -v s="$size_mb" -v m="$min_mb" 'BEGIN{exit !(s < m)}'; then
      status="CRIT"; notes+=("too_small:${size_mb}MB<${min_mb}MB")
    fi
    # Integrity
    if ! remote_verify "$host" "$verify" "$path"; then
      status="CRIT"; notes+=("verify_failed:${verify:-none}")
    fi

    if [ "$status" = "OK" ]; then
      lm_info "[$host] [OK] $path size=${size_mb}MB age=${age_h}h verify=${verify:-none}"
    else
      lm_info "[$host] [CRIT] $path size=${size_mb}MB age=${age_h}h verify=${verify:-none} notes=${notes[*]}"
      append_alert "$host|$pattern|$path|${size_mb}MB|${age_h}h|$verify|CRIT|${notes[*]}"
    fi
  done

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" backup_check.alerts.XXXXXX)"
lm_info "=== Backup Check Started (verify_timeout=${VERIFY_TIMEOUT}s) ==="

lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"

failures=$(printf '%s' \"$alerts\" | sed '/^$/d' | wc -l | tr -d ' ')
status=OK
[ \"$failures\" != \"0\" ] && status=CRIT
echo backup_check summary status=$status failures=$failures
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="Backups require attention"
  body="One or more backup checks failed.

Host | Pattern | Path | Size | Age | Verify | Status | Notes
-----|---------|------|------|-----|--------|--------|------
$(echo "$alerts" | awk -F'|' '{printf "%s | %s | %s | %s | %s | %s | %s | %s\n",$1,$2,$3,$4,$5,$6,$7,(NF>=8?$8:"")}')

This is an automated message from backup_check.sh."
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Backup Check Finished ==="
