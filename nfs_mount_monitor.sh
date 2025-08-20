#!/bin/bash
# nfs_mount_monitor.sh - Verify NFS/CIFS mounts are present & healthy (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Checks one or many Linux servers for required network filesystems:
#     - ensures mountpoint exists and is mounted with expected fstype/remote
#     - detects stale/unresponsive mounts via timed ops
#     - optional RW test (create/remove temp file)
#     - optional auto (re)mount on failure
#   Logs a concise report and can email alerts when checks fail.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"        # One host per line; if missing → local mode
EXCLUDED="/etc/linux_maint/excluded.txt"         # Optional: hosts to skip
MOUNTS_CONF="/etc/linux_maint/mounts.txt"        # CSV: host,mp,fstype,remote,options,mode,timeout
ALERT_EMAILS="/etc/linux_maint/emails.txt"       # Optional: recipients (one per line)
LOGFILE="/var/log/nfs_mount_monitor.log"         # Report log
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no"

# Behavior
EMAIL_ON_FAILURE="true"
AUTO_REMOUNT="false"                 # Attempt (re)mount when not mounted or unhealthy
UMOUNT_FLAGS="-fl"                   # Force+lazy unmount for stuck NFS; tune as needed
DEFAULT_TIMEOUT=8                    # Seconds for each health operation

MAIL_SUBJECT_PREFIX='[NFS Mount Monitor]'

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

# Return 0 if mounted with expected fstype/remote; 1 otherwise.
remote_is_mounted(){
  local host="$1" mp="$2" fstype="$3" remote="$4"
  ssh_do "$host" "awk '\$2==\"$mp\" {print \$1, \$3}' /proc/mounts" | \
    awk -v wantfs="$fstype" -v wantr="$remote" '
      {
        dev=$1; fs=$2;
        okfs = (wantfs=="" || fs==wantfs);
        okrem = (wantr=="" || dev==wantr);
        if (okfs && okrem) {found=1}
      }
      END{exit (found?0:1)}'
}

# Health test: ls/df (RO) and optional RW touch
remote_health_check(){
  local host="$1" mp="$2" mode="$3" to="$4"
  [ -z "$to" ] && to="$DEFAULT_TIMEOUT"
  # Quick responsive checks (avoid hanging forever with timeout)
  if ! ssh_do "$host" "timeout $to bash -lc 'df -P \"$mp\" >/dev/null && ls -ld \"$mp\" >/dev/null'"; then
    echo "stale"; return
  fi
  if [ "$mode" = "rw" ]; then
    local tf=".mnt_health_$$.$RANDOM"
    if ! ssh_do "$host" "timeout $to bash -lc 'touch \"$mp/$tf\" && sync && rm -f \"$mp/$tf\"'"; then
      echo "rw_failed"; return
    fi
  fi
  echo "ok"
}

# Attempt to mount (or remount) using provided details
remote_mount(){
  local host="$1" mp="$2" fstype="$3" remote="$4" opts="$5"
  local optflag=""
  [ -n "$opts" ] && optflag="-o $opts"
  ssh_do "$host" "mkdir -p \"$mp\" && mount -t \"$fstype\" $optflag \"$remote\" \"$mp\""
}

remote_umount(){
  local host="$1" mp="$2"
  ssh_do "$host" "umount $UMOUNT_FLAGS \"$mp\""
}

