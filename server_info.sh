#!/bin/bash
# servers_info.sh - Collect detailed server information daily (distributed)
# Author: Shenhav_Hezi
# Version: 2.0 (refactored to use linux_maint.sh)
# Description:
#   Gathers system, hardware, network, storage, and security information
#   for auditing and troubleshooting across distributed Linux systems.
#   Saves output to LOGDIR with hostname and date.

# ===== Shared helpers =====
. /usr/local/lib/linux_maint.sh || { echo "Missing /usr/local/lib/linux_maint.sh"; exit 1; }
LM_PREFIX="[servers_info] "
LM_LOGFILE="/var/log/servers_info.log"
: "${LM_MAX_PARALLEL:=0}"     # 0 = sequential; set >0 to run hosts concurrently

lm_require_singleton "servers_info"

# ========================
# Configuration
# ========================
LOGDIR="/var/log/server_info"
DATE_SHORT="$(date +%Y-%m-%d)"

# Ensure local dirs
mkdir -p "$LOGDIR" "$(dirname "$LM_LOGFILE")"

# ========================
# Remote report snippet
# ========================
read -r -d '' remote_info_cmd <<'EOS'
HOST="$(hostname -s)"
DATE="$(date +%Y-%m-%d)"
echo "===== Server Info Report - ${HOST} - ${DATE} ====="
echo

### 1. General System Info
echo ">>> GENERAL SYSTEM INFO"
if command -v hostnamectl >/dev/null 2>&1; then
  hostnamectl
else
  uname -a
fi
uptime || true
echo

### 2. CPU & Memory
echo ">>> CPU & MEMORY"
( lscpu 2>/dev/null | grep -E 'Model name|Socket|CPU\(s\)' ) || true
free -h 2>/dev/null || true
echo "Load Average: $(cat /proc/loadavg 2>/dev/null || echo '? ? ?')"
echo

### 3. Disk & Filesystems
echo ">>> DISK & FILESYSTEMS"
df -hT 2>/dev/null || true
lsblk 2>/dev/null || true
( mount 2>/dev/null | grep -E '^/' ) || true
echo

### 4. Volume Groups & LVM
echo ">>> LVM CONFIGURATION"
vgs 2>/dev/null || echo "No volume groups"
lvs 2>/dev/null || echo "No logical volumes"
pvs 2>/dev/null || echo "No physical volumes"
echo

### 5. RAID / Multipath
echo ">>> RAID / MULTIPATH"
( cat /proc/mdstat 2>/dev/null ) || echo "No RAID configured"
multipath -ll 2>/dev/null || echo "No multipath devices"
echo

### 6. Network Info
echo ">>> NETWORK CONFIGURATION"
ip a 2>/dev/null || true
ip route 2>/dev/null || true
( ss -H -tulpen 2>/dev/null || ss -H -tuln 2>/dev/null ) || true
echo

### 7. Users & Access
echo ">>> USERS & ACCESS"
who 2>/dev/null || true
last -n 10 2>/dev/null || true
( getent group sudo 2>/dev/null || getent group wheel 2>/dev/null || true )
echo

### 8. Services & Processes
echo ">>> RUNNING SERVICES & PROCESSES"
if command -v systemctl >/dev/null 2>&1; then
  systemctl list-units --type=service --state=running 2>/dev/null || true
else
  service --status-all 2>/dev/null || rc-service -S 2>/dev/null || true
fi
echo
echo "Top 10 processes by memory:"
ps aux --sort=-%mem 2>/dev/null | head -n 11 || true
echo
echo "Top 10 processes by CPU:"
ps aux --sort=-%cpu 2>/dev/null | head -n 11 || true
echo

### 9. Security & Configurations
echo ">>> SECURITY CONFIGURATION"
( iptables -L -n 2>/dev/null || firewall-cmd --list-all 2>/dev/null ) || echo "No firewall detected"
sestatus 2>/dev/null || echo "SELinux not installed/enabled"
echo

### 10. Packages & Updates
echo ">>> PACKAGE STATUS"
if command -v apt >/dev/null 2>&1; then
  apt list --upgradable 2>/dev/null | grep -v '^Listing' || true
elif command -v yum >/dev/null 2>&1; then
  yum check-update 2>/dev/null || true
elif command -v dnf >/dev/null 2>&1; then
  dnf check-update 2>/dev/null || true
fi
echo

echo "===== End of Report for ${HOST} ====="
EOS

# ========================
# Per-host runner
# ========================
run_for_host(){
  local host="$1"
  local report="${LOGDIR}/${host}_info_${DATE_SHORT}.log"

  lm_info "Collecting server info on $host -> $report"

  if ! lm_reachable "$host"; then
    lm_err "[$host] SSH unreachable; writing stub report"
    {
      echo "===== Server Info Report - ${host} - ${DATE_SHORT} ====="
      echo
      echo "ERROR: SSH unreachable from collector host at $(date '+%Y-%m-%d %H:%M:%S')"
      echo "===== End of Report for ${host} ====="
    } > "$report"
    return
  fi

  # Run remote snippet and capture output to local report file
  lm_ssh "$host" bash -lc "$remote_info_cmd" > "$report" 2>&1 || {
    lm_err "[$host] remote snippet failed (partial output saved)"
  }

  lm_info "Completed $host"
}

# ========================
# Main
# ========================
lm_info "=== servers_info run started (output dir: $LOGDIR) ==="
lm_for_each_host run_for_host
lm_info "=== servers_info run finished ==="
