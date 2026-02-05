#!/usr/bin/env bash
set -euo pipefail

# Build an RPM using rpmbuild.
# Usage:
#   ./packaging/rpm/build_rpm.sh [version]

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SPEC="$ROOT/packaging/rpm/linux-maint.spec"
VERSION="${1:-$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)}"

WORK="${WORK:-/tmp/linux-maint-rpmbuild}"
rm -rf "$WORK"
mkdir -p "$WORK"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# Create source tarball

# Ensure BUILD_INFO matches VERSION+git sha for this build
"$ROOT/tools/gen_build_info.sh" >/dev/null 2>&1 || true
TARBALL="$WORK/SOURCES/linux-maint-${VERSION}.tar.gz"

tmpdir="$WORK/src/linux-maint-${VERSION}"
mkdir -p "$tmpdir"
# Copy repo content into tarball source dir (exclude .git and local logs)
rsync -a --delete \
  --exclude '.git' --exclude '.logs*' --exclude 'dist' --exclude '__pycache__' \
  "$ROOT/" "$tmpdir/" >/dev/null

tar -C "$WORK/src" -czf "$TARBALL" "linux-maint-${VERSION}"

# Build
rpmbuild \
  --define "_topdir $WORK" \
  --define "version $VERSION" \
  -ba "$SPEC"

echo "RPMs built under: $WORK/RPMS"
find "$WORK/RPMS" -type f -name '*.rpm' -maxdepth 3 -print
