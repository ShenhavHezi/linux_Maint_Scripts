# Linux Maintenance Toolkit (linux-maint)

`linux-maint` is a lightweight health/maintenance toolkit for Linux administrators.
Run it locally or from a monitoring node over SSH, get structured logs + a simple OK/WARN/CRIT summary.


## What you get

- **Standardized summary contract** per monitor (`monitor=... host=... status=... reason=...`) for automation.
- **Hardened wrapper**: if a monitor fails without emitting a summary line, the wrapper emits `status=UNKNOWN reason=no_summary_emitted`.
- **Timeout protection** per monitor (`MONITOR_TIMEOUT_SECS`) to avoid hanging runs.
- **Config/baseline gating with SKIP**: missing optional files produce `status=SKIP` with a reason.
- **Fleet counters** derived from summary lines (`SUMMARY_HOSTS ok=.. warn=.. crit=.. unknown=.. skipped=..`).
- Optional **Prometheus textfile** output for node_exporter.


## What it does

- Runs a set of modular checks (disk/inodes, CPU/memory/load, services, network reachability, NTP drift, patch/reboot hints,
  kernel events, cert expiry, NFS mounts, storage health best-effort, backups freshness, inventory export, and drift checks).
- Works **locally** or **across many hosts** via `/etc/linux_maint/servers.txt`.
- Produces machine-parseable summary lines (`monitor=... status=...`) and an aggregated run log.


## Supported environments (high level)

- **Linux distributions**: designed for common enterprise distros (RHEL-like, Debian/Ubuntu, SUSE-like). Some monitors auto-detect available tooling.
- **Execution**: local host checks and/or distributed checks over SSH from a monitoring node.
- **Schedulers**: cron or systemd timer (installer can set these up).


## Requirements (minimal)

- `bash` + standard core utilities (`awk`, `sed`, `grep`, `df`, `ps`, etc.)
- `ssh` client for distributed mode
- `sudo`/root recommended (many checks read privileged state and write to `/var/log` and `/etc/linux_maint`)

Optional (improves coverage): `smartctl` (smartmontools), `nvme` (nvme-cli), vendor RAID CLIs.

## Dark-site / offline (air-gapped) use

This project is designed to work in environments without direct Internet access.

Typical workflow:
1. On a connected machine, download a release tarball (or clone the repo).
2. Transfer it to the dark-site environment.
3. Install using `install.sh` and your internal package repos/mirrors.

Full offline install steps: [`docs/DARK_SITE.md`](docs/DARK_SITE.md).

Release/version tracking notes and deeper configuration reference: [`docs/reference.md`](docs/reference.md).


## Quickstart

### Local run (from the repo)

```bash
git clone https://github.com/ShenhavHezi/linux_Maint_Scripts.git
cd linux_Maint_Scripts
sudo ./run_full_health_monitor.sh
sudo ./bin/linux-maint status
```

### Distributed run (monitoring node)

Example using CLI flags (recommended):

```bash
sudo linux-maint run --group prod --parallel 10
# or
sudo linux-maint run --hosts server-a,server-b --exclude server-c
```

Planning safely (no execution):

```bash
sudo linux-maint run --group prod --dry-run
sudo linux-maint run --group prod --dry-run --shuffle --limit 10
sudo linux-maint run --group prod --debug --dry-run
```

```bash
sudo install -d -m 0755 /etc/linux_maint
printf '%s
' server-a server-b server-c | sudo tee /etc/linux_maint/servers.txt
sudo /usr/local/sbin/run_full_health_monitor.sh
```

## Install (recommended)

```bash
sudo ./install.sh --with-user --with-timer --with-logrotate
```

Manual install is also supported (see Appendix).

## Configuration (the 3 files you’ll touch first)

Templates are in `etc/linux_maint/*.example`; installed configs live in `/etc/linux_maint/`.

- `servers.txt` — target hosts for SSH mode
- `services.txt` — services to verify
- `network_targets.txt` — optional reachability checks

## How to read results


### Example: status output (compact)

