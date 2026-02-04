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

# ========= Wrapper-level notification (single email summary per run) =========
# Optional; designed to be called by the wrapper script (run_full_health_monitor.sh).
#
# Config precedence:
#   1) environment variables (LM_NOTIFY, LM_NOTIFY_TO, etc)
#   2) /etc/linux_maint/notify.conf (simple KEY=VALUE lines)
#
# Supported keys:
#   LM_NOTIFY=0|1
#   LM_NOTIFY_TO="a@b,c@d"   (comma/space separated)
#   LM_NOTIFY_ONLY_ON_CHANGE=0|1
#   LM_NOTIFY_SUBJECT_PREFIX="[linux_maint]"
#   LM_NOTIFY_STATE_DIR="/var/lib/linux_maint"
#
lm_load_notify_conf() {
  local conf="${LM_NOTIFY_CONF:-/etc/linux_maint/notify.conf}"
  [ -f "$conf" ] || return 0
  # shellcheck disable=SC1090
  set -a
  # shellcheck disable=SC1090
  . "$conf" || true
  set +a
}

lm_notify_should_send() {
  local summary_text="$1"

  local enabled="${LM_NOTIFY:-0}"
  [ "$enabled" = "1" ] || [ "$enabled" = "true" ] || return 1

  local to="${LM_NOTIFY_TO:-}"
  [ -n "$to" ] || { lm_warn "LM_NOTIFY enabled but LM_NOTIFY_TO is empty; skipping notify"; return 1; }

  local only_change="${LM_NOTIFY_ONLY_ON_CHANGE:-0}"
  if [ "$only_change" = "1" ] || [ "$only_change" = "true" ]; then
    local state_dir="${LM_NOTIFY_STATE_DIR:-${LM_STATE_DIR:-/var/lib/linux_maint}}"
    mkdir -p "$state_dir" 2>/dev/null || true
    local state_file="$state_dir/last_summary.sha256"
    local cur
    cur="$(printf "%s" "$summary_text" | sha256sum | awk '{print $1}')"
    if [ -f "$state_file" ]; then
      local prev
      prev="$(cat "$state_file" 2>/dev/null || true)"
      if [ "$cur" = "$prev" ]; then
        return 1
      fi
    fi
    printf "%s\n" "$cur" > "$state_file" 2>/dev/null || true
  fi

  return 0
}

lm_notify_send() {
  local subject="$1" body="$2"

  local to="${LM_NOTIFY_TO:-}"
  local prefix="${LM_NOTIFY_SUBJECT_PREFIX:-[linux_maint]}"

  # Choose a transport; try common options.
  if command -v mail >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    # shellcheck disable=SC2086
    # shellcheck disable=SC2046
    set -- $(echo "$to" | tr "," " ")
    printf "%s\n" "$body" | mail -s "${prefix} ${subject}" "$@"
    return 0
  fi

  if command -v sendmail >/dev/null 2>&1; then
    local from="${LM_NOTIFY_FROM:-linux_maint@$(hostname -f 2>/dev/null || hostname)}"
    {
      echo "From: $from"
      echo "To: $to"
      echo "Subject: ${prefix} ${subject}"
      echo ""
      echo "$body"
    } | sendmail -t
    return 0
  fi

  lm_warn "No supported mail transport found (mail/sendmail); skipping notify"
  return 0
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
