#!/bin/bash
# config_drift_monitor.sh - Detect drift in critical config files vs baseline (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[config_drift] "
LM_LOGFILE="/var/log/config_drift_monitor.log"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; set >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle (library-level)

lm_require_singleton "config_drift_monitor"

# ========================
# Script configuration
# ========================
CONFIG_PATHS="/etc/linux_maint/config_paths.txt"        # Targets (files/dirs/globs)
ALLOWLIST_FILE="/etc/linux_maint/config_allowlist.txt"  # Optional: paths to ignore (exact or substring)
BASELINE_DIR="/etc/linux_maint/baselines/configs"       # Per-host baselines live here

# Behavior
AUTO_BASELINE_INIT="true"   # If baseline missing for a host, create it from current snapshot
BASELINE_UPDATE="false"     # After reporting, accept current as new baseline
EMAIL_ON_DRIFT="true"       # Send email when drift detected

MAIL_SUBJECT_PREFIX='[Config Drift Monitor]'

# ========================
# Helpers (script-local)
# ========================
ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")" "$BASELINE_DIR"; }

mail_if_enabled(){ 
  [ "$EMAIL_ON_DRIFT" = "true" ] || return 0
  lm_mail "$1" "$2"
}

# Return 0 if path is allowlisted (skip drift for this path)
is_allowed_path(){
  local path="$1"
  [ -f "$ALLOWLIST_FILE" ] || return 1
  # exact match OR substring (case-insensitive)
  grep -Fxq -- "$path" "$ALLOWLIST_FILE" && return 0
  grep -iFq -- "$path" "$ALLOWLIST_FILE" && return 0
  return 1
}

