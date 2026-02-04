#!/bin/bash
# network_monitor.sh - Ping / TCP / HTTP checks from each host (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)

# ===== Shared helpers =====
. "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" || { echo "Missing ${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}"; exit 1; }
LM_PREFIX="[network_monitor] "
LM_LOGFILE="${LM_LOGFILE:-/var/log/network_monitor.log}"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; set >0 to run hosts in parallel
: "${LM_EMAIL_ENABLED:=true}" # master email toggle (library uses this)

lm_require_singleton "network_monitor"

# ========================
# Configuration
# ========================
TARGETS="/etc/linux_maint/network_targets.txt"   # CSV: host,check,target,key=val,...
MAIL_SUBJECT_PREFIX='[Network Monitor]'

# Defaults (overridable per-check via key=val in targets file)
PING_COUNT=3
PING_TIMEOUT=3
PING_LOSS_WARN=20
PING_LOSS_CRIT=50
PING_RTT_WARN_MS=150
PING_RTT_CRIT_MS=500

TCP_TIMEOUT=3
TCP_LAT_WARN_MS=300
TCP_LAT_CRIT_MS=1000

HTTP_TIMEOUT=5
HTTP_LAT_WARN_MS=800
HTTP_LAT_CRIT_MS=2000
HTTP_EXPECT=""   # default: 200–399 when empty

# ========================
# Small helpers
# ========================
ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" network_monitor.alerts.XXXXXX)"
append_alert(){ echo "$1" >> "$ALERTS_FILE"; }

# HTTP code matcher
http_code_ok(){
  local code="$1" expect="$2"
  if [ -z "$expect" ]; then
    [ "$code" -ge 200 ] && [ "$code" -lt 400 ]
    return
  fi
  if [[ "$expect" =~ ^[1-5]xx$ ]]; then
    local p="${expect%xx}"
    [ "$code" -ge $((p*100)) ] && [ "$code" -lt $((p*100+100)) ]
    return
  fi
  if [[ "$expect" =~ ^[0-9]{3}-[0-9]{3}$ ]]; then
    local a="${expect%-*}" b="${expect#*-}"
    [ "$code" -ge "$a" ] && [ "$code" -le "$b" ]
    return
  fi
  if [[ "$expect" =~ , ]]; then
    IFS=',' read -r -a arr <<<"$expect"
    for x in "${arr[@]}"; do [ "$code" -eq "$x" ] && return 0; done
    return 1
  fi
  [[ "$expect" =~ ^[0-9]{3}$ ]] && { [ "$code" -eq "$expect" ]; return; }
  [ "$code" -ge 200 ] && [ "$code" -lt 400 ]
}

# Parse key=val pairs into an assoc array name passed as $1
parse_params(){
  declare -n _dst="$1"; shift
  for pair in "$@"; do
    [ -z "$pair" ] && continue
    _dst["${pair%%=*}"]="${pair#*=}"
  done
}

