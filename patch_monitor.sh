#!/bin/bash
# patch_monitor.sh - Check pending OS updates and reboot requirements (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Scans one or many Linux servers for:
#     - total pending updates
#     - security updates
#     - kernel updates
#     - reboot-required state
#   Works across distros (APT/DNF/YUM/ZYPPER) and logs a concise report.
#   Optionally emails a summary when action is required.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"     # One host per line (hostname or IP)
EXCLUDED="/etc/linux_maint/excluded.txt"      # Optional: hosts to skip
ALERT_EMAILS="/etc/linux_maint/emails.txt"    # Optional: recipients (one per line)
LOGFILE="/var/log/patch_monitor.log"          # Log file
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no"
MAIL_SUBJECT_PREFIX="[Patch Monitor]"

# When true, send email if any host has security updates OR reboot is required
EMAIL_ON_ACTION="true"

# ========================
# Helpers
# ========================

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOGFILE"; }

is_excluded() {
  local host="$1"
  [ -f "$EXCLUDED" ] || return 1
  grep -Fxq "$host" "$EXCLUDED"
}

ssh_do() {
  local host="$1"; shift
  ssh $SSH_OPTS "$host" "$@" 2>/dev/null
}

remote_pkg_mgr() {
  local host="$1"
  # order matters (dnf first on RHEL8+)
  if ssh_do "$host" "command -v apt-get >/dev/null"; then echo "apt"; return; fi
  if ssh_do "$host" "command -v dnf >/dev/null";     then echo "dnf"; return; fi
  if ssh_do "$host" "command -v yum >/dev/null";     then echo "yum"; return; fi
  if ssh_do "$host" "command -v zypper >/dev/null";  then echo "zypper"; return; fi
  echo "unknown"
}

remote_os() {
  local host="$1"
  ssh_do "$host" "source /etc/os-release 2>/dev/null && echo \$PRETTY_NAME || uname -sr"
}

# ---- Per-manager probes (return counts) ----
probe_apt() {
  local host="$1"
  # total upgradable
  local total=$(ssh_do "$host" "apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print \$2}' | wc -l")
  # security upgrades (heuristic by 'security' pocket)
  local sec=$(ssh_do "$host" "apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print \$0}' | grep -Ei 'security' | wc -l")
  # kernel updates (image/headers/generic)
  local kern=$(ssh_do "$host" "apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print \$2}' | grep -E '^linux-(image|headers|generic)' | wc -l")
  echo "$total $sec $kern"
}

probe_dnf() {
  local host="$1"
  local total=$(ssh_do "$host" "dnf -q check-update --refresh | awk '/^[[:alnum:]][[:alnum:]._+-]*[[:space:]]+[0-9]/{print \$1}' | wc -l" )
  local sec=$(ssh_do "$host" "dnf -q updateinfo --security list updates | grep -Ev '^(Last metadata|Updates Information Summary|$)' | wc -l" )
  local kern=$(ssh_do "$host" "dnf -q check-update kernel\\* | awk '/^[Kk]ernel/{print \$1}' | wc -l")
  echo "$total $sec $kern"
}

probe_yum() {
  local host="$1"
  local total=$(ssh_do "$host" "yum -q check-update | awk '/^[[:alnum:]][[:alnum:]._+-]*[[:space:]]+[0-9]/{print \$1}' | wc -l" )
  # security (best-effort; requires updateinfo metadata)
  local sec=$(ssh_do "$host" "yum -q updateinfo list security updates | grep -Ev '^(Loaded plugins|security:|$)' | wc -l" )
  local kern=$(ssh_do "$host" "yum -q check-update kernel | awk '/^[Kk]ernel/{print \$1}' | wc -l")
  echo "$total $sec $kern"
}

probe_zypper() {
  local host="$1"
  local total=$(ssh_do "$host" "zypper -q lu | tail -n +3 | wc -l")
  local sec=$(ssh_do "$host" "zypper -q lp -g security | tail -n +3 | wc -l")
  local kern=$(ssh_do "$host" "zypper -q lu | awk 'NR>2 && /kernel/{print}' | wc -l")
  echo "$total $sec $kern"
}

reboot_required() {
  local host="$1" pmgr="$2"
  # Ubuntu/Debian
  if [ "$pmgr" = "apt" ]; then
    ssh_do "$host" "[ -f /var/run/reboot-required ] && echo yes || echo no"
    return
  fi
  # RHEL/Fedora (dnf/yum) if needs-restarting exists
  if ssh_do "$host" "command -v needs-restarting >/dev/null"; then
    # exit 1 means reboot required
    ssh_do "$host" "needs-restarting -r >/dev/null 2>&1; if [ \$? -ne 0 ]; then echo yes; else echo no; fi"
    return
  fi
  # SUSE: use zypper ps (if any processes using deleted files)
  if [ "$pmgr" = "zypper" ]; then
    ssh_do "$host" "zypper -q ps -s | grep -q 'There are running processes' && echo yes || echo no"
    return
  fi
  # fallback unknown
  echo "unknown"
}

send_email_if_needed() {
  local subject="$1"
  local body="$2"

  [ "$EMAIL_ON_ACTION" = "true" ] || return 0
  [ -s "$ALERT_EMAILS" ] || return 0
  command -v mail >/dev/null || return 0

  while IFS= read -r to; do
    [ -n "$to" ] && printf "%s\n" "$body" | mail -s "$MAIL_SUBJECT_PREFIX $subject" "$to"
  done < "$ALERT_EMAILS"
}

check_host() {
  local host="$1"
  log "===== Checking patches on $host ====="

  # reachability
  if ! ssh_do "$host" "echo ok" | grep -q ok; then
    log "[$host] ERROR: SSH unreachable."
    return 1
  fi

  local os="$(remote_os "$host")"
  local mgr="$(remote_pkg_mgr "$host")"
  log "[$host] OS: $os | PkgMgr: $mgr"

  local total=0 sec=0 kern=0
  case "$mgr" in
    apt)    read total sec kern <<<"$(probe_apt "$host")" ;;
    dnf)    read total sec kern <<<"$(probe_dnf "$host")" ;;
    yum)    read total sec kern <<<"$(probe_yum "$host")" ;;
    zypper) read total sec kern <<<"$(probe_zypper "$host")" ;;
    *)      log "[$host] WARNING: Unsupported package manager."; return 0 ;;
  esac

  local reboot="$(reboot_required "$host" "$mgr")"

  log "[$host] Pending updates: total=$total, security=$sec, kernel=$kern, reboot_required=$reboot"

  # If action needed, email concise summary
  if { [ "$sec" -gt 0 ] || [ "$kern" -gt 0 ] || [ "$reboot" = "yes" ]; }; then
    local subj="$host: security=$sec kernel=$kern reboot=$reboot"
    local body="Host: $host
OS: $os
Package manager: $mgr
Pending updates: total=$total, security=$sec, kernel=$kern
Reboot required: $reboot

This is an automated notice from patch_monitor.sh."
    send_email_if_needed "$subj" "$body"
  fi

  log "===== Completed $host ====="
}

# ========================
# Main
# ========================
log "=== Patch Monitor Started ==="

if [ -f "$SERVERLIST" ]; then
  while IFS= read -r HOST; do
    [ -z "$HOST" ] && continue
    is_excluded "$HOST" && { log "Skipping $HOST (excluded)"; continue; }
    check_host "$HOST"
  done < "$SERVERLIST"
else
  # Local mode
  check_host "localhost"
fi

log "=== Patch Monitor Finished ==="
