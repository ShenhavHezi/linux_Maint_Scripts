#!/usr/bin/env bash
# linux_maint.sh - Shared helpers for Linux_Maint_Scripts
# Author: Shenhav_Hezi
# Version: 1.0
# Usage:
#   . /usr/local/lib/linux_maint.sh   # source at the top of your script
# Quick integration recipe:
# Install the lib (Require only once)
# sudo mkdir -p /usr/local/lib
# sudo cp lib/linux_maint.sh /usr/local/lib/linux_maint.sh
# sudo chmod 0644 /usr/local/lib/linux_maint.sh

# ========= Strict mode (safe defaults) =========
set -o pipefail

# ========= Defaults (overridable via env from the caller script) =========
: "${LM_LOGFILE:=/var/log/linux_maint.log}"
: "${LM_EMAILS:=/etc/linux_maint/emails.txt}"
: "${LM_EXCLUDED:=/etc/linux_maint/excluded.txt}"
: "${LM_SERVERLIST:=/etc/linux_maint/servers.txt}"
: "${LM_HOSTS_DIR:=/etc/linux_maint/hosts.d}"   # optional host groups directory
: "${LM_GROUP:=}"                          # optional group name (maps to $LM_HOSTS_DIR/<group>.txt)
: "${LM_LOCKDIR:=/var/lock}"
: "${LM_STATE_DIR:=/var/tmp}"
: "${LM_SSH_OPTS:=-o BatchMode=yes -o ConnectTimeout=7 -o StrictHostKeyChecking=no}"
: "${LM_EMAIL_ENABLED:=true}"      # scripts can set LM_EMAIL_ENABLED=false to suppress email
: "${LM_MAX_PARALLEL:=0}"          # 0 = sequential
: "${LM_PREFIX:=}"                 # optional log prefix (script can set)

# ========= Pretty timestamps =========
lm_ts() { date '+%Y-%m-%d %H:%M:%S'; }

# ========= Logging =========
# lm_log LEVEL MSG...
lm_log() {
  local lvl="$1"; shift
  local line
  line="$(lm_ts) - ${LM_PREFIX}${lvl} - $*"
  # print to stdout and append to LM_LOGFILE (create parent dir if needed)
  mkdir -p "$(dirname "$LM_LOGFILE")" 2>/dev/null || true
  echo "$line" | tee -a "$LM_LOGFILE" >/dev/null
}
lm_info(){ lm_log INFO "$@"; }
lm_warn(){ lm_log WARN "$@"; }
lm_err(){  lm_log ERROR "$@"; }
lm_die(){  lm_err "$@"; exit 1; }

# ========= Locking (prevent overlapping runs) =========
# Usage: lm_require_singleton myscript      → exits if already running
lm_require_singleton() {
  local name="$1"
  mkdir -p "$LM_LOCKDIR" 2>/dev/null || true
  exec {__lm_lock_fd}>"$LM_LOCKDIR/${name}.lock" || lm_die "Cannot open lock file"
  if ! flock -n "$__lm_lock_fd"; then
    lm_warn "Another ${name} is already running; exiting."
    exit 0
  fi
}

# ========= Email =========
lm_mail() {
  local subject="$1" body="$2"
  [ "$LM_EMAIL_ENABLED" = "true" ] || return 0
  [ -s "$LM_EMAILS" ] || { lm_warn "Email list $LM_EMAILS missing/empty; skipping email"; return 0; }
  command -v mail >/dev/null || { lm_warn "mail command not found; skipping email"; return 0; }
  while IFS= read -r to; do
    [ -n "$to" ] && printf "%s\n" "$body" | mail -s "$subject" "$to"
  done < "$LM_EMAILS"
}

# ========= SSH helpers =========
# lm_ssh HOST CMD...
lm_ssh() {
  local host="$1"; shift
  if [ "$host" = "localhost" ] || [ "$host" = "127.0.0.1" ]; then
    bash -lc "$*" 2>/dev/null
  else
    # LM_SSH_OPTS may contain multiple ssh arguments. Split intentionally into an array.
    local -a _ssh_opts=()
    # shellcheck disable=SC2206
    _ssh_opts=(${LM_SSH_OPTS:-})
    # shellcheck disable=SC2029
    ssh "${_ssh_opts[@]}" "$host" "$@" 2>/dev/null
  fi
}
# quick reachability probe (0=ok)
lm_reachable() { lm_ssh "$1" "echo ok" | grep -q ok; }