# ========================
# Remote probes
# ========================
run_ping(){
  local onhost="$1" target="$2"; shift 2
  declare -A P=(); parse_params P "$@"
  local cnt="${P[count]:-$PING_COUNT}"
  local to="${P[timeout]:-$PING_TIMEOUT}"
  local lw="${P[loss_warn]:-$PING_LOSS_WARN}"
  local lc="${P[loss_crit]:-$PING_LOSS_CRIT}"
  local rw="${P[rtt_warn_ms]:-$PING_RTT_WARN_MS}"
  local rc="${P[rtt_crit_ms]:-$PING_RTT_CRIT_MS}"

  local out
  out="$(lm_ssh "$onhost" "ping -c $cnt -w $to '$target' 2>/dev/null || ping -n -c $cnt -w $to '$target' 2>/dev/null")"
  if [ -z "$out" ]; then
    lm_err "[$onhost] ping $target tool/permission failure"
    append_alert "$onhost|ping|$target|tool_failure"
    return
  fi

  local loss avg ams="?"
  loss="$(printf "%s\n" "$out" | awk -F',' '/packet loss/ {for(i=1;i<=NF;i++) if($i ~ /packet loss/) {gsub(/[^0-9.]/,"",$i); print $i; exit}}')"
  avg="$(printf "%s\n" "$out" | awk -F'/' '/min\/avg\/|round-trip/ {print $5; exit}')"
  [ -z "$loss" ] && loss="100"
  [ -n "$avg" ] && ams=$(awk -v a="$avg" 'BEGIN{printf("%.0f", a)}')

  local status="OK" note=""
  awk -v L="$loss" -v LC="$lc" 'BEGIN{exit !(L >= LC)}' && { status="CRIT"; note="loss_ge_${lc}%"; }
  if [ "$status" = "OK" ]; then
    awk -v L="$loss" -v LW="$lw" 'BEGIN{exit !(L >= LW)}' && { status="WARN"; note="loss_ge_${lw}%"; }
  fi
  if [ "$ams" != "?" ]; then
    [ "$ams" -ge "$rc" ] && { status="CRIT"; note="${note:+$note,}rtt_ge_${rc}ms"; }
    [ "$status" = "OK" ] && [ "$ams" -ge "$rw" ] && { status="WARN"; note="rtt_ge_${rw}ms"; }
  fi

  lm_info "[$onhost] [$status] ping $target loss=${loss}% avg=${ams}ms ${note:+note=$note}"
  [ "$status" != "OK" ] && append_alert "$onhost|ping|$target|$note"
}

run_tcp(){
  local onhost="$1" hostport="$2"; shift 2
  declare -A P=(); parse_params P "$@"
  local to="${P[timeout]:-$TCP_TIMEOUT}"
  local lw="${P[latency_warn_ms]:-$TCP_LAT_WARN_MS}"
  local lc="${P[latency_crit_ms]:-$TCP_LAT_CRIT_MS}"
  local host="${hostport%%:*}" port="${hostport##*:}"

  local out
  out="$(lm_ssh "$onhost" "start=\$(date +%s%3N 2>/dev/null); exec 3<>/dev/tcp/$host/$port; rc=\$?; end=\$(date +%s%3N 2>/dev/null); [ \$rc -eq 0 ] && { exec 3>&-; echo OK \$((end-start)); } || echo FAIL" )"
  if echo "$out" | grep -q '^OK '; then
    local ms; ms="$(echo "$out" | awk '{print $2}')"
    local status="OK" note=""
    [ -z "$ms" ] && ms="?"
    [ "$ms" != "?" ] && [ "$ms" -ge "$lc" ] && { status="CRIT"; note="lat_ge_${lc}ms"; }
    [ "$status" = "OK" ] && [ "$ms" != "?" ] && [ "$ms" -ge "$lw" ] && { status="WARN"; note="lat_ge_${lw}ms"; }
    lm_info "[$onhost] [$status] tcp ${host}:${port} conn_ms=${ms} ${note:+note=$note}"
    [ "$status" != "OK" ] && append_alert "$onhost|tcp|${host}:${port}|$note"
    return
  fi

  if lm_ssh "$onhost" "command -v nc >/dev/null"; then
    if lm_ssh "$onhost" "nc -z -w $to '$host' '$port'"; then
      lm_info "[$onhost] [OK] tcp ${host}:${port} reachable (nc)"
    else
      lm_err "[$onhost] [CRIT] tcp ${host}:${port} unreachable (nc)"
      append_alert "$onhost|tcp|${host}:${port}|unreachable"
    fi
  else
    lm_err "[$onhost] [CRIT] tcp ${host}:${port} no /dev/tcp timing and nc missing"
    append_alert "$onhost|tcp|${host}:${port}|tool_missing"
  fi
}

