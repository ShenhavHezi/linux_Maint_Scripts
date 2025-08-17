# Linux Maintenance Scripts

Collection of useful Linux system maintenance scripts (monitoring, cleanup, automation).

---

## 📑 Table of Contents
- [Disk Monitor (`disk_monitor.sh`)](#disk_monitorsh--linux-disk-usage-monitoring-script)
- [Another Script (future)](#another-script-name)



















# 📄 disk_monitor.sh — Linux Disk Usage Monitoring Script

## 🔹 Overview
`disk_monitor.sh` is a **Bash script** designed to monitor disk usage on one or more Linux servers.  
It checks all mounted filesystems and generates alerts if usage exceeds a defined threshold.  

The script can run in two modes:
- **Local mode** → monitor the server it’s running on.  
- **Distributed mode** → monitor multiple servers remotely via SSH from a central master server.  

This makes it useful both for personal Linux machines and production environments.

---

## 🔹 Features
- ✅ Configurable disk usage **threshold** (default: 90%)  
- ✅ Checks **all filesystems** (ignores `tmpfs` and `devtmpfs`)  
- ✅ Supports **multiple servers** using an external `servers.txt`  
- ✅ Sends alerts to **multiple recipients** defined in `emails.txt` or as a string  
- ✅ Logs all results (OK + ALERT) to `/var/log/disks_monitor.log`  
- ✅ Works unattended via `cron` scheduling  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
/usr/local/bin/disk_monitor.sh
- Configuration files:
/etc/linux_maint/servers.txt # list of servers
/etc/linux_maint/emails.txt # list of email recipients
- Log file:  
/var/log/disks_monitor.log

---

## 🔹 Configuration

### 1. Disk usage threshold
THRESHOLD=90
Modify this value if you want a different threshold (e.g., 80%).

### 2. Server list
📌 /etc/linux_maint/servers.txt
One server per line (hostname or IP).
Example:
By convention:  
- Script itself: 
server1.example.com
server2.example.com
server3.example.com
If you don’t want a file, you can write directly in the script:
SERVERLIST="server1.example.com,server2.example.com"

### 3. Email recipients

📌 /etc/linux_maint/emails.txt
One email per line.
Example:
alice@example.com
bob@example.com

If you don’t want a file, you can write directly in the script:
ALERT_EMAIL="alice@example.com,bob@example.com"

### 🔹 Usage
Run manually
bash /usr/local/bin/disk_monitor.sh

Run daily via cron
Edit crontab:
crontab -e
Add line to run every day at 8:00 AM:
0 8 * * * /usr/local/bin/disk_monitor.sh

### 🔹 Example Log Output
[2025-08-17 08:00:00] === Starting distributed disk check (Threshold: 90%) ===
[2025-08-17 08:00:01] Checking server: server1.example.com
[2025-08-17 08:00:01] OK: server1.example.com - /dev/sda1 mounted on / is at 42%
[2025-08-17 08:00:01] ALERT: server1.example.com - /dev/sdb1 mounted on /data is at 92%
[2025-08-17 08:00:02] Checking server: server2.example.com
[2025-08-17 08:00:02] OK: server2.example.com - /dev/sda1 mounted on / is at 68%
[2025-08-17 08:00:02] === Distributed disk check completed ===

### 🔹 Requirements

Linux system (RHEL, CentOS, Fedora, Ubuntu, Debian)
ssh configured for passwordless login to target servers
mail command available (mailx or mailutils)



