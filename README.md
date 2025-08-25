# Linux Maintenance Scripts

A curated set of lightweight Bash tools for day-to-day Linux ops: monitoring, inventory, baselines, and drift detection. Most scripts support **distributed mode** (run checks on many hosts via SSH) and **email alerts**.

---

## 📚 Table of Contents
- [Conventions & Layout](#Conventions--and--Layout) 
- Shared Helpers (linux_maint.sh)
- Quickstart
- Script Matrix

Script:
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
- [Network_Monitor.sh (`network_monitor.sh`)](#network_monitorsh--ping--tcp--http-network-monitor)
- [Process_Hog_Monitor.sh (`process_hog_monitor.sh`)](#process_hog_monitorsh--sustained-cpuram-process-monitor)
---


## 🧭 Conventions & Layout <a name="Conventions--and--Layout"></a>
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


## 🛠️ Shared Helpers (`linux_maint.sh`)
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


## ⚡ Quickstart

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
`sudo bash /usr/local/bin/distributed_disk_monitor.sh`

#### 4) Add cron (example: daily at 03:00)
```
sudo crontab -e
0 3 * * * /usr/local/bin/patch_monitor.sh
```


## 🧾 Script Matrix

| Script                          | Purpose                                                 | Runs On      | Log                                           |
| ------------------------------- | ------------------------------------------------------- | ------------ | --------------------------------------------- |
| distributed\_disk\_monitor.sh   | Disk usage threshold alerts                             | Local + SSH  | `/var/log/disks_monitor.log`                  |
| distributed\_health\_monitor.sh | CPU/Mem/Load/Disk snapshot                              | Local + SSH  | `/var/log/health_monitor.log`                 |
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








# 📄 disk_monitor.sh — Linux Disk Usage Monitoring Script <a name="disk_monitorsh--linux-disk-usage-monitoring-script"></a>













