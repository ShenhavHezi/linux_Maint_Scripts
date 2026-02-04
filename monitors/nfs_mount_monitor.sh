#!/usr/bin/env bash
# nfs_mount_monitor.sh - Check NFS mounts are present and responsive (local/distributed)
# Author: Shenhav_Hezi
# Version: 1.0
#
# What it does:
# - Lists NFS mounts via findmnt (fallback: /proc/mounts)
# - For each NFS mountpoint:
#     * checks it is still mounted
#     * checks it is responsive using a bounded timeout (stat)
# - Produces one-line stdout summary for wrapper logs.

set -euo pipefail

. "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" || { echo "Missing ${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}"; exit 1; }
LM_PREFIX="[nfs_mount] "
LM_LOGFILE="${LM_LOGFILE:-/var/log/nfs_mount_monitor.log}"
: "${LM_MAX_PARALLEL:=0}"
: "${LM_EMAIL_ENABLED:=true}"

lm_require_singleton "nfs_mount_monitor"

mkdir -p "$(dirname "$LM_LOGFILE")" 2>/dev/null || true

MAIL_SUBJECT_PREFIX='[NFS Mount Monitor]'
EMAIL_ON_ISSUE="true"

# timeout for responsiveness check per mount
: "${NFS_STAT_TIMEOUT:=5}"

ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" nfs_mount_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }
mail_if_enabled(){ [ "$EMAIL_ON_ISSUE" = "true" ] || return 0; lm_mail "$1" "$2"; }

# remote command: print mountpoint|source per nfs mount
collect_nfs_mounts_cmd='
if command -v findmnt >/dev/null 2>&1; then
  findmnt -rn -t nfs,nfs4 -o TARGET,SOURCE 2>/dev/null | awk "NF>=1{print $1 \"|\" ($2?$2:"-") }"
else
  awk "$3 ~ /^nfs/ {print $2 \"|\" $1}" /proc/mounts 2>/dev/null
fi
'

run_for_host(){
  local host="$1"
  lm_info "===== Checking NFS mounts on $host ====="

  local checked=0 bad=0

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    bad=$((bad+1))
    lm_summary "nfs_mount_monitor" "$host" "CRIT" checked=$checked bad=$bad
    # legacy:
    # echo "nfs_mount_monitor host=$host status=CRIT checked=$checked bad=$bad"
    lm_info "===== Completed $host ====="
    return
  fi

  local mounts
  mounts="$(lm_ssh "$host" bash -lc "$collect_nfs_mounts_cmd" || true)"
  if [ -z "$mounts" ]; then
    lm_info "[$host] No NFS mounts found."
    lm_summary "nfs_mount_monitor" "$host" "OK" checked=0 bad=0
    # legacy:
    # echo "nfs_mount_monitor host=$host status=OK checked=0 bad=0"
    lm_info "===== Completed $host ====="
    return
  fi

  while IFS='|' read -r mp src; do
    mp="${mp//[[:space:]]/}"
    src="${src:-}"; src="${src# }"
    [ -z "$mp" ] && continue
    checked=$((checked+1))

    # Still mounted?
    if ! lm_ssh "$host" bash -lc "mountpoint -q '$mp'"; then
      lm_err "[$host] [CRIT] NFS mountpoint not mounted: $mp (src=${src:-?})"
      append_alert "$host|unmounted|$mp|${src:-?}"
      bad=$((bad+1))
      continue
    fi

    # Responsiveness: stat with timeout
    if ! lm_ssh "$host" bash -lc "timeout ${NFS_STAT_TIMEOUT}s stat -f '$mp' >/dev/null 2>&1"; then
      lm_err "[$host] [CRIT] NFS mount unresponsive: $mp (src=${src:-?})"
      append_alert "$host|unresponsive|$mp|${src:-?}"
      bad=$((bad+1))
      continue
    fi

    lm_info "[$host] [OK] NFS mount healthy: $mp (src=${src:-?})"
  done <<<"$mounts"

  local status=OK
  [ "$bad" -gt 0 ] && status=CRIT

  lm_summary "nfs_mount_monitor" "$host" "$status" checked=$checked bad=$bad
  # legacy:
  # echo "nfs_mount_monitor host=$host status=$status checked=$checked bad=$bad"
  lm_info "===== Completed $host ====="
}

lm_info "=== NFS Mount Monitor Started (stat_timeout=${NFS_STAT_TIMEOUT}s) ==="

lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="NFS mount issues detected"
  body="Host | Issue | Mount | Source\n-----|-------|-------|-------\n$(echo "$alerts" | awk -F'|' 'NF>=4{printf "%s | %s | %s | %s\n",$1,$2,$3,$4}')\n\nThis is an automated message from nfs_mount_monitor.sh."
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== NFS Mount Monitor Finished ==="
