#!/bin/bash
# patch_monitor.sh - Check pending OS updates and reboot requirements (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Scans one or many Linux servers for:
#     - total pending updates
#     - security updates
#     - kernel updates
#     - reboot-required state
#   Works across distros (APT/DNF/YUM/ZYPPER) and logs a concise report.
#   Optionally emails a per-host summary when action is required.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[patch_monitor] "
LM_LOGFILE="/var/log/patch_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; >0 run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master toggle for lm_mail

lm_require_singleton "patch_monitor"

MAIL_SUBJECT_PREFIX='[Patch Monitor]'
EMAIL_ON_ACTION="true"        # Email only if host has security updates OR kernel updates OR reboot required

# ========================
# Helpers (script-local)
# ========================
mail_if_enabled(){ [ "$EMAIL_ON_ACTION" = "true" ] || return 0; lm_mail "$1" "$2"; }

remote_pkg_mgr() {
  local host="$1"
  if lm_ssh "$host" "command -v apt-get >/dev/null"; then echo "apt"; return; fi
  if lm_ssh "$host" "command -v dnf >/dev/null";     then echo "dnf"; return; fi
  if lm_ssh "$host" "command -v yum >/dev/null";     then echo "yum"; return; fi
  if lm_ssh "$host" "command -v zypper >/dev/null";  then echo "zypper"; return; fi
  echo "unknown"
}

remote_os() {
  local host="$1"
  lm_ssh "$host" bash -lc 'source /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -sr'
}

# ---- Per-manager probes (echo: "total security kernel") ----
probe_apt() {
  local host="$1"
  local total sec kern
  total=$(lm_ssh "$host" "apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print \$2}' | wc -l")
  sec=$(lm_ssh "$host" "apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print \$0}' | grep -Ei 'security' | wc -l")
  kern=$(lm_ssh "$host" "apt-get -s upgrade 2>/dev/null | awk '/^Inst /{print \$2}' | grep -E '^linux-(image|headers|generic)' | wc -l")
  echo "${total:-0} ${sec:-0} ${kern:-0}"
}

probe_dnf() {
  local host="$1"
  local total sec kern
  total=$(lm_ssh "$host" "dnf -q check-update --refresh | awk '/^[[:alnum:]][[:alnum:]._+-]*[[:space:]]+[0-9]/{print \$1}' | wc -l")
  sec=$(lm_ssh "$host" "dnf -q updateinfo --security list updates | grep -Ev '^(Last metadata|Updates Information Summary|$)' | wc -l")
  kern=$(lm_ssh "$host" "dnf -q check-update 'kernel*' | awk '/^[Kk]ernel/{print \$1}' | wc -l")
  echo "${total:-0} ${sec:-0} ${kern:-0}"
}

probe_yum() {
  local host="$1"
  local total sec kern
  total=$(lm_ssh "$host" "yum -q check-update | awk '/^[[:alnum:]][[:alnum:]._+-]*[[:space:]]+[0-9]/{print \$1}' | wc -l")
  sec=$(lm_ssh "$host" "yum -q updateinfo list security updates | grep -Ev '^(Loaded plugins|security:|$)' | wc -l")
  kern=$(lm_ssh "$host" "yum -q check-update kernel | awk '/^[Kk]ernel/{print \$1}' | wc -l")
  echo "${total:-0} ${sec:-0} ${kern:-0}"
}

probe_zypper() {
  local host="$1"
  local total sec kern
  total=$(lm_ssh "$host" "zypper -q lu | tail -n +3 | wc -l")
  sec=$(lm_ssh "$host" "zypper -q lp -g security | tail -n +3 | wc -l")
  kern=$(lm_ssh "$host" "zypper -q lu | awk 'NR>2 && /kernel/{print}' | wc -l")
  echo "${total:-0} ${sec:-0} ${kern:-0}"
}

reboot_required() {
  local host="$1" pmgr="$2"
  case "$pmgr" in
    apt)
      lm_ssh "$host" "[ -f /var/run/reboot-required ] && echo yes || echo no"
      return
      ;;
  esac
  if lm_ssh "$host" "command -v needs-restarting >/dev/null"; then
    lm_ssh "$host" 'needs-restarting -r >/dev/null 2>&1; if [ $? -ne 0 ]; then echo yes; else echo no; fi'
    return
  fi
  if [ "$pmgr" = "zypper" ]; then
    lm_ssh "$host" "zypper -q ps -s | grep -q 'There are running processes' && echo yes || echo no"
    return
  fi
  echo "unknown"
}

# ========================
# Per-host runner
# ========================
run_for_host() {
  local host="$1"
  lm_info "===== Checking patches on $host ====="

  local status=OK

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable; skipping"
    lm_info "===== Completed $host ====="
    return
  fi

  local os mgr
  os="$(remote_os "$host")"
  mgr="$(remote_pkg_mgr "$host")"
  lm_info "[$host] OS: $os | PkgMgr: $mgr"

  local total=0 sec=0 kern=0
  case "$mgr" in
    apt)    read -r total sec kern <<<"$(probe_apt "$host")" ;;
    dnf)    read total sec kern <<<"$(probe_dnf "$host")" ;;
    yum)    read total sec kern <<<"$(probe_yum "$host")" ;;
    zypper) read total sec kern <<<"$(probe_zypper "$host")" ;;
    *)      lm_warn "[$host] Unsupported package manager; skipping"; lm_info "===== Completed $host ====="; return ;;
  esac

  local reboot; reboot="$(reboot_required "$host" "$mgr")"

  lm_info "[$host] Pending updates: total=$total, security=$sec, kernel=$kern, reboot_required=$reboot"


  if [ "${sec:-0}" -gt 0 ] || [ "${kern:-0}" -gt 0 ] || [ "$reboot" = "yes" ]; then
    status=WARN
  fi

  # Per-host email if action needed
  if { [ "${sec:-0}" -gt 0 ] || [ "${kern:-0}" -gt 0 ] || [ "$reboot" = "yes" ]; }; then
    local subj="$host: security=${sec:-0} kernel=${kern:-0} reboot=$reboot"
    local body="Host: $host
OS: $os
Package manager: $mgr
Pending updates: total=${total:-0}, security=${sec:-0}, kernel=${kern:-0}
Reboot required: $reboot

This is an automated notice from patch_monitor.sh."
    mail_if_enabled "$MAIL_SUBJECT_PREFIX $subj" "$body"
  fi
  echo patch_monitor host=$host status=$status total=${total:-0} security=${sec:-0} kernel=${kern:-0} reboot_required=$reboot



  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
lm_info "=== Patch Monitor Started ==="
lm_for_each_host run_for_host
lm_info "=== Patch Monitor Finished ==="
