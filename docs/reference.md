# Linux-maint Reference (Detailed)

This document contains the detailed reference sections moved out of the main README.


## Optional packages for full coverage (recommended on bare metal)

Some monitors provide best results when these tools are installed:
- `storage_health_monitor.sh`: `smartctl` (smartmontools) and `nvme` (nvme-cli)


### Vendor RAID controller tooling (optional)

On some bare-metal servers, SMART data is hidden behind a hardware RAID controller.
If you want controller-level health (virtual disk state, predictive failures, rebuilds), install the appropriate vendor CLI.
`storage_health_monitor.sh` will auto-detect and use these tools when available:

- `storcli` / `perccli` (Broadcom/LSI MegaRAID family)
- `ssacli` (HPE Smart Array)
- `omreport` (Dell OMSA)

If none are installed, the monitor reports controller status as `ctrl=NA()` and continues with mdraid/SMART/NVMe checks.

Install examples:

### RHEL / CentOS / Rocky / Alma / Fedora
```bash
sudo dnf install -y smartmontools nvme-cli
```

### Debian / Ubuntu
```bash
sudo apt-get update
sudo apt-get install -y smartmontools nvme-cli
```

### SUSE / openSUSE
```bash
sudo zypper install -y smartmontools nvme-cli
```

## Monitor reference (what checks what)

| Script | Purpose | Config required to be useful | Typical WARN/CRIT causes |
|---|---|---|---|
| `health_monitor.sh` | CPU/mem/load/disk/top snapshot | none | low disk, load spikes, memory pressure |
| `inode_monitor.sh` | inode utilization thresholds | optional thresholds/excludes | inode exhaustion |
| `network_monitor.sh` | ping/tcp/http checks | `network_targets.txt` | packet loss, TCP connect fail, HTTP latency/status |
| `service_monitor.sh` | service health (systemd) | `services.txt` | inactive/failed services |
| `ntp_drift_monitor.sh` | time sync health | none | unsynced clock, high offset |
| `patch_monitor.sh` | pending updates/reboot hints | none | security updates pending, reboot required |
| `storage_health_monitor.sh` | RAID/SMART/NVMe storage health | none (best-effort) | degraded RAID, SMART failures, NVMe critical warnings |
| `kernel_events_monitor.sh` | kernel log scan (OOM/I/O/FS/hung tasks) | none (journalctl recommended) | OOM killer events, disk I/O errors, filesystem errors |
| `cert_monitor.sh` | certificate expiry | `certs.txt` | expiring/expired certs, verify failures |
| `nfs_mount_monitor.sh` | NFS mounted + responsive | none | stale/unresponsive mounts |
| `ports_baseline_monitor.sh` | port drift vs baseline | `ports_baseline.txt` (gate) | new/removed listening ports |
| `config_drift_monitor.sh` | config drift vs baseline | `config_paths.txt` | changed hashes vs baseline |
| `user_monitor.sh` | user/sudoers drift + SSH failures | baseline inputs | new users, sudoers changed, brute-force attempts |
| `backup_check.sh` | backup freshness/integrity | `backup_targets.csv` | old/missing/small/corrupt backups |
| `inventory_export.sh` | HW/SW inventory CSV | none | collection failures |



### Keeping README defaults in sync

If you change default thresholds/paths inside scripts, regenerate the **Tuning knobs** section before committing:

```bash
python3 tools/update_readme_defaults.py
```

## Tuning knobs (common configuration variables)

### Wrapper-level notification (single summary email per run)

By default, the wrapper does **not** send email. You can enable a single per-run summary email using either environment variables or `/etc/linux_maint/notify.conf`.

Supported settings:
- `LM_NOTIFY` = `0|1` (default: `0`)
- `LM_NOTIFY_TO` = `"user@company.com,ops@company.com"` (required when enabled; comma/space separated)
- `LM_NOTIFY_ONLY_ON_CHANGE` = `0|1` (default: `0`)
- `LM_NOTIFY_SUBJECT_PREFIX` = `"[linux_maint]"`
- `LM_NOTIFY_STATE_DIR` = `"/var/lib/linux_maint"` (where the last-run hash is stored; falls back to `LM_STATE_DIR`)
- `LM_NOTIFY_FROM` = `"linux_maint@<host>"` (used when `sendmail` is the transport)

