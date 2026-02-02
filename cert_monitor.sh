#!/bin/bash
# cert_monitor.sh - Monitor TLS certificate expiry and validity for endpoints
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Checks TLS certificates for a list of endpoints and optional SNI/STARTTLS.
#   Reports days-until-expiry, issuer/subject, and OpenSSL verify status.
#   Logs concise lines and emails a single aggregated alert.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[cert_monitor] "
LM_LOGFILE="/var/log/cert_monitor.log"
: "${LM_EMAIL_ENABLED:=true}"
lm_require_singleton "cert_monitor"
mkdir -p "$(dirname "$LM_LOGFILE")"

MAIL_SUBJECT_PREFIX='[Cert Monitor]'

# ========================
# Configuration
# ========================
TARGETS_FILE="/etc/linux_maint/certs.txt"   # Formats (one per line):
#  host[:port]                               # default port 443
#  [ipv6]:port
#  host:port,sni=example.com
#  host:port,starttls=smtp
#  host:port,sni=example.com,starttls=imap
THRESHOLD_WARN_DAYS=30
THRESHOLD_CRIT_DAYS=7
TIMEOUT_SECS=10
EMAIL_ON_WARN="true"

# ========================
# Helpers (script-local)
# ========================
mail_if_enabled(){ [ "$EMAIL_ON_WARN" = "true" ] || return 0; lm_mail "$1" "$2"; }

parse_target_line() {
  # Input line -> HOST|PORT|SNI|STARTTLS
  local line="$1" hostport sni starttls host port extra token
  sni=""; starttls=""; host=""; port="443"

  # split head (host[:port] / [ipv6]:port) from extras
  hostport="${line%%,*}"
  extra="${line#"$hostport"}"
  extra="${extra#,}"  # remove leading comma if present

  # host/port parsing
  if [[ "$hostport" =~ ^\[.*\]:[0-9]+$ ]]; then
    host="${hostport%\]*}"; host="${host#[}"; port="${hostport##*:}"
  else
    # if exactly one colon and digits after it -> treat as host:port; else default 443
    if [[ "$hostport" == *:* ]] && [ "$(printf "%s" "$hostport" | grep -o ":" | wc -l)" -eq 1 ] && [[ "${hostport##*:}" =~ ^[0-9]+$ ]]; then
      host="${hostport%%:*}"; port="${hostport##*:}"
    else
      host="$hostport"; port="443"
    fi
  fi

  # parse extras (order-independent)
  IFS=',' read -r -a arr <<< "$extra"
  for token in "${arr[@]}"; do
    [ -z "$token" ] && continue
    case "$token" in
      sni=*)       sni="${token#sni=}" ;;
      starttls=*)  starttls="${token#starttls=}" ;;
      *)           [ -z "$sni" ] && sni="$token" ;;  # bare token treated as SNI
    esac
  done
  [ -z "$sni" ] && sni="$host"
  printf "%s|%s|%s|%s\n" "$host" "$port" "$sni" "$starttls"
}

extract_leaf_cert() {
  # Reads s_client output on stdin, prints the first cert PEM block
  awk '
    /-----BEGIN CERTIFICATE-----/ {inblk=1}
    inblk {print}
    /-----END CERTIFICATE-----/ {exit}
  '
}

