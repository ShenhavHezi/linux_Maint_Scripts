#!/usr/bin/env bash
set -euo pipefail

# Repo-portable runner: place this file on a server and install to /usr/local/sbin/
# It expects the repo scripts under /usr/local/libexec/linux_maint by default.

# Default install location (can be overridden)
SCRIPTS_DIR_BASE="${SCRIPTS_DIR:-/usr/local/libexec/linux_maint}"
REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
if [[ -d "$REPO_DIR/monitors" ]]; then
  SCRIPTS_DIR_DEFAULT="$REPO_DIR/monitors"
else
  SCRIPTS_DIR_DEFAULT="$SCRIPTS_DIR_BASE"
fi
SCRIPTS_DIR="${SCRIPTS_DIR:-$SCRIPTS_DIR_DEFAULT}"

# Ensure monitors use the repo library when running from a checkout
if [[ -f "$REPO_DIR/lib/linux_maint.sh" ]]; then
  export LINUX_MAINT_LIB="$REPO_DIR/lib/linux_maint.sh"
fi
export LM_LOCKDIR="${LM_LOCKDIR:-/tmp}"
export LM_STATE_DIR="${LM_STATE_DIR:-/tmp}"

# Load optional notification config (wrapper-level). Default OFF.
if [[ -f "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" ]]; then
  # shellcheck disable=SC1090
  . "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" >/dev/null 2>&1 || true
  if command -v lm_load_notify_conf >/dev/null 2>&1; then
    lm_load_notify_conf || true
  fi
fi


if [[ -d "$REPO_DIR/monitors" ]]; then
  LOG_DIR_DEFAULT="$REPO_DIR/.logs"
else
  LOG_DIR_DEFAULT="/var/log/health"
fi

# Load installed configuration files (best-effort).
if [ -f "$REPO_DIR/lib/linux_maint_conf.sh" ]; then
  # shellcheck disable=SC1090
  . "$REPO_DIR/lib/linux_maint_conf.sh" || true
  if command -v lm_load_config >/dev/null 2>&1; then lm_load_config || true; fi
fi

LOG_DIR="${LOG_DIR:-$LOG_DIR_DEFAULT}"
STATUS_FILE="$LOG_DIR/last_status_full"

mkdir -p "$LOG_DIR"
chmod 0755 "$LOG_DIR"

logfile="$LOG_DIR/full_health_monitor_$(date +%F_%H%M%S).log"

tmp_report="/tmp/full_health_monitor_report.$$"
tmp_summary="/tmp/full_health_monitor_summary.$$"

# Optional: write machine-parseable summaries to a separate file
# Defaults to /var/log/health/full_health_monitor_summary_latest.log
SUMMARY_DIR="${SUMMARY_DIR:-$LOG_DIR}"
SUMMARY_LATEST_FILE="${SUMMARY_LATEST_FILE:-$SUMMARY_DIR/full_health_monitor_summary_latest.log}"
SUMMARY_JSON_LATEST_FILE="${SUMMARY_JSON_LATEST_FILE:-$SUMMARY_DIR/full_health_monitor_summary_latest.json}"
SUMMARY_JSON_FILE="${SUMMARY_JSON_FILE:-$SUMMARY_DIR/full_health_monitor_summary_$(date +%F_%H%M%S).json}"
PROM_DIR="${PROM_DIR:-/var/lib/node_exporter/textfile_collector}"
PROM_FILE="${PROM_FILE:-$PROM_DIR/linux_maint.prom}"
SUMMARY_FILE="${SUMMARY_FILE:-$SUMMARY_DIR/full_health_monitor_summary_$(date +%F_%H%M%S).log}"
trap 'rm -f "$tmp_summary"' EXIT

# Minimal config (local mode)
# Minimal config (local mode)
# In unprivileged environments (e.g. CI), fall back to a repo-local config dir.
CFG_DIR="${LM_CFG_DIR:-/etc/linux_maint}"
if ! mkdir -p "$CFG_DIR" 2>/dev/null; then
  CFG_DIR="${LM_CFG_DIR_FALLBACK:-$REPO_DIR/.etc_linux_maint}"
  mkdir -p "$CFG_DIR"
fi
[ -f "$CFG_DIR/servers.txt" ] || echo "localhost" > "$CFG_DIR/servers.txt"
[ -f "$CFG_DIR/excluded.txt" ] || : > "$CFG_DIR/excluded.txt"

# Point library defaults at our chosen config directory (do not override explicit env).
export LM_SERVERLIST="${LM_SERVERLIST:-$CFG_DIR/servers.txt}"
export LM_EXCLUDED="${LM_EXCLUDED:-$CFG_DIR/excluded.txt}"
export LM_SERVICES="${LM_SERVICES:-$CFG_DIR/services.txt}"


