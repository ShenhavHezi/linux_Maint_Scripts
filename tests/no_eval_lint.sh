#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# Disallow eval usage in code directories (security hardening)
# Use fixed-string search to avoid regex escaping issues.
if grep -RIn --exclude-dir='.git' --exclude='*.md' -- 'eval ' \
    "$ROOT_DIR/bin" "$ROOT_DIR/lib" "$ROOT_DIR/monitors" "$ROOT_DIR/tools"; then
  echo "FAIL: eval usage detected" >&2
  exit 1
fi

echo "no-eval lint ok"
