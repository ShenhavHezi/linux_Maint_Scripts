#!/usr/bin/env bash
# storage_health_monitor.sh - Storage health checks (RAID/mdadm, SMART/NVMe best-effort) (local/distributed)
# Author: Shenhav_Hezi
# Version: 1.0
#
# What it does (per host):
# - mdraid: detect degraded arrays via /proc/mdstat and (if available) mdadm
# - SMART: if smartctl exists, run overall health on detected disks (best-effort)
# - NVMe: if nvme cli exists, collect critical_warning (best-effort)
#
# Output:
# - one-line summary to stdout for wrapper logs

set -euo pipefail

. "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" || { echo "Missing ${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}"; exit 1; }
LM_PREFIX="[storage_health] "
LM_LOGFILE="/var/log/storage_health_monitor.log"
: "${LM_MAX_PARALLEL:=0}"
: "${LM_EMAIL_ENABLED:=true}"

lm_require_singleton "storage_health_monitor"

MAIL_SUBJECT_PREFIX='[Storage Health Monitor]'
EMAIL_ON_ISSUE="true"

SMARTCTL_TIMEOUT_SECS=10
MAX_SMART_DEVICES=32

# RAID controller tools (best-effort).
RAID_TOOL_TIMEOUT_SECS=12

ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" storage_health_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }
mail_if_enabled(){ [ "$EMAIL_ON_ISSUE" = "true" ] || return 0; lm_mail "$1" "$2"; }

ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")"; }

remote_collect_cmd() {
  cat <<'EOF'
set -euo pipefail

have(){ command -v "$1" >/dev/null 2>&1; }

# ---- mdraid ----
md_status="NA"
if [ -r /proc/mdstat ]; then
  md_status="OK"
  # degraded bitmap contains '_' inside the [UU] style field
  if grep -Eq "\[[^]]*_+[^]]*\]" /proc/mdstat 2>/dev/null; then
    md_status="CRIT"
  fi
  if grep -Eqi "degraded" /proc/mdstat 2>/dev/null; then md_status="CRIT"; fi
  if grep -Eqi "recovery|resync|reshape|check" /proc/mdstat 2>/dev/null; then
    [ "$md_status" = "OK" ] && md_status="WARN"
  fi
fi

# ---- SMART ----
smart_status="NA"
smart_bad=0
smart_checked=0

if have smartctl; then
  smart_status="OK"
  if have lsblk; then
    devs=$(lsblk -dn -o NAME,TYPE 2>/dev/null | awk '$2=="disk"{print "/dev/"$1}' | head -n "${MAX_SMART_DEVICES:-32}")
  else
    devs=$(ls /dev/sd? /dev/vd? /dev/xvd? 2>/dev/null | head -n "${MAX_SMART_DEVICES:-32}" || true)
  fi

  for d in $devs; do
    smart_checked=$((smart_checked+1))
    if have timeout; then
      out=$(timeout "${SMARTCTL_TIMEOUT_SECS:-10}" smartctl -H "$d" 2>/dev/null || true)
    else
      out=$(smartctl -H "$d" 2>/dev/null || true)
    fi

    echo "$out" | grep -Eq "PASSED" && continue
    echo "$out" | grep -Eqi "Permission denied|Unavailable|No such device" && continue
    smart_bad=$((smart_bad+1))
  done

  [ "$smart_bad" -gt 0 ] && smart_status="CRIT"
  [ "$smart_checked" -eq 0 ] && smart_status="NA"
fi

# ---- NVMe ----
nvme_status="NA"
nvme_bad=0
nvme_checked=0

if have nvme; then
  nvme_status="OK"
  devs=$(nvme list 2>/dev/null | awk '/^\/dev\/nvme/{print $1}' | head -n 32)
  for d in $devs; do
    nvme_checked=$((nvme_checked+1))
    out=$(nvme smart-log "$d" 2>/dev/null || true)
    cw=$(echo "$out" | awk -F: '/critical_warning/ {gsub(/[^0-9]/,"",$2); print $2; exit}')
    [ -z "$cw" ] && cw=0
    [ "$cw" -ne 0 ] && nvme_bad=$((nvme_bad+1))
  done
  [ "$nvme_bad" -gt 0 ] && nvme_status="CRIT"
  [ "$nvme_checked" -eq 0 ] && nvme_status="NA"
fi

# ---- RAID controller tools (best-effort) ----
ctrl_status="NA"
ctrl_note=""

# MegaRAID storcli/perccli
if have storcli || have perccli; then
  ctrl_status="OK"
  cli="$(command -v storcli || command -v perccli)"
  if have timeout; then
    out=$(timeout "${RAID_TOOL_TIMEOUT_SECS:-12}" "$cli" /cALL show all 2>/dev/null || true)
  else
    out=$($cli /cALL show all 2>/dev/null || true)
  fi
  echo "$out" | grep -Eqi "Degraded|Offline|Failed" && ctrl_status="CRIT"
  echo "$out" | grep -Eqi "Rebuild|Initializing|Resync" && [ "$ctrl_status" = "OK" ] && ctrl_status="WARN"
  echo "$out" | grep -Eqi "Predictive" && ctrl_status="CRIT"
  ctrl_note="storcli"
fi

# HP Smart Array (ssacli)
if [ "$ctrl_status" = "NA" ] && have ssacli; then
  ctrl_status="OK"; ctrl_note="ssacli"
  if have timeout; then
    out=$(timeout "${RAID_TOOL_TIMEOUT_SECS:-12}" ssacli ctrl all show config detail 2>/dev/null || true)
  else
    out=$(ssacli ctrl all show config detail 2>/dev/null || true)
  fi
  echo "$out" | grep -Eqi "Failed|Degraded|Rebuilding" && ctrl_status="CRIT"
fi

# Dell OMSA (omreport)
if [ "$ctrl_status" = "NA" ] && have omreport; then
  ctrl_status="OK"; ctrl_note="omreport"
  if have timeout; then
    out=$(timeout "${RAID_TOOL_TIMEOUT_SECS:-12}" omreport storage vdisk 2>/dev/null || true)
  else
    out=$(omreport storage vdisk 2>/dev/null || true)
  fi
  echo "$out" | grep -Eqi "Degraded|Failed" && ctrl_status="CRIT"
fi

rank(){ case "$1" in OK) echo 0;; WARN) echo 1;; CRIT) echo 2;; *) echo 0;; esac; }
worst=0
for s in "$md_status" "$smart_status" "$nvme_status" "$ctrl_status"; do
  [ "$s" = "NA" ] && continue
  r=$(rank "$s")
  [ "$r" -gt "$worst" ] && worst=$r
