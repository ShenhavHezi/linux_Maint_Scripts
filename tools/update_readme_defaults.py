#!/usr/bin/env python3
"""Update README.md: regenerate the 'Tuning knobs' section from script defaults.

This keeps documentation aligned with actual script defaults.

Usage:
  python3 tools/update_readme_defaults.py

It updates README.md in-place.
"""

from pathlib import Path
import re

REPO_DIR = Path(__file__).resolve().parents[1]
README = REPO_DIR / "README.md"

SCRIPTS_ORDER = [
    ("inode_monitor.sh", ["THRESHOLDS", "EXCLUDE_MOUNTS", "DEFAULT_WARN", "DEFAULT_CRIT", "EXCLUDE_FSTYPES_RE"]),
    ("network_monitor.sh", [
        "TARGETS",
        "PING_COUNT", "PING_TIMEOUT", "PING_LOSS_WARN", "PING_LOSS_CRIT", "PING_RTT_WARN_MS", "PING_RTT_CRIT_MS",
        "TCP_TIMEOUT", "TCP_LAT_WARN_MS", "TCP_LAT_CRIT_MS",
        "HTTP_TIMEOUT", "HTTP_LAT_WARN_MS", "HTTP_LAT_CRIT_MS", "HTTP_EXPECT",
    ]),
    ("service_monitor.sh", ["SERVICES", "AUTO_RESTART", "EMAIL_ON_ALERT"]),
    ("ports_baseline_monitor.sh", ["BASELINE_DIR", "ALLOWLIST_FILE", "AUTO_BASELINE_INIT", "BASELINE_UPDATE", "INCLUDE_PROCESS", "EMAIL_ON_CHANGE"]),
    ("config_drift_monitor.sh", ["CONFIG_PATHS", "ALLOWLIST_FILE", "BASELINE_DIR", "AUTO_BASELINE_INIT", "BASELINE_UPDATE", "EMAIL_ON_DRIFT"]),
    ("user_monitor.sh", [
        "USERS_BASELINE_DIR", "SUDO_BASELINE_DIR",
        "AUTO_BASELINE_INIT", "BASELINE_UPDATE", "EMAIL_ON_ALERT",
        "USER_MIN_UID",
        "FAILED_WINDOW_HOURS", "FAILED_WARN", "FAILED_CRIT",
    ]),
    ("backup_check.sh", ["TARGETS", "INTEGRITY_TIMEOUT", "EMAIL_ON_ALERT"]),
    ("cert_monitor.sh", ["CERTS", "THRESHOLD_WARN_DAYS", "THRESHOLD_CRIT_DAYS", "TIMEOUT_SECS", "EMAIL_ON_WARN"]),
    ("storage_health_monitor.sh", ["SMARTCTL_TIMEOUT_SECS", "MAX_SMART_DEVICES", "RAID_TOOL_TIMEOUT_SECS", "EMAIL_ON_ISSUE"]),
    ("kernel_events_monitor.sh", ["KERNEL_WINDOW_HOURS", "WARN_COUNT", "CRIT_COUNT", "PATTERNS", "EMAIL_ON_ALERT"]),
    ("preflight_check.sh", ["REQ_CMDS", "OPT_CMDS"]),
    ("disk_trend_monitor.sh", ["STATE_BASE", "WARN_DAYS", "CRIT_DAYS", "HARD_WARN_PCT", "HARD_CRIT_PCT", "MIN_POINTS", "EXCLUDE_FSTYPES_RE", "EXCLUDE_MOUNTS_FILE"]),
    ("nfs_mount_monitor.sh", ["NFS_STAT_TIMEOUT", "EMAIL_ON_ISSUE"]),
    ("inventory_export.sh", ["OUTPUT_DIR", "DETAILS_DIR", "MAIL_ON_RUN"]),
]


def parse_assignments(path: Path) -> dict[str, str]:
    lines = path.read_text(errors="ignore").splitlines()[:260]
    found: dict[str, str] = {}
    for line in lines:
        if line.strip().startswith("#"):
            continue
        m = re.match(r"^([A-Z][A-Z0-9_]+)=(.*)$", line)
        if m:
            found.setdefault(m.group(1), m.group(2).strip())
        m2 = re.match(r"^:\s*\"\$\{([A-Z][A-Z0-9_]+):=([^}]*)\}\"", line)
        if m2:
            found.setdefault(m2.group(1), m2.group(2).strip())
    return found


def generate_markdown() -> str:
    md: list[str] = []
    md.append("Most defaults below are taken directly from the scripts (current repository version).")
    md.append("")

    for script, keys in SCRIPTS_ORDER:
        script_path = REPO_DIR / script
        if not script_path.exists():
            continue
        vals = parse_assignments(script_path)

        md.append(f"### `{script}`")
        printed = False
        for k in keys:
            if k in vals:
                printed = True
                md.append(f"- `{k}` = `{vals[k]}`")
        if not printed:
            md.append("- (no documented tuning knobs extracted)")
        md.append("")

    return "\n".join(md).strip() + "\n"


def main() -> None:
    text = README.read_text()

    # Replace everything between the Tuning knobs header and Exit codes header
    pattern = r"## Tuning knobs \(common configuration variables\)[\s\S]*?(?=\n## Exit codes \(for automation\))"
    m = re.search(pattern, text)
    if not m:
        raise SystemExit("Could not locate tuning knobs section to replace")

    replacement = "## Tuning knobs (common configuration variables)\n\n" + generate_markdown() + "\n"
    updated = text[: m.start()] + replacement + text[m.end() :]

    if updated != text:
        README.write_text(updated)
        print("Updated README.md tuning knobs section.")
    else:
        print("README.md already up to date.")


if __name__ == "__main__":
    main()
