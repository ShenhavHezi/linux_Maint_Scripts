#!/bin/bash
# shellcheck disable=SC1090
set -euo pipefail

# Defaults for standalone runs (wrapper sets these)
: "${LM_LOCKDIR:=/tmp}"
: "${LM_LOG_DIR:=.logs}"

# Dependency checks (local runner)
lm_require_cmd "inventory_export" "localhost" awk || exit $?
lm_require_cmd "inventory_export" "localhost" flock || exit $?
lm_require_cmd "inventory_export" "localhost" grep || exit $?
lm_require_cmd "inventory_export" "localhost" sed || exit $?
lm_require_cmd "inventory_export" "localhost" sort || exit $?
lm_require_cmd "inventory_export" "localhost" tr || exit $?
lm_require_cmd "inventory_export" "localhost" wc || exit $?
lm_require_cmd "inventory_export" "localhost" paste || exit $?
lm_require_cmd "inventory_export" "localhost" ip || exit $?
lm_require_cmd "inventory_export" "localhost" df || exit $?
lm_require_cmd "inventory_export" "localhost" lsblk || exit $?
lm_require_cmd "inventory_export" "localhost" free || exit $?
lm_require_cmd "inventory_export" "localhost" hostname || exit $?
lm_require_cmd "inventory_export" "localhost" uname || exit $?
lm_require_cmd "inventory_export" "localhost" date || exit $?
lm_require_cmd "inventory_export" "localhost" nproc || exit $?
lm_require_cmd "inventory_export" "localhost" lscpu --optional || true
lm_require_cmd "inventory_export" "localhost" vgs --optional || true
lm_require_cmd "inventory_export" "localhost" lvs --optional || true
lm_require_cmd "inventory_export" "localhost" pvs --optional || true
lm_require_cmd "inventory_export" "localhost" systemd-detect-virt --optional || true

# inventory_export.sh - Export concise HW/SW inventory per host to a daily CSV (+details)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)

# ===== Shared helpers =====
. "${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}" || { echo "Missing ${LINUX_MAINT_LIB:-/usr/local/lib/linux_maint.sh}"; exit 1; }
LM_PREFIX="[inventory_export] "
LM_LOGFILE="${LM_LOGFILE:-/var/log/inventory_export.log}"
: "${LM_MAX_PARALLEL:=0}"     # 0=sequential; set >0 to run hosts concurrently
: "${LM_EMAIL_ENABLED:=true}" # master email toggle

lm_require_singleton "inventory_export"

# ========================
# Script configuration
# ========================
OUTPUT_DIR="/var/log/inventory"
DETAILS_DIR="${OUTPUT_DIR}/details"

# Email (optional): send a short summary when the run finishes
MAIL_ON_RUN="false"
MAIL_SUBJECT_PREFIX='[Inventory Export]'

# ========================
# Helpers
# ========================
ensure_dirs(){ mkdir -p "$(dirname "$LM_LOGFILE")" "$OUTPUT_DIR" "$DETAILS_DIR"; }
csv_escape(){ local s="$1"; s="${s//\"/\"\"}"; printf "\"%s\"" "$s"; }

# ---- CSV header + append with flock (safe under parallelism) ----
write_csv_header_if_needed(){
  local csv_file="$1"
  local lock="${csv_file}.lock"
  mkdir -p "$(dirname "$csv_file")"
  (
    flock -x 9
    if [ ! -f "$csv_file" ]; then
      printf "%s\n" "date,host,fqdn,os,kernel,arch,virt,uptime,cpu_model,sockets,cores_per_socket,threads_per_core,vcpus,mem_mb,swap_mb,disk_total_gb,rootfs_use,vgs,lvs,pvs,vgs_size_gb,ip_list,default_gw,dns_servers,pkg_count" > "$csv_file"
    fi
  ) 9>"$lock"
}

append_csv_row_locked(){
  local csv_file="$1"; shift
  local lock="${csv_file}.lock"
  (
    flock -x 9
    {
      csv_escape "$1";  printf ",";   # date
      csv_escape "$2";  printf ",";   # host
      csv_escape "$3";  printf ",";   # fqdn
      csv_escape "$4";  printf ",";   # os
      csv_escape "$5";  printf ",";   # kernel
      csv_escape "$6";  printf ",";   # arch
      csv_escape "$7";  printf ",";   # virt
      csv_escape "$8";  printf ",";   # uptime
      csv_escape "$9";  printf ",";   # cpu_model
      csv_escape "${10}"; printf ","; # sockets
      csv_escape "${11}"; printf ","; # cores_per_socket
      csv_escape "${12}"; printf ","; # threads_per_core
      csv_escape "${13}"; printf ","; # vcpus
      csv_escape "${14}"; printf ","; # mem_mb
      csv_escape "${15}"; printf ","; # swap_mb
      csv_escape "${16}"; printf ","; # disk_total_gb
      csv_escape "${17}"; printf ","; # rootfs_use
      csv_escape "${18}"; printf ","; # vgs
      csv_escape "${19}"; printf ","; # lvs
      csv_escape "${20}"; printf ","; # pvs
      csv_escape "${21}"; printf ","; # vgs_size_gb
      csv_escape "${22}"; printf ","; # ip_list
      csv_escape "${23}"; printf ","; # default_gw
      csv_escape "${24}"; printf ","; # dns_servers
      csv_escape "${25}";             # pkg_count
      printf "\n"
    } >> "$csv_file"
  ) 9>"$lock"
}

