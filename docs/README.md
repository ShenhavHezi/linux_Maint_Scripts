# Documentation

This directory contains the extended documentation for **linux-maint**.

## Start here

- **Main overview + quickstart**: see the repository [`README.md`](../README.md)
- **Full reference** (detailed): [`reference.md`](reference.md)

## What’s in the reference

`reference.md` includes:
- monitor reference (what each script checks)
- tuning knobs and per-monitor configuration
- configuration files under `/etc/linux_maint/`
- offline/air-gapped installation notes
- development/CI notes
- upgrading, uninstall, log rotation


## Developer hooks (optional)

This repo includes optional git hooks under `.githooks/`.
To enable them locally:

```bash
git config core.hooksPath .githooks
```

The `pre-push` hook ensures `summarize.txt` autogen sections are up to date.
