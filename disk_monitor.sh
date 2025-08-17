#!/bin/bash
# distributed_disk_monitor.sh - Run disk usage checks on multiple servers
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Checks disk usage on all servers listed in SERVERLIST.
#   Alerts if usage exceeds THRESHOLD.
#   Logs results to LOGFILE and emails alerts to addresses in ALERT_EMAIL.

# ========================
# Configurable Parameters
# ========================
THRESHOLD=90
LOGFILE="/var/log/disks_monitor.log"
ALERT_EMAIL="/etc/linux_maint/emails.txt"   # File with one email per line, or "mail1,mail2,mail3"
SERVERLIST="/etc/linux_maint/servers.txt"   # File with one server per line, or "server1,server2,server3"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# ========================
# Helper Functions
# ========================
log_message() {
    echo "[$DATE] $1" | tee -a "$LOGFILE"
}

get_emails() {
    if [[ -f "$ALERT_EMAIL" ]]; then
        tr '\n' ' ' < "$ALERT_EMAIL"
    else
        echo "$ALERT_EMAIL" | tr ',' ' '
    fi
}

get_servers() {
    if [[ -f "$SERVERLIST" ]]; then
        cat "$SERVERLIST"
    else
        echo "$SERVERLIST" | tr ',' ' '
    fi
}

send_alert() {
    local server=$1
    local filesystem=$2
    local usage=$3
    local recipients
    recipients=$(get_emails)

    if [[ -n "$recipients" ]]; then
        echo -e "Warning: $filesystem on $server is at ${usage}% usage\nChecked at: $DATE" \
        | mail -s "Disk Usage Alert: $server - $filesystem ${usage}%" $recipients
    fi
}

# ========================
# Main Script
# ========================
log_message "=== Starting distributed disk check (Threshold: $THRESHOLD%) ==="

for server in $(get_servers); do
    [[ -z "$server" ]] && continue
    log_message "Checking server: $server"

    ssh -o BatchMode=yes -o ConnectTimeout=5 "$server" \
        "df -hP | grep -vE '^Filesystem|tmpfs|devtmpfs'" 2>/dev/null | while read -r line; do
        filesystem=$(echo "$line" | awk '{print $1}')
        usage=$(echo "$line" | awk '{print $5}' | tr -d '%')
        mountpoint=$(echo "$line" | awk '{print $6}')

        if (( usage >= THRESHOLD )); then
            log_message "ALERT: $server - $filesystem mounted on $mountpoint is at ${usage}%"
            send_alert "$server" "$filesystem ($mountpoint)" "$usage"
        else
            log_message "OK: $server - $filesystem mounted on $mountpoint is at ${usage}%"
        fi
    done
done

log_message "=== Distributed disk check completed ==="
exit 0