# Remote hasher for a single pattern ($1). Emits lines: "algo|hash|/absolute/path"
# Supports file/glob/dir/dir/** (recursive)
remote_hash_cmd='
p="$1"
hashbin="$(command -v sha256sum || command -v md5sum)"
algo="$( [ "${hashbin##*/}" = "sha256sum" ] && echo sha256 || echo md5 )"

emit_file(){
  f="$1"
  [ -f "$f" ] || return
  h="$($hashbin "$f" 2>/dev/null | awk "{print \$1}")"
  [ -n "$h" ] && printf "%s|%s|%s\n" "$algo" "$h" "$(readlink -f "$f" 2>/dev/null || echo "$f")"
}

if [[ "$p" == */** ]]; then
  base="${p%/**}"
  [ -d "$base" ] && find "$base" -type f -print0 2>/dev/null | xargs -0r "$hashbin" 2>/dev/null | awk -v a="$algo" "{printf \"%s|%s|%s\\n\", a, \$1, \$2}"
elif [[ "$p" == */ ]]; then
  dir="${p%/}"
  [ -d "$dir" ] && find "$dir" -maxdepth 1 -type f -print0 2>/dev/null | xargs -0r "$hashbin" 2>/dev/null | awk -v a="$algo" "{printf \"%s|%s|%s\\n\", a, \$1, \$2}"
elif [[ "$p" == *\"* ]]; then
  : # ignore bad quotes
elif [[ "$p" == *\"* ]]; then
  : # guard
elif [[ "$p" == *"*"* || "$p" == *"?"* ]]; then
  shopt -s nullglob dotglob
  for f in $p; do emit_file "$f"; done
else
  emit_file "$p"
fi
'

collect_current(){
  local host="$1"
  local lines=""
  [ -f "$CONFIG_PATHS" ] || { lm_err "[$host] config paths file $CONFIG_PATHS not found."; echo ""; return; }

  while IFS= read -r pat; do
    pat="$(echo "$pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$pat" ] && continue
    [[ "$pat" =~ ^# ]] && continue
    # Pass $pat as $1 to the remote snippet (bash -c 'code' _ "$pat")
    out=$(lm_ssh "$host" bash -lc "'$remote_hash_cmd'" _ "$pat")
    [ -n "$out" ] && lines+="$out"$'\n'
  done < "$CONFIG_PATHS"

  # normalize + sort unique
  printf "%s" "$lines" | sed '/^$/d' | sort -u
}

# Compare baseline vs current. Expect files containing "algo|hash|path"
compare_and_report(){
  local host="$1" cur_file="$2" base_file="$3"

  local cur_paths base_paths
  cur_paths="$(awk -F'|' '{print $3}' "$cur_file" | sort -u)"
  base_paths="$(awk -F'|' '{print $3}' "$base_file" | sort -u)"

  # NEW and REMOVED by set difference
  local new_file removed_file
  new_file="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  removed_file="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  comm -13 <(printf "%s\n" "$base_paths") <(printf "%s\n" "$cur_paths") > "$new_file"
  comm -23 <(printf "%s\n" "$base_paths") <(printf "%s\n" "$cur_paths") > "$removed_file"

  # MODIFIED: paths in intersection where hash differs
  local modified_file
  modified_file="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  awk -F'|' 'NR==FNR{b[$3]=$1"|" $2; next} {c[$3]=$1"|" $2} END{for(p in b){if(p in c && b[p]!=c[p]) print p "|" b[p] "|" c[p]}}' \
      "$base_file" "$cur_file" > "$modified_file"

  # Apply allowlist to NEW and MODIFIED (path-based)
  local new_filtered modified_filtered
  new_filtered="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  modified_filtered="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"

  if [ -s "$new_file" ]; then
    while IFS= read -r p; do
      is_allowed_path "$p" && continue
      echo "$p"
    done < "$new_file" > "$new_filtered"
  else : > "$new_filtered"; fi

  if [ -s "$modified_file" ]; then
    while IFS= read -r line; do
      p="${line%%|*}"
      is_allowed_path "$p" && continue
      echo "$line"
    done < "$modified_file" > "$modified_filtered"
  else : > "$modified_filtered"; fi

  local changes=0

  if [ -s "$modified_filtered" ]; then
    changes=1
    lm_info "[$host] MODIFIED files:"
    awk -F'|' '{printf "  * %s (old:%s new:%s)\n",$1,$2,$3}' "$modified_filtered" | while IFS= read -r L; do lm_info "$L"; done
  fi

  if [ -s "$new_filtered" ]; then
    changes=1
    lm_info "[$host] NEW files:"
    awk '{printf "  + %s\n",$0}' "$new_filtered" | while IFS= read -r L; do lm_info "$L"; done
  fi

  if [ -s "$removed_file" ]; then
    changes=1
    lm_info "[$host] REMOVED files:"
    awk '{printf "  - %s\n",$0}' "$removed_file" | while IFS= read -r L; do lm_info "$L"; done
  fi

  # Email summary if there were changes
  if [ "$changes" -eq 1 ]; then
    local subj="Config drift detected on $host"
    local body="Host: $host

MODIFIED:
$( [ -s "$modified_filtered" ] && awk -F'|' '{printf "  * %s (old:%s new:%s)\n",$1,$2,$3}' "$modified_filtered" || echo "  (none)")

NEW:
$( [ -s "$new_filtered" ] && awk '{printf "  + %s\n",$0}' "$new_filtered" || echo "  (none)")

REMOVED:
$( [ -s "$removed_file" ] && awk '{printf "  - %s\n",$0}' "$removed_file" || echo "  (none)")

Allowlist: $ALLOWLIST_FILE
"
    mail_if_enabled "$MAIL_SUBJECT_PREFIX $subj" "$body"
  fi

  rm -f "$new_file" "$removed_file" "$modified_file" "$new_filtered" "$modified_filtered"
  return 0
}

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Checking config drift on $host ====="

  local modified=0
  local added=0
  local removed=0

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    return
  fi

  local cur_file; cur_file="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}")"
  collect_current "$host" > "$cur_file"

  if [ ! -s "$cur_file" ]; then
    lm_warn "[$host] No files matched from $CONFIG_PATHS"
  fi

  local base_file="$BASELINE_DIR/${host}.baseline"
  if [ ! -f "$base_file" ]; then
    if [ "$AUTO_BASELINE_INIT" = "true" ]; then
      cp -f "$cur_file" "$base_file"
      lm_info "[$host] Baseline created at $base_file (initial snapshot)."
      rm -f "$cur_file"
      lm_info "===== Completed $host ====="
      return
    else
      lm_warn "[$host] Baseline missing ($base_file). Set AUTO_BASELINE_INIT=true or create it manually."
      rm -f "$cur_file"
      lm_info "===== Completed $host ====="
      return
    fi
  fi

  compare_and_report "$host" "$cur_file" "$base_file"

  modified=$( [ -f "$modified_filtered" ] && wc -l < "$modified_filtered" 2>/dev/null || echo 0)
  added=$( [ -f "$new_filtered" ] && wc -l < "$new_filtered" 2>/dev/null || echo 0)
  removed=$( [ -f "$removed_file" ] && wc -l < "$removed_file" 2>/dev/null || echo 0)

  if [ "$BASELINE_UPDATE" = "true" ]; then
    cp -f "$cur_file" "$base_file"
    lm_info "[$host] Baseline updated."
  fi

  rm -f "$cur_file"

  total_changes=$((modified+added+removed))
  status=$( [ "$total_changes" -gt 0 ] && echo WARN || echo OK )
  echo "config_drift_monitor host=$host status=$status modified=$modified added=$added removed=$removed"

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
ensure_dirs
lm_info "=== Config Drift Monitor Started ==="

lm_for_each_host run_for_host

lm_info "=== Config Drift Monitor Finished ==="
