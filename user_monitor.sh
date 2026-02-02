#!/bin/bash
# user_monitor.sh - Monitor user and SSH access across multiple servers
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   - Detects NEW/REMOVED system users vs a per-host baseline.
#   - Detects sudoers file changes vs a per-host baseline.
#   - Counts failed SSH logins (journalctl preferred, log files fallback) and alerts on thresholds.
#   - Runs locally or across hosts defined in servers.txt.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[user_monitor] "
LM_LOGFILE="/var/log/user_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; set >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle

lm_require_singleton "user_monitor"

MAIL_SUBJECT_PREFIX='[User Monitor]'

# ========================
# Script configuration
# ========================
USERS_BASELINE_DIR="/etc/linux_maint/baselines/users"       # per-host: ${host}.users
SUDO_BASELINE_DIR="/etc/linux_maint/baselines/sudoers"      # per-host: ${host}.sudoers
AUTO_BASELINE_INIT="true"    # create baseline on first run
BASELINE_UPDATE="false"      # update baseline to current after reporting
EMAIL_ON_ALERT="true"        # send email if anomalies are detected

# User selection (default: all users). To focus on human users set USER_MIN_UID=1000.
: "${USER_MIN_UID:=0}"       # include users with UID >= USER_MIN_UID, plus 'root'

# Failed SSH login thresholds (lookback window uses journalctl when available)
FAILED_WINDOW_HOURS=24
FAILED_WARN=10
FAILED_CRIT=50

# ========================
# Helpers (script-local)
# ========================
ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")" "$USERS_BASELINE_DIR" "$SUDO_BASELINE_DIR"; }

ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" user_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

mail_if_enabled(){ [ "$EMAIL_ON_ALERT" = "true" ] || return 0; lm_mail "$1" "$2"; }

# --- Remote collectors ---
collect_users_cmd='
min_uid="$1"
awk -F: -v m="$min_uid" '\''($3>=m || $1=="root"){print $1}'\'' /etc/passwd 2>/dev/null | sort -u
'

sudoers_hash_cmd='
hashbin="$(command -v sha256sum || command -v md5sum)"
[ -r /etc/sudoers ] || { echo ""; exit 0; }
"$hashbin" /etc/sudoers 2>/dev/null | awk "{print \$1}"
'

failed_ssh_cmd='
hrs="$1"
if command -v journalctl >/dev/null 2>&1; then
  journalctl -S "-${hrs}h" -u ssh -u sshd 2>/dev/null | grep -c "Failed password" || true
else
  # Fallback: best-effort (not strictly time-bounded)
  { grep -h "Failed password" /var/log/auth.log /var/log/secure 2>/dev/null || true; } | wc -l
fi
'

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Starting checks on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    lm_info "===== Completed $host ====="
    return
  fi

  # ---------- Users ----------
  local users_current users_base users_base_file
  users_base_file="$USERS_BASELINE_DIR/${host}.users"
  users_current="$(lm_ssh "$host" bash -lc "$collect_users_cmd" _ "$USER_MIN_UID")"

  if [ -z "$users_current" ]; then
    lm_err "[$host] unable to collect user list"
  else
    if [ ! -f "$users_base_file" ]; then
      if [ "$AUTO_BASELINE_INIT" = "true" ]; then
        printf "%s\n" "$users_current" > "$users_base_file"
        lm_info "[$host] users baseline created at $users_base_file"
      else
        lm_warn "[$host] users baseline missing ($users_base_file)"
      fi
    else
      users_base="$(cat "$users_base_file")"
      local new_users removed_users
      new_users="$(comm -13 <(printf "%s\n" "$users_base") <(printf "%s\n" "$users_current"))"
      removed_users="$(comm -23 <(printf "%s\n" "$users_base") <(printf "%s\n" "$users_current"))"

      if [ -n "$new_users" ]; then
        while IFS= read -r u; do
          [ -n "$u" ] && append_alert "$host|user_new|$u"
        done <<< "$new_users"
        lm_warn "[$host] NEW users: $(echo "$new_users" | paste -sd',' -)"
      fi
      if [ -n "$removed_users" ]; then
        while IFS= read -r u; do
          [ -n "$u" ] && append_alert "$host|user_removed|$u"
        done <<< "$removed_users"
        lm_warn "[$host] REMOVED users: $(echo "$removed_users" | paste -sd',' -)"
      fi

      [ "$BASELINE_UPDATE" = "true" ] && { printf "%s\n" "$users_current" > "$users_base_file"; lm_info "[$host] users baseline updated."; }
    fi
  fi

  # ---------- Sudoers ----------
  local sudo_hash sudo_base sudo_base_file
  sudo_base_file="$SUDO_BASELINE_DIR/${host}.sudoers"
  sudo_hash="$(lm_ssh "$host" bash -lc "$sudoers_hash_cmd")"

  if [ -z "$sudo_hash" ]; then
    lm_warn "[$host] sudoers hash unavailable (no file or no permissions)"
  else
    if [ ! -f "$sudo_base_file" ]; then
      if [ "$AUTO_BASELINE_INIT" = "true" ]; then
        echo "$sudo_hash" > "$sudo_base_file"
        lm_info "[$host] sudoers baseline created at $sudo_base_file"
      else
        lm_warn "[$host] sudoers baseline missing ($sudo_base_file)"
      fi
    else
      sudo_base="$(cat "$sudo_base_file")"
      if [ "$sudo_hash" != "$sudo_base" ]; then
        lm_err "[$host] sudoers file changed (baseline vs current)"
        append_alert "$host|sudoers_changed|old=${sudo_base:0:8} new=${sudo_hash:0:8}"
        [ "$BASELINE_UPDATE" = "true" ] && { echo "$sudo_hash" > "$sudo_base_file"; lm_info "[$host] sudoers baseline updated."; }
      else
        lm_info "[$host] sudoers unchanged"
      fi
    fi
  fi

  # ---------- Failed SSH logins ----------
  local failed failed_status="OK"
  failed="$(lm_ssh "$host" bash -lc "$failed_ssh_cmd" _ "$FAILED_WINDOW_HOURS")"
  [ -z "$failed" ] && failed=0

  if [ "$failed" -ge "$FAILED_CRIT" ]; then
    failed_status="CRIT"
    append_alert "$host|failed_ssh|CRIT:$failed in ${FAILED_WINDOW_HOURS}h"
  elif [ "$failed" -ge "$FAILED_WARN" ]; then
    failed_status="WARN"
    append_alert "$host|failed_ssh|WARN:$failed in ${FAILED_WINDOW_HOURS}h"
  fi
  lm_info "[$host] failed SSH logins last ${FAILED_WINDOW_HOURS}h: $failed ($failed_status)"

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
ensure_dirs
lm_info "=== User Monitor Script Started ==="

lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="User/sudoers/SSH anomalies detected"
  body="Host | Category | Detail
-----|----------|-------
$(echo "$alerts" | awk -F'|' 'NF>=3{printf "%s | %s | %s\n",$1,$2,$3}') 

Window: last ${FAILED_WINDOW_HOURS}h; thresholds WARN=${FAILED_WARN}, CRIT=${FAILED_CRIT}
Baselines: users=${USERS_BASELINE_DIR}/<host>.users, sudoers=${SUDO_BASELINE_DIR}/<host>.sudoers
Baseline init=${AUTO_BASELINE_INIT}, update=${BASELINE_UPDATE}"
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== User Monitor Script Finished ==="
