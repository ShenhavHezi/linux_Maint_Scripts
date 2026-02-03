#!/usr/bin/env bash
# config_validate.sh - Validate /etc/linux_maint configuration files (best-effort)
# Author: Shenhav_Hezi
# Version: 1.0

set -euo pipefail

. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[config_validate] "
LM_LOGFILE="/var/log/config_validate.log"

lm_require_singleton "config_validate"

CFG_DIR="/etc/linux_maint"

warn=0
crit=0

ok(){ lm_info "OK  $*"; }
wa(){ lm_warn "WARN $*"; warn=$((warn+1)); }
cr(){ lm_err  "CRIT $*"; crit=$((crit+1)); }

check_csv_cols(){
  local file="$1" mincols="$2" name="$3"
  [ -s "$file" ] || { wa "$name missing/empty: $file"; return; }
  local bad
  bad=$(awk -F',' -v N="$mincols" '
    /^[[:space:]]*#/ {next}
    NF==0 {next}
    NF<N {print NR":"$0}
  ' "$file" | head -n 5)
  if [ -n "$bad" ]; then
    cr "$name has rows with <${mincols} columns: $file (examples: $bad)"
  else
    ok "$name format looks OK: $file"
  fi
}

check_list(){
  local file="$1" name="$2"
  [ -s "$file" ] || { wa "$name missing/empty: $file"; return; }
  ok "$name present: $file"
}

# Validate network_targets.txt
validate_network(){
  local f="$CFG_DIR/network_targets.txt"
  [ -s "$f" ] || { wa "network_targets missing/empty: $f"; return; }
  local bad
  bad=$(awk -F',' '
    /^[[:space:]]*#/ {next}
    NF==0 {next}
    NF<3 {print NR":"$0; next}
    {c=$2; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c);
     if(c!="ping" && c!="tcp" && c!="http") print NR":"$0}
  ' "$f" | head -n 5)
  if [ -n "$bad" ]; then
    cr "network_targets invalid rows (need >=3 cols and check in ping|tcp|http): $bad"
  else
    ok "network_targets format looks OK: $f"
  fi
}

# Validate backup_targets.csv (host,pattern,max_age_hours,min_size_mb,verify) or similar
validate_backup(){
  local f="$CFG_DIR/backup_targets.csv"
  [ -s "$f" ] || { wa "backup_targets missing/empty: $f"; return; }
  local bad
  bad=$(awk -F',' '
    /^[[:space:]]*#/ {next}
    NF==0 {next}
    NF<5 {print NR":"$0}
  ' "$f" | head -n 5)
  if [ -n "$bad" ]; then
    cr "backup_targets rows with <5 columns: $bad"
  else
    ok "backup_targets format looks OK: $f"
  fi
}

validate_certs(){
  local f="$CFG_DIR/certs.txt"
  [ -s "$f" ] || { wa "certs missing/empty (cert monitor will check 0): $f"; return; }
  ok "certs file present: $f"
}

validate(){
  mkdir -p "$(dirname "$LM_LOGFILE")" || true

  check_list "$CFG_DIR/servers.txt" "servers"
  check_list "$CFG_DIR/services.txt" "services"

  validate_network
  validate_backup
  validate_certs

  check_list "$CFG_DIR/config_paths.txt" "config_paths"

  # gates
  if [ -s "$CFG_DIR/ports_baseline.txt" ]; then
    ok "ports_baseline gate present"
  else
    wa "ports_baseline gate missing: $CFG_DIR/ports_baseline.txt"
  fi

  if [ "$crit" -gt 0 ]; then
    echo "config_validate status=CRIT warn=$warn crit=$crit"
    exit 2
  fi
  if [ "$warn" -gt 0 ]; then
    echo "config_validate status=WARN warn=$warn crit=$crit"
    exit 1
  fi
  echo "config_validate status=OK warn=$warn crit=$crit"
  exit 0
}

validate "$@" | tee -a "$LM_LOGFILE" >/dev/null
