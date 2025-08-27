# Linux Maintenance Scripts

A curated set of lightweight Bash tools for day-to-day Linux ops: monitoring, inventory, baselines, and drift detection. Most scripts support **distributed mode** (run checks on many hosts via SSH) and **email alerts**.

---

## 📚 Table of Contents
- [Conventions & Layout](#conventions--and--layout) 
- [Shared Helpers (`linux_maint.sh`)](#shared--helpers)
- [Quickstart](#quickstart)
- [Script Matrix](#script--matrix)
a
### Scripts:
- [Disk Monitor (`disk_monitor.sh`)](#disk--monitor)
- [Health_Monitor (`health_monitor.sh`)](#health--monitor)
- [User_Monitor (`user_monitor.sh`)](#user--monitor)
- [Service_Monitor (`service_monitor.sh`)](#service--monitor)
- [Servers_Info (`servers_info.sh`)](#servers--info)
- [Patch_Monitor (`patch_monitor.sh`)](#patch--monitor)
- [Cert_Monitor (`cert_monitor.sh`)](#cert--monitor)
- [NTP_Drift_Monitor (`ntp_drift_monitor.sh`)](#ntp--drift--monitor)
- [Log_Growth_Guard.sh (`log_growth_guard.sh`)](#log--growth--guard)
- [Ports_Baseline_Monitor.sh (`ports_baseline_monitor.sh`)](#ports--baseline--monitor)
- [Backup_Check.sh (`backup_check.sh`)](#backup--check)
- [NFS_mount_monitor.sh (`nfs_mount_monitor.sh`)](#nfs--mount--monitor)
- [Config_Drift_Monitor.sh (`config_drift_monitor.sh`)](#config--drift--monitor)
- [Inode_Monitor.sh (`inode_monitor.sh`)](#inode--monitor)
- [Inventory_Export.sh (`inventory_export.sh`)](#inventory--export)
- [Network_Monitor.sh (`network_monitor.sh`)](#network--monitor)
- [Process_Hog_Monitor.sh (`process_hog_monitor.sh`)](#process--hog--monitor)
---


## 🧭 Conventions & Layout <a name="conventions--and--layout"></a>
**Install paths (convention):**

`/usr/local/bin/                 # scripts`

`/usr/local/lib/linux_maint.sh   # shared helper library`

`/etc/linux_maint/               # config (servers, emails, allowlists, baselines)`

`/var/log/                       # logs (per script)`

`/var/tmp/                       # state files (per host/script)`


**Common config files:**

`/etc/linux_maint/servers.txt — one host per line (used by distributed scripts)`

`/etc/linux_maint/excluded.txt — optional list of hosts to skip`

`/etc/linux_maint/emails.txt — optional recipients (one per line)`

**Email:** Scripts use the system mail/mailx if present. Many support toggles like `EMAIL_ON_*="true"`.

**Cron:** All scripts are safe to run unattended; examples are provided in each section.


## 🛠️ Shared Helpers (`linux_maint.sh`) <a name="shared--helpers"></a>
Some scripts (currently `ntp_drift_monitor.sh` and `backup_check.sh`) are refactored to use this helper library.

**Key env vars (optional):**

`LM_PREFIX` — log prefix (e.g., `[ntp_drift]` )

`LM_LOGFILE` — path to script log

`LM_MAX_PARALLEL` — number of parallel hosts (0 = sequential)

`LM_EMAIL_ENABLED` — master toggle for email (`true`/`false`)

**Key functions:**

`lm_for_each_host <fn>` — iterate hosts (respects excluded list & parallelism)

`lm_ssh <host> <cmd...>` — run command over SSH with sane defaults

`lm_reachable <host>` — quick reachability check

`lm_mail <subject> <body>` — send email if enabled

`lm_info/lm_warn/lm_err` — structured logging

`lm_require_singleton <name>` — prevent re-entrancy

**Drop the file at** `/usr/local/lib/linux_maint.sh` **and source it from scripts that support it.**


## ⚡ Quickstart <a name="quickstart"></a>

#### 1) Create config directory and seed files

```
sudo mkdir -p /etc/linux_maint /usr/local/bin /usr/local/lib /var/log
echo -e "host1\nhost2"        | sudo tee /etc/linux_maint/servers.txt
echo "ops@example.com"        | sudo tee /etc/linux_maint/emails.txt
```

#### 2) Install scripts + helper (example)
```
sudo cp *.sh /usr/local/bin/
sudo cp linux_maint.sh /usr/local/lib/
```

#### 3) Try one script locally
`sudo bash /usr/local/bin/disk_monitor.sh`

#### 4) Add cron (example: daily at 03:00)
```
sudo crontab -e
0 3 * * * /usr/local/bin/patch_monitor.sh
```


## 🧾 Script Matrix <a name="script--matrix"></a>

| Script                          | Purpose                                                 | Runs On      | Log                                           |
| ------------------------------- | ------------------------------------------------------- | ------------ | --------------------------------------------- |
| disk\_monitor.sh                | Disk usage threshold alerts                             | Local + SSH  | `/var/log/disks_monitor.log`                  |
| health\_monitor.sh              | CPU/Mem/Load/Disk snapshot                              | Local + SSH  | `/var/log/health_monitor.log`                 |
| user\_monitor.sh                | New/removed users, sudoers checksum, failed SSH         | Local + SSH  | `/var/log/user_monitor.log`                   |
| service\_monitor.sh             | Status of critical services; optional auto-restart      | Local + SSH  | `/var/log/service_monitor.log`                |
| servers\_info.sh                | Daily system snapshot (HW/OS/net/services)              | Local (typ.) | `/var/log/server_info/<host>_info_<date>.log` |
| patch\_monitor.sh               | Pending updates, security/kernel, reboot flag           | Local + SSH  | `/var/log/patch_monitor.log`                  |
| cert\_monitor.sh                | TLS expiry & OpenSSL verify for endpoints               | Local only   | `/var/log/cert_monitor.log`                   |
| ntp\_drift\_monitor.sh          | Time sync impl + offset/stratum (uses `linux_maint.sh`) | Local + SSH  | `/var/log/ntp_drift_monitor.log`              |
| log\_growth\_guard.sh           | Log absolute size & growth rate                         | Local + SSH  | `/var/log/log_growth_guard.log`               |
| ports\_baseline\_monitor.sh     | NEW/REMOVED listeners vs baseline                       | Local + SSH  | `/var/log/ports_baseline_monitor.log`         |
| backup\_check.sh                | Latest backup age/size/verify (uses `linux_maint.sh`)   | Local + SSH  | `/var/log/backup_check.log`                   |
| nfs\_mount\_monitor.sh          | Mount presence/health; optional remount                 | Local + SSH  | `/var/log/nfs_mount_monitor.log`              |
| config\_drift\_monitor.sh       | File hashes vs baseline; NEW/MOD/REMOVED                | Local + SSH  | `/var/log/config_drift_monitor.log`           |
| inode\_monitor.sh               | Inode usage thresholds per mount                        | Local + SSH  | `/var/log/inode_monitor.log`                  |
| inventory\_export.sh            | CSV inventory + per-host details                        | Local + SSH  | `/var/log/inventory_export.log`               |








## 📄 disk_monitor.sh — Linux Disk Usage Monitoring Script <a name="disk--monitor"></a>
**What it does:** Checks all mounted filesystems (skips tmpfs/devtmpfs) and alerts above a threshold.

#### Config: 
`THRESHOLD=90`

`/etc/linux_maint/servers.txt`

`/etc/linux_maint/emails.txt`

**Log:** `/var/log/disks_monitor.log`

**Run:** `bash /usr/local/bin/disk_monitor.sh`

**Cron:**` 0 8 * * * /usr/local/bin/disk_monitor.sh`


## 📄 health_monitor.sh — System Health <a name="health--monitor"></a>

**What it does:** Collects uptime, load, CPU/mem, disk usage, top processes; emails full report.

#### Config: 
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`


**Log:** `/var/log/health_monitor.log`

**Cron:** ` 0 8 * * * /usr/local/bin/health_monitor.sh`


## 📄 user_monitor.sh — Users & SSH Access <a name="user--monitor"></a>

**What it does:** Detects new/removed users vs baseline, sudoers checksum drift, and failed SSH logins today.

#### Config: 
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/baseline_users.txt (from cut -d: -f1 /etc/passwd)`

`/etc/linux_maint/baseline_sudoers.txt (from md5sum /etc/sudoers | awk '{print $1}')`

`/etc/linux_maint/emails.txt (optional)`

**Log:** `/var/log/user_monitor.log`

**Cron:** `0 0 * * * /usr/local/bin/user_monitor.sh`

Update baselines when legitimate changes occur.

## 📄 service_monitor.sh — Critical Services <a name="service--monitor"></a>

**What it does:** Checks `systemctl is-active` (or SysV fallback) for services in services.txt; optional auto-restart.

#### Config:
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/services.txt`

`/etc/linux_maint/emails.txt`

`AUTO_RESTART="false" (set true to enable)`

**Log:** `/var/log/service_monitor.log`

**Cron:** ` 0 * * * * /usr/local/bin/service_monitor.sh`


## 📄 servers_info.sh — Daily Server Snapshot <a name="servers--info"></a>

**What it does:** One comprehensive log per host: CPU/mem/load, disks/mounts/LVM, RAID/multipath, net, users, services, firewall, updates.

#### Config: 
`/etc/linux_maint/servers.txt`

**Logs:** `/var/log/server_info/<host>_info_<date>.log`

**Cron:** `0 2 * * * /usr/local/bin/servers_info.sh`


## 📄 patch_monitor.sh — Updates & Reboot <a name="patch--monitor"></a>

**What it does:** Counts total/security/kernel updates and detects reboot-required (best-effort per distro).

**Managers:** apt, dnf, yum, zypper

#### Config: 
`/etc/linux_maint/servers.txt` 

`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`

**Log:** `/var/log/patch_monitor.log`

**Cron:** `0 3 * * * /usr/local/bin/patch_monitor.sh`



## 📄 cert_monitor.sh — TLS Expiry & Validity <a name="cert--monitor"></a>

**What it does:** Checks endpoints (host[:port][,sni][,starttls=proto]), parses leaf cert, days remaining, and OpenSSL verify code.

#### Config: 
`/etc/linux_maint/certs.txt`

`/etc/linux_maint/emails.txt`

`THRESHOLD_DAYS=30`

`TIMEOUT_SECS=10`

`EMAIL_ON_WARN="true"`

**Log:**
`/var/log/cert_monitor.log`

**Cron:** `0 1 * * * /usr/local/bin/cert_monitor.sh`


## 📄 ntp_drift_monitor.sh — Time Sync & Drift <a name="ntp--drift--monitor"></a>

**What it does:** Supports chrony, ntpd, systemd-timesyncd. Reports offset(ms), stratum, source, sync status.
Refactored to use `linux_maint.sh` with parallelism and aggregated email.

#### Config: 
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`

`OFFSET_WARN_MS=100`

`OFFSET_CRIT_MS=500`

`EMAIL_ON_ISSUE="true"`

**Log:** `/var/log/ntp_drift_monitor.log`

**Cron:** `0 * * * * /usr/local/bin/ntp_drift_monitor.sh`


## 📄 log_growth_guard.sh — Log Size & Growth <a name="log--growth--guard"></a>

**What it does:** Checks absolute size and MB/hour growth; notes rotations; optional rotate command (off by default).

#### Config:
`/etc/linux_maint/log_paths.txt (supports file/glob/dir/dir/**)`

`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`

`SIZE_WARN_MB=1024`

`SIZE_CRIT_MB=2048`

`RATE_WARN_MBPH=200`

`RATE_CRIT_MBPH=500`

**Log:** `/var/log/log_growth_guard.log`

**Cron:** `0 * * * * /usr/local/bin/log_growth_guard.sh`


## 📄 ports_baseline_monitor.sh — Listening Ports Baseline <a name="ports--baseline--monitor"></a>

**What it does:** Normalizes listeners to `proto|port|process`. Compares to per-host baseline; flags NEW/REMOVED; allowlist supported.

**Baselines:** `/etc/linux_maint/baselines/ports/<host>.baseline`

**Allowlist:** `/etc/linux_maint/ports_allowlist.txt (proto:port or proto:port:proc-substring)`

#### Config: 
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`

`AUTO_BASELINE_INIT="true"`

`BASELINE_UPDATE="false"`

`EMAIL_ON_CHANGE="true"`

**Log:** `var/log/ports_baseline_monitor.log`

**Cron:** `0 * * * * /usr/local/bin/ports_baseline_monitor.sh`


## 📄 backup_check.sh — Backup Freshness & Integrity <a name="backup--check"></a>

**What it does:** Finds newest file per pattern and validates age, min size, and optional integrity.
Refactored to use linux_maint.sh with aggregated email.

**Targets CSV:** `/etc/linux_maint/backup_targets.csv`

**Format:** `host,pattern,min_size_mb,max_age_hours,verify`

**verify:** `none|tar|gzip|cmd:<shell>`(file path passed as $1)

#### Config: /etc/linux_maint/servers.txt
`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`

`VERIFY_TIMEOUT=60`

`EMAIL_ON_FAILURE="true"`

**Log:** `/var/log/backup_check.log`

**Cron:** `30 2 * * * /usr/local/bin/backup_check.sh`



## 📄 nfs_mount_monitor.sh — NFS/CIFS Mount Health <a name="nfs--mount--monitor"></a>

**What it does:** Verifies expected mounts exist and are healthy; optional RW test and auto-remount (disabled by default).

**Mounts CSV:** `/etc/linux_maint/mounts.txt` `host` `mountpoint` `fstype` `remote` `options` `mode` `timeout`

#### Config: 
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`

`AUTO_REMOUNT="false"`

`UMOUNT_FLAGS="-fl"`

`DEFAULT_TIMEOUT=8`

**Log:** `/var/log/nfs_mount_monitor.log`

**Cron:** `*/10 * * * * /usr/local/bin/nfs_mount_monitor.sh`


## 📄 config_drift_monitor.sh — Config Baseline & Drift <a name="config--drift--monitor"></a>

**What it does:** Hashes files/dirs/globs (incl. recursive /**) and compares to per-host baseline. 
Reports **MODIFIED/NEW/REMOVED**. Allowlist supported.

**Paths:** `/etc/linux_maint/config_paths.txt`

**Allowlist:** `/etc/linux_maint/config_allowlist.txt (exact or substring matches)`

**Baselines:** `/etc/linux_maint/baselines/configs/<host>.baseline`

#### Config: 
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt `

`/etc/linux_maint/emails.txt`

`AUTO_BASELINE_INIT="true"`

`BASELINE_UPDATE="false" `

`EMAIL_ON_DRIFT="true"`

**Log:** `/var/log/config_drift_monitor.log`

**Cron:** `30 2 * * * /usr/local/bin/config_drift_monitor.sh`



## 📄 inode_monitor.sh — Inode Usage <a name="inode--monitor"></a>

**What it does:** Per-mount WARN/CRIT thresholds with a global default; ignores pseudo FS types.

**Thresholds CSV:** `/etc/linux_maint/inode_thresholds.txt → mount` `warn%` `crit%` (use * for default)

**Exclude list:** `/etc/linux_maint/inode_exclude.txt (optional)`

#### Config: 
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt`

`/etc/linux_maint/emails.txt`

**Log:** `/var/log/inode_monitor.log`

**Cron:** `0 * * * * /usr/local/bin/inode_monitor.sh`


## 📄 inventory_export.sh — Hardware/Software Inventory Export Script <a name="inventory--export"></a>

**What it does:** Collects key HW/SW facts from each host and appends to a daily CSV. Also saves a per-host details snapshot (CPU, memory, disks, filesystems, LVM, IPs, routes).

**CSV fields (daily file):**
date,host,fqdn,os,kernel,arch,virt,uptime,cpu_model,sockets,cores_per_socket,threads_per_core,vcpus,mem_mb,swap_mb,disk_total_gb,rootfs_use,vgs,lvs,pvs,vgs_size_gb,ip_list,default_gw,dns_servers,pkg_count

#### Config:
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt` (optional)

`/etc/linux_maint/emails.txt` (optional; used if `MAIL_ON_RUN=true`)

**Output:**

`CSV → /var/log/inventory/inventory_<YYYY-MM-DD>.csv`

`Details → /var/log/inventory/details/<host>_<YYYY-MM-DD>.txt`

**Log:** `/var/log/inventory_export.log`

**Cron:** `10 2 * * * /usr/local/bin/inventory_export.sh`

**Notes:** Works on Debian/Ubuntu (dpkg) and RHEL/Fedora/SUSE (rpm). Missing tools are skipped gracefully.


## 📄 network_monitor.sh — Ping / TCP / HTTP Network Monitor <a name="network--monitor"></a>

**What it does:** From each host, runs network probes:
- ping → packet loss & avg RTT thresholds
- tcp → port reachability & connect latency
- http/https → status code & total latency (curl)

Reads checks from a targets file and aggregates WARN/CRIT to a single email.

#### Config:

`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt` (optional)

`/etc/linux_maint/emails.txt` (optional; used if `EMAIL_ON_ALERT=true`)

`/etc/linux_maint/network_targets.txt` (checks)

**Targets format (CSV, one per line):** `host,check,target,key=val,key=val,...`

**host:** exact hostname from servers.txt or * for all

**check:** ping | tcp | http | https

**target:**
- ping → hostname/IP
- tcp → host:port
- http(s) → URL

**common keys:**

**ping:** `count (3)` `timeout (3s)` `loss_warn (20)` `loss_crit (50)` `rtt_warn_ms (150)` `rtt_crit_ms (500)`

**tcp:** `timeout (3s)` `latency_warn_ms (300)` `latency_crit_ms (1000)`

**http(s):** `timeout (5s)` `latency_warn_ms (800)` `latency_crit_ms (2000)` `expect (e.g. 2xx, 200-399, 200,301,302, or 200)`

**Examples:**
```
*,ping,8.8.8.8,count=3,timeout=3,rtt_warn_ms=120,rtt_crit_ms=400
*,tcp,internal-db:5432,timeout=2,latency_warn_ms=250,latency_crit_ms=800
web01,http,https://app.example.com/health,timeout=3,expect=200
```

**Log:** `/var/log/network_monitor.log`

**Cron:** `*/5 * * * * /usr/local/bin/network_monitor.sh`

**Notes:** Uses `/dev/tcp` latency when possible; falls back to nc. HTTP requires curl on target hosts.




## 📄 process_hog_monitor.sh — Sustained CPU/RAM Process Monitor <a name="process--hog--monitor"></a>

**What it does:** Samples processes and alerts only if a process stays above CPU and/or MEM thresholds for configured durations (filters out one-off spikes). Keeps per-host state between runs.

#### Config:
`/etc/linux_maint/servers.txt`

`/etc/linux_maint/excluded.txt` (optional)

`/etc/linux_maint/emails.txt` (optional; used if `EMAIL_ON_ALERT=true`)

`/etc/linux_maint/process_hog_ignore.txt` (optional; case-insensitive substrings of commands to ignore, one per line)

**Thresholds & behavior (tunable inside the script):** `CPU_WARN=70` `CPU_CRIT=90` `MEM_WARN=30` `MEM_CRIT=60` `DURATION_WARN_SEC=120` `DURATION_CRIT_SEC=300` `MAX_PROCESSES=0` (0 = consider all; otherwise top N by CPU)

**Log:** `/var/log/process_hog_monitor.log`
**State:** `/var/tmp/process_hog_monitor.<host>.state`

**Cron:** `*/5 * * * * /usr/local/bin/process_hog_monitor.sh`

**Notes**: Identifies processes via PID + /proc/PID/stat start time to avoid PID-reuse issues. Mails one aggregated table of sustained hogs.