# service_monitor requires services.txt; provide safe defaults if missing
if [ ! -s "$CFG_DIR/services.txt" ]; then
  cat > "$CFG_DIR/services.txt" <<'SVC'
# critical services
sshd
crond
docker
NetworkManager
SVC
  chmod 0644 "$CFG_DIR/services.txt"
fi

# Disable email unless explicitly enabled
export LM_EMAIL_ENABLED="${LM_EMAIL_ENABLED:-false}"

# Per-monitor execution timeout (wrapper-level safety)
MONITOR_TIMEOUT_SECS="${MONITOR_TIMEOUT_SECS:-600}"

# health_monitor already includes: uptime/load/cpu/mem/disk/top processes.
# Avoid overlaps by excluding disk_monitor/process_hog/server_info.

declare -a scripts=(
  "preflight_check.sh"
  "config_validate.sh"
  "health_monitor.sh"
  "inode_monitor.sh"
  "disk_trend_monitor.sh"
  "network_monitor.sh"
  "service_monitor.sh"
  "ntp_drift_monitor.sh"
  "patch_monitor.sh"
  "storage_health_monitor.sh"
  "kernel_events_monitor.sh"
  "cert_monitor.sh"
  "nfs_mount_monitor.sh"
  "ports_baseline_monitor.sh"
  "config_drift_monitor.sh"
  "user_monitor.sh"
  "backup_check.sh"
  "inventory_export.sh"
)

{
  echo "SUMMARY full_health_monitor host=$(hostname -f 2>/dev/null || hostname) started=$(date -Is)"
  echo "SCRIPTS_DIR=$SCRIPTS_DIR"
  echo "LM_EMAIL_ENABLED=$LM_EMAIL_ENABLED"
  echo "SCRIPT_ORDER=${scripts[*]}"
  echo "============================================================"
} > "$tmp_report"

run_one() {
  local s="$1"
  local path="$SCRIPTS_DIR/$s"
  echo "" >> "$tmp_report"
  echo "==== RUN $s @ $(date '+%F %T') ====" >> "$tmp_report"

  # Emit standardized SKIP summary lines when wrapper gates skip a monitor
  skip_monitor() {
    local reason="$1"
    echo "SKIP: $reason" >> "$tmp_report"
    echo "monitor=${s%.sh} host=all status=SKIP node=$(hostname -f 2>/dev/null || hostname) reason=$reason" >> "$tmp_report"
    skipped=$((skipped+1))
    return 0
  }

  # Skip monitors that require config/baselines unless present
  case "$s" in
    cert_monitor.sh)
      [ -s /etc/linux_maint/certs.txt ] || { skip_monitor "missing:/etc/linux_maint/certs.txt"; }
      ;;
    ports_baseline_monitor.sh)
      [ -s /etc/linux_maint/ports_baseline.txt ] || { skip_monitor "missing:/etc/linux_maint/ports_baseline.txt"; }
      ;;
    config_drift_monitor.sh)
      [ -s /etc/linux_maint/config_paths.txt ] || { skip_monitor "missing:/etc/linux_maint/config_paths.txt"; }
      ;;
    user_monitor.sh)
      [ -s /etc/linux_maint/baseline_users.txt ] || { skip_monitor "missing:/etc/linux_maint/baseline_users.txt"; }
      [ -s /etc/linux_maint/baseline_sudoers.txt ] || { skip_monitor "missing:/etc/linux_maint/baseline_sudoers.txt"; }
      ;;
  esac

  if [ ! -f "$path" ]; then
    echo "MISSING: $path" >> "$tmp_report"
    return 3
  fi

  if [ "$s" = "config_validate.sh" ]; then
    # Validation warnings should not fail the full run; log output but ignore exit code.
    bash "$path" >> "$tmp_report" 2>&1 || true
    return 0
  fi

  # Wrapper-level timeout to prevent a single monitor from hanging the whole run
  if command -v timeout >/dev/null 2>&1; then
    timeout "$MONITOR_TIMEOUT_SECS" bash "$path" >> "$tmp_report" 2>&1
  else
    bash "$path" >> "$tmp_report" 2>&1
  fi
}

skipped=0
worst=0
ok=0; warn=0; crit=0; unk=0