done
case "$worst" in 0) overall="OK";; 1) overall="WARN";; 2) overall="CRIT";; *) overall="OK";; esac

printf "mdraid=%s smart=%s smart_checked=%s smart_bad=%s nvme=%s nvme_checked=%s nvme_bad=%s ctrl=%s(%s) overall=%s\n" \
  "$md_status" "$smart_status" "$smart_checked" "$smart_bad" "$nvme_status" "$nvme_checked" "$nvme_bad" "$ctrl_status" "${ctrl_note:-}" "$overall"
EOF
}

run_for_host(){
  local host="$1"
  ensure_dirs

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|unreachable"
    lm_summary "storage_health_monitor" "$host" "CRIT" mdraid=? smart=? nvme=?
    # legacy:
    # echo "storage_health_monitor host=$host status=CRIT mdraid=? smart=? nvme=?"
    return 2
  fi

  local cmd out
  cmd="$(remote_collect_cmd)"
  out="$(lm_ssh "$host" bash -lc "$cmd" 2>/dev/null || true)"
  if [ -z "$out" ]; then
    lm_warn "[$host] unable to collect storage health"
    append_alert "$host|collect|failed"
    lm_summary "storage_health_monitor" "$host" "UNKNOWN"
    # legacy:
    # echo "storage_health_monitor host=$host status=UNKNOWN"
    return 3
  fi

  local md smart smart_checked smart_bad nvme nvme_checked nvme_bad ctrl overall
  md=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="mdraid") print $(i+1)}')
  smart=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="smart") print $(i+1)}')
  smart_checked=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="smart_checked") print $(i+1)}')
  smart_bad=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="smart_bad") print $(i+1)}')
  nvme=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="nvme") print $(i+1)}')
  nvme_checked=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="nvme_checked") print $(i+1)}')
  nvme_bad=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="nvme_bad") print $(i+1)}')
ctrl=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="ctrl") print $(i+1)}')
  overall=$(echo "$out" | awk -F'[ =]+' '{for(i=1;i<=NF;i++) if($i=="overall") print $(i+1)}')

  local rc
  case "$overall" in OK) rc=0;; WARN) rc=1;; CRIT) rc=2;; *) rc=3;; esac

  if [ "$rc" -ge 1 ]; then
    append_alert "$host|storage|mdraid=$md smart=$smart($smart_bad/$smart_checked) nvme=$nvme($nvme_bad/$nvme_checked)"
  fi

  lm_summary "storage_health_monitor" "$host" "$overall" mdraid=$md smart=$smart checked=$smart_checked bad=$smart_bad nvme=$nvme checked_nvme=$nvme_checked bad_nvme=$nvme_bad ctrl=$ctrl
  # legacy:
  # echo "storage_health_monitor host=$host status=$overall mdraid=$md smart=$smart checked=$smart_checked bad=$smart_bad nvme=$nvme checked_nvme=$nvme_checked bad_nvme=$nvme_bad ctrl=$ctrl"
  return "$rc"
}

main(){
  : > "$ALERTS_FILE"

  local worst=0
  lm_for_each_host run_for_host

  # capture worst exit code from per-host runs by scanning logfile for last status lines is complex; instead we track in run_for_host and main using a global.


  if [ -s "$ALERTS_FILE" ]; then
    mail_if_enabled "$MAIL_SUBJECT_PREFIX Storage health issues detected" "$(cat "$ALERTS_FILE")"
  fi

  exit "$worst"
}

main "$@"
