# Linux Maintenance Scripts

Collection of useful Linux system maintenance scripts (monitoring, cleanup, automation).

---

## 📑 Table of Contents
- [Disk Monitor (`disk_monitor.sh`)](#disk_monitorsh--linux-disk-usage-monitoring-script)
- [Health_Monitor (`health_monitor.sh`)](#health_monitorsh--linux-health-monitoring-script)
- [User_Monitor (`user_monitor.sh`)](#user_monitorsh--linux-user--access-monitoring-script)
- [Service_Monitor (`service_monitor.sh`)](#service_monitorsh--linux-service-monitoring-script)
- [Servers_Info (`servers_info.sh`)](#servers_infosh--linux-server-information-snapshot-script)
- [Patch_Monitor (`patch_monitor.sh`)](#patch_monitorsh--linux-patch--reboot-monitoring-script)
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


# 📄 service_monitor.sh — Linux Service Monitoring Script <a name="service_monitorsh--linux-service-monitoring-script"></a>

## 🔹 Overview
`service_monitor.sh` is a **Bash script** designed to monitor the status of critical services on one or more Linux servers.  
It checks whether services like `sshd`, `cron`, `nginx`, `postgresql`, etc. are running and alerts if any are inactive or failed.  

The script can run in two modes:
- **Local mode** → monitor the server it’s running on.  
- **Distributed mode** → monitor multiple servers remotely via SSH from a central master server.  

This makes it suitable for both security hardening and production monitoring.

---

## 🔹 Features
- ✅ Monitors **critical services** (systemd or SysV init)  
- ✅ Supports **multiple servers** using an external `servers.txt`  
- ✅ Configurable **list of services** in `services.txt`  
- ✅ Logs all results to `/var/log/service_monitor.log`  
- ✅ Optional **auto-restart** of failed services  
- ✅ Optional email alerts to recipients in `emails.txt`  
- ✅ Works unattended via `cron` scheduling  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/service_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`   # list of servers  
  `/etc/linux_maint/services.txt`  # list of services to check  
  `/etc/linux_maint/emails.txt`    # list of email recipients (optional)  

- Log file:  
  `/var/log/service_monitor.log`

---

## 🔹 Configuration

### 1. Server list
📌 `/etc/linux_maint/servers.txt`  
One server per line (hostname or IP).  
Example:
server1
server2
server3


### 2. Service list
📌 `/etc/linux_maint/services.txt`  
One service per line.  
Example:
sshd
cron
nginx
postgresql


### 3. Email recipients (optional)
📌 `/etc/linux_maint/emails.txt`  
One email per line.  
Example:
bob@example.com
alice@example.com


### 4. Auto-restart setting
Inside the script:  
`AUTO_RESTART="false"`
Change to true if you want failed services to be restarted automatically.

🔹 Usage
Run manually
bash /usr/local/bin/service_monitor.sh

Run daily via cron

Edit crontab:
crontab -e

Add line to run every hour:
0 * * * * /usr/local/bin/service_monitor.sh

🔹 Example Log Output
==============================================
 Linux Distributed Service Check
 Date: 2025-08-20 12:00:00
==============================================
>>> Service check on server1 (2025-08-20 12:00:00)
[OK] sshd is active
[OK] cron is active
[FAIL] nginx is NOT active
Attempted restart of nginx
----------------------------------------------

>>> Service check on server2 (2025-08-20 12:00:03)
[OK] sshd is active
[OK] cron is active
----------------------------------------------

🔹 Requirements

Linux system (RHEL, CentOS, Fedora, Ubuntu, Debian)
SSH configured for passwordless login to target servers
systemctl or service command available on target servers
mail command available for email alerts (mailx or mailutils)

🔹 Limitations

Auto-restart is disabled by default to avoid unintended restarts in production.
If a service is missing entirely, the script reports it as inactive but does not attempt installation.
Currently does not check service configuration files or resource usage (can be added later).


# 📄 servers_info.sh — Linux Server Information Snapshot Script <a name="servers_infosh--linux-server-information-snapshot-script"></a>

## 🔹 Overview
`servers_info.sh` is a **Bash script** designed to collect comprehensive system information from one or more Linux servers.  
It provides a daily snapshot of critical server details such as CPU, memory, storage, volume groups, processes, services, and network configuration.  

The script can run in two modes:
- **Local mode** → gather information from the server it’s running on.  
- **Distributed mode** → gather information from multiple servers remotely via SSH from a central master server.  

This makes it useful for daily audits, troubleshooting, and long-term system documentation.

---

## 🔹 Features
- ✅ Collects **general system info** (hostname, kernel, uptime)  
- ✅ Captures **CPU, memory, and load averages**  
- ✅ Reports **disk usage, block devices, and mount points**  
- ✅ Extracts **Volume Group (VG), Logical Volume (LV), and Physical Volume (PV)** details  
- ✅ Includes **RAID / multipath** status if configured  
- ✅ Logs **network configuration, routing, and listening ports**  
- ✅ Tracks **active users, last logins, and sudoers group membership**  
- ✅ Lists **running services** and top CPU/memory consuming processes  
- ✅ Dumps **firewall and SELinux status**  
- ✅ Notes **pending package updates**  
- ✅ Saves each server’s snapshot into `/var/log/server_info/<hostname>_info_<date>.log`  
- ✅ Runs unattended via `cron`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/servers_info.sh`

- Configuration file (servers to check):  
  `/etc/linux_maint/servers.txt`

- Log directory:  
  `/var/log/server_info/`  

Each server produces a separate log file:
`/var/log/server_info/server1_info_2025-08-20.log`
`/var/log/server_info/server2_info_2025-08-20.log`

---

## 🔹 Configuration

### 1. Server list
📌 `/etc/linux_maint/servers.txt`  
One server per line (hostname or IP).  
Example:
server1
server2
server3


---

## 🔹 Usage

### Run manually
bash /usr/local/bin/servers_info.sh
Run daily via cron

Edit crontab:
crontab -e
Add line to run every day at 2:00 AM:

`0 2 * * * /usr/local/bin/servers_info.sh`

🔹 Example Log Output
==============================================
 Linux Server Information Report
 Date: 2025-08-20
 Host: server1
==============================================

>>> GENERAL SYSTEM INFO
Hostname: server1
OS: Ubuntu 22.04 LTS
Kernel: 5.15.0-78-generic
Uptime: up 12 days, 4 hours

>>> CPU & MEMORY
Model name: Intel(R) Xeon(R) CPU E5-2670 v3 @ 2.30GHz
CPU(s): 8
Memory:
              total   used   free   shared  buff/cache   available
Mem:           32G    15G    10G      1G        7G         20G
Load Average: 0.42 0.38 0.36

>>> DISK & FILESYSTEMS
Filesystem   Size   Used   Avail  Use%  Mounted on
/dev/sda1     50G    20G    28G   42%   /

>>> VOLUME GROUPS
VG   #PV #LV #SN Attr   VSize   VFree
vg0    1   3   0 wz--n-  500G   100G

>>> NETWORK CONFIGURATION
inet 192.168.1.10/24 scope global eth0
Default route: via 192.168.1.1 dev eth0
Listening Ports:
tcp   0   0 0.0.0.0:22   0.0.0.0:*   LISTEN   (sshd)
tcp   0   0 0.0.0.0:5432 0.0.0.0:*   LISTEN   (postgres)

>>> USERS & ACCESS
Logged in users:
root     pts/0  2025-08-20 12:05 (192.168.1.100)
Recent logins:
user1 pts/1 Mon Aug 19 15:21 still logged in
Sudo group: user1, admin

>>> SERVICES & PROCESSES
Active services: sshd, cron, systemd-journald, ...
Top 5 processes by memory:
PID  CMD       %MEM %CPU
1234 java      8.0  15.2
...

>>> SECURITY
Firewall: 3 rules configured
SELinux: disabled

>>> PACKAGE UPDATES
3 packages can be upgraded:
- openssl
- bash
- libc6


🔹 Requirements

Linux system (RHEL, CentOS, Fedora, Ubuntu, Debian)
SSH configured for passwordless login to target servers (for distributed mode)
Standard Linux tools: lscpu, lsblk, df, systemctl, ip, ss, ps, last, iptables or firewalld

🔹 Limitations

Does not check databases, application configs, or cron jobs by default (can be extended).
Package update check depends on distro (apt or yum).
AIX systems will need AIX-specific extensions (using lsvg, lslpp, etc.).


# 📄 patch_monitor.sh — Linux Patch & Reboot Monitoring Script <a name="patch_monitorsh--linux-patch--reboot-monitoring-script"></a>

## 🔹 Overview
`patch_monitor.sh` is a **Bash script** that checks one or many Linux servers for:
- Pending package updates (total)
- **Security** updates
- **Kernel** updates
- Whether a **reboot is required**

It supports the common package managers (`apt`, `dnf`, `yum`, `zypper`) and can run either locally or against multiple hosts via SSH. The script logs a concise report and can email you whenever action is required.

---

## 🔹 Features
- ✅ Detects **pending updates** per server (APT/DNF/YUM/ZYPPER)
- ✅ Flags **security** and **kernel** updates
- ✅ Detects **reboot required** state (Debian/Ubuntu, RHEL/Fedora, SUSE best-effort)
- ✅ Supports **multiple servers** (`servers.txt`) and **excluded hosts** (`excluded.txt`)
- ✅ Logs all results to `/var/log/patch_monitor.log`
- ✅ Optional **email alerts** to recipients in `emails.txt`
- ✅ Works unattended via **cron**
- ✅ Clean design: configuration files in `/etc/linux_maint/`

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/patch_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`   # list of servers  
  `/etc/linux_maint/excluded.txt`  # list of excluded servers (optional)  
  `/etc/linux_maint/emails.txt`    # list of email recipients (optional)  

- Log file:  
  `/var/log/patch_monitor.log`

---

## 🔹 Configuration

### 1) Server list
📌 `/etc/linux_maint/servers.txt`  
One server per line (hostname or IP).  
Example:
server1
server2
server3


### 2) Excluded servers (optional)
📌 `/etc/linux_maint/excluded.txt`  
Servers here will be skipped.
server2


### 3) Email recipients (optional)
📌 `/etc/linux_maint/emails.txt`  
One email per line:
bob@example.com
alice@example.com

> The script emails only when **security updates** or **kernel updates** exist, or when a **reboot is required**.

---

## 🔹 Usage

### Run manually
bash /usr/local/bin/patch_monitor.sh
Run daily via cron

Edit crontab:
crontab -e
Add line to run every day at 3:00 AM:

`0 3 * * * /usr/local/bin/patch_monitor.sh`

🔹 Example Log Output
==============================================
 Linux Patch & Reboot Check
 Date: 2025-08-20 03:00:01
==============================================
===== Checking patches on server1 =====
[server1] OS: Ubuntu 22.04.4 LTS | PkgMgr: apt
[server1] Pending updates: total=12, security=3, kernel=1, reboot_required=yes
===== Completed server1 =====

===== Checking patches on server2 =====
[server2] OS: AlmaLinux 9.4 | PkgMgr: dnf
[server2] Pending updates: total=8, security=2, kernel=0, reboot_required=no
===== Completed server2 =====

🔹 Requirements

Linux targets with one of: apt, dnf, yum, or zypper
SSH configured for passwordless login to target servers (for distributed mode)
mail/mailx installed on the host running the script (only if you want email alerts)
For better reboot detection on RHEL/Fedora, install dnf-utils / yum-utils (needs-restarting)

🔹 Limitations

Security update detection relies on distro metadata; if repositories lack security advisories, counts may be incomplete.
Reboot detection is best-effort on RPM/SUSE systems when needs-restarting is missing.
The script does not apply updates; it only reports. (Can be extended with a safe window + approval flow.)






