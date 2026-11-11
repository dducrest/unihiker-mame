#!/bin/bash
# Tests install.sh without a board: runs it twice in an arm64 Debian buster container,
# then checks the result. The second run must change nothing.
#
#   scripts/test-in-docker.sh [--platform linux/arm64|linux/arm/v7]
#
# Needs Docker and a filled packages/ folder (run scripts/fetch-packages.sh first).
# Runs on macOS (bash 3.2) and in CI.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
PLATFORM=linux/arm64
IMAGE=debian:buster

while [ $# -gt 0 ]; do
  case $1 in
    --platform) [ $# -ge 2 ] || exit 2; PLATFORM=$2; shift ;;
    -h | --help) sed -n '2,8s/^# \{0,1\}//p' "$0"; exit 0 ;;
    *) echo "error: unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

[ -f "$REPO/packages/Packages" ] || { echo "error: run scripts/fetch-packages.sh first" >&2; exit 1; }
docker info >/dev/null 2>&1 || { echo "error: Docker is not running" >&2; exit 1; }

echo "==> Running install.sh in $IMAGE ($PLATFORM)"
docker run --rm --platform "$PLATFORM" -v "$REPO:/src:ro" "$IMAGE" bash -euo pipefail -c '
  fails=0
  check() {  # check "description" command...
    local what=$1; shift
    if "$@"; then echo "    ok:     $what"; else echo "    FAILED: $what"; fails=$((fails + 1)); fi
  }

  # Simulate what deploy.sh does: stage the repo, write VERSION, copy ROMs.
  mkdir -p /tmp/unihiker-gb /root/roms
  cp -a /src/assets /src/config /src/launcher /src/systemd /src/scripts /src/packages /tmp/unihiker-gb/
  printf "commit=docker-test\ndeployed=2026-01-01T00:00:00Z\n" > /tmp/unihiker-gb/VERSION
  rom="Test Game (USA).gb"
  echo "not a real rom" > "/root/roms/$rom"
  echo "old save" > "/root/roms/Test Game (USA).sav"

  args=(--src /tmp/unihiker-gb --rom-file "$rom" --bt-ertm-fix)

  echo "==> First run"
  bash /tmp/unihiker-gb/scripts/install.sh "${args[@]}" | tee /tmp/run1.log
  echo "==> Second run (must change nothing)"
  bash /tmp/unihiker-gb/scripts/install.sh "${args[@]}" | tee /tmp/run2.log

  echo "==> Checking the result"
  check "second run made no changes" grep -q "changes made: 0" /tmp/run2.log
  check "mgba is installed" test -x /usr/games/mgba
  check "jstest is installed" test -x /usr/bin/jstest
  check "bluetoothctl is installed" test -x /usr/bin/bluetoothctl
  check "python3 has tkinter" python3 -c "import tkinter"
  check "boot ROM is set (name with spaces and brackets)" \
    bash -c ". /etc/unihiker-gb/game.conf && [ \"\$ROM_FILE\" = \"$rom\" ]"
  check "old save moved to /root/saves" test -f "/root/saves/Test Game (USA).sav"
  check "old save no longer in /root/roms" test ! -e "/root/roms/Test Game (USA).sav"
  check "version stamp written" grep -q "commit=docker-test" /etc/unihiker-gb/version
  check "package arch in version stamp" grep -q "packages_arch=" /etc/unihiker-gb/version
  for f in start-gb.sh status-screen.py check-skip-button.py controller-event.sh set-rom.sh \
           pair-bluetooth.sh lib/rom-rules.sh splash.png gamecontrollerdb.txt; do
    check "/opt/unihiker-gb/$f installed" test -f "/opt/unihiker-gb/$f"
  done
  check "start-gb.sh is executable" test -x /opt/unihiker-gb/start-gb.sh
  check "systemd unit installed" test -f /etc/systemd/system/gameboy.service
  check "udev rule installed" test -f /etc/udev/rules.d/99-unihiker-gb-controller.rules
  check "ERTM workaround installed" test -f /etc/modprobe.d/unihiker-gb-bluetooth.conf
  check "mGBA config installed" test -f /root/.config/mgba/config.ini
  check "only the local apt source was used" grep -q "file:/opt/unihiker-gb/packages" /etc/apt/sources.list.d/unihiker-gb.list

  echo "==> set-rom.sh"
  echo "another rom" > /root/roms/second.gbc
  check "set-rom.sh accepts a good name" /opt/unihiker-gb/set-rom.sh second.gbc
  check "set-rom.sh updated game.conf" bash -c ". /etc/unihiker-gb/game.conf && [ \"\$ROM_FILE\" = second.gbc ]"
  echo "x" > "/root/roms/bad\$name.gb"
  check "set-rom.sh rejects a dangerous name" bash -c "! /opt/unihiker-gb/set-rom.sh \"bad\\\$name.gb\" 2>/dev/null"
  check "set-rom.sh rejects a missing file" bash -c "! /opt/unihiker-gb/set-rom.sh missing.gb 2>/dev/null"
  check "game.conf unchanged after rejections" bash -c ". /etc/unihiker-gb/game.conf && [ \"\$ROM_FILE\" = second.gbc ]"

  echo "==> install.sh refuses packages for the wrong architecture"
  cp -a /tmp/unihiker-gb /tmp/wrong-arch
  sed -i "s/^arch=.*/arch=armhf-not-this-board/" /tmp/wrong-arch/packages/manifest.txt
  check "wrong architecture is refused" bash -c "! bash /tmp/wrong-arch/scripts/install.sh --src /tmp/wrong-arch >/dev/null 2>&1"

  if [ "$fails" -eq 0 ]; then echo "==> All checks passed"; else echo "==> $fails check(s) FAILED"; exit 1; fi
'