Example `/etc/linux_maint/notify.conf`:

```bash
LM_NOTIFY=1
LM_NOTIFY_TO="ops@company.com"
LM_NOTIFY_ONLY_ON_CHANGE=1
LM_NOTIFY_SUBJECT_PREFIX="[linux_maint]"
```

Mail transport auto-detection:
- uses `mail` if available
- otherwise uses `sendmail`


Most defaults below are taken directly from the scripts (current repository version).

### `inode_monitor.sh`
- `THRESHOLDS` = `"/etc/linux_maint/inode_thresholds.txt"   # CSV: mountpoint,warn%,crit% (supports '*' default)`
- `EXCLUDE_MOUNTS` = `"/etc/linux_maint/inode_exclude.txt"  # Optional: list of mountpoints to skip`
- `DEFAULT_WARN` = `80`
- `DEFAULT_CRIT` = `95`
- `EXCLUDE_FSTYPES_RE` = `'^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?|debugfs|rpc_pipefs|autofs|devpts|mqueue|hugetlbfs|fuse\..*|binfmt_misc|pstore|nsfs)$'`

### `network_monitor.sh`
- `TARGETS` = `"/etc/linux_maint/network_targets.txt"   # CSV: host,check,target,key=val,...`
- `PING_COUNT` = `3`
- `PING_TIMEOUT` = `3`
- `PING_LOSS_WARN` = `20`
- `PING_LOSS_CRIT` = `50`
- `PING_RTT_WARN_MS` = `150`
- `PING_RTT_CRIT_MS` = `500`
- `TCP_TIMEOUT` = `3`
- `TCP_LAT_WARN_MS` = `300`
- `TCP_LAT_CRIT_MS` = `1000`
- `HTTP_TIMEOUT` = `5`
- `HTTP_LAT_WARN_MS` = `800`
- `HTTP_LAT_CRIT_MS` = `2000`
- `HTTP_EXPECT` = `""   # default: 200–399 when empty`

### `service_monitor.sh`
- `SERVICES` = `"/etc/linux_maint/services.txt"     # One service per line (unit name). Comments (#…) and blanks allowed.`
- `AUTO_RESTART` = `"false"                          # "true" to attempt restart on failure (requires root or sudo NOPASSWD)`
- `EMAIL_ON_ALERT` = `"false"                        # "true" to email when any service is not active`

### `ports_baseline_monitor.sh`
- `BASELINE_DIR` = `"/etc/linux_maint/baselines/ports"       # Per-host baselines live here`
- `ALLOWLIST_FILE` = `"/etc/linux_maint/ports_allowlist.txt"  # Optional allowlist`
- `AUTO_BASELINE_INIT` = `"true"       # If no baseline for a host, create it from current snapshot`
- `BASELINE_UPDATE` = `"false"         # If true, replace baseline with current snapshot after reporting`
- `INCLUDE_PROCESS` = `"true"          # Include process names in baseline when available`
- `EMAIL_ON_CHANGE` = `"true"          # Send email when NEW/REMOVED entries are detected`

### `config_drift_monitor.sh`
- `CONFIG_PATHS` = `"/etc/linux_maint/config_paths.txt"        # Targets (files/dirs/globs)`
- `ALLOWLIST_FILE` = `"/etc/linux_maint/config_allowlist.txt"  # Optional: paths to ignore (exact or substring)`
- `BASELINE_DIR` = `"/etc/linux_maint/baselines/configs"       # Per-host baselines live here`
- `AUTO_BASELINE_INIT` = `"true"   # If baseline missing for a host, create it from current snapshot`
- `BASELINE_UPDATE` = `"false"     # After reporting, accept current as new baseline`
- `EMAIL_ON_DRIFT` = `"true"       # Send email when drift detected`