for s in "${scripts[@]}"; do
  set +e
  before_lines=$(grep -a -c "^monitor=" "$tmp_report" 2>/dev/null || echo 0)
  run_one "$s"
  rc=$?
  after_lines=$(grep -a -c "^monitor=" "$tmp_report" 2>/dev/null || echo 0)
  if [ "$rc" -ne 0 ] && [ "$after_lines" -le "$before_lines" ]; then
    # Hardening: a monitor failed but emitted no standardized summary line.
    echo "monitor=${s%.sh} host=runner status=UNKNOWN node=$(hostname -f 2>/dev/null || hostname) reason=no_summary_emitted rc=$rc" >> "$tmp_report"
  fi
  set -e

  case "$rc" in
    0) ok=$((ok+1));;
    1) warn=$((warn+1));;
    2) crit=$((crit+1));;
    *) unk=$((unk+1)); rc=3;;
  esac
  [ "$rc" -gt "$worst" ] && worst="$rc"
done

case "$worst" in
  0) overall="OK";;
  1) overall="WARN";;
  2) overall="CRIT";;
  *) overall="UNKNOWN";;
esac

{
  echo "SUMMARY_RESULT overall=$overall ok=$ok warn=$warn crit=$crit unknown=$unk skipped=$skipped finished=$(date -Is) exit_code=$worst"
  echo "SUMMARY_MONITORS ok=$ok warn=$warn crit=$crit unknown=$unk skipped=$skipped"
  echo "SUMMARY_RESULT_NOTE SUMMARY_RESULT counts are per-monitor-script exit codes; fleet counters are in SUMMARY_HOSTS derived from monitor= lines"
  echo "============================================================"
  # Final status summary: explicitly extract only standardized machine lines.
  # These come from lib/linux_maint.sh: lm_summary() -> lines starting with "monitor=".
  echo "FINAL_STATUS_SUMMARY (monitor= lines only)"
  tmp_mon=$(mktemp /tmp/linux_maint_mon.XXXXXX)
  grep -a '^monitor=' "$tmp_report" > "$tmp_mon" || true
  cat "$tmp_mon" 2>/dev/null || true
  echo "============================================================"

# ------------------------
# HUMAN_STATUS_SUMMARY (ops-friendly)
# ------------------------
# Avoid reading+appending to the same file in one block: snapshot monitor lines first.
_tmp_mon_snapshot=$(mktemp /tmp/linux_maint_mon_snapshot.XXXXXX)
grep -a '^monitor=' "$tmp_report" > "$_tmp_mon_snapshot" 2>/dev/null || true

# shellcheck disable=SC2030
# shellcheck disable=SC2030
hosts_ok=0
# shellcheck disable=SC2030
hosts_warn=0
# shellcheck disable=SC2030
hosts_crit=0
# shellcheck disable=SC2030
hosts_unknown=0
# shellcheck disable=SC2030
hosts_skip=0
# Fleet-level counters derived from monitor= lines (per-host/per-monitor)
if [ -f "$_tmp_mon_snapshot" ]; then
  hosts_ok=$(grep -a -c " status=OK( |$)" "$_tmp_mon_snapshot" 2>/dev/null || echo 0)
  hosts_warn=$(grep -a -c " status=WARN( |$)" "$_tmp_mon_snapshot" 2>/dev/null || echo 0)
  hosts_crit=$(grep -a -c " status=CRIT( |$)" "$_tmp_mon_snapshot" 2>/dev/null || echo 0)
  hosts_unknown=$(grep -a -c " status=UNKNOWN( |$)" "$_tmp_mon_snapshot" 2>/dev/null || echo 0)
  hosts_skip=$(grep -a -c " status=SKIP( |$)" "$_tmp_mon_snapshot" 2>/dev/null || echo 0)
fi


echo "SUMMARY_HOSTS ok=$hosts_ok warn=$hosts_warn crit=$hosts_crit unknown=$hosts_unknown skipped=$hosts_skip"
_tmp_human=$(mktemp /tmp/linux_maint_human.XXXXXX)
{
  echo ""
  echo "HUMAN_STATUS_SUMMARY"
  echo "run_host=$(hostname -f 2>/dev/null || hostname)"
  echo "timestamp=$(date -Is)"
  echo "overall=$overall exit_code=$worst ok=$ok warn=$warn crit=$crit unknown=$unk skipped=$skipped"
  echo "fleet_hosts_ok=$hosts_ok fleet_hosts_warn=$hosts_warn fleet_hosts_crit=$hosts_crit fleet_hosts_unknown=$hosts_unknown fleet_hosts_skipped=$hosts_skip"

  echo ""
  echo "Top CRIT/WARN/UNKNOWN (from monitor= lines)"
  awk '
    {mon="";host="";st="";msg=""}
    {for(i=1;i<=NF;i++){split($i,a,"="); if(a[1]=="monitor")mon=a[2]; if(a[1]=="host")host=a[2]; if(a[1]=="status")st=a[2]; if(a[1]=="msg")msg=a[2];}}
    st=="CRIT" || st=="WARN" || st=="UNKNOWN" {print st ": " host " " mon (msg?" - " msg:"")}
  ' "$_tmp_mon_snapshot" | head -n 50

  echo ""
  echo "Logs: $logfile"
  echo "Summary: $SUMMARY_FILE"
} > "$_tmp_human"

cat "$_tmp_human" >> "$tmp_report"
# (moved cleanup to after notify so it can include the human+monitor snapshot)
# rm -f "$_tmp_human" "$_tmp_mon_snapshot" 2>/dev/null || true


  # ---- notify (optional, wrapper-level) ----
  # ---- diff since last run (optional, for more actionable notifications) ----
  DIFF_STATE_DIR="${LM_NOTIFY_STATE_DIR:-${LM_STATE_DIR:-/var/lib/linux_maint}}"
  PREV_SUMMARY="$DIFF_STATE_DIR/last_summary_monitor_lines.log"
  CUR_SUMMARY="$_tmp_mon_snapshot"
  DIFF_TEXT=""
  if [[ -f "$PREV_SUMMARY" && -f "$CUR_SUMMARY" && -x "$REPO_DIR/tools/summary_diff.py" ]]; then
    DIFF_TEXT="$(python3 "$REPO_DIR/tools/summary_diff.py" "$PREV_SUMMARY" "$CUR_SUMMARY" 2>/dev/null || true)"
  fi
  # persist current for next run (best-effort)
  mkdir -p "$DIFF_STATE_DIR" 2>/dev/null || true
  cp -f "$CUR_SUMMARY" "$PREV_SUMMARY" 2>/dev/null || true
  if command -v lm_notify_should_send >/dev/null 2>&1; then
    _notify_text="$(cat "$_tmp_human" 2>/dev/null; if [ -n "$DIFF_TEXT" ]; then echo ""; echo "DIFF_SINCE_LAST_RUN"; echo "$DIFF_TEXT"; fi; echo ""; echo "FINAL_STATUS_SUMMARY"; cat "$_tmp_mon_snapshot" 2>/dev/null)"
    if lm_notify_should_send "$_notify_text"; then
      lm_notify_send "health summary overall=$overall" "$_notify_text" || true
      echo "NOTIFY: sent summary email" >> "$tmp_report"
    else
      echo "NOTIFY: skipped" >> "$tmp_report"
    fi
  fi

  # cleanup tmp files created for summaries
  rm -f "$_tmp_human" "$_tmp_mon_snapshot" 2>/dev/null || true


cat "$tmp_report"

} | awk '{ print strftime("[%F %T]"), $0 }' | tee "$logfile" >/dev/null

