#!/bin/bash
# ports_baseline_monitor.sh - Detect new/removed listening ports vs a baseline (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)

# ===== Shared helpers =====
. "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" || { echo "Missing ${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}"; exit 1; }
LM_PREFIX="[ports_baseline] "
LM_LOGFILE="${LM_LOGFILE:-/var/log/ports_baseline_monitor.log}"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; set >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle

lm_require_singleton "ports_baseline_monitor"

# If running unprivileged and /etc/linux_maint is not writable, skip to avoid failing CI/contract tests.
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
  if ! mkdir -p /etc/linux_maint 2>/dev/null; then
    echo "SKIP: requires root (cannot write /etc/linux_maint)"
    lm_summary "ports_baseline_monitor" "localhost" "SKIP" reason="unprivileged_no_etc"
    exit 0
  fi
fi

# ========================
# Script configuration
# ========================
BASELINE_DIR="/etc/linux_maint/baselines/ports"       # Per-host baselines live here
ALLOWLIST_FILE="/etc/linux_maint/ports_allowlist.txt"  # Optional allowlist

# Behavior flags
AUTO_BASELINE_INIT="true"       # If no baseline for a host, create it from current snapshot
BASELINE_UPDATE="false"         # If true, replace baseline with current snapshot after reporting
INCLUDE_PROCESS="true"          # Include process names in baseline when available

MAIL_SUBJECT_PREFIX='[Ports Baseline Monitor]'
EMAIL_ON_CHANGE="true"          # Send email when NEW/REMOVED entries are detected

# ========================
# Helpers (script-local)
# ========================
ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")" "$BASELINE_DIR"; }

mail_if_enabled(){
  [ "$EMAIL_ON_CHANGE" = "true" ] || return 0
  lm_mail "$1" "$2"
}