### `user_monitor.sh`
- `USERS_BASELINE_DIR` = `"/etc/linux_maint/baselines/users"       # per-host: ${host}.users`
- `SUDO_BASELINE_DIR` = `"/etc/linux_maint/baselines/sudoers"      # per-host: ${host}.sudoers`
- `AUTO_BASELINE_INIT` = `"true"    # create baseline on first run`
- `BASELINE_UPDATE` = `"false"      # update baseline to current after reporting`
- `EMAIL_ON_ALERT` = `"true"        # send email if anomalies are detected`
- `USER_MIN_UID` = `0`
- `FAILED_WINDOW_HOURS` = `24`
- `FAILED_WARN` = `10`
- `FAILED_CRIT` = `50`

### `backup_check.sh`
- `TARGETS` = `"/etc/linux_maint/backup_targets.csv"  # CSV: host,pattern,min_size_mb,max_age_hours,verify`

### `cert_monitor.sh`
- `THRESHOLD_WARN_DAYS` = `30`
- `THRESHOLD_CRIT_DAYS` = `7`
- `TIMEOUT_SECS` = `10`
- `EMAIL_ON_WARN` = `"true"`

### `storage_health_monitor.sh`
- `SMARTCTL_TIMEOUT_SECS` = `10`
- `MAX_SMART_DEVICES` = `32`
- `RAID_TOOL_TIMEOUT_SECS` = `12`
- `EMAIL_ON_ISSUE` = `"true"`

### `kernel_events_monitor.sh`
- `KERNEL_WINDOW_HOURS` = `24`
- `WARN_COUNT` = `1`
- `CRIT_COUNT` = `5`
- `PATTERNS` = `'oom-killer|out of memory|killed process|soft lockup|hard lockup|hung task|blocked for more than|I/O error|blk_update_request|Buffer I/O error|EXT4-fs error|XFS \(|btrfs: error|nvme.*timeout|resetting link|ata[0-9].*failed|mce:|machine check'`
- `EMAIL_ON_ALERT` = `"true"`

### `preflight_check.sh`
- `REQ_CMDS` = `(bash awk sed grep df ssh)`
- `OPT_CMDS` = `(openssl ss netstat journalctl smartctl nvme mail timeout)`

### `disk_trend_monitor.sh`
- `STATE_BASE` = `"/var/lib/linux_maint/disk_trend"`
- `WARN_DAYS` = `14`
- `CRIT_DAYS` = `7`
- `HARD_WARN_PCT` = `90`
- `HARD_CRIT_PCT` = `95`
- `MIN_POINTS` = `2`
- `EXCLUDE_FSTYPES_RE` = `'^(tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|cgroup2?|debugfs|rpc_pipefs|autofs|devpts|mqueue|hugetlbfs|fuse\..*|binfmt_misc|pstore|nsfs)$'`
- `EXCLUDE_MOUNTS_FILE` = `"/etc/linux_maint/disk_trend_exclude_mounts.txt"`

### `nfs_mount_monitor.sh`
- `NFS_STAT_TIMEOUT` = `5`
- `EMAIL_ON_ISSUE` = `"true"`

### `inventory_export.sh`
- `OUTPUT_DIR` = `"/var/log/inventory"`
- `DETAILS_DIR` = `"${OUTPUT_DIR}/details"`
- `MAIL_ON_RUN` = `"false"`


## Exit codes (for automation)

The wrapper prints a final `SUMMARY_RESULT` line that includes counters: `ok`, `warn`, `crit`, `unknown`, and `skipped` (for monitors skipped due to missing config gates).

All scripts aim to follow:
- `0` = OK
- `1` = WARN
- `2` = CRIT
- `3` = UNKNOWN/ERROR

The wrapper returns the **worst** exit code across all executed monitors.


## Installed file layout (recommended)

## CLI usage (`linux-maint`) (appendix)

After installation, use the `linux-maint` CLI as the primary interface.



