#!/bin/bash
# log_growth_guard.sh - Detect oversized / fast-growing logs (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Scans one or many Linux servers and checks configured log files/sets for:
#     - absolute size thresholds (WARN/CRIT)
#     - growth rate since last run (MB/hour; WARN/CRIT)
#   Keeps a per-host state file with previous sizes/timestamps,
#   logs a concise report, and can send aggregated email alerts.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[log_growth_guard] "
LM_LOGFILE="/var/log/log_growth_guard.log"
: "${LM_MAX_PARALLEL:=0}"     # 0 = sequential; >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle

lm_require_singleton "log_growth_guard"

MAIL_SUBJECT_PREFIX='[Log Growth Guard]'

# ========================
# Configuration
# ========================
LOG_PATHS="/etc/linux_maint/log_paths.txt"    # Patterns: file | dir/ | dir/** | globs (*.log)
STATE_DIR="${LM_STATE_DIR:-/var/tmp}"         # Where per-host state lives

# Size thresholds (in MB)
: "${SIZE_WARN_MB:=1024}"
: "${SIZE_CRIT_MB:=2048}"

# Growth rate thresholds (in MB per hour)
: "${RATE_WARN_MBPH:=200}"
: "${RATE_CRIT_MBPH:=500}"

EMAIL_ON_ALERT="true"                          # Send aggregated email if any WARN/CRIT
AUTO_ROTATE="false"                            # If true, execute ROTATE_CMD on offending host/path
ROTATE_CMD=""                                  # e.g., 'logrotate -f /etc/logrotate.d/myapp' OR 'cp /dev/null "{file}"'
                                               # Tip: use the placeholder {file} to inject the matched file path safely.

# ========================
# Helpers (script-local)
# ========================
mail_if_enabled(){ [ "$EMAIL_ON_ALERT" = "true" ] || return 0; lm_mail "$1" "$2"; }
ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")" "$STATE_DIR"; }

rate_status() {
  # $1=size_mb (int), $2=rate_mbph (float or '?')
  local size_mb="$1" rate_mbph="$2" st="OK"
  # Size gates
  if [ "$size_mb" -ge "$SIZE_CRIT_MB" ]; then
    st="CRIT"
  elif [ "$size_mb" -ge "$SIZE_WARN_MB" ]; then
    st="WARN"
  fi
  # Rate gates (worst wins)
  if [ "$rate_mbph" != "?" ]; then
    if awk "BEGIN{exit !($rate_mbph >= $RATE_CRIT_MBPH)}"; then
      st="CRIT"
    elif awk "BEGIN{exit !($rate_mbph >= $RATE_WARN_MBPH)}"; then
      [ "$st" = "OK" ] && st="WARN"
    fi
  fi
  echo "$st"
}

rotate_if_enabled() {
  # $1=host, $2=path
  [ "$AUTO_ROTATE" = "true" ] || return 0
  [ -n "$ROTATE_CMD" ] || return 0
  local host="$1" path="$2" cmd
  # Safely inject file path using {file} placeholder
  if printf "%s" "$ROTATE_CMD" | grep -q "{file}"; then
    # Escape the path for shell
    local esc; esc="$(printf "%q" "$path")"
    cmd="${ROTATE_CMD//\{file\}/$esc}"
    lm_info "[$host] rotate_cmd: $cmd"
    lm_ssh "$host" bash -lc "$cmd" || lm_warn "[$host] rotate_cmd failed for $path"
  else
    # No placeholder: execute as-is (for handlers like logrotate configs)
    lm_info "[$host] rotate_cmd (no {file} placeholder): $ROTATE_CMD"
    lm_ssh "$host" bash -lc "$ROTATE_CMD" || lm_warn "[$host] rotate_cmd failed"
  fi
}

