#!/bin/bash
# Tests scripts/pair-bluetooth.sh without Bluetooth hardware: each case runs in a fresh
# Debian buster container with tests/fakes/bluetoothctl standing in for BlueZ 5.50.
# The fake knows three devices (a gamepad, a phone and an unnamed device).
#
#   tests/test-pair-bluetooth.sh
#
# Needs Docker. Runs on macOS (bash 3.2) and in CI.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
IMAGE=debian:buster
GAMEPAD=AA:BB:CC:DD:EE:01
fails=0

# run_case <stdin> <shell commands>: prints the combined output.
run_case() {
  printf '%b' "$1" | docker run --rm -i -v "$REPO:/src:ro" \
    -e PATH=/src/tests/fakes:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    "$IMAGE" bash -c "$2" 2>&1 || true
}
expect() {  # expect "description" "output" "text that must appear"
  if printf '%s' "$2" | grep -qF -- "$3"; then
    echo "    ok:     $1"
  else
    echo "    FAILED: $1 (expected: $3)"
    fails=$((fails + 1))
  fi
}

echo "==> Scan and accept the default choice"
out=$(run_case '\n\n' '/src/scripts/pair-bluetooth.sh --scan-seconds 1 --no-restart; echo "exit=$?"; cat /tmp/bt/calls')
expect "gamepad listed first" "$out" "1) $GAMEPAD  Wireless Gamepad [controller]"
expect "pairing agent registered" "$out" "session: agent NoInputNoOutput"
expect "gamepad paired" "$out" "session: pair $GAMEPAD"
expect "gamepad trusted" "$out" "cmd: trust $GAMEPAD"
expect "gamepad connected" "$out" "cmd: connect $GAMEPAD"
expect "joystick device found" "$out" "game controller ready: /dev/input/js0"
expect "exits 0" "$out" "exit=0"

echo "==> --mac with a device that's already paired"
out=$(run_case '' 'mkdir -p /tmp/bt && touch /tmp/bt/paired.AA:BB:CC:DD:EE:02
  /src/scripts/pair-bluetooth.sh --mac aa:bb:cc:dd:ee:02 --no-restart; echo "exit=$?"; cat /tmp/bt/calls')
expect "pairing skipped" "$out" "already paired"
expect "exits 0" "$out" "exit=0"
if printf '%s' "$out" | grep -q "session: scan on"; then
  echo "    FAILED: --mac still scanned"; fails=$((fails + 1))
else
  echo "    ok:     --mac skips the scan"
fi

echo "==> Pairing fails"
out=$(run_case '\n1\n' 'FAKE_PAIR=fail PAIR_TIMEOUT=3 /src/scripts/pair-bluetooth.sh --scan-seconds 1 --no-restart; echo "exit=$?"')
expect "shows BlueZ's error" "$out" "AuthenticationFailed"
expect "says what to do" "$out" "Put the controller in pairing mode again"
expect "exits 1" "$out" "exit=1"

echo "==> Bad input"
out=$(run_case '\n9\n' '/src/scripts/pair-bluetooth.sh --scan-seconds 1 --no-restart; echo "exit=$?"')
expect "number not in the list refused" "$out" "not a number from the list: 9"
out=$(run_case '' '/src/scripts/pair-bluetooth.sh --mac nope; echo "exit=$?"')
expect "bad address refused" "$out" "not a Bluetooth address: NOPE"

if [ "$fails" -eq 0 ]; then echo "==> All checks passed"; else echo "==> $fails check(s) FAILED"; exit 1; fi
