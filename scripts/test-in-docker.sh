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
  check "xdotool is installed" test -x /usr/bin/xdotool
  check "python3 has tkinter" python3 -c "import tkinter"
  check "boot ROM is set (name with spaces and brackets)" \
    bash -c ". /etc/unihiker-gb/game.conf && [ \"\$ROM_FILE\" = \"$rom\" ]"
  check "old save moved to /root/saves" test -f "/root/saves/Test Game (USA).sav"
  check "old save no longer in /root/roms" test ! -e "/root/roms/Test Game (USA).sav"
  check "version stamp written" grep -q "commit=docker-test" /etc/unihiker-gb/version
  check "package arch in version stamp" grep -q "packages_arch=" /etc/unihiker-gb/version
  for f in start-gb.sh status-screen.py check-skip-button.py hotkeys.py controller-event.sh set-rom.sh \
           pair-bluetooth.sh set-rotation.sh lib/rom-rules.sh splash.png splash-landscape.png; do
    check "/opt/unihiker-gb/$f installed" test -f "/opt/unihiker-gb/$f"
  done
  check "no controller database installed" test ! -e /opt/unihiker-gb/gamecontrollerdb.txt
  check "controller mapping in mGBA config" grep -q "^keyA=" /root/.config/mgba/config.ini
  timeout 2 /opt/unihiker-gb/hotkeys.py --dry-run >/tmp/hotkeys.log 2>&1 || true
  check "hotkeys.py reads L/R/Select/Start from the mGBA config" \
    grep -q "default mapping: L=4 R=5 Select=8 Start=9" /tmp/hotkeys.log
  check "start-gb.sh is executable" test -x /opt/unihiker-gb/start-gb.sh
  check "set-rotation.sh is executable" test -x /opt/unihiker-gb/set-rotation.sh
  check "first install sets the default screen orientation" grep -qx "DISPLAY_ROTATION=right" /etc/unihiker-gb/board.conf
  check "first install writes the X rotation file (right = CW)" grep -q "Option *\"Rotate\" *\"CW\"" /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  check "display orientation unit installed" grep -q "ExecStart=/opt/unihiker-gb/set-rotation.sh --from-config" \
    /etc/systemd/system/unihiker-gb-display.service
  check "systemd unit installed" test -f /etc/systemd/system/gameboy.service
  check "Bluetooth link security unit installed" test -f /etc/systemd/system/unihiker-gb-bluetooth.service
  check "bt-link-security.sh is executable" test -x /opt/unihiker-gb/bt-link-security.sh
  btsec_rc=0; BT_WAIT_SECONDS=1 /opt/unihiker-gb/bt-link-security.sh > /tmp/btsec.log 2>&1 || btsec_rc=$?
  check "bt-link-security.sh exits 0 without an adapter" test "$btsec_rc" -eq 0
  check "bt-link-security.sh says there is no adapter" grep -q "no Bluetooth adapter hci0" /tmp/btsec.log
  check "udev rule installed" test -f /etc/udev/rules.d/99-unihiker-gb-controller.rules
  check "ERTM workaround installed" test -f /etc/modprobe.d/unihiker-gb-bluetooth.conf
  check "mGBA config installed" test -f /root/.config/mgba/config.ini
  check "only the local apt source was used" grep -q "file:/opt/unihiker-gb/packages" /etc/apt/sources.list.d/unihiker-gb.list

  echo "==> install.sh replaces an outdated mGBA config, keeping a backup"
  echo "; edited by hand" >> /root/.config/mgba/config.ini
  bash /tmp/unihiker-gb/scripts/install.sh --src /tmp/unihiker-gb --no-start > /tmp/run3.log 2>&1
  check "mGBA config matches the repo again" cmp -s /src/config/mgba-config.ini /root/.config/mgba/config.ini
  check "hand-edited copy kept as a backup" bash -c "grep -l \"edited by hand\" /root/.config/mgba/config.ini.bak-* >/dev/null"
  check "Xbox controller section installed" grep -q "^\[gba.input-profile.Xbox Wireless Controller\]" /root/.config/mgba/config.ini

  echo "==> install.sh --rotate"
  bash /tmp/unihiker-gb/scripts/install.sh --src /tmp/unihiker-gb --no-start --rotate left > /tmp/rot1.log 2>&1
  check "--rotate left is written to board.conf" grep -qx "DISPLAY_ROTATION=left" /etc/unihiker-gb/board.conf
  check "--rotate keeps the old board.conf as a backup" grep -qx "DISPLAY_ROTATION=right" /etc/unihiker-gb/board.conf.bak
  check "--rotate left rewrites the X rotation file (CCW)" grep -q "Option *\"Rotate\" *\"CCW\"" /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  check "--rotate with --no-start says it applies next boot" grep -q "applies from the next boot" /tmp/rot1.log
  bash /tmp/unihiker-gb/scripts/install.sh --src /tmp/unihiker-gb --no-start > /tmp/rot2.log 2>&1
  check "a deploy without --rotate keeps the setting" grep -qx "DISPLAY_ROTATION=left" /etc/unihiker-gb/board.conf
  check "a deploy without --rotate changes nothing" grep -q "changes made: 0" /tmp/rot2.log
  rc=0; bash /tmp/unihiker-gb/scripts/install.sh --src /tmp/unihiker-gb --no-start --rotate sideways > /tmp/rot3.log 2>&1 || rc=$?
  check "--rotate sideways is refused" test "$rc" -eq 2
  check "a refused --rotate leaves board.conf alone" grep -qx "DISPLAY_ROTATION=left" /etc/unihiker-gb/board.conf

  bash /tmp/unihiker-gb/scripts/install.sh --src /tmp/unihiker-gb --no-start --rotate normal > /tmp/rot4.log 2>&1
  check "--rotate normal removes the X rotation file" test ! -e /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  bash /tmp/unihiker-gb/scripts/install.sh --src /tmp/unihiker-gb --no-start --rotate right > /tmp/rot5.log 2>&1
  check "--rotate right writes it again (CW)" grep -q "Option *\"Rotate\" *\"CW\"" /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf

  echo "==> set-rotation.sh"
  rotate() {  # rotate <out> <args>...: runs set-rotation.sh (stdout to <out>), returns its exit status
    local out=$1; shift
    /opt/unihiker-gb/set-rotation.sh "$@" > "$out" 2>/tmp/rot-err.log
  }
  rc=0; rotate /tmp/rot-same.out right || rc=$?
  check "set-rotation.sh: same direction exits 0" test "$rc" -eq 0
  check "set-rotation.sh: same direction changes nothing" test ! -s /tmp/rot-same.out
  rotate /tmp/rot-inv.out inverted
  check "set-rotation.sh inverted: says changed" grep -qx changed /tmp/rot-inv.out
  check "set-rotation.sh inverted: Rotate UD" grep -q "Option *\"Rotate\" *\"UD\"" /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  rc=0; rotate /tmp/rot-bad.out sideways || rc=$?
  check "set-rotation.sh: refuses an unknown direction (exit 2)" test "$rc" -eq 2
  check "set-rotation.sh: a refused direction leaves the file alone" grep -q "\"UD\"" /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  rotate /tmp/rot-cfg.out --from-config
  check "set-rotation.sh --from-config: back to board.conf (right)" grep -q "Option *\"Rotate\" *\"CW\"" /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  cp /etc/unihiker-gb/board.conf /tmp/board.conf.saved
  echo "DISPLAY_ROTATION=sideways" > /etc/unihiker-gb/board.conf
  rc=0; rotate /tmp/rot-badcfg.out --from-config || rc=$?
  check "set-rotation.sh --from-config: bad setting exits 0" test "$rc" -eq 0
  check "set-rotation.sh --from-config: bad setting means portrait" test ! -e /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  check "set-rotation.sh --from-config: ... with a warning" grep -q "warning: DISPLAY_ROTATION" /tmp/rot-err.log
  cp /tmp/board.conf.saved /etc/unihiker-gb/board.conf
  rotate /tmp/rot-cfg2.out --from-config

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

  echo "==> start-gb.sh boot flow (with stand-ins for X, systemctl, mGBA and the board button)"
  # The container has no display, user manager or board, so xset, systemctl and mGBA are
  # replaced by scripts that log how they were called, and pinpong by a fake module.
  calls=/tmp/calls.log
  mkdir -p /tmp/stubs/pinpong /dev/input
  printf "#!/bin/sh\necho \"xset \$*\" >> $calls\n" > /usr/local/bin/xset
  printf "#!/bin/sh\necho \"systemctl \$*\" >> $calls\n" > /usr/local/bin/systemctl
  chmod +x /usr/local/bin/xset /usr/local/bin/systemctl
  mv /usr/games/mgba /usr/games/mgba.real
  printf "#!/bin/sh\necho \"mgba \$*\" >> $calls\n" > /usr/games/mgba
  chmod +x /usr/games/mgba
  touch /tmp/stubs/pinpong/__init__.py
  printf "%s\n" "import os" "class Board:" "    def __init__(self, name): pass" \
    "    def begin(self): pass" "class Pin:" "    P28 = 28" "    IN = 0" \
    "    def __init__(self, pin, mode): pass" \
    "    def read_digital(self): return 0 if os.environ.get(\"FAKE_B\") == \"held\" else 1" \
    > /tmp/stubs/pinpong/board.py
  boot() {  # boot <log>: runs start-gb.sh as gameboy.service would, with a timeout
    : > "$calls"
    local rc=0
    PYTHONPATH=/tmp/stubs timeout 30 /opt/unihiker-gb/start-gb.sh > "$1" 2>&1 || rc=$?
    # Stop the background hotkeys.py (no pkill in the base image).
    for d in /proc/[0-9]*; do
      if grep -q hotkeys.py "$d/cmdline" 2>/dev/null; then kill "${d#/proc/}" 2>/dev/null || true; fi
    done
    return "$rc"
  }

  printf "ROM_FILE=missing.gb\n" > /etc/unihiker-gb/game.conf
  rc=0; boot /tmp/boot-missing.log || rc=$?
  check "missing ROM: exits 2 (no restart)" test "$rc" -eq 2
  check "missing ROM: says which file" grep -q "ROM not found: /root/roms/missing.gb" /tmp/boot-missing.log
  check "missing ROM: menu left running" bash -c "! grep -q PyboardUI $calls"

  /opt/unihiker-gb/set-rom.sh second.gbc >/dev/null

  touch /dev/input/js0
  rc=0; boot /tmp/boot-normal.log || rc=$?
  check "normal boot: exits 0" test "$rc" -eq 0
  check "normal boot: screen blanking off" grep -q "xset s off" "$calls"
  check "normal boot: rotation left in place" test -f /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  check "normal boot: desktop not restarted" bash -c "! grep -q lightdm $calls"
  check "normal boot: menu stopped" grep -q "systemctl --user stop PyboardUI.service" "$calls"
  check "normal boot: menu not restarted" bash -c "! grep -q \"systemctl --user start\" $calls"
  check "normal boot: skip check ran" grep -q "button B not held" /tmp/boot-normal.log
  check "normal boot: mGBA started with the ROM, saves and states in /root/saves" grep -qx \
    "mgba -f -C savegamePath=/root/saves -C savestatePath=/root/saves /root/roms/second.gbc" "$calls"
  check "normal boot: start logged for boot timing" grep -q "starting mGBA: second.gbc" /tmp/boot-normal.log

  rc=0; FAKE_B=held boot /tmp/boot-skip.log || rc=$?
  check "skip button, rotated: exits 0 (no restart)" test "$rc" -eq 0
  check "skip button, rotated: rotation removed for this boot" test ! -e /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf
  check "skip button, rotated: desktop restarted in portrait" grep -qx "systemctl restart --no-block lightdm.service" "$calls"
  check "skip button, rotated: menu left to the new desktop login" bash -c "! grep -q \"systemctl --user start\" $calls"
  check "skip button, rotated: mGBA not started" bash -c "! grep -q ^mgba $calls"
  check "the next boot rotates again (unihiker-gb-display.service)" bash -c \
    "[ \"\$(/opt/unihiker-gb/set-rotation.sh --from-config 2>/dev/null)\" = changed ] && grep -q CW /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf"

  /opt/unihiker-gb/set-rotation.sh normal >/dev/null 2>&1
  rc=0; FAKE_B=held boot /tmp/boot-skip2.log || rc=$?
  check "skip button, portrait: exits 0 (no restart)" test "$rc" -eq 0
  check "skip button, portrait: menu started again" grep -q "systemctl --user start PyboardUI.service" "$calls"
  check "skip button, portrait: desktop not restarted" bash -c "! grep -q lightdm $calls"
  check "skip button, portrait: mGBA not started" bash -c "! grep -q ^mgba $calls"

  rm -f /dev/input/js0
  mv /usr/games/mgba.real /usr/games/mgba

  echo "==> controller-event.sh"
  check "controller-event.sh handles remove with nothing running" /opt/unihiker-gb/controller-event.sh remove
  check "controller-event.sh handles add with nothing running" /opt/unihiker-gb/controller-event.sh add
  # A process named mgba stands in for the emulator. Under CPU emulation (arm64 on an x86
  # CI runner, via QEMU) every process runs inside the emulator, so pidof cannot find it by
  # name and these checks cannot run; they do run on an arm64 Mac and passed on the board.
  mkdir -p /tmp/fake && cp /bin/sleep /tmp/fake/mgba
  /tmp/fake/mgba 120 & fake=$!
  for _ in $(seq 10); do pidof mgba >/dev/null && break; sleep 1; done
  if pidof mgba >/dev/null; then
    # state: the process state letter (S running/sleeping, T stopped). The kernel applies
    # SIGSTOP/SIGCONT asynchronously, so state_is waits briefly for the expected one.
    state() { sed -n "s/^State:[[:space:]]*\([A-Z]\).*/\1/p" "/proc/$fake/status"; }
    state_is() { for _ in $(seq 10); do [ "$(state)" = "$1" ] && return 0; sleep 0.5; done; return 1; }
    /opt/unihiker-gb/controller-event.sh remove
    check "last controller removed: mGBA frozen" state_is T
    /opt/unihiker-gb/controller-event.sh add
    check "controller added: mGBA running again" state_is S
    touch /dev/input/js1
    /opt/unihiker-gb/controller-event.sh remove
    check "one of two controllers removed: mGBA keeps running" state_is S
    rm -f /dev/input/js1
  else
    echo "    skipped: pause/resume checks (pidof cannot see processes by name under CPU emulation)"
  fi
  kill "$fake" 2>/dev/null || true

  if [ "$fails" -eq 0 ]; then echo "==> All checks passed"; else echo "==> $fails check(s) FAILED"; exit 1; fi
'