```text
$ sudo linux-maint status
...
=== Summary (compact) ===
totals: CRIT=1 WARN=2 UNKNOWN=0 SKIP=1 OK=14

problems:
CRIT ntp_drift_monitor reason=ntp_drift_high
WARN patch_monitor reason=security_updates_pending
SKIP backup_check reason=missing_targets_file
```

Tips:
- `sudo linux-maint status --verbose` for raw summary lines
- `sudo linux-maint status --problems 100` to list more problems (max 100)


- **Exit codes** (wrapper): `0 OK`, `1 WARN`, `2 CRIT`, `3 UNKNOWN`
- Logs:
  - Aggregated: `/var/log/health/` (installed mode)
  - Per-monitor: `/var/log/` (or overridden via `LM_LOGFILE`)

### Artifacts produced (installed mode)

The wrapper writes both a full log and summary artifacts you can parse/ship to monitoring:

- Full run log: `/var/log/health/full_health_monitor_<timestamp>.log` + `full_health_monitor_latest.log`
- Summary (only `monitor=` lines): `/var/log/health/full_health_monitor_summary_<timestamp>.log` + `full_health_monitor_summary_latest.log`
- Summary JSON: `..._summary_<timestamp>.json` + `..._summary_latest.json`
- Prometheus textfile (optional): `/var/lib/node_exporter/textfile_collector/linux_maint.prom`

See the full contract and artifact details in [`docs/reference.md`](docs/reference.md#output-contract-machine-parseable-summary-lines).
- The wrapper also emits fleet-accurate counters derived from `monitor=` lines: `SUMMARY_HOSTS ok=.. warn=.. crit=.. unknown=.. skipped=..`.

### Summary contract (for automation)

Each monitor emits lines like:

```text
monitor=<name> host=<target> status=<OK|WARN|CRIT|UNKNOWN|SKIP> node=<runner> key=value...
```

Notes:
- For non-`OK` statuses, monitors typically include a `reason=<token>` key (e.g. `ssh_unreachable`, `baseline_missing`, `collect_failed`).
- Full contract details and artifact locations are documented in [`docs/reference.md`](docs/reference.md#output-contract-machine-parseable-summary-lines).
- `SKIP` means the monitor intentionally did not evaluate (e.g., missing optional config/baseline).

## Common knobs

### Optional email notification (single summary per run)

Create `/etc/linux_maint/notify.conf`:

```bash
LM_NOTIFY=1
LM_NOTIFY_TO="ops@company.com"
LM_NOTIFY_ONLY_ON_CHANGE=1
```

Details in [`docs/reference.md`](docs/reference.md).

- `MONITOR_TIMEOUT_SECS` (default `600`)
- `LM_EMAIL_ENABLED=false` by default
- `LM_NOTIFY` (wrapper-level per-run email summary; default `0` / off)
- `LM_SSH_OPTS` (e.g. `-o BatchMode=yes -o ConnectTimeout=3`)
- `LM_LOCAL_ONLY=true` (force local-only; used in CI)

## Table of Contents

- [What it does](#what-it-does)
- [Supported environments (high level)](#supported-environments-high-level)
- [Requirements (minimal)](#requirements-minimal)
- [Dark-site / offline (air-gapped) use](docs/DARK_SITE.md)
- [Quickstart](#quickstart)
-   [Local run (from the repo)](#local-run-from-the-repo)
-   [Distributed run (monitoring node)](#distributed-run-monitoring-node)
- [Install (recommended)](#install-recommended)
- [Configuration (the 3 files you’ll touch first)](#configuration-the-3-files-youll-touch-first)
- [How to read results](#how-to-read-results)
-   [Summary contract (for automation)](#summary-contract-for-automation)
- [Common knobs](#common-knobs)
- [Full reference](docs/reference.md)



## Operator quick reference

See [`docs/QUICK_REFERENCE.md`](docs/QUICK_REFERENCE.md).

## Full reference

See [`docs/reference.md`](docs/reference.md) for monitors reference, tuning per monitor, configuration file details, offline/air-gapped notes, CI, uninstall, upgrading, etc.
