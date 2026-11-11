#!/bin/bash
# Downloads the Debian buster packages the board needs, with all their dependencies,
# into packages/ so install.sh can install them without internet access.
#
#   scripts/fetch-packages.sh [--platform linux/arm64|linux/arm/v7]
#
# Needs Docker. Default platform: linux/arm64 (use linux/arm/v7 if the board's
# `dpkg --print-architecture` says armhf). Runs on macOS (bash 3.2) and in CI.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
OUT="$REPO/packages"
PLATFORM=linux/arm64
IMAGE=debian:buster
# Keep in sync with PACKAGES in scripts/install.sh.
PACKAGES="mgba-sdl bluez joystick python3-tk"

usage() {
  sed -n '2,8s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case $1 in
    --platform) [ $# -ge 2 ] || usage 2; PLATFORM=$2; shift ;;
    -h | --help) usage 0 ;;
    *) printf 'error: unknown option: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done

command -v docker >/dev/null || { echo "error: Docker is not installed" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "error: Docker is not running (start Docker Desktop)" >&2; exit 1; }

echo "==> Removing the previous package set from packages/"
mkdir -p "$OUT"
rm -f "$OUT"/*.deb "$OUT/Packages" "$OUT/Release" "$OUT/manifest.txt"

echo "==> Downloading $PACKAGES and dependencies for $PLATFORM (this takes a few minutes)"
# The dependency tree is resolved in full (not just what the container lacks), so the
# board gets newer versions of shared libraries too if its own are older.
docker run --rm --platform "$PLATFORM" -e PACKAGES="$PACKAGES" -v "$OUT:/out" "$IMAGE" bash -euo pipefail -c '
  # buster is archived. Include the security and point-release updates too: the base
  # image (and most boards) already have those versions of the core libraries.
  cat > /etc/apt/sources.list <<EOF
deb http://archive.debian.org/debian buster main
deb http://archive.debian.org/debian buster-updates main
deb http://archive.debian.org/debian-security buster/updates main
EOF
  apt-get -qq -o Acquire::Check-Valid-Until=false update
  # apt-utils provides apt-ftparchive, used below to write the package index.
  DEBIAN_FRONTEND=noninteractive apt-get -qq install -y --no-install-recommends apt-utils >/dev/null
  cd /tmp && mkdir debs && chown _apt debs && cd debs
  # shellcheck disable=SC2086
  apt-cache depends --recurse --no-recommends --no-suggests --no-conflicts \
      --no-breaks --no-replaces --no-enhances $PACKAGES |
    grep "^[a-z0-9]" | sort -u > /tmp/wanted
  # Virtual packages (no real .deb) are skipped by filtering on what apt can actually show.
  xargs apt-cache show --no-all-versions < /tmp/wanted 2>/dev/null |
    sed -n "s/^Package: //p" | sort -u > /tmp/real
  xargs apt-get -qq download < /tmp/real
  cp ./*.deb /out/
  cd /out
  apt-ftparchive packages . > Packages
  apt-ftparchive release . > Release
  echo "arch=$(dpkg --print-architecture)" > manifest.txt
'

{
  echo "packages=$PACKAGES"
  echo "platform=$PLATFORM"
  echo "fetched=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "fetched_from_commit=$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)"
} >>"$OUT/manifest.txt"

n=$(find "$OUT" -name '*.deb' | wc -l | tr -d ' ')
size=$(du -sh "$OUT" | cut -f1)
echo "==> Done: $n packages ($size) in packages/"
