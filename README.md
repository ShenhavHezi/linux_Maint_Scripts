# Linux Maintenance Scripts

Collection of useful Linux system maintenance scripts (monitoring, cleanup, automation).

---

## 📑 Table of Contents
- [Disk Monitor (`disk_monitor.sh`)](#disk_monitorsh--linux-disk-usage-monitoring-script)
- [Health_Monitor (`health_monitor.sh`)](#health_monitorsh--linux-health-monitoring-script)
- [User_Monitor (`user_monitor.sh`)](#user_monitorsh--linux-user--access-monitoring-script)
---


# 📄 disk_monitor.sh — Linux Disk Usage Monitoring Script <a name="disk_monitorsh--linux-disk-usage-monitoring-script"></a>

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
  /etc/linux_maint/servers.txt   # list of servers  
  /etc/linux_maint/emails.txt    # list of email recipients
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
server1
server2
server3
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


# 📄 health_monitor.sh — Linux Health Check Script <a name="health_monitorsh--linux-health-monitoring-script"></a>

## 🔹 Overview
`health_monitor.sh` is a **Bash script** designed to monitor the overall health of one or more Linux servers.  
It collects CPU, memory, load average, and disk usage, then generates a daily report.  

The script can run in two modes:
- **Local mode** → monitor the server it’s running on.  
- **Distributed mode** → monitor multiple servers remotely via SSH from a central master server.  

This makes it suitable for both personal Linux machines and production environments.

---

## 🔹 Features
- ✅ Monitors **CPU load**, **memory usage**, and **disk usage**  
- ✅ Supports **multiple servers** using an external `servers.txt`  
- ✅ Skips servers listed in `excluded.txt`  
- ✅ Logs all results to `/var/log/health_monitor.log`  
- ✅ Emails the report to multiple recipients listed in `emails.txt`  
- ✅ Works unattended via `cron` scheduling  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
/usr/local/bin/health_monitor.sh

- Configuration files:  
 /etc/linux_maint/servers.txt # list of servers
 /etc/linux_maint/excluded.txt # list of excluded servers
 /etc/linux_maint/emails.txt # list of email recipients
- Log file:
  /var/log/health_monitor.log

    
---

## 🔹 Configuration

### 1. Server list
📌 `/etc/linux_maint/servers.txt`  
One server per line (hostname or IP).  
Example:
server1
server2
server3

### 2. Excluded servers
📌 `/etc/linux_maint/excluded.txt`  
One server per line. Servers here will be skipped during health checks.  
Example:
server2

### 3. Email recipients
📌 `/etc/linux_maint/emails.txt`  
One email per line.  
Example:
bob@example.com
alice2@example.com


---

### 🔹 Usage
Run manually
bash /usr/local/bin/health_monitor.sh

Run daily via cron
Edit crontab:
crontab -e
Add line to run every day at 8:00 AM:
0 8 * * * /usr/local/bin/health_monitor.sh

🔹 Example Log Output
==============================================
 Linux Distributed Health Check 
 Date: 2025-08-17 08:00:00
==============================================
>>> Health check on server1 (2025-08-17 08:00:00)
--- Hostname: server1
--- Uptime:
 08:00:00 up 12 days, 3:15, 3 users, load average: 1.21, 1.08, 0.95
--- CPU Load:
top - 08:00:01 up 12 days,  3:15,  3 users,  load average: 1.21, 1.08, 0.95
--- Memory Usage (MB):
              total        used        free      shared  buff/cache   available
Mem:           7982        2100        3500         150        2382        5500
--- Disk Usage:
Filesystem     Type      Size  Used Avail Use% Mounted on
/dev/sda1      ext4       50G   20G   28G  42% /
--- Top 5 Processes by CPU:
  PID COMMAND         %CPU %MEM
 1234 java            12.5  8.0
 5678 nginx            5.0  1.2
...
--- Top 5 Processes by Memory:
  PID COMMAND         %CPU %MEM
 1234 java            12.5  8.0
 5678 postgres         2.5  6.0
----------------------------------------------

🔹 Requirements

Linux system (RHEL, CentOS, Fedora, Ubuntu, Debian)
ssh configured for passwordless login to target servers
mail command available (mailx or mailutils)

🔹 Limitations

Sends one email per execution with the entire report
Does not currently monitor network statistics or service health (can be added later)
Requires SSH key setup for multi-server environments

# 📄 user_monitor.sh — Linux User & Access Monitoring Script <a name="user_monitorsh--linux-user--access-monitoring-script"></a>

## 🔹 Overview
`user_monitor.sh` is a **Bash script** designed to monitor user accounts and SSH access activity across one or more Linux servers.  
It detects new or removed system users, changes in sudo privileges, and failed SSH login attempts.  

The script can run in two modes:
- **Local mode** → monitor the server it’s running on.  
- **Distributed mode** → monitor multiple servers remotely via SSH from a central master server.  

This makes it suitable for both security auditing and operational monitoring in production environments.

---

## 🔹 Features
- ✅ Detects **newly added or removed system users** (compared to baseline)  
- ✅ Monitors for **changes in sudoers configuration**  
- ✅ Reports **failed SSH login attempts in the last 24h**  
- ✅ Supports **multiple servers** using an external `servers.txt`  
- ✅ Logs all results to `/var/log/user_monitor.log`  
- ✅ Optional email alerts to recipients in `emails.txt`  
- ✅ Works unattended via `cron` scheduling  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/user_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`      # list of servers  
  `/etc/linux_maint/baseline_users.txt`   # baseline user list  
  `/etc/linux_maint/baseline_sudoers.txt` # baseline sudoers hash  
  `/etc/linux_maint/emails.txt`       # list of email recipients  

- Log file:  
  `/var/log/user_monitor.log`

---

## 🔹 Configuration

### 1. Server list
📌 `/etc/linux_maint/servers.txt`  
One server per line (hostname or IP).  
Example:
server1
server2
server3

### 2. User baseline
📌 `/etc/linux_maint/baseline_users.txt` 
Initial list of valid system users. Generate on a trusted server:

cut -d: -f1 /etc/passwd > /etc/linux_maint/baseline_users.txt

### 3. Sudoers baseline
📌 `/etc/linux_maint/baseline_sudoers.txt`
Initial checksum of sudoers file:

md5sum /etc/sudoers | awk '{print $1}' > /etc/linux_maint/baseline_sudoers.txt

### 4. Email recipients (optional)
📌 `/etc/linux_maint/emails.txt`
One email per line:
Alice@example.com
Bob@example.com

🔹 Usage
Run manually
bash /usr/local/bin/user_monitor.sh

Run daily via cron
Edit crontab:
crontab -e

Add line to run every day at midnight:
0 0 * * * /usr/local/bin/user_monitor.sh

🔹 Example Log Output
==============================================
 Linux Distributed User & Access Check
 Date: 2025-08-20 00:00:01
==============================================
>>> User check on server1 (2025-08-20 00:00:01)
--- New users detected: testuser
--- Removed users: guest
--- WARNING: Sudoers file has changed!
--- Failed SSH logins today: 12
----------------------------------------------

>>> User check on server2 (2025-08-20 00:00:04)
--- No new users detected
--- No sudoers changes
--- Failed SSH logins today: 0
----------------------------------------------

🔹 Requirements

Linux system (RHEL, CentOS, Fedora, Ubuntu, Debian)
SSH configured for passwordless login to target servers
md5sum command available on target servers
mail command available for email alerts (mailx or mailutils)

🔹 Limitations

Baseline files must be updated manually when legitimate changes occur (e.g., adding a new user).
Failed SSH login detection is limited to the last 24h and depends on log rotation.
Does not yet monitor user group changes (can be added later).