check_one() {
  local host="$1" port="$2" sni="$3" starttls="$4"
  local cmd="openssl s_client -servername \"$sni\" -connect \"$host:$port\" -showcerts"
  [ -n "$starttls" ] && cmd="$cmd -starttls $starttls"

  local out
  out=$(timeout "${TIMEOUT_SECS}s" bash -lc "$cmd < /dev/null 2>/dev/null") || out=""

  if [ -z "$out" ]; then
    echo "status=CRIT host=$host port=$port sni=$sni days=? verify=? subject=? issuer=? note=connection_failed"
    return
  fi

  # Verify return code
  local verify_line verify_code verify_desc
  verify_line=$(printf "%s\n" "$out" | awk '/Verify return code:/ {line=$0} END{print line}')
  verify_code=$(printf "%s\n" "$verify_line" | sed -n 's/.*Verify return code: \([0-9]\+\).*/\1/p')
  verify_desc=$(printf "%s\n" "$verify_line" | sed -n 's/.*Verify return code: [0-9]\+ (\(.*\)).*/\1/p')
  [ -z "$verify_code" ] && verify_code="?"

  # Leaf certificate fields
  local leaf subject issuer enddate
  leaf="$(printf "%s\n" "$out" | extract_leaf_cert)"
  if [ -z "$leaf" ]; then
    echo "status=CRIT host=$host port=$port sni=$sni days=? verify=$verify_code/$verify_desc subject=? issuer=? note=no_leaf_cert"
    return
  fi

  subject="$(printf "%s" "$leaf" | openssl x509 -noout -subject 2>/dev/null | sed 's/^subject= *//')"
  issuer="$(printf "%s" "$leaf" | openssl x509 -noout -issuer 2>/dev/null | sed 's/^issuer= *//')"
  enddate="$(printf "%s" "$leaf" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"

  local exp_epoch now_epoch days_left
  exp_epoch=$(date -u -d "$enddate" +%s 2>/dev/null) || exp_epoch=0
  now_epoch=$(date -u +%s)
  if [ "$exp_epoch" -eq 0 ]; then
    days_left="?"
  else
    days_left=$(( (exp_epoch - now_epoch) / 86400 ))
  fi

  # Status
  local status="OK" note=""
  if [ "$days_left" = "?" ]; then
    status="WARN"; note="date_parse_error"
  elif [ "$days_left" -lt 0 ]; then
    status="CRIT"; note="expired"
  elif [ "$days_left" -le "$THRESHOLD_CRIT_DAYS" ]; then
    status="CRIT"; note="<=${THRESHOLD_CRIT_DAYS}d"
  elif [ "$days_left" -le "$THRESHOLD_WARN_DAYS" ]; then
    status="WARN"; note="<=${THRESHOLD_WARN_DAYS}d"
  fi
  if [ "$verify_code" != "0" ] && [ "$verify_code" != "?" ] && [ "$status" = "OK" ]; then
    status="WARN"; note="verify:$verify_desc"
  fi

  # shell-quote subject/issuer minimally (avoid breaking logs)
  subject="${subject//\"/\\\"}"
  issuer="${issuer//\"/\\\"}"

  echo "status=$status host=$host port=$port sni=$sni days=$days_left verify=$verify_code/$verify_desc subject=\"$subject\" issuer=\"$issuer\" note=$note"
}

# ========================
# Main
# ========================
lm_info "=== Cert Monitor Started (warn=${THRESHOLD_WARN_DAYS}d crit=${THRESHOLD_CRIT_DAYS}d timeout=${TIMEOUT_SECS}s) ==="

[ -s "$TARGETS_FILE" ] || { lm_err "Targets file not found/empty: $TARGETS_FILE"; exit 1; }

ALERTS_FILE="$(mktemp -p "${LM_STATE_DIR:-/var/tmp}" cert_monitor.alerts.XXXXXX)"
while IFS= read -r raw; do
  raw="$(echo "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [ -z "$raw" ] && continue
  [[ "$raw" =~ ^# ]] && continue

  IFS='|' read -r HOST PORT SNI STARTTLS <<<"$(parse_target_line "$raw")"
  res="$(check_one "$HOST" "$PORT" "$SNI" "$STARTTLS")"

  status="$(printf "%s\n" "$res" | awk '{for(i=1;i<=NF;i++) if($i ~ /^status=/){print substr($i,8)}}')"
  days="$(  printf "%s\n" "$res" | awk '{for(i=1;i<=NF;i++) if($i ~ /^days=/){print substr($i,6)}}')"
  verify="$(printf "%s\n" "$res" | awk '{for(i=1;i<=NF;i++) if($i ~ /^verify=/){print substr($i,8)}}')"
  note="$(  printf "%s\n" "$res" | awk '{for(i=1;i<=NF;i++) if($i ~ /^note=/){print substr($i,6)}}')"

  lm_info "[$status] $HOST:$PORT (SNI=$SNI) days_left=${days:-?} verify=$verify ${note:+note=$note}"

  if [ "$status" = "WARN" ] || [ "$status" = "CRIT" ]; then
    printf "%s|%s|%s|%s|%s|%s\n" "$HOST:$PORT" "$SNI" "${days:-?}" "$verify" "$status" "$note" >> "$ALERTS_FILE"
  fi
done < "$TARGETS_FILE"

alerts="$(cat "$ALERTS_FILE" 2>/dev/null)"
rm -f "$ALERTS_FILE" 2>/dev/null || true

if [ -n "$alerts" ]; then
  subject="Certificates require attention"
  body="Thresholds: WARN<=${THRESHOLD_WARN_DAYS}d, CRIT<=${THRESHOLD_CRIT_DAYS}d (or expired)

Endpoint | SNI | Days Left | Verify | Status | Note
---------|-----|-----------|--------|--------|-----
$(echo "$alerts" | awk -F'|' '{printf "%s | %s | %s | %s | %s | %s\n",$1,$2,$3,$4,$5,(NF>=6?$6:"")}')

This is an automated message from cert_monitor.sh."
  mail_if_enabled "$MAIL_SUBJECT_PREFIX $subject" "$body"
fi

lm_info "=== Cert Monitor Finished ==="
