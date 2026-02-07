#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

sudo -n true >/dev/null 2>&1 || { echo "sudo without password required for this test" >&2; exit 0; }

sudo bash "$ROOT_DIR/run_full_health_monitor.sh" >/dev/null 2>&1 || true
summary="$ROOT_DIR/.logs/full_health_monitor_summary_latest.log"

[ -f "$summary" ] || { echo "Missing summary file: $summary" >&2; exit 1; }

# Optional allowlist of exceptions (one exact line per entry)
ALLOWLIST_FILE="$ROOT_DIR/tests/summary_reason_allowlist.txt"


# Fail if any non-OK status line lacks reason=
# Fail if any non-OK status line lacks reason= (with explicit allowlist exceptions)
missing=$(awk -v allow="$ALLOWLIST_FILE" '
  function allowlisted(line){
    if(allow=="") return 0;
    # if allowlist file is missing, treat as empty
    if(system("test -f " allow " >/dev/null 2>&1")!=0) return 0;
    cmd="grep -Fxq -- "" line "" " allow " >/dev/null 2>&1";
    return system(cmd)==0;
  }
  /^monitor=/ {
    st=""; has_reason=0;
    for(i=1;i<=NF;i++){
      if($i ~ /^status=/){split($i,a,"="); st=a[2]}
      if($i ~ /^reason=/){has_reason=1}
    }
    if(st!="" && st!="OK" && has_reason==0 && !allowlisted($0)){print $0}
  }
' "$summary" || true)

if [ -n "$missing" ]; then
  echo "Found non-OK summary lines missing reason=:" >&2
  echo "$missing" >&2
  exit 1
fi

echo "reason lint ok"