run_http(){
  local onhost="$1" url="$2"; shift 2
  declare -A P=(); parse_params P "$@"
  local to="${P[timeout]:-$HTTP_TIMEOUT}"
  local lw="${P[latency_warn_ms]:-$HTTP_LAT_WARN_MS}"
  local lc="${P[latency_crit_ms]:-$HTTP_LAT_CRIT_MS}"
  local exp="${P[expect]:-$HTTP_EXPECT}"

  if ! lm_ssh "$onhost" "command -v curl >/dev/null"; then
    lm_err "[$onhost] http $url curl missing"
    append_alert "$onhost|http|$url|curl_missing"
    return
  fi

  local line; line="$(lm_ssh "$onhost" "curl -sS -o /dev/null -w '%{http_code} %{time_total}' --max-time $to '$url'")"
  local code time_s ms="?"
  code="$(echo "$line" | awk '{print $1}')"
  time_s="$(echo "$line" | awk '{print $2}')"
  [ -n "$time_s" ] && ms="$(awk -v t="$time_s" 'BEGIN{printf("%.0f", t*1000)}')"

  local status="OK" note=""
  if ! http_code_ok "$code" "$exp"; then
    status="CRIT"; note="bad_status:$code"
  fi
  if [ "$ms" != "?" ] && [ "$ms" -ge "$lc" ]; then
    status="CRIT"; note="${note:+$note,}lat_ge_${lc}ms"
  elif [ "$status" = "OK" ] && [ "$ms" -ge "$lw" ]; then
    status="WARN"; note="lat_ge_${lw}ms"
  fi

  lm_info "[$onhost] [$status] http $url code=$code ms=$ms ${note:+note=$note}"
  [ "$status" != "OK" ] && append_alert "$onhost|http|$url|$note"
}

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  lm_info "===== Network checks from $host ====="

  local checked=0

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    append_alert "$host|ssh|$host|ssh_unreachable"
    return
  fi

  [ -s "$TARGETS" ] || { lm_err "[$host] targets file $TARGETS missing/empty"; return; }

  # Rows for this host (* or exact), require at least 3 columns
  while IFS=',' read -r _thost check target rest; do
    checked=$((checked+1))
    IFS=',' read -r -a kv <<<"${rest}"
    case "$check" in
      ping) run_ping "$host" "$target" "${kv[@]}" ;;
      tcp)  run_tcp  "$host" "$target" "${kv[@]}" ;;
      http|https) run_http "$host" "$target" "${kv[@]}" ;;
      *) lm_warn "[$host] unknown check '$check' for target '$target'";;
    esac
  done < <(lm_csv_rows_for_host "$TARGETS" "$host" 3)

  lm_info "===== Completed $host ====="
  local failures=0
  failures=$( [ -f "$ALERTS_FILE" ] && wc -l < "$ALERTS_FILE" 2>/dev/null || echo 0 )
  status=$( [ "$failures" -gt 0 ] && echo CRIT || echo OK )
  lm_summary "network_monitor" "$host" "$status" checked=$checked failures=$failures
  # legacy:
  # echo "network_monitor host=$host status=$status checked=$checked failures=$failures"

}
# ========================
# Main
# ========================
lm_info "=== Network Monitor Started ==="
lm_for_each_host run_for_host

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="Network checks: WARN/CRIT detected"
  body="From network_monitor.sh:

Host | Check | Target | Note
----------------------------
$(echo "$alerts" | awk -F'|' 'NF>=4{printf "%s | %s | %s | %s\n",$1,$2,$3,$4}') 

Defaults: ping(count=$PING_COUNT,timeout=$PING_TIMEOUT,loss${PING_LOSS_WARN}/${PING_LOSS_CRIT},rtt${PING_RTT_WARN_MS}/${PING_RTT_CRIT_MS}ms),
tcp(timeout=$TCP_TIMEOUT,lat${TCP_LAT_WARN_MS}/${TCP_LAT_CRIT_MS}ms),
http(timeout=$HTTP_TIMEOUT,lat${HTTP_LAT_WARN_MS}/${HTTP_LAT_CRIT_MS}ms,expect=${HTTP_EXPECT:-200-399})."
  lm_mail "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Network Monitor Finished ==="