ln -sfn "$logfile" "$LOG_DIR/full_health_monitor_latest.log"

# Write a separate, machine-parseable summary file (optional but enabled by default).
# Contains only "monitor=" lines (no timestamps) so it can be parsed by tools/CI.
mkdir -p "$SUMMARY_DIR" 2>/dev/null || true
tmp_mon=$(mktemp /tmp/linux_maint_mon.XXXXXX)
  grep -a '^monitor=' "$tmp_report" > "$tmp_mon" || true
  cat "$tmp_mon" > "$tmp_summary" 2>/dev/null || :
cat "$tmp_summary" > "$SUMMARY_FILE" 2>/dev/null || true
ln -sfn "$(basename "$SUMMARY_FILE")" "$SUMMARY_LATEST_FILE" 2>/dev/null || true
rm -f "$tmp_summary" 2>/dev/null || true

# Also write JSON + Prometheus outputs (best-effort)
# shellcheck disable=SC2031
SUMMARY_FILE="$SUMMARY_FILE" SUMMARY_JSON_FILE="$SUMMARY_JSON_FILE" SUMMARY_JSON_LATEST_FILE="$SUMMARY_JSON_LATEST_FILE" PROM_FILE="$PROM_FILE" LM_HOSTS_OK="${hosts_ok:-0}" LM_HOSTS_WARN="${hosts_warn:-0}" LM_HOSTS_CRIT="${hosts_crit:-0}" LM_HOSTS_UNKNOWN="${hosts_unknown:-0}" LM_HOSTS_SKIPPED="${hosts_skip:-0}" LM_OVERALL="$overall" LM_EXIT_CODE="$worst" LM_STATUS_FILE="$STATUS_FILE" python3 - <<'PY' || true
import json, os
summary_file=os.environ.get("SUMMARY_FILE")
json_file=os.environ.get("SUMMARY_JSON_FILE")
json_latest=os.environ.get("SUMMARY_JSON_LATEST_FILE")
prom_file=os.environ.get("PROM_FILE")
hosts_ok=int(os.environ.get("LM_HOSTS_OK","0"))
hosts_warn=int(os.environ.get("LM_HOSTS_WARN","0"))
hosts_crit=int(os.environ.get("LM_HOSTS_CRIT","0"))
hosts_unknown=int(os.environ.get("LM_HOSTS_UNKNOWN","0"))
hosts_skipped=int(os.environ.get("LM_HOSTS_SKIPPED","0"))
overall=os.environ.get("LM_OVERALL","UNKNOWN")
exit_code=int(os.environ.get("LM_EXIT_CODE","3"))