# ---- Remote collector: prints "path|size_bytes|mtime_epoch" for a pattern ($1)
read -r -d '' remote_collect_cmd <<'EOS'
p="$1"
emit() { f="$1"; [ -f "$f" ] || return; s=$(stat -c %s "$f" 2>/dev/null || echo 0); t=$(stat -c %Y "$f" 2>/dev/null || date +%s); printf "%s|%s|%s\n" "$f" "$s" "$t"; }
if [[ "$p" == */** ]]; then
  base="${p%/**}"
  [ -d "$base" ] && find "$base" -type f -printf "%p|%s|%T@\n" 2>/dev/null | awk 'BEGIN{FS="|"}{printf "%s|%s|%d\n",$1,$2,int($3)}'
elif [[ "$p" == */ ]]; then
  dir="${p%/}"
  [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -printf "%p|%s|%T@\n" 2>/dev/null | awk 'BEGIN{FS="|"}{printf "%s|%s|%d\n",$1,$2,int($3)}'
elif [[ "$p" == *"*"* || "$p" == *"?"* ]]; then
  shopt -s nullglob dotglob
  for f in $p; do emit "$f"; done
else
  emit "$p"
fi
EOS

collect_for_host() {
  local host="$1"
  [ -s "$LOG_PATHS" ] || { lm_err "[$host] log paths file missing/empty: $LOG_PATHS"; echo ""; return; }
  local lines="" pat out
  while IFS= read -r pat; do
    pat="$(echo "$pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$pat" ] && continue
    [[ "$pat" =~ ^# ]] && continue
    out="$(lm_ssh "$host" bash -lc "$remote_collect_cmd" _ "$pat")"
    [ -n "$out" ] && lines+="$out"$'\n'
  done < "$LOG_PATHS"
  printf "%s" "$lines" | sed '/^$/d'
}

# ========================
# Aggregation
# ========================
ALERTS_FILE="$(mktemp -p "${STATE_DIR}" log_growth_guard.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

# ========================
# Per-host runner
# ========================
run_for_host() {
  local host="$1"
  lm_info "===== Checking log growth on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    lm_info "===== Completed $host ====="
    return
  fi

  local now; now="$(date +%s)"
  local state="${STATE_DIR}/log_growth_guard.${host}.state"
  local prev="${STATE_DIR}/log_growth_guard.${host}.prev"
  [ -f "$state" ] || : > "$state"
  cp -f "$state" "$prev" 2>/dev/null || :

  local current; current="$(collect_for_host "$host")"
  [ -z "$current" ] && { lm_warn "[$host] no matching files from $LOG_PATHS"; rm -f "$prev" 2>/dev/null; lm_info "===== Completed $host ====="; return; }

  : > "$state"  # new state

  # Iterate current files
  local line path bytes mtime cur_mb prev_b prev_ts dt delta rate note status
  while IFS='|' read -r path bytes mtime; do
    [ -z "$path" ] && continue
    # Current size (rounded up MB)
    cur_mb=$(( (bytes + 1048575) / 1048576 ))

    # Lookup previous entry
    prev_b="$(awk -F'|' -v p="$path" '$1==p{print $2; exit}' "$prev")"
    prev_ts="$(awk -F'|' -v p="$path" '$1==p{print $3; exit}' "$prev")"

    rate="?"
    note=""
    if [ -n "$prev_b" ] && [ -n "$prev_ts" ]; then
      dt=$(( now - prev_ts ))
      if [ "$dt" -gt 0 ]; then
        delta=$(( bytes - prev_b ))
        if [ "$delta" -lt 0 ]; then
          note="rotated_or_truncated"
          delta=0
        fi
        rate="$(awk -v d="$delta" -v t="$dt" 'BEGIN{printf("%.1f", (d/1048576.0)/(t/3600.0))}')"
      fi
    fi

    status="$(rate_status "$cur_mb" "$rate")"
    lm_info "[$status] $path size=${cur_mb}MB rate=${rate}MB/h ${note:+note=$note}"

    if [ "$status" != "OK" ]; then
      append_alert "$host|$path|${cur_mb}MB|${rate}MB/h|$status${note:+|$note}"
      rotate_if_enabled "$host" "$path"
    fi

    # Persist new state
    printf "%s|%s|%s\n" "$path" "$bytes" "$now" >> "$state"
  done <<< "$current"

  # Mention previously-tracked files that vanished
  while IFS='|' read -r p_old _ ts_old; do
    printf "%s\n" "$current" | grep -Fq "$p_old" || lm_info "[INFO] $p_old no longer present (rotated/removed)"
  done < "$prev"

  rm -f "$prev" 2>/dev/null || :
  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
ensure_dirs
lm_info "=== Log Growth Guard Started (size warn=${SIZE_WARN_MB}MB crit=${SIZE_CRIT_MB}MB; rate warn=${RATE_WARN_MBPH}MB/h crit=${RATE_CRIT_MBPH}MB/h) ==="

lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="Oversized / fast-growing logs detected"
  body="Thresholds:
  - Size: WARN=${SIZE_WARN_MB}MB, CRIT=${SIZE_CRIT_MB}MB
  - Rate: WARN=${RATE_WARN_MBPH}MB/h, CRIT=${RATE_CRIT_MBPH}MB/h

Host | Path | Size | Rate | Status | Note
-----|------|------|------|--------|-----
$(echo "$alerts" | awk -F'|' '{printf "%s | %s | %s | %s | %s | %s\n",$1,$2,$3,$4,$5,(NF>=6?$6:"")}')

This is an automated message from log_growth_guard.sh."
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Log Growth Guard Finished ==="