check_one_mount(){
  local host="$1" mp="$2" fstype="$3" remote="$4" opts="$5" mode="$6" to="$7"
  [ -z "$to" ] && to="$DEFAULT_TIMEOUT"
  [ -z "$mode" ] && mode="ro"

  local status notes=""
  if ! remote_is_mounted "$host" "$mp" "$fstype" "$remote"; then
    status="CRIT"; notes="not_mounted"
    log "[$host] [CRIT] $mp not mounted (expected fstype=$fstype remote=$remote)"
    if [ "$AUTO_REMOUNT" = "true" ] && [ -n "$fstype" ] && [ -n "$remote" ]; then
      log "[$host] Attempting mount: mount -t $fstype -o ${opts:-<none>} $remote $mp"
      if remote_mount "$host" "$mp" "$fstype" "$remote" "$opts"; then
        # verify again
        if remote_is_mounted "$host" "$mp" "$fstype" "$remote"; then
          log "[$host] [INFO] Mounted $mp successfully."
          status="OK"; notes="mounted_now"
        else
          log "[$host] [CRIT] Mount reported success but not visible in /proc/mounts."
        fi
      else
        log "[$host] [CRIT] Mount command failed."
      fi
    fi
  else
    # Mounted: run health checks
    local health; health=$(remote_health_check "$host" "$mp" "$mode" "$to")
    case "$health" in
      ok)      status="OK";;
      stale)   status="CRIT"; notes="stale_or_unresponsive";;
      rw_failed) status="WARN"; notes="rw_test_failed";;
      *)       status="WARN"; notes="unknown_health";;
    esac

    # Remediate if stale and allowed
    if [ "$status" = "CRIT" ] && [ "$AUTO_REMOUNT" = "true" ]; then
      log "[$host] Attempting remount: umount $UMOUNT_FLAGS $mp && mount..."
      remote_umount "$host" "$mp"
      remote_mount "$host" "$mp" "$fstype" "$remote" "$opts"
      # Re-test quickly
      if remote_is_mounted "$host" "$mp" "$fstype" "$remote"; then
        local health2; health2=$(remote_health_check "$host" "$mp" "$mode" "$to")
        if [ "$health2" = "ok" ]; then
          log "[$host] [INFO] Remount succeeded and healthy: $mp"
          status="OK"; notes="remounted_ok"
        else
          log "[$host] [CRIT] Remount did not restore health: $mp ($health2)"
        fi
      else
        log "[$host] [CRIT] Remount failed: $mp"
      fi
    fi
  fi

  echo "$status|$host|$mp|$fstype|$remote|$mode|$notes"
}

check_host(){
  local host="$1"
  log "===== Checking mounts on $host ====="

  # reachability (skip for localhost)
  if [ "$host" != "localhost" ]; then
    if ! ssh_do "$host" "echo ok" | grep -q ok; then
      log "[$host] ERROR: SSH unreachable."
      echo "ALERT:$host:ssh_unreachable"
      return
    fi
  fi

  [ -s "$MOUNTS_CONF" ] || { log "[$host] ERROR: mounts file $MOUNTS_CONF missing/empty."; return; }

  # CSV columns: host,mp,fstype,remote,options,mode,timeout
  # host can be specific hostname or "*" for all
  awk -F',' -v H="$host" '
    /^[[:space:]]*#/ {next}
    NF>=4 {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1);
      if($1==H || $1=="*"){print $0}
    }' "$MOUNTS_CONF" |
  while IFS=',' read -r h mp fstype remote opts mode to; do
    # trim whitespace
    mp="$(echo "$mp" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    fstype="$(echo "$fstype" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    remote="$(echo "$remote" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    opts="$(echo "$opts" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    mode="$(echo "$mode" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    to="$(echo "$to" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

    [ -z "$mp" ] && { log "[$host] WARNING: empty mountpoint in $MOUNTS_CONF"; continue; }

    res=$(check_one_mount "$host" "$mp" "$fstype" "$remote" "$opts" "$mode" "$to")
    IFS='|' read -r st hh mpp fs rm mm notes <<<"$res"
    if [ "$st" != "OK" ]; then
      echo "ALERT:$host:$mpp:$st:$notes"
      log "[$host] [$st] $mpp fstype=$fs remote=$rm mode=${mm:-ro} notes=${notes:-none}"
    else
      log "[$host] [OK] $mpp fstype=$fs remote=$rm mode=${mm:-ro}"
    fi
  done

  log "===== Completed $host ====="
}

# ========================
# Main
# ========================
log "=== NFS/CIFS Mount Monitor Started ==="

alerts=""
if [ -f "$SERVERLIST" ]; then
  while IFS= read -r HOST; do
    [ -z "$HOST" ] && continue
    is_excluded "$HOST" && { log "Skipping $HOST (excluded)"; continue; }
    out="$(check_host "$HOST")"
    case "$out" in
      *ALERT:*) alerts+=$(printf "%s\n" "$out" | sed 's/^.*ALERT://')$'\n' ;;
    esac
  done < "$SERVERLIST"
else
  out="$(check_host "localhost")"
  case "$out" in
    *ALERT:*) alerts+=$(printf "%s\n" "$out" | sed 's/^.*ALERT://')$'\n' ;;
  esac
fi

if [ -n "$alerts" ]; then
  subject="Mount failures detected"
  body="The following mount checks failed:

Host | Mountpoint | Status | Notes
----------------------------------
$(echo "$alerts" | awk -F: 'NF>=4{printf "%s | %s | %s | %s\n",$1,$2,$3,$4}') 

AUTO_REMOUNT=${AUTO_REMOUNT}. This is an automated message from nfs_mount_monitor.sh."
  send_mail "$subject" "$body"
fi

log "=== NFS/CIFS Mount Monitor Finished ==="
