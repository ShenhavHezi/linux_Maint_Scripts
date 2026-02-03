#!/usr/bin/env bash
# tools/pre-commit.sh - Local checks before committing (optional)
# Runs the same checks enforced by CI.

set -euo pipefail

echo "[pre-commit] Running shellcheck..."
if ! command -v shellcheck >/dev/null 2>&1; then
  echo "shellcheck not found. Install it (e.g. apt-get install shellcheck / dnf install ShellCheck)" >&2
  exit 1
fi
shellcheck -x -- ./*.sh ./install.sh ./linux-maint ./tools/*.sh

echo "[pre-commit] Verifying README tuning knobs are in sync..."
python3 tools/update_readme_defaults.py

git diff --exit-code README.md

echo "[pre-commit] OK"
