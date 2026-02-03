#!/usr/bin/env bash
# tools/make_tarball.sh - Build a versioned tarball for offline/dark-site installs
#
# Produces a tarball under ./dist/ that contains the repo contents PLUS a BUILD_INFO file.
# Enforces a clean git working tree to avoid accidental uncommitted builds.

set -euo pipefail

OUTDIR="${OUTDIR:-dist}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$REPO_ROOT"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required to build a tarball" >&2
  exit 1
fi

# Require clean working tree
if [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree not clean. Commit/stash changes before building a release tarball." >&2
  git status --porcelain
  exit 1
fi

sha="$(git rev-parse --short HEAD)"
branch="$(git rev-parse --abbrev-ref HEAD)"
date_utc="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
version_tag="$(git describe --tags --always 2>/dev/null || echo "$sha")"

name="linux_Maint_Scripts-${version_tag}-${sha}"
mkdir -p "$OUTDIR"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Export repo without .git
# (git archive is ideal and deterministic)
if git archive --format=tar HEAD | tar -xf - -C "$workdir"; then
  :
else
  echo "ERROR: git archive failed" >&2
  exit 1
fi

cat > "$workdir/BUILD_INFO" <<EOF
project=linux_Maint_Scripts
version=${version_tag}
commit=${sha}
branch=${branch}
built_at_utc=${date_utc}
EOF

# Create tarball

tarball="$OUTDIR/${name}.tgz"
( cd "$workdir" && tar -czf "$REPO_ROOT/$tarball" . )

echo "Built: $tarball"

echo "Contents checksum (sha256):"
sha256sum "$tarball" | awk '{print $1"  "$2}'
