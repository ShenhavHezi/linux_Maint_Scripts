#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LM="$ROOT_DIR/bin/linux-maint"

sudo -n true >/dev/null 2>&1 || { echo "sudo without password required for this test" >&2; exit 0; }

sudo bash "$ROOT_DIR/run_full_health_monitor.sh" >/dev/null 2>&1 || true
out=$(sudo bash "$LM" status --quiet)

# Must include totals + problems
echo "$out" | grep -q '^totals: ' || { echo "Missing totals" >&2; exit 1; }
echo "$out" | grep -q '^problems:' || { echo "Missing problems header" >&2; exit 1; }

# Must NOT include verbose headers
if echo "$out" | grep -q '^=== Mode ==='; then
  echo "Found Mode header in --quiet output" >&2
  exit 1
fi

if echo "$out" | grep -q 'Installed paths'; then
  echo "Found Installed paths in --quiet output" >&2
  exit 1
fi

echo "status --quiet ok"
