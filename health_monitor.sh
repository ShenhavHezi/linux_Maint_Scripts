#!/bin/bash
# distributed_health_monitor.sh - Run health checks on multiple Linux servers
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Collects CPU, memory, load average, and disk usage from all servers listed in SERVERLIST.
#   Skips servers listed in EXCLUDELIST.
#   Logs results to LOGFILE and emails report to addresses in ALERT_EMAIL.

# --- Configuration ---
SERVERLIST="/etc/linux_maint/servers.txt"      # List of servers
EXCLUDELIST="/etc/linux_maint/excluded.txt"    # List of excluded servers
ALERT_EMAIL="/etc/linux_maint/emails.txt"      # Email recipients
LOGFILE="/var/log/health_monitor.log"          # Log file
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# --- Ensure log directory exists ---
mkdir -p "$(dirname "$LOGFILE")"

# --- Start log ---
echo "==============================================" >> "$LOGFILE"
echo " Linux Distributed Health Check "              >> "$LOGFILE"
echo " Date: $DATE"                                  >> "$LOGFILE"
echo "==============================================" >> "$LOGFILE"

# --- Function to check if a server is excluded ---
is_excluded() {
    grep -qx "$1" "$EXCLUDELIST" 2>/dev/null
}

# --- Loop through servers ---
while read -r server; do
    # Skip empty lines or comments
    [[ -z "$server" || "$server" =~ ^# ]] && continue

    if is_excluded "$server"; then
        echo "Skipping excluded server: $server" >> "$LOGFILE"
        continue
    fi

    echo ">>> Health check on $server ($DATE)" >> "$LOGFILE"

    ssh -o ConnectTimeout=10 "$server" bash -s << 'EOF' >> "$LOGFILE" 2>&1
        echo "--- Hostname: $(hostname)"
        echo "--- Uptime:"
        uptime
        echo "--- CPU Load:"
        top -bn1 | grep "load average"
        echo "--- Memory Usage (MB):"
        free -m
        echo "--- Disk Usage:"
        df -hT | grep -E "^/dev"
        echo "--- Top 5 Processes by CPU:"
        ps -eo pid,comm,%cpu,%mem --sort=-%cpu | head -6
        echo "--- Top 5 Processes by Memory:"
        ps -eo pid,comm,%cpu,%mem --sort=-%mem | head -6
        echo "----------------------------------------------"
EOF

done < "$SERVERLIST"

# --- Email report ---
if [ -s "$ALERT_EMAIL" ]; then
    mail -s "Linux Health Check Report - $DATE" $(cat "$ALERT_EMAIL") < "$LOGFILE"
fi
