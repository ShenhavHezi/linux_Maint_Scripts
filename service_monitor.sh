#!/bin/bash
# service_monitor.sh - Monitor critical services across multiple servers
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Checks status of system services (sshd, cron, nginx, etc.)
#   across multiple Linux servers. Logs results and alerts if
#   any service is inactive or failed. Optionally restarts services.

# ========================
# Configuration Variables
# ========================
SERVERLIST="/etc/linux_maint/servers.txt"   # List of servers
SERVICES="/etc/linux_maint/services.txt"    # List of services to check
LOGFILE="/var/log/service_monitor.log"      # Log file
ALERT_EMAILS="/etc/linux_maint/emails.txt"  # Email recipients (optional)
AUTO_RESTART="false"                        # Set to "true" to auto-restart failed services

# ========================
# Helper Functions
# ========================

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

check_service() {
    local HOST=$1
    local SERVICE=$2

    STATUS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
        "systemctl is-active $SERVICE 2>/dev/null || service $SERVICE status 2>/dev/null | grep -q 'running' && echo running")

    if [[ "$STATUS" == "active" || "$STATUS" == "running" ]]; then
        log_message "[$HOST] [OK] $SERVICE is active"
    else
        log_message "[$HOST] [FAIL] $SERVICE is NOT active"
        if [ "$AUTO_RESTART" == "true" ]; then
            ssh "$HOST" "systemctl restart $SERVICE 2>/dev/null || service $SERVICE restart 2>/dev/null"
            log_message "[$HOST] Attempted restart of $SERVICE"
        fi
    fi
}

check_server() {
    local HOST=$1
    log_message "===== Starting service checks on $HOST ====="

    for SERVICE in $(cat "$SERVICES"); do
        check_service "$HOST" "$SERVICE"
    done

    log_message "===== Completed service checks on $HOST ====="
}

# ========================
# Main Execution
# ========================
log_message "=== Service Monitor Script Started ==="

if [ ! -f "$SERVERLIST" ]; then
    log_message "ERROR: Server list file $SERVERLIST not found!"
    exit 1
fi

if [ ! -f "$SERVICES" ]; then
    log_message "ERROR: Services file $SERVICES not found!"
    exit 1
fi

for SERVER in $(cat "$SERVERLIST"); do
    check_server "$SERVER"
done

log_message "=== Service Monitor Script Finished ==="