### Commands



- `linux-maint run` *(root required)*: run the full wrapper (`run_full_health_monitor.sh`).

- `linux-maint status` *(root required)*: show the last run summary + recent WARN/CRIT/SKIP lines.

- `linux-maint logs [n]` *(root required)*: tail the latest wrapper log (default `n=200`).

- `linux-maint preflight` *(root recommended)*: check dependencies/SSH/config readiness.

- `linux-maint validate` *(root recommended)*: validate `/etc/linux_maint` config file formats (best-effort).

- `linux-maint version`: show installed `BUILD_INFO` (if present).

- `linux-maint install [args]`: run `./install.sh` from a checkout (pass-through).

- `linux-maint uninstall [args]`: run `./install.sh --uninstall` from a checkout (pass-through).

- `linux-maint make-tarball`: build an offline tarball (see below).



### Environment



- `PREFIX` (default: `/usr/local`) overrides installed locations.



### Root requirement



Installed mode writes logs/locks under `/var/log` and `/var/lock` and may require privileged access for some checks.

Use `sudo linux-maint <command>` when in doubt.




```text
/usr/local/sbin/run_full_health_monitor.sh
/usr/local/lib/linux_maint.sh
/usr/local/libexec/linux_maint/
  backup_check.sh
  cert_monitor.sh
  config_drift_monitor.sh
  health_monitor.sh
  inode_monitor.sh
  inventory_export.sh
  network_monitor.sh
  nfs_mount_monitor.sh
  ntp_drift_monitor.sh
  patch_monitor.sh
  storage_health_monitor.sh
  kernel_events_monitor.sh
  ports_baseline_monitor.sh
  service_monitor.sh
  user_monitor.sh

/etc/linux_maint/
  servers.txt
  excluded.txt
  services.txt
  network_targets.txt
  certs.txt
  ports_baseline.txt
  config_paths.txt
  backup_targets.csv
  baseline_users.txt
  baseline_sudoers.txt
  baselines/

/var/log/health/
  full_health_monitor_latest.log
```


## What runs in the nightly "full package" (cron)
The system cron (root) runs the wrapper:

```bash
/usr/local/sbin/run_full_health_monitor.sh
```

That wrapper executes these scripts (in order):

- `health_monitor.sh` – snapshot: uptime, load, CPU/mem, disk usage, top processes
- `inode_monitor.sh` – inode usage thresholds
- `network_monitor.sh` – ping/tcp/http checks from `/etc/linux_maint/network_targets.txt`
- `service_monitor.sh` – critical service status from `/etc/linux_maint/services.txt`
- `ntp_drift_monitor.sh` – NTP/chrony/timesyncd sync and drift
- `patch_monitor.sh` – pending updates + reboot-required hints
- `cert_monitor.sh` – certificate expiry checks from `/etc/linux_maint/certs.txt`
- `nfs_mount_monitor.sh` – NFS mount presence + responsiveness checks
- `ports_baseline_monitor.sh` – detect new/removed listening ports vs baseline
- `config_drift_monitor.sh` – detect drift in critical config files vs baseline
- `user_monitor.sh` – detect user/sudoers anomalies vs baseline
- `backup_check.sh` – verify backups from `/etc/linux_maint/backup_targets.csv`
- `inventory_export.sh` – write daily inventory CSV under `/var/log/inventory/`

### Wrapper log output
The wrapper writes an aggregated log to:

- `/var/log/health/full_health_monitor_latest.log`

It also writes a machine-parseable summary (only `monitor=` lines) to:

- `/var/log/health/full_health_monitor_summary_latest.log`
- `/var/log/health/full_health_monitor_summary_latest.json` *(same content as JSON array)*

This file is intended for automation/CI ingestion and is what `linux-maint status` will prefer when present.

Optional: Prometheus export (textfile collector format)

- Default path: `/var/lib/node_exporter/textfile_collector/linux_maint.prom`
- Metric: `linux_maint_monitor_status{monitor="...",host="..."}` where OK=0, WARN=1, CRIT=2, UNKNOWN/SKIP=3