# ========= Exclusions & host list =========
lm_is_excluded() { [ -f "$LM_EXCLUDED" ] && grep -Fxq "$1" "$LM_EXCLUDED"; }
# yields hosts to stdout (one per line)
lm_hosts() {
  # Host selection precedence:
  #  1) LM_GROUP=<name> and $LM_HOSTS_DIR/<name>.txt exists
  #  2) LM_SERVERLIST (default /etc/linux_maint/servers.txt)
  #  3) fallback: localhost

  local group_file=""
  if [ -n "${LM_GROUP:-}" ]; then
    group_file="${LM_HOSTS_DIR:-/etc/linux_maint/hosts.d}/${LM_GROUP}.txt"
    if [ -f "$group_file" ]; then
      grep -vE '^[[:space:]]*($|#)' "$group_file"
      return 0
    else
      lm_warn "LM_GROUP set to '${LM_GROUP}' but group file not found: $group_file"
    fi
  fi

  if [ -f "$LM_SERVERLIST" ]; then
    grep -vE '^[[:space:]]*($|#)' "$LM_SERVERLIST"
  else
    echo "localhost"
  fi
}



# ========= Timeout wrapper =========
# Usage: lm_timeout 5s bash -lc 'df -h'
lm_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$@"
  else
    bash -lc "${*:2}"
  fi
}

# ========= CSV row selector (common pattern) =========
# Prints rows from CSV where column1 matches $2 or "*" and has at least $3 columns.
lm_csv_rows_for_host() {
  local file="$1" host="$2" mincols="${3:-1}"
  [ -s "$file" ] || return 0
  awk -F',' -v H="$host" -v N="$mincols" '
    /^[[:space:]]*#/ {next}
    NF>=N {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1)
      if($1==H || $1=="*") print $0
    }' "$file"
}

# ========= Platform detection =========
lm_platform() {
  case "$(uname -s 2>/dev/null)" in
    Linux) echo linux;;
    AIX)   echo aix;;
    *)     echo unknown;;
  esac
}

# ========= Small job-pool for per-host parallelism =========
# Usage: lm_for_each_host my_function   (function will be called with $host)
lm_for_each_host() {
  local fn="$1"
  local -a PIDS=()
  local running=0

  while read -r HOST; do
    [ -z "$HOST" ] && continue
    lm_is_excluded "$HOST" && { lm_info "Skipping $HOST (excluded)"; continue; }

    if [ "${LM_MAX_PARALLEL:-0}" -gt 0 ]; then
      # background with simple pool
      "$fn" "$HOST" &
      PIDS+=($!)
      running=$((running+1))
      if [ "$running" -ge "$LM_MAX_PARALLEL" ]; then
        wait -n
        running=$((running-1))
      fi
    else
      "$fn" "$HOST"
    fi
  done < <(lm_hosts)

  # wait remaining
  if [ "${#PIDS[@]}" -gt 0 ]; then
    wait "${PIDS[@]}" 2>/dev/null || true
  fi
}

# ========= Standard summary line =========
# Usage: lm_summary <monitor_name> <status> [key=value ...]
# Prints a single machine-parseable line.
# Example:
#   lm_summary "patch_monitor" "WARN" total=5 security=2 reboot_required=unknown
# ========= Standard summary line =========
# Usage: lm_summary <monitor_name> <target_host> <status> [key=value ...]
# Prints a single machine-parseable line.
# Example:
#   lm_summary "patch_monitor" "$host" "WARN" total=5 security=2 reboot_required=unknown
lm_summary() {
  local monitor="$1" target_host="$2" status="$3"; shift 3
  local node
  node="$(hostname -f 2>/dev/null || hostname)"
  # shellcheck disable=SC2086
  echo "monitor=${monitor} host=${target_host} status=${status} node=${node} $*" | sed "s/[[:space:]]\+/ /g; s/[[:space:]]$//"
}
