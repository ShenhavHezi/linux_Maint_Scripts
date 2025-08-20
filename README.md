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
- [Cert_Monitor (`cert_monitor.sh`)](#cert_monitorsh--tls-certificate-expiry--validity-monitor)
- [NTP_Drift_Monitor (`ntp_drift_monitor.sh`)](#ntp_drift_monitorsh--ntpchrony-time-drift-monitoring-script)
- [Log_Growth_Guard.sh (`log_growth_guard.sh`)](#log_growth_guardsh--log-size--growth-monitoring-script)
- [Ports_Baseline_Monitor.sh (`ports_baseline_monitor.sh`)](#ports_baseline_monitorsh--listening-ports-baseline--drift-monitor)
- [Backup_Check.sh (`backup_check.sh`)](#backup_checksh--backup-freshness-size--integrity-monitor)
- [NFS_mount_monitor.sh (`nfs_mount_monitor.sh`)](#nfs_mount_monitorsh--nfscifs-mount-health-monitor)
- [Config_Drift_Monitor.sh (`config_drift_monitor.sh`)](#config_drift_monitorsh--configuration-baseline--drift-monitor)
- [Inode_Monitor.sh (`inode_monitor.sh`)](#inode_monitorsh--inode-usage-monitoring-script)
- [Inventory_Export.sh (`inventory_export.sh`)](#inventory_exportsh--hardwaresoftware-inventory-export-script)
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


# 📄 cert_monitor.sh — TLS Certificate Expiry & Validity Monitor <a name="cert_monitorsh--tls-certificate-expiry--validity-monitor"></a>

## 🔹 Overview
`cert_monitor.sh` is a **Bash script** that checks TLS certificates for one or more endpoints and alerts you before they expire.  
It supports plain TLS (e.g., HTTPS on 443) and **STARTTLS** for common services, validates the certificate with OpenSSL, and reports the **days remaining**, **issuer/subject**, and **verify status**.

The script runs from a central server — no SSH needed to targets — and is ideal for monitoring public and internal services.

---

## 🔹 Features
- ✅ Checks any `host:port` that speaks TLS (default port 443)  
- ✅ Optional **SNI** override per target  
- ✅ Optional **STARTTLS** (e.g., `smtp`, `imap`, `pop3`, `ldap`, `ftp`, `postgres`)  
- ✅ Reports **days-until-expiry**, **verify status**, **issuer**, **subject**  
- ✅ Logs results to `/var/log/cert_monitor.log`  
- ✅ Optional email alerts via recipients in `emails.txt`  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/cert_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/certs.txt`   # endpoints to check  
  `/etc/linux_maint/emails.txt`  # email recipients (optional)  

- Log file:  
  `/var/log/cert_monitor.log`

---

## 🔹 Configuration

### 1) Targets list
📌 `/etc/linux_maint/certs.txt`  
One endpoint per line, supports optional SNI and STARTTLS.  
Format:
host[:port][,sni][,starttls=proto]
Examples:
example.com # implies :443, SNI=example.com
example.com:443 # explicit 443
internal.example:8443 # custom port, SNI=internal.example
db.myco.lan:5432,myapp.lan # custom SNI for TLS on 5432
mail.example.com:25,starttls=smtp
imap.example.com:143,starttls=imap


### 2) Email recipients (optional)
📌 `/etc/linux_maint/emails.txt`  
One email per line:
alice@example.com
bob@example.com


### 3) Threshold & timeout
Inside the script:
THRESHOLD_DAYS=30     # Warn when certificate has <= 30 days remaining
TIMEOUT_SECS=10       # Per-connection timeout for openssl
EMAIL_ON_WARN="true"  # Send email when WARN/CRIT is detected

## 🔹 Usage

### Run manually
bash /usr/local/bin/cert_monitor.sh
Run daily via cron

Edit crontab:
crontab -e
Add line to run every day at 3:00 AM:

`0 3 * * * /usr/local/bin/cert_monitor.sh`

🔹 Example Log Output
==============================================
 TLS Certificate Check
 Date: 2025-08-20 01:00:01
==============================================
[OK] example.com:443 (SNI=example.com) days_left=82 verify=0/ok

[WARN] internal.example:8443 (SNI=internal.example) days_left=14 verify=0/ok note=near_expiry

[CRIT] legacy.example:443 (SNI=legacy.example) days_left=-3 verify=10/certificate has expired note=expired

[WARN] mail.example.com:25 (SNI=mail.example.com) days_left=28 verify=0/ok note=near_expiry


🔹 Requirements

Linux host with openssl, timeout, mail/mailx (mail optional)
Network access from the monitoring host to the listed endpoints
For STARTTLS, OpenSSL must support the given protocol name (e.g., -starttls smtp)

🔹 Limitations

OpenSSL verification uses system trust; custom/private CAs may show non-zero verify codes unless installed in system trust store.
Date parsing relies on GNU date. On non-GNU systems, adjust the parsing or install coreutils.
This script checks endpoint certificates, not files on disk (e.g., local PEMs/keystores).


# 📄 ntp_drift_monitor.sh — NTP/Chrony Time Drift Monitoring Script <a name="ntp_drift_monitorsh--ntpchrony-time-drift-monitoring-script"></a>

## 🔹 Overview
`ntp_drift_monitor.sh` is a **Bash script** that checks whether your Linux servers are properly time-synchronized and how far their clocks drift from NTP.  
It supports **chrony**, **ntpd**, and **systemd-timesyncd**, reporting **offset (ms)**, **stratum**, **time source**, and an overall status (**OK/WARN/CRIT**).

The script can run in two modes:
- **Local mode** → check the server it’s running on.  
- **Distributed mode** → check multiple servers via SSH from a central master node.

---

## 🔹 Features
- ✅ Detects installed time-sync implementation (chrony / ntpd / timesyncd)  
- ✅ Reports **offset (ms)**, **stratum**, **source**, and **sync state**  
- ✅ Thresholds for **WARN**/**CRIT** based on offset (default 100ms / 500ms)  
- ✅ Logs results to `/var/log/ntp_drift_monitor.log`  
- ✅ Supports **multiple servers** (`servers.txt`) and **excluded hosts** (`excluded.txt`)  
- ✅ Optional **email alerts** to recipients in `emails.txt`  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/ntp_drift_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`   # list of servers  
  `/etc/linux_maint/excluded.txt`  # list of excluded servers (optional)  
  `/etc/linux_maint/emails.txt`    # list of email recipients (optional)  

- Log file:  
  `/var/log/ntp_drift_monitor.log`

---

## 🔹 Configuration

### 1) Thresholds
Inside the script:
OFFSET_WARN_MS=100
OFFSET_CRIT_MS=500
EMAIL_ON_ISSUE="true"

### 2) Server list
📌 /etc/linux_maint/servers.txt
server1
server2
server3

### 3) Excluded servers (optional)
📌 /etc/linux_maint/excluded.txt
server2

### 4) Email recipients (optional)
📌 /etc/linux_maint/emails.txt
alice@example.com
bob@example.com

## 🔹 Usage

### Run manually
bash /usr/local/bin/ntp_drift_monitor.sh

Run hourly via cron (recommended)
Edit crontab:
crontab -e
`0 * * * * /usr/local/bin/ntp_drift_monitor.sh`

🔹 Example Log Output
==============================================
 NTP Drift Check
 Date: 2025-08-20 12:00:00
==============================================
===== Checking time sync on server1 =====
[OK] server1 impl=chrony offset_ms=12 stratum=3 source=POOL 2.aub/* synced=yes note=leap:Normal
===== Checking time sync on server2 =====
[WARN] server2 impl=ntpd offset_ms=142 stratum=2 source=*192.0.2.10 synced=yes note=peerline
===== Checking time sync on server3 =====
[CRIT] server3 impl=timesyncd offset_ms=? stratum=3 source=time.google.com synced=no note=timesync

🔹 Requirements

Linux systems with at least one of: chronyc, ntpq, or timedatectl show-timesync
SSH configured for passwordless login to target servers (for distributed mode)
mail/mailx installed on the monitoring node (only if you want email alerts)

🔹 Limitations

Offset parsing uses tool outputs and may vary slightly with distro/localization.
For systemd-timesyncd, offset is derived from LastOffsetNSec and may be ? on older versions.
The script reports sync health; it does not attempt any time correction.

# 📄 log_growth_guard.sh — Log Size & Growth Monitoring Script <a name="log_growth_guardsh--log-size--growth-monitoring-script"></a>

## 🔹 Overview
`log_growth_guard.sh` is a **Bash script** that detects **oversized** and **rapidly growing** log files.  
It compares current sizes to the previous run, computes **growth rate (MB/hour)**, flags **WARN/CRIT** conditions, and keeps a per-host state file.  
Run it locally or against multiple servers via SSH from a central node.

---

## 🔹 Features
- ✅ Monitors **absolute size** and **growth rate** of logs  
- ✅ Supports **multiple servers** (`servers.txt`) and **excluded hosts**  
- ✅ Handles **globs**, **directories**, and **recursive** paths  
- ✅ Notes when files are **rotated or truncated**  
- ✅ Logs to `/var/log/log_growth_guard.log`  
- ✅ Optional **email alerts** to recipients in `emails.txt`  
- ✅ Optional (off by default) **auto-rotate command** execution  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration in `/etc/linux_maint/`

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/log_growth_guard.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`   # list of servers  
  `/etc/linux_maint/excluded.txt`  # optional skip list  
  `/etc/linux_maint/log_paths.txt` # log targets (see below)  
  `/etc/linux_maint/emails.txt`    # optional recipients  

- Log file:  
  `/var/log/log_growth_guard.log`

- State files (per host):  
  `/var/tmp/log_growth_guard.<host>.state`

---

## 🔹 Configuration

### 1) Log targets
📌 `/etc/linux_maint/log_paths.txt`  
One target per line. Comments start with `#`. Supported forms:

/var/log/syslog # single file
/var/log/*.log # glob (expanded remotely)
/opt/app/logs/ # all files (non-recursive)
/opt/app/logs/** # recursive (all files under dir)


### 2) Thresholds & behavior
Inside the script:

SIZE_WARN_MB=1024

SIZE_CRIT_MB=2048

RATE_WARN_MBPH=200

RATE_CRIT_MBPH=500

EMAIL_ON_ALERT="true"

AUTO_ROTATE="false"        # keep false unless you know exactly what you want to run

ROTATE_CMD=""              # e.g., 'logrotate -f /etc/logrotate.d/myapp'

## 🔹 Usage

### Run manually
bash /usr/local/bin/log_growth_guard.sh

Run hourly via cron (recommended)
Edit crontab:
crontab -e
`0 * * * * /usr/local/bin/log_growth_guard.sh`

🔹 Example Log Output
==============================================
 Log Growth Guard
 Date: 2025-08-20 12:00:00
==============================================
===== Checking log growth on app01 =====
[OK] /var/log/syslog size=128MB rate=0.4MB/h

[WARN] /opt/app/logs/app.log size=1350MB rate=22.7MB/h

[CRIT] /opt/app/logs/audit.log size=2150MB rate=610.2MB/h note=rotated_or_truncated

[INFO] /opt/app/logs/old.log no longer present (rotated/removed)

===== Completed app01 =====

🔹 Requirements

Linux targets with bash, stat, find, and standard coreutils
SSH key-based login for distributed mode
mail/mailx on the monitoring node (only if you want email alerts)

🔹 Limitations

Rate is computed between runs; the first run has no prior baseline.
If clocks differ heavily between hosts, timestamps still rely on the monitoring node’s run time (size deltas still valid).
Auto-rotation is disabled by default; use with care and only with a safe ROTATE_CMD.

# 📄 ports_baseline_monitor.sh — Listening Ports Baseline & Drift Monitor <a name="ports_baseline_monitorsh--listening-ports-baseline--drift-monitor"></a>

## 🔹 Overview
`ports_baseline_monitor.sh` is a **Bash script** that detects changes in listening network ports by comparing the current state to a saved **baseline** per host.  
It normalizes sockets to `proto|port|process`, highlights **NEW** and **REMOVED** listeners, applies an **allowlist** for known/expected additions, logs the results, and can email alerts.

The script can run in two modes:
- **Local mode** → check the server it’s running on.  
- **Distributed mode** → check multiple servers via SSH from a central master node.

---

## 🔹 Features
- ✅ Captures listening ports via `ss` (with process names when available)  
- ✅ Falls back to `netstat` when needed  
- ✅ Per-host **baseline** in `/etc/linux_maint/baselines/ports/<host>.baseline`  
- ✅ Flags **NEW** and **REMOVED** entries  
- ✅ **Allowlist** support (`proto:port` or `proto:port:proc-substring`)  
- ✅ Logs to `/var/log/ports_baseline_monitor.log`  
- ✅ Optional automatic **baseline initialization** and **baseline updates**  
- ✅ Optional **email alerts** to recipients in `emails.txt`  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/ports_baseline_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`                   # list of servers  
  `/etc/linux_maint/excluded.txt`                  # optional skip list  
  `/etc/linux_maint/baselines/ports/<host>.baseline`  # per-host baseline  
  `/etc/linux_maint/ports_allowlist.txt`           # optional allowlist  
  `/etc/linux_maint/emails.txt`                    # optional recipients  

- Log file:  
  `/var/log/ports_baseline_monitor.log`

---

## 🔹 Baseline Format
Each line is normalized as:
proto|port|process

Examples:
tcp|22|sshd
udp|123|chronyd
tcp|5432|postgres

> If the process name isn’t available, `-` is used. Run the script with sufficient privileges for best results.

---

## 🔹 Allowlist Format
One rule per line; comments start with `#`.  
- `proto:port` — ignore any new listener on that `proto/port`.  
- `proto:port:proc-substring` — ignore only if the process name contains the substring (case-insensitive).  
Examples:
Common allowances
tcp:22:sshd
udp:123:chrony
tcp:9100:node_exporter
tcp:8443


---

## 🔹 Configuration
Inside the script:

`SERVERLIST="/etc/linux_maint/servers.txt"`

`EXCLUDED="/etc/linux_maint/excluded.txt"`

`BASELINE_DIR="/etc/linux_maint/baselines/ports"`

`ALLOWLIST_FILE="/etc/linux_maint/ports_allowlist.txt"`

`ALERT_EMAILS="/etc/linux_maint/emails.txt"`

`LOGFILE="/var/log/ports_baseline_monitor.log"`

`AUTO_BASELINE_INIT="true"   # create baseline if missing`

`BASELINE_UPDATE="false"     # accept current as new baseline after reporting`

`INCLUDE_PROCESS="true"      # include process names when available`

`EMAIL_ON_CHANGE="true"      # send email on changes`

## 🔹 Usage

### Run manually
bash /usr/local/bin/ports_baseline_monitor.sh

Run hourly via cron (recommended)
Edit crontab:
crontab -e
`0 * * * * /usr/local/bin/ports_baseline_monitor.sh`

🔹 Example Log Output
==============================================
 Ports Baseline Monitor
 Date: 2025-08-20 12:00:00
==============================================
===== Checking ports on app01 =====
[app01] NEW listening entries:
  + tcp/9100 (node_exporter)
  + tcp/8443 (-)
[app01] REMOVED listening entries:
  - tcp/5601 (kibana)
===== Completed app01 =====

===== Checking ports on db01 =====
[db01] NEW listening entries:
  + tcp/5432 (postgres)
===== Completed db01 =====

🔹 Requirements

Linux targets with ss (iproute2). If ss is not available, netstat as fallback.
Root privileges recommended to capture process names for listeners.
SSH key-based login for distributed mode.
mail/mailx on the monitoring node (only if you want email alerts).

🔹 Limitations

Process names may be - if permissions are insufficient or the tool can’t resolve PIDs.
Some daemons spawn short-lived listeners; frequent intervals reduce false negatives.
Baseline management: set BASELINE_UPDATE="true" temporarily to accept legitimate changes after a rollout.


# 📄 backup_check.sh — Backup Freshness, Size & Integrity Monitor <a name="backup_checksh--backup-freshness-size--integrity-monitor"></a>

## 🔹 Overview
`backup_check.sh` is a **Bash script** that verifies your backups actually exist, are recent, large enough, and (optionally) pass a quick integrity test.  
It can run locally or across multiple servers via SSH from a central node.

---

## 🔹 Features
- ✅ Finds the **latest backup file** per target pattern  
- ✅ Checks **age** (max hours) and **minimum size** (MB)  
- ✅ Optional **integrity verification** (`tar`, `gzip`, or custom `cmd:<shell>`)  
- ✅ Supports **multiple servers** and wildcard `*` host entries  
- ✅ Logs to `/var/log/backup_check.log`  
- ✅ Optional email alerts to recipients in `emails.txt`  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration files in `/etc/linux_maint/`

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/backup_check.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`         # list of servers  
  `/etc/linux_maint/excluded.txt`        # optional skip list  
  `/etc/linux_maint/backup_targets.csv`  # backup definitions (see below)  
  `/etc/linux_maint/emails.txt`          # optional recipients  

- Log file:  
  `/var/log/backup_check.log`

---

## 🔹 Targets Configuration (`backup_targets.csv`)
CSV format with **five columns** (no headers required). One target per line:
host,pattern,min_size_mb,max_age_hours,verify
- `host` — hostname/IP from `servers.txt` or `*` for all hosts  
- `pattern` — file glob on the target host (e.g., `/var/backups/*.tar.gz`)  
- `min_size_mb` — minimum file size in MB  
- `max_age_hours` — maximum allowed age for the newest matching file  
- `verify` — one of:
  - `none` — skip integrity test  
  - `tar` — run `tar -tzf <file>`  
  - `gzip` — run `gzip -t <file>`  
  - `cmd:<shell>` — run custom command; `<file>` is appended as the last arg

**Examples**
/var/backups/.tar.gz,100,36,tar
db01,/pg_backups/.dump,500,24,none
app01,/opt/app/backup/.gz,200,24,gzip
app02,/opt/app/snapshots/*.tgz,150,24,cmd:/usr/local/bin/verify_snapshot.sh

🔹 Usage
Run manually
bash /usr/local/bin/backup_check.sh

Run daily via cron

Edit crontab:
crontab -e

Add line to run every day at 02:30:
`30 2 * * * /usr/local/bin/backup_check.sh`

🔹 Example Log Output
==============================================
 Backup Check
 Date: 2025-08-20 02:30:00
==============================================
===== Checking backups on db01 =====
[OK] /pg_backups/base_2025-08-19.dump size=812.4MB age=23.8h verify=none
===== Completed db01 =====

===== Checking backups on app01 =====
[CRIT] /opt/app/backup/app_2025-08-18.tar.gz size=88.3MB age=47.1h verify=tar notes=too_small:88.3MB<100MB too_old:47.1h>36h
===== Completed app01 =====


🔹 Requirements

Linux targets with bash, find, stat, and standard coreutils
SSH key-based login for distributed mode
mail/mailx on the monitoring node (only if you want email alerts)
For integrity tests: appropriate tools on targets (tar, gzip, or your custom verifier)


🔹 Limitations

Integrity checks are lightweight sanity tests, not full restores.
Very large backups may exceed the VERIFY_TIMEOUT (default 60s); adjust as needed.
Patterns match files in a single directory (non-recursive). If you need recursion, create separate targets per directory.


# 📄 nfs_mount_monitor.sh — NFS/CIFS Mount Health Monitor <a name="nfs_mount_monitorsh--nfscifs-mount-health-monitor"></a>

## 🔹 Overview
`nfs_mount_monitor.sh` is a **Bash script** that verifies required network filesystems (NFS/CIFS) are **mounted and healthy**.  
It checks presence, filesystem type, and remote target; detects **stale** mounts with timed operations; can perform an optional **RW test**; and (optionally) tries to **auto-(re)mount** on failure.

The script can run in two modes:
- **Local mode** → check the server it’s running on.  
- **Distributed mode** → check multiple servers via SSH from a central node.

---

## 🔹 Features
- ✅ Validates **mountpoint**, **fstype**, and **remote** match expectations  
- ✅ Health checks with timeout to detect **stale/unresponsive** mounts  
- ✅ Optional **RW test** (touch + delete in the mount)  
- ✅ Optional **auto-remount** (disabled by default)  
- ✅ Supports **multiple servers** and **per-host** target rows  
- ✅ Logs to `/var/log/nfs_mount_monitor.log`  
- ✅ Optional email alerts (`emails.txt`)  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration in `/etc/linux_maint/`

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/nfs_mount_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`   # list of servers  
  `/etc/linux_maint/excluded.txt`  # optional skip list  
  `/etc/linux_maint/mounts.txt`    # required mounts per host (CSV)  
  `/etc/linux_maint/emails.txt`    # optional recipients  

- Log file:  
  `/var/log/nfs_mount_monitor.log`

---

## 🔹 Mounts Configuration (`/etc/linux_maint/mounts.txt`)
**CSV** with up to **7 columns** (no header). One row per required mount:
host, mountpoint, fstype, remote, options, mode, timeout
- `host` — hostname/IP from `servers.txt` or `*` for all hosts  
- `mountpoint` — local directory to be mounted (must exist; script will `mkdir -p` on auto-mount)  
- `fstype` — e.g., `nfs`, `nfs4`, `cifs`  
- `remote` — e.g., `server:/export/share` or `//filesrv/shared` (for CIFS)  
- `options` — mount options (e.g., `rw,_netdev,vers=3,timeo=600,retrans=2`), empty to skip  
- `mode` — `ro` (default) or `rw` (perform a write test)  
- `timeout` — per-operation timeout seconds (defaults to `8`)

**Examples**
*,/mnt/share,nfs,fs01:/export/share,rw,_netdev,5
app01,/mnt/appdata,nfs,fs02:/export/appdata,rsize=262144,wsize=262144,rw,rw,8
db01,/mnt/backup,nfs,backup:/vol/backup,_netdev,ro,10
files1,/mnt/smb,cifs,//filesrv/shared,credentials=/root/.smbcred,ro,8


> For CIFS, ensure credentials/options are present and readable by root on the target host.

---

## 🔹 Configuration (inside script)

`EMAIL_ON_FAILURE="true"`

`AUTO_REMOUNT="false"             # change to "true" to allow auto (re)mount`

`UMOUNT_FLAGS="-fl"               # tune for your environment`

`DEFAULT_TIMEOUT=8`

🔹 Usage
Run manually
bash /usr/local/bin/nfs_mount_monitor.sh

Edit crontab:
crontab -e

Run every 10 minutes via cron (example)
`*/10 * * * * /usr/local/bin/nfs_mount_monitor.sh`

🔹 Example Log Output==============================================
 NFS/CIFS Mount Monitor
 Date: 2025-08-20 12:00:00
==============================================
===== Checking mounts on app01 =====
[app01] [OK] /mnt/share fstype=nfs remote=fs01:/export/share mode=ro
[app01] [WARN] /mnt/appdata fstype=nfs remote=fs02:/export/appdata mode=rw notes=rw_test_failed
[app01] [CRIT] /mnt/backup not mounted (expected fstype=nfs remote=backup:/vol/backup)
===== Completed app01 =====


🔹 Requirements

Linux targets with bash, timeout, /proc/mounts, and mount/umount
SSH key-based login for distributed mode
For CIFS: cifs-utils (or equivalent) installed on targets
For email: mail/mailx on the monitoring node

🔹 Limitations

Auto-remount can be disruptive on busy hosts; keep disabled unless you have a safe window.
RW test creates/removes a temporary file inside the mount; use mode=ro for read-only mounts.
Stale NFS can hang some tools; the script uses timeout aggressively to avoid blocking.


# 📄 config_drift_monitor.sh — Configuration Baseline & Drift Monitor <a name="config_drift_monitorsh--configuration-baseline--drift-monitor"></a>

## 🔹 Overview
`config_drift_monitor.sh` is a **Bash script** that tracks changes in critical configuration files.  
It hashes a configured set of files (supports **files**, **globs**, **directories**, and **recursive** patterns), compares against a per-host **baseline**, and reports **MODIFIED**, **NEW**, and **REMOVED** items.

The script can run in two modes:
- **Local mode** → check the server it’s running on.  
- **Distributed mode** → check multiple servers via SSH from a central node.

---

## 🔹 Features
- ✅ Supports **files**, **globs** (`*.conf`), **dir/** (non-recursive) and **dir/**`**` (recursive)  
- ✅ Stores per-host **baseline** in `/etc/linux_maint/baselines/configs/<host>.baseline`  
- ✅ Detects **MODIFIED**, **NEW**, **REMOVED** files  
- ✅ **Allowlist** to ignore known/expected changes (path-based)  
- ✅ Uses `sha256sum` (falls back to `md5sum`) and records the algorithm with each hash  
- ✅ Logs to `/var/log/config_drift_monitor.log`  
- ✅ Optional **email alerts** to recipients in `emails.txt`  
- ✅ Optional **auto-baseline init** and **post-report baseline update**  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration files in `/etc/linux_maint/`

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/config_drift_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`            # list of servers  
  `/etc/linux_maint/excluded.txt`           # optional skip list  
  `/etc/linux_maint/config_paths.txt`       # what to monitor (see below)  
  `/etc/linux_maint/config_allowlist.txt`   # paths to ignore (optional)  
  `/etc/linux_maint/emails.txt`             # email recipients (optional)

- Baselines:  
  `/etc/linux_maint/baselines/configs/<host>.baseline`

- Log file:  
  `/var/log/config_drift_monitor.log`

---

## 🔹 Paths Configuration (`/etc/linux_maint/config_paths.txt`)
One target per line. Comments start with `#`. Supported forms:

`/etc/ssh/sshd_config # single file`
`/etc/.conf # glob (expanded on the host)`
`/etc/ # all files at top-level of /etc (non-recursive)`
`/etc/** # recursively all files under /etc`
`/opt/app/conf/.yaml`


> Tip: be selective. Start with the most sensitive configs: `sshd_config`, `sudoers`, `sysctl.conf`, `limits.conf`, app configs, etc.

---

## 🔹 Allowlist (`/etc/linux_maint/config_allowlist.txt`)
Lines are **paths** to ignore for drift reporting.  
Matches are **exact** or **substring** (case-insensitive).  
Examples:

`/etc/machine-id`
`/etc/adjtime`
`/var/lib/myapp/runtime.yaml`


---

## 🔹 Script Configuration (inside the script)

`AUTO_BASELINE_INIT="true"   # create baseline if missing`

`BASELINE_UPDATE="false"     # accept current snapshot as new baseline after reporting`

`EMAIL_ON_DRIFT="true"       # send email when drift detected`


🔹 Usage
Run manually
bash /usr/local/bin/config_drift_monitor.sh

Run daily via cron

Edit crontab:
crontab -e

Add line to run every day at 02:30:
`30 2 * * * /usr/local/bin/config_drift_monitor.sh`

🔹 Example Log Output
==============================================
 Config Drift Monitor
 Date: 2025-08-20 01:00:00
==============================================
===== Checking config drift on web01 =====
[web01] MODIFIED files:
  * /etc/ssh/sshd_config (old:sha256|d3adbeef... new:sha256|9f1c2a... )
[web01] NEW files:
  + /etc/nginx/conf.d/new-site.conf
[web01] REMOVED files:
  - /etc/sysctl.d/99-tuning.conf
===== Completed web01 =====


🔹 Requirements

Linux targets with bash, find, sha256sum/md5sum, standard coreutils
SSH key-based login for distributed mode
mail/mailx on the monitoring node (optional, for alerts)

🔹 Limitations

This script detects that content changed, not what changed inside a file. For diffs, investigate manually or extend the script to fetch and diff text configs.
Hashing large recursive trees can be heavy; scope your patterns to key config areas.
On systems lacking sha256sum, md5sum is used (baseline lines record the algorithm).


# 📄 inode_monitor.sh — Inode Usage Monitoring Script <a name="inode_monitorsh--inode-usage-monitoring-script"></a>

## 🔹 Overview
`inode_monitor.sh` is a **Bash script** that watches inode usage per filesystem and alerts when usage crosses configurable thresholds.  
It’s the perfect safety net for issues where disk **space** looks fine but inode **count** is exhausted (common with tiny-file workloads, logs, caches).

The script can run in two modes:
- **Local mode** → monitor the server it’s running on.  
- **Distributed mode** → monitor multiple servers via SSH from a central node.  

---

## 🔹 Features
- ✅ Collects inode usage from `df -PTi`  
- ✅ Per-mount **WARN/CRIT thresholds** with a global default (`*`)  
- ✅ Skips pseudo filesystems (tmpfs, proc, cgroup, etc.)  
- ✅ Optional mountpoint **exclude list**  
- ✅ Supports **multiple servers** (`servers.txt`) and **excluded hosts** (`excluded.txt`)  
- ✅ Logs all results to `/var/log/inode_monitor.log`  
- ✅ Optional email alerts to recipients in `emails.txt`  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/inode_monitor.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`           # list of servers  
  `/etc/linux_maint/excluded.txt`          # list of excluded servers (optional)  
  `/etc/linux_maint/inode_thresholds.txt`  # per-mount thresholds (see below)  
  `/etc/linux_maint/inode_exclude.txt`     # optional mountpoints to skip  
  `/etc/linux_maint/emails.txt`            # list of email recipients (optional)  

- Log file:  
  `/var/log/inode_monitor.log`

---

## 🔹 Thresholds Configuration (`/etc/linux_maint/inode_thresholds.txt`)
CSV with **three columns** (no header):  
mountpoint,warn%,crit%
- Use `*` for a default rule applied when no exact mount rule exists.  
- Example:
`*,80,95`
`/,80,95`
`/var,85,95`
`/home,90,97`


> If `inode_thresholds.txt` is missing, defaults are **warn=80%**, **crit=95%**.

---

## 🔹 Exclude Mounts (optional)
📌 `/etc/linux_maint/inode_exclude.txt`  
One mountpoint per line to ignore:

`/snap`

`/var/lib/docker`


> The script already ignores pseudo FS types (tmpfs, proc, sysfs, overlay, …). Use this file for extra noise reduction.

---

## 🔹 Usage

### Run manually

bash /usr/local/bin/inode_monitor.sh

Run hourly via cron (recommended)

`crontab -e`

`0 * * * * /usr/local/bin/inode_monitor.sh`

🔹 Example Log Output
==============================================
 Inode Monitor
 Date: 2025-08-20 12:00:00
==============================================
===== Checking inode usage on app01 =====
[app01] [OK] / type=ext4 inodes=3276800 used=120345 use%=7 warn=80 crit=95
[app01] [WARN] /var type=ext4 inodes=1048576 used=908763 use%=86 warn=85 crit=95
[app01] [CRIT] /var/cache type=ext4 inodes=524288 used=506044 use%=96 warn=85 crit=95
===== Completed app01 =====


🔹 Requirements

Linux systems with df (coreutils)
SSH configured for passwordless login to target servers (for distributed mode)
mail/mailx installed on the monitoring node (only if you want email alerts)

🔹 Limitations

Mountpoints with spaces are unusual; -P format minimizes issues but avoid them where possible.
Some minimal distros may not support df -T; script falls back gracefully without filesystem type.
This script reports inode pressure; cleanup policies (e.g., log rotation) should be handled separately.



# 📄 inventory_export.sh — Hardware/Software Inventory Export Script <a name="inventory_exportsh--hardwaresoftware-inventory-export-script"></a>

## 🔹 Overview
`inventory_export.sh` is a **Bash script** that collects a concise hardware/software inventory from one or more Linux servers and writes it to a daily **CSV** file.  
It also saves a per-host **details snapshot** (CPU, disks, filesystems, LVM, network) for deeper troubleshooting.

The script can run in two modes:
- **Local mode** → export the server it’s running on.  
- **Distributed mode** → export multiple servers via SSH from a central node.  

---

## 🔹 Features
- ✅ Exports a **single CSV row per host** with stable fields (see below)  
- ✅ Saves per-host **details** text file (lscpu, lsblk, df, LVM, IP, routes)  
- ✅ Skips unavailable commands gracefully  
- ✅ Supports **multiple servers** (`servers.txt`) and **excluded hosts** (`excluded.txt`)  
- ✅ Logs to `/var/log/inventory_export.log`  
- ✅ Optional email summary to recipients in `emails.txt`  
- ✅ Works unattended via **cron**  
- ✅ Clean design: configuration files in `/etc/linux_maint/`  

---

## 🔹 File Locations
By convention:  
- Script itself:  
  `/usr/local/bin/inventory_export.sh`

- Configuration files:  
  `/etc/linux_maint/servers.txt`   # list of servers  
  `/etc/linux_maint/excluded.txt`  # optional skip list  
  `/etc/linux_maint/emails.txt`    # optional recipients  

- Log file:  
  `/var/log/inventory_export.log`

- Output directory:  
  `/var/log/inventory/`  
  - CSV (daily): `inventory_YYYY-MM-DD.csv`  
  - Details per host: `details/<host>_YYYY-MM-DD.txt`

---

## 🔹 CSV Columns
In order:
`date,host,fqdn,os,kernel,arch,virt,uptime,cpu_model,`
`sockets,cores_per_socket,threads_per_core,vcpus,mem_mb,swap_mb,`
`disk_total_gb,rootfs_use,vgs,lvs,pvs,vgs_size_gb,ip_list,default_gw,dns_servers,pkg_count`


> `ip_list` and `dns_servers` are `;`-separated if multiple values exist.  
> `pkg_count` is from `dpkg-query` on DEB systems or `rpm -qa | wc -l` on RPM systems.

---

## 🔹 Usage

### Run manually

bash /usr/local/bin/inventory_export.sh

Run daily via cron (recommended)
`crontab -e`
`0 2 * * * /usr/local/bin/inventory_export.sh`

🔹 Example CSV Row
2025-08-20T12:00:21+00:00,app01,app01.example.com,Ubuntu 22.04 LTS,5.15.0-78-generic,x86_64,kvm,"up 12 days, 4 hours","Intel(R) Xeon(R) CPU",2,8,2,32,65536,8192,500,"42%",1,3,1,600,"10.0.1.10;10.0.2.10","10.0.1.1","8.8.8.8;1.1.1.1",1852



🔹 Requirements

Linux targets with standard tools (hostnamectl, lscpu, free, lsblk, df, ip)
Optional: LVM tools (vgs/lvs/pvs) for VG/LV counts and total size
SSH key-based login to targets (for distributed mode)
mail/mailx on the monitoring node (only if you enable email summary)


🔹 Limitations

Values are a snapshot at run time; for trending, load the CSV into a DB or sheet.
Some fields may be empty on minimal systems (e.g., no LVM, no swap).
disk_total_gb sums physical disk devices as reported by lsblk and may not reflect SAN/thin provisioning perfectly.