Each script prints a **single one-line summary** to stdout so the wrapper log stays readable.

If a monitor is skipped by the wrapper due to missing config gates, the wrapper emits a standardized summary line with `status=SKIP` and a `reason=` field.
Detailed logs are still written per-script under `/var/log/*.log`.

## Configuration files under `/etc/linux_maint/`
Minimal files created/used:

- `servers.txt` – hosts list (default: `localhost`)
- `excluded.txt` – optional excluded hosts
- `services.txt` – services to check
- `network_targets.txt` – network checks (CSV)
- `certs.txt` – cert targets (one per line)
- `ports_baseline.txt` – (legacy) initial ports baseline list
- `config_paths.txt` – list of critical config paths to baseline
- `baseline_users.txt` / `baseline_sudoers.txt` – initial user/sudoers baseline inputs

Baselines created by monitors:

- `/etc/linux_maint/baselines/ports/<host>.baseline`
- `/etc/linux_maint/baselines/config/<host>.baseline` (if enabled in script)
- `/etc/linux_maint/baselines/users/<host>.users`
- `/etc/linux_maint/baselines/sudoers/<host>.sudoers`


## Optional monitors: enablement examples

Some monitors are intentionally **skipped** until you provide configuration files.
This keeps first-run output clean and avoids false alerts.

### Enable `network_monitor.sh`

Create `/etc/linux_maint/network_targets.txt` (CSV):

```bash
sudo tee /etc/linux_maint/network_targets.txt >/dev/null <<'EOF'
# host,check,target,key=value...
localhost,ping,8.8.8.8,count=3,timeout=3
localhost,tcp,1.1.1.1:443,timeout=3
localhost,http,https://example.com,timeout=5,expect=200-399
EOF
```

### Enable `cert_monitor.sh`

Create `/etc/linux_maint/certs.txt` (one target per line; supports optional params after `|`):

```bash
sudo tee /etc/linux_maint/certs.txt >/dev/null <<'EOF'
# host:port
example.com:443

# SNI override (when hostname differs from certificate name)
api.example.com:443|sni=api.example.com

# STARTTLS example (if you monitor SMTP)
smtp.example.com:587|starttls=smtp
EOF
```

### Enable `backup_check.sh`

Create `/etc/linux_maint/backup_targets.csv`:

```bash
sudo tee /etc/linux_maint/backup_targets.csv >/dev/null <<'EOF'
# host,pattern,max_age_hours,min_size_mb,verify
*,/backups/db/db_*.tar.gz,24,100,tar
localhost,/var/backups/etc_*.tar.gz,48,10,gzip
EOF
```

### Enable `ports_baseline_monitor.sh`

`ports_baseline_monitor.sh` maintains per-host baselines under:
- `/etc/linux_maint/baselines/ports/<host>.baseline`

The wrapper only runs this monitor when `/etc/linux_maint/ports_baseline.txt` exists.
Create it as an (optional) “gate” file (contents are not used by the monitor):

```bash
sudo install -D -m 0644 /dev/null /etc/linux_maint/ports_baseline.txt
```

On first run, the baseline will be auto-created (when `AUTO_BASELINE_INIT=true`).

### Enable `config_drift_monitor.sh`

Create `/etc/linux_maint/config_paths.txt` with one path/pattern per line:

```bash
sudo tee /etc/linux_maint/config_paths.txt >/dev/null <<'EOF'
/etc/ssh/sshd_config
/etc/sudoers
/etc/fstab
/etc/sysctl.conf
/etc/cron.d/
EOF
```

Then run the wrapper again:

```bash
sudo /usr/local/sbin/run_full_health_monitor.sh
```


## Quick manual run

### Installed mode requires root (recommended)

The installed tool writes logs/locks under `/var/log` and `/var/lock` and may need privileged access for some checks.
Run the wrapper/CLI via `sudo`, cron, or a systemd timer.

Run the full package now:

