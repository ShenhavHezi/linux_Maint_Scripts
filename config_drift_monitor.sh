#!/bin/bash
# config_drift_monitor.sh - Detect drift in critical config files vs baseline (distributed)
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Hashes a configured set of config files (supports files, globs, directories, recursive),
#   compares against a per-host baseline, and reports:
#     - MODIFIED files (hash changed)
#     - NEW files (present now, absent in baseline)
#     - REMOVED files (present in baseline, missing now)
#   Supports an allowlist, optional baseline auto-init/update, and email alerts.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"              # One host per line; if missing → local mode
EXCLUDED="/etc/linux_maint/excluded.txt"               # Optional: hosts to skip
CONFIG_PATHS="/etc/linux_maint/config_paths.txt"       # Targets (files/dirs/globs); see README
ALLOWLIST_FILE="/etc/linux_maint/config_allowlist.txt" # Optional: paths to ignore (exact or substring)
BASELINE_DIR="/etc/linux_maint/baselines/configs"      # Per-host baselines live here
ALERT_EMAILS="/etc/linux_maint/emails.txt"             # Optional: recipients (one per line)

LOGFILE="/var/log/config_drift_monitor.log"            # Report log
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no"

# Behavior
AUTO_BASELINE_INIT="true"     # If baseline missing for a host, create it from current snapshot
BASELINE_UPDATE="false"       # After reporting, accept current as new baseline
EMAIL_ON_DRIFT="true"         # Send email when drift detected

MAIL_SUBJECT_PREFIX='[Config Drift Monitor]'

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
  [ "$EMAIL_ON_DRIFT" = "true" ] || return 0