def parse_kv(line):
    parts=line.strip().split()
    d={}
    for p in parts:
        if "=" in p:
            k,v=p.split("=",1)
            d[k]=v
    return d

rows=[]
if summary_file and os.path.exists(summary_file):
    with open(summary_file,"r",encoding="utf-8",errors="ignore") as f:
        for line in f:
            if line.startswith("monitor="):
                rows.append(parse_kv(line))

# Wrap rows with metadata so consumers can use one stable JSON contract.
# Back-compat: set LM_JSON_LEGACY_LIST=1 to output only the list.
legacy = os.environ.get("LM_JSON_LEGACY_LIST","0") == "1"

def read_status_file(path):
    d={}
    try:
        with open(path,"r",encoding="utf-8",errors="ignore") as f:
            for line in f:
                line=line.strip()
                if not line or "=" not in line: continue
                k,v=line.split("=",1)
                d[k]=v
    except FileNotFoundError:
        pass
    return d

status_file = os.environ.get("LM_STATUS_FILE")
meta = read_status_file(status_file) if status_file else {}

payload = rows if legacy else {"meta": meta, "rows": rows}

if json_file:
    os.makedirs(os.path.dirname(json_file), exist_ok=True)
    with open(json_file,"w",encoding="utf-8") as f:
        json.dump(payload,f,indent=2,sort_keys=True)
    if json_latest:
        try:
            if os.path.islink(json_latest) or os.path.exists(json_latest):
                try: os.unlink(json_latest)
                except: pass
            os.symlink(os.path.basename(json_file),json_latest)
        except: pass

status_map={"OK":0,"WARN":1,"CRIT":2,"UNKNOWN":3,"SKIP":3}
if prom_file and rows:
    try:
        os.makedirs(os.path.dirname(prom_file), exist_ok=True)
        with open(prom_file,"w",encoding="utf-8") as f:
            f.write("# HELP linux_maint_monitor_status Monitor status as exit-code scale (OK=0,WARN=1,CRIT=2,UNKNOWN/SKIP=3)\n")
            f.write("# TYPE linux_maint_monitor_status gauge\n")
            f.write("\n# HELP linux_maint_overall_status Overall run status as exit-code scale (OK=0,WARN=1,CRIT=2,UNKNOWN=3)\n")
            f.write("# TYPE linux_maint_overall_status gauge\n")
            f.write(f"linux_maint_overall_status {exit_code}\n")
            f.write("\n# HELP linux_maint_summary_hosts_count Fleet counters derived from monitor= lines\n")
            f.write("# TYPE linux_maint_summary_hosts_count gauge\n")
            f.write(f"linux_maint_summary_hosts_count{{status=\"ok\"}} {hosts_ok}\n")
            f.write(f"linux_maint_summary_hosts_count{{status=\"warn\"}} {hosts_warn}\n")
            f.write(f"linux_maint_summary_hosts_count{{status=\"crit\"}} {hosts_crit}\n")
            f.write(f"linux_maint_summary_hosts_count{{status=\"unknown\"}} {hosts_unknown}\n")
            f.write(f"linux_maint_summary_hosts_count{{status=\"skipped\"}} {hosts_skipped}\n")
            for r in rows:
                mon=r.get("monitor","unknown"); host=r.get("host","all"); st=r.get("status","UNKNOWN")
                val=status_map.get(st,3)
                f.write(f"linux_maint_monitor_status{{monitor=\"{mon}\",host=\"{host}\"}} {val}\n")
    except: pass
PY

{
  echo "timestamp=$(date -Is)"
  echo "host=$(hostname -f 2>/dev/null || hostname)"
  echo "overall=$overall"
  echo "exit_code=$worst"
  echo "logfile=$logfile"
} > "$STATUS_FILE"
chmod 0644 "$STATUS_FILE"

rm -f "$tmp_report" 2>/dev/null || true

exit "$worst"