# Normalize "ss" output to "proto|port|proc"
collect_with_ss() {
  local host="$1"
  local out
  # Try with process info (-p) first (requires root on many distros), then without
  if [ "$INCLUDE_PROCESS" = "true" ]; then
    out="$(lm_ssh "$host" "ss -H -tulpen 2>/dev/null")"
  fi
  [ -z "$out" ] && out="$(lm_ssh "$host" "ss -H -tuln 2>/dev/null")"
  [ -z "$out" ] && { echo ""; return; }

  printf "%s\n" "$out" | awk -v incp="$INCLUDE_PROCESS" '
    BEGIN{FS="[[:space:]]+"}
    {
      proto=$1; local=$5; proc="-";
      # Extract port from Local Address:Port (IPv4/IPv6 safe: take text after last colon)
      port=local; sub(/^.*:/,"",port);
      # Extract process name from users:(("name",pid=..,fd=..))
      if (incp=="true") {
        if (match($0, /users:\(\(([^,"]+)/, m) && m[1] != "") proc=m[1];
      }
      print proto "|" port "|" proc
    }
  ' | sort -u
}

# Fallback using netstat
collect_with_netstat() {
  local host="$1"
  local out
  out="$(lm_ssh "$host" "netstat -tulpen 2>/dev/null || netstat -tuln 2>/dev/null")"
  [ -z "$out" ] && { echo ""; return; }
  printf "%s\n" "$out" | awk '
    BEGIN{IGNORECASE=1}
    /^Proto/ || /^Active/ {next}
    /^[tu]cp/ || /^[tu]dp/ {
      proto=$1; local=$4; prog="-";
      # Some netstat variants shift cols; find "PID/Program name" field
      for(i=1;i<=NF;i++){
        if($i ~ /[0-9]+\/[[:graph:]]+/){split($i,a,"/"); if(a[2]!="") prog=a[2]}
      }
      port=local; sub(/^.*:/,"",port);
      print proto "|" port "|" prog
    }
  ' | sort -u
}

collect_current() {
  local host="$1"
  local lines
  lines="$(collect_with_ss "$host")"
  [ -z "$lines" ] && lines="$(collect_with_netstat "$host")"
  printf "%s\n" "$lines" | sed '/^$/d'
}

# Allowlist match: "proto:port" or "proto:port:proc-substring" (case-insensitive for proc)
is_allowed() {
  local entry="$1"   # proto|port|proc
  local proto port proc rest
  proto="${entry%%|*}"
  rest="${entry#*|}"; port="${rest%%|*}"
  proc="${entry##*|}"

  [ -f "$ALLOWLIST_FILE" ] || return 1
  while IFS= read -r rule; do
    rule="$(echo "$rule" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$rule" ] && continue
    [[ "$rule" =~ ^# ]] && continue
    IFS=':' read -r rp rport rproc <<<"$rule"
    [ "$rp" = "$proto" ] || continue
    [ "$rport" = "$port" ] || continue
    if [ -n "$rproc" ]; then
      echo "$proc" | grep -iq -- "$rproc" || continue
    fi
    return 0
  done < "$ALLOWLIST_FILE"
  return 1
}

compare_and_report() {
  local host="$1" cur_file="$2" base_file="$3"
  local new_file removed_file
  new_file="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  removed_file="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"

  comm -13 "$base_file" "$cur_file" > "$new_file"
  comm -23 "$base_file" "$cur_file" > "$removed_file"

  # Filter NEW entries through allowlist
  local new_filtered; new_filtered="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  if [ -s "$new_file" ]; then
    while IFS= read -r e; do
      is_allowed "$e" && continue
      echo "$e"
    done < "$new_file" > "$new_filtered"
  else
    : > "$new_filtered"
  fi

  local changes=0

  if [ -s "$new_filtered" ]; then
    changes=1
    lm_info "[$host] NEW listening entries:"
    awk -F'|' '{printf "  + %s/%s (%s)\n",$1,$2,$3}' "$new_filtered" | while IFS= read -r L; do lm_info "$L"; done
  fi

  if [ -s "$removed_file" ]; then
    changes=1
    lm_info "[$host] REMOVED listening entries:"
    awk -F'|' '{printf "  - %s/%s (%s)\n",$1,$2,$3}' "$removed_file" | while IFS= read -r L; do lm_info "$L"; done
  fi

  if [ "$changes" -eq 1 ]; then
    local subj="Port changes on $host"
    local body="Host: $host

New entries:
$( [ -s "$new_filtered" ] && awk -F'|' '{printf "  + %s/%s (%s)\n",$1,$2,$3}' "$new_filtered" || echo "  (none)")

Removed entries:
$( [ -s "$removed_file" ] && awk -F'|' '{printf "  - %s/%s (%s)\n",$1,$2,$3}' "$removed_file" || echo "  (none)")

Note: allowlist from $ALLOWLIST_FILE applied to NEW entries."
    mail_if_enabled "$MAIL_SUBJECT_PREFIX $subj" "$body"
  fi

  rm -f "$new_file" "$removed_file" "$new_filtered"
  return 0
}

# ========================
# Per-host runner
# ========================
run_for_host() {
  local host="$1"
  lm_info "===== Checking ports on $host ====="

  local new_count=0
  local removed_count=0

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    lm_summary "ports_baseline_monitor" "$host" "CRIT" reason=ssh_unreachable new=0 removed=0
    lm_info "===== Completed $host ====="
    return 2
  fi

  local cur_file; cur_file="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  collect_current "$host" | sort -u > "$cur_file"

  if [ ! -s "$cur_file" ]; then
    lm_warn "[$host] No listening sockets detected."
  fi

  local base_file="$BASELINE_DIR/${host}.baseline"
  if [ ! -f "$base_file" ]; then
    if [ "$AUTO_BASELINE_INIT" = "true" ]; then
      cp -f "$cur_file" "$base_file"
      lm_info "[$host] Baseline created at $base_file (initial snapshot)."
      lm_summary "ports_baseline_monitor" "$host" "SKIP" reason=baseline_created new=0 removed=0
      rm -f "$cur_file"
      lm_info "===== Completed $host ====="
      return 0
    else
      lm_warn "[$host] Baseline missing ($base_file). Set AUTO_BASELINE_INIT=true or create it manually."
      lm_summary "ports_baseline_monitor" "$host" "SKIP" reason=baseline_missing new=0 removed=0
      rm -f "$cur_file"
      lm_info "===== Completed $host ====="
      return 0
    fi
  fi

  compare_and_report "$host" "$cur_file" "$base_file"

  # Counts for one-line summary (raw diffs; allowlist not applied here)
  new_count=$(comm -13 "$base_file" "$cur_file" 2>/dev/null | wc -l | tr -d ' ')
  removed_count=$(comm -23 "$base_file" "$cur_file" 2>/dev/null | wc -l | tr -d ' ')

  if [ "$BASELINE_UPDATE" = "true" ]; then
    cp -f "$cur_file" "$base_file"
    lm_info "[$host] Baseline updated."
  fi

  rm -f "$cur_file"
  lm_info "===== Completed $host ====="

  local status=OK
  if [ "$new_count" -gt 0 ] || [ "$removed_count" -gt 0 ]; then
    status=WARN
  fi
  lm_summary "ports_baseline_monitor" "$host" "$status" reason=ports_baseline_changed new=$new_count removed=$removed_count
  # legacy:
  # echo "ports_baseline_monitor host=$host status=$status new=$new_count removed=$removed_count"

}
# ========================
# Main
# ========================
ensure_dirs
lm_info "=== Ports Baseline Monitor Started ==="

lm_for_each_host_rc run_for_host
worst=$?
exit "$worst"

lm_info "=== Ports Baseline Monitor Finished ==="
