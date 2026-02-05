# linux-maint — Operator Quick Reference

This page is meant for day-to-day operational use.

## Common commands

```bash
# Run full suite (installed mode)
sudo linux-maint run

# Quick health view (compact)
sudo linux-maint status

# Show more problems (max 100)
sudo linux-maint status --problems 100

# Raw summary lines
sudo linux-maint status --verbose

# Latest logs
sudo linux-maint logs 200

# Diagnostics
sudo linux-maint doctor
```

## Fleet runs (monitoring node)

```bash
# Plan only (no execution)
sudo linux-maint run --group prod --dry-run

# Run group with parallelism
sudo linux-maint run --group prod --parallel 10

# Ad-hoc list
sudo linux-maint run --hosts server-a,server-b --exclude server-c
```

## What to check when something is wrong

1. `sudo linux-maint status --verbose`
2. `sudo linux-maint logs 200`
3. `sudo linux-maint doctor`

## Artifacts (installed mode)

- Full log: `/var/log/health/full_health_monitor_latest.log`
- Summary log: `/var/log/health/full_health_monitor_summary_latest.log`
- Summary JSON: `/var/log/health/full_health_monitor_summary_latest.json`
- Last status file: `/var/log/health/last_status_full`