# Remote collector: emit KEY=value lines for all fields the CSV expects.
remote_inv_cmd='
DATE="$(date -Iseconds)"
host="$(hostname -s)"
fqdn="$(hostname -f 2>/dev/null || echo "$host")"
if [ -r /etc/os-release ]; then . /etc/os-release; os="$PRETTY_NAME"; else os="$(uname -s)"; fi
kernel="$(uname -r)"
arch="$(uname -m)"
virt="$(command -v systemd-detect-virt >/dev/null && systemd-detect-virt || echo unknown)"
uptime_p="$(uptime -p 2>/dev/null || echo "")"
cpu_model="$(lscpu 2>/dev/null | awk -F: "/Model name|Model Name/{sub(/^ +/,\"\",\$2); print \$2; exit}")"
sockets="$(lscpu 2>/dev/null | awk -F: "/Socket\\(s\\)/{gsub(/ /,\"\",\$2); print \$2; exit}")"
cores_per_socket="$(lscpu 2>/dev/null | awk -F: "/Core\\(s\\) per socket/{gsub(/ /,\"\",\$2); print \$2; exit}")"
threads_per_core="$(lscpu 2>/dev/null | awk -F: "/Thread\\(s\\) per core/{gsub(/ /,\"\",\$2); print \$2; exit}")"
vcpus="$(nproc 2>/dev/null || lscpu 2>/dev/null | awk -F: "/CPU\\(s\\)/{gsub(/ /,\"\",\$2); print \$2; exit}")"
mem_mb="$(free -m 2>/dev/null | awk \"/Mem:/{print \$2}\")"
swap_mb="$(free -m 2>/dev/null | awk \"/Swap:/{print \$2}\")"
disk_total_gb="$(lsblk -b -d -o SIZE,TYPE 2>/dev/null | awk \"/disk/{s+=\\$1} END{printf \\\"%.0f\\\", s/1024/1024/1024}\")"
rootfs_pct="$(df -P / 2>/dev/null | awk \"NR==2{print \\$5}\")"
vgs_count="$(vgs --noheadings 2>/dev/null | wc -l | tr -d \" \")"
lvs_count="$(lvs --noheadings 2>/dev/null | wc -l | tr -d \" \")"
pvs_count="$(pvs --noheadings 2>/dev/null | wc -l | tr -d \" \")"
vgs_size_gb="$(vgs --noheadings -o vg_size --units g 2>/dev/null | awk \"{gsub(/g/i,\\\"\\\"); if(\\$1>0) s+=\\$1} END{if(s>0) printf \\\"%.0f\\\", s;}\")"
ips="$(ip -o -4 addr show scope global 2>/dev/null | awk \"{print \\$4}\" | sed -e \"s#/.*##\" | paste -sd \";\" -)"
gw="$(ip route show default 2>/dev/null | awk \"/default/{print \\$3; exit}\")"
dns="$(awk \"/^nameserver/{print \\$2}\" /etc/resolv.conf 2>/dev/null | paste -sd \";\" -)"
pkg_count=\"\"
if command -v dpkg-query >/dev/null; then pkg_count=$(dpkg-query -f \".\" -W 2>/dev/null | wc -c); fi
if [ -z \"$pkg_count\" ] && command -v rpm >/dev/null; then pkg_count=$(rpm -qa 2>/dev/null | wc -l); fi

# Emit lines
echo "DATE=$DATE"
echo "HOST=$host"
echo "FQDN=$fqdn"
echo "OS=$os"
echo "KERNEL=$kernel"
echo "ARCH=$arch"
echo "VIRT=$virt"
echo "UPTIME=$uptime_p"
echo "CPU_MODEL=$cpu_model"
echo "SOCKETS=$sockets"
echo "CORES_PER_SOCKET=$cores_per_socket"
echo "THREADS_PER_CORE=$threads_per_core"
echo "VCPUS=$vcpus"
echo "MEM_MB=$mem_mb"
echo "SWAP_MB=$swap_mb"
echo "DISK_TOTAL_GB=$disk_total_gb"
echo "ROOTFS_USE=$rootfs_pct"
echo "VGS=$vgs_count"
echo "LVS=$lvs_count"
echo "PVS=$pvs_count"
echo "VGS_SIZE_GB=$vgs_size_gb"
echo "IPS=$ips"
echo "GW=$gw"
echo "DNS=$dns"
echo "PKG_COUNT=$pkg_count"
'

# Remote "details" snapshot for human-friendly context
remote_details_cmd='
echo "===== Host ====="; hostnamectl 2>/dev/null || true
echo
echo "===== CPU ====="; lscpu 2>/dev/null || true
echo
echo "===== Memory ====="; free -h 2>/dev/null || true
echo
echo "===== Block Devices (lsblk) ====="; lsblk -o NAME,TYPE,SIZE,ROTA,SERIAL,MODEL 2>/dev/null || true
echo
echo "===== Filesystems (df -hT) ====="; df -hT 2>/dev/null || true
echo
echo "===== LVM (vgs) ====="; vgs -o vg_name,vg_size,vg_free,vg_attr --noheadings 2>/dev/null || true
echo
echo "===== LVM (lvs) ====="; lvs -o vg_name,lv_name,lv_size,attr --noheadings 2>/dev/null || true
echo
echo "===== Network (ip -4 addr) ====="; ip -o -4 addr show 2>/dev/null || true
echo
echo "===== Routes ====="; ip route 2>/dev/null || true
'

# ========================
# Globals for this run
# ========================
DATE_SHORT="$(date +%Y-%m-%d)"
CSV_FILE="${OUTPUT_DIR}/inventory_${DATE_SHORT}.csv"

# ========================
# Per-host worker
# ========================
run_for_host(){
  local host="$1"

  lm_info "===== Collecting inventory on $host ====="

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable"
    lm_summary "inventory_export" "$host" "CRIT" reason=ssh_unreachable
    return 2
  fi

  # --- inventory values ---
  declare -A V
  while IFS='=' read -r k v; do
    [ -z "$k" ] && continue
    V["$k"]="$v"
  done < <(lm_ssh "$host" bash -lc "'$remote_inv_cmd'")

  write_csv_header_if_needed "$CSV_FILE"
  append_csv_row_locked "$CSV_FILE" \
    "${V[DATE]}" "${V[HOST]}" "${V[FQDN]}" "${V[OS]}" "${V[KERNEL]}" "${V[ARCH]}" "${V[VIRT]}" "${V[UPTIME]}" \
    "${V[CPU_MODEL]}" "${V[SOCKETS]}" "${V[CORES_PER_SOCKET]}" "${V[THREADS_PER_CORE]}" "${V[VCPUS]}" \
    "${V[MEM_MB]}" "${V[SWAP_MB]}" "${V[DISK_TOTAL_GB]}" "${V[ROOTFS_USE]}" \
    "${V[VGS]}" "${V[LVS]}" "${V[PVS]}" "${V[VGS_SIZE_GB]}" \
    "${V[IPS]}" "${V[GW]}" "${V[DNS]}" "${V[PKG_COUNT]}"

  lm_info "[$host] row appended: os=${V[OS]} arch=${V[ARCH]} cpu=${V[CPU_MODEL]} mem=${V[MEM_MB]}MB disks=${V[DISK_TOTAL_GB]}GB vgs=${V[VGS]} lvs=${V[LVS]}"

  # --- details snapshot ---
  local details="${DETAILS_DIR}/${V[HOST]}_${DATE_SHORT}.txt"
  lm_ssh "$host" bash -lc "'$remote_details_cmd'" > "$details"
  lm_info "[$host] details -> $details"

  lm_info "===== Completed $host ====="
}

# ========================
# Main
# ========================
ensure_dirs
lm_info "=== Inventory Export Started (CSV: $CSV_FILE) ==="

lm_for_each_host_rc run_for_host
worst=$?
# Continue to write summary and optionally mail; exit with worst at end


# One-line summary to stdout (for wrapper logs)
today_csv="$OUTPUT_DIR/inventory_$(date +%F).csv"
rows=0
[ -f "$today_csv" ] && rows=$(($(wc -l < "$today_csv" 2>/dev/null || echo 1)-1))
lm_summary "inventory_export" "runner" "OK" csv="$today_csv" hosts=${rows:-0}
# legacy:
# echo inventory_export summary status=OK csv="$today_csv" hosts=${rows:-0}
exit "$worst"
lm_info "=== Inventory Export Finished ==="

if [ "$MAIL_ON_RUN" = "true" ]; then
  lm_mail "$MAIL_SUBJECT_PREFIX Inventory CSV ready" "Inventory written to: $CSV_FILE"
fi