```bash
sudo /usr/local/sbin/run_full_health_monitor.sh
sudo tail -n 200 /var/log/health/full_health_monitor_latest.log
```





## Offline releases / version tracking

For a step-by-step guide, see: `docs/DARK_SITE.md`.

For dark-site environments, you can generate a versioned tarball that includes a `BUILD_INFO` file.
After installation, version info (when present) is stored at:

- `/usr/local/share/linux_maint/BUILD_INFO`

Build a tarball on a connected workstation:

```bash
./tools/make_tarball.sh
# output: dist/linux_Maint_Scripts-<version>-<sha>.tgz
```

Copy the tarball to the offline server, extract, then install:

```bash
tar -xzf dist/linux_Maint_Scripts-*.tgz
sudo ./install.sh
cat /usr/local/share/linux_maint/BUILD_INFO
```

## Air-gapped / offline installation

If your target servers cannot access GitHub/the Internet, you can still deploy this project.

On a connected workstation:

```bash
git clone https://github.com/ShenhavHezi/linux_Maint_Scripts.git
cd linux_Maint_Scripts

# Recommended: build a versioned tarball with BUILD_INFO
./tools/make_tarball.sh
# output: dist/linux_Maint_Scripts-<version>-<sha>.tgz
```

Copy the generated tarball from `dist/` to the dark-site server, extract, then install:

```bash
tar -xzf linux_Maint_Scripts-*.tgz
sudo ./install.sh --with-logrotate
# (optional)
# sudo ./install.sh --with-user --with-timer --with-logrotate
```

## Development / CI (appendix)

This repository includes a GitHub Actions workflow that:
- runs `shellcheck` on scripts
- verifies the README "Tuning knobs" section is in sync (`tools/update_readme_defaults.py`)


## Developer hooks (optional)

For contributors, you can enable a local pre-commit hook that runs the same checks as CI
(`shellcheck` + README tuning-knobs sync).

Enable repo-local git hooks:

```bash
git config core.hooksPath .githooks
```

Or run the checks manually:

```bash
./tools/pre-commit.sh
```

## Uninstall

Remove the installed files (does not remove your config/baselines unless you choose to):

```bash
# Programs
sudo rm -f /usr/local/sbin/run_full_health_monitor.sh
sudo rm -f /usr/local/lib/linux_maint.sh
sudo rm -rf /usr/local/libexec/linux_maint

# (Optional) configuration + baselines
sudo rm -rf /etc/linux_maint

# (Optional) logs
sudo rm -rf /var/log/health
sudo rm -f /var/log/*monitor*.log /var/log/*_monitor.log /var/log/*_check.log /var/log/inventory_export.log

# (Optional) logrotate entry
sudo rm -f /etc/logrotate.d/linux_maint
```


## Log rotation (recommended)

These scripts write logs under `/var/log/` (plus an aggregated wrapper log under `/var/log/health/`).
On most systems, these logs should be rotated.

Example `logrotate` config (create `/etc/logrotate.d/linux_maint`):

```conf
/var/log/*monitor*.log /var/log/*_monitor.log /var/log/*_check.log /var/log/inventory_export.log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}

/var/log/health/*.log {
  daily
  rotate 14
  missingok
  notifempty
  compress
  delaycompress
  copytruncate
}
```

Notes:
- `copytruncate` is used so rotation is safe even if a script is still writing.
- Tune `rotate`/`daily` to match your retention needs.

## Upgrading

To upgrade on a node where you installed using the recommended paths:

```bash
cd /path/to/linux_Maint_Scripts
git pull

sudo install -D -m 0755 lib/linux_maint.sh /usr/local/lib/linux_maint.sh
sudo install -D -m 0755 run_full_health_monitor.sh /usr/local/sbin/run_full_health_monitor.sh
sudo install -D -m 0755 monitors/*.sh /usr/local/libexec/linux_maint/
```

After upgrading:
- Review `git diff` for config file name changes.
- Re-run the wrapper once and check: `/var/log/health/full_health_monitor_latest.log`.
