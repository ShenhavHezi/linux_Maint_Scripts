#!/bin/bash
# user_monitor.sh - Monitor user and SSH access across multiple servers
# Author: Shenhav_Hezi
# Version: 1.0
# Description:
#   Checks for unauthorized changes in system users and sudoers,
#   and monitors failed SSH login attempts. Can run locally or
#   across multiple servers listed in SERVERLIST.
#   Logs results and alerts if anomalies are detected.

# ========================
# Configuration Variables
# ========================
SERVERLIST="servers.txt"            # List of servers to check (one per line)
BASELINE_USERS="baseline_users.txt" # Baseline list of users
BASELINE_SUDOERS="baseline_sudoers.txt" # Baseline sudoers hash
LOGFILE="/var/log/user_monitor.log" # Log file
ALERT_EMAIL="admin@example.com"     # Email for alerts (optional)

# ========================
# Helper Functions
# ========================

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOGFILE"
}

check_users() {
    local HOST=$1
    log_message "Checking users on $HOST ..."

    # Get current user list
    CURRENT_USERS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "cut -d: -f1 /etc/passwd" 2>/dev/null)

    if [ -z "$CURRENT_USERS" ]; then
        log_message "ERROR: Unable to fetch user list from $HOST"
        return
    fi

    # Compare with baseline
    NEW_USERS=$(comm -13 <(sort "$BASELINE_USERS") <(echo "$CURRENT_USERS" | sort))
    REMOVED_USERS=$(comm -23 <(sort "$BASELINE_USERS") <(echo "$CURRENT_USERS" | sort))

    if [ -n "$NEW_USERS" ]; then
        log_message "[$HOST] New users detected: $NEW_USERS"
    fi
    if [ -n "$REMOVED_USERS" ]; then
        log_message "[$HOST] Users removed: $REMOVED_USERS"
    fi
}

check_sudoers() {
    local HOST=$1
    log_message "Checking sudoers on $HOST ..."

    # Hash the sudoers file
    REMOTE_HASH=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" "md5sum /etc/sudoers 2>/dev/null | awk '{print \$1}'")

    if [ -z "$REMOTE_HASH" ]; then
        log_message "ERROR: Unable to fetch sudoers hash from $HOST"
        return
    fi

    if [ ! -f "$BASELINE_SUDOERS" ]; then
        echo "$REMOTE_HASH" > "$BASELINE_SUDOERS"
        log_message "Baseline sudoers hash created."
    else
        BASELINE_HASH=$(cat "$BASELINE_SUDOERS")
        if [ "$REMOTE_HASH" != "$BASELINE_HASH" ]; then
            log_message "[$HOST] WARNING: Sudoers file has changed!"
        fi
    fi
}

check_failed_logins() {
    local HOST=$1
    log_message "Checking failed SSH logins on $HOST ..."

    FAILED_LOGINS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
        "grep 'Failed password' /var/log/auth.log 2>/dev/null | grep \"$(date '+%b %e')\" | wc -l")

    if [ -z "$FAILED_LOGINS" ]; then
        # Try RHEL log path
        FAILED_LOGINS=$(ssh -o BatchMode=yes -o ConnectTimeout=5 "$HOST" \
            "grep 'Failed password' /var/log/secure 2>/dev/null | grep \"$(date '+%b %e')\" | wc -l")
    fi

    log_message "[$HOST] Failed SSH logins today: $FAILED_LOGINS"
}

check_server() {
    local HOST=$1
    log_message "===== Starting checks on $HOST ====="
    check_users "$HOST"
    check_sudoers "$HOST"
    check_failed_logins "$HOST"
    log_message "===== Completed checks on $HOST ====="
}

# ========================
# Main Execution
# ========================
log_message "=== User Monitor Script Started ==="

if [ ! -f "$SERVERLIST" ]; then
    log_message "ERROR: Server list file $SERVERLIST not found!"
    exit 1
fi

for SERVER in $(cat "$SERVERLIST"); do
    check_server "$SERVER"
done

log_message "=== User Monitor Script Finished ==="
