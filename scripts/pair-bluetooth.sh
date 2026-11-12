#!/bin/bash
# Pairs a Bluetooth controller with the board: scans, lets you pick the controller, then
# pairs, trusts and connects it, so it reconnects by itself after every reboot.
# Run on the board (installed to /opt/unihiker-gb/), usually through ./deploy.sh --pair:
#
#   pair-bluetooth.sh [--scan-seconds N] [--mac XX:XX:XX:XX:XX:XX] [--no-restart]
#
#   --scan-seconds N   how long to look for controllers (default 15)
#   --mac MAC          skip the scan and pair this address
#   --no-restart       don't restart the game afterwards
#
# Needs a person: put the controller in pairing mode when asked. BlueZ 5.50 (Debian buster).
set -euo pipefail

SCAN_SECONDS=15
MAC=""
RESTART=yes
PAIR_TIMEOUT=${PAIR_TIMEOUT:-30}      # seconds to wait for pairing to finish
CONNECT_TIMEOUT=${CONNECT_TIMEOUT:-15}   # seconds to wait for the controller to connect and show up as /dev/input/js*

usage() {
  sed -n '2,12s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case $1 in
    --scan-seconds) [ $# -ge 2 ] && [[ $2 =~ ^[0-9]+$ ]] || usage 2; SCAN_SECONDS=$2; shift ;;
    --mac) [ $# -ge 2 ] || usage 2; MAC=${2^^}; shift ;;
    --no-restart) RESTART=no ;;
    -h | --help) usage 0 ;;
    *) printf 'error: unknown option: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done

say() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

valid_mac() { [[ $1 =~ ^([0-9A-F]{2}:){5}[0-9A-F]{2}$ ]]; }
# info_field MAC FIELD: prints e.g. "yes" for "Paired: yes" in `bluetoothctl info`.
info_field() { bluetoothctl info "$1" 2>/dev/null | sed -n "s/^[[:space:]]*$2: //p" | head -n 1; }
# wait_for SECONDS COMMAND...: retries COMMAND once a second until it succeeds.
wait_for() {
  local seconds=$1; shift
  for _ in $(seq "$seconds"); do
    if "$@"; then return 0; fi
    sleep 1
  done
  return 1
}
is_paired() { [ "$(info_field "$1" Paired)" = yes ]; }
is_connected() { [ "$(info_field "$1" Connected)" = yes ]; }
have_joystick() { compgen -G '/dev/input/js*' >/dev/null; }

[ "$(id -u)" -eq 0 ] || die "run as root"
command -v bluetoothctl >/dev/null || die "bluetoothctl isn't installed (run ./deploy.sh again)"
if [ -n "$MAC" ] && ! valid_mac "$MAC"; then die "not a Bluetooth address: $MAC"; fi

# 1. Bluetooth on -----------------------------------------------------------------------
say "Turning Bluetooth on"
if command -v systemctl >/dev/null && ! systemctl is-active --quiet bluetooth; then
  systemctl start bluetooth
fi
wait_for 10 bluetoothctl show >/dev/null 2>&1 ||
  die "no Bluetooth adapter found (bluetoothctl show). Check: bluetoothctl list"
bluetoothctl power on >/dev/null
[ "$(bluetoothctl show | sed -n 's/^[[:space:]]*Powered: //p')" = yes ] ||
  die "couldn't power the Bluetooth adapter on"
# Link-level security, so the controller can reconnect after a reboot (see the script).
if [ -x /opt/unihiker-gb/bt-link-security.sh ]; then
  BT_WAIT_SECONDS=5 /opt/unihiker-gb/bt-link-security.sh | sed 's/^/    /'
fi

# One bluetoothctl session stays open in the background for the whole run: it holds the
# pairing agent (NoInputNoOutput: controllers have no keyboard or screen to confirm a code)
# and the scan. Everything else uses short one-off bluetoothctl commands.
SESSION_LOG=$(mktemp)
coproc BT { bluetoothctl >"$SESSION_LOG" 2>&1; }
bt() { printf '%s\n' "$*" >&"${BT[1]}"; }
cleanup() {
  if [ -n "${BT_PID:-}" ]; then
    bt "scan off" 2>/dev/null || true
    bt "quit" 2>/dev/null || true
    wait "$BT_PID" 2>/dev/null || true
  fi
  rm -f "$SESSION_LOG"
}
trap cleanup EXIT
bt "agent NoInputNoOutput"
bt "default-agent"

# 2. Find the controller ----------------------------------------------------------------
if [ -z "$MAC" ]; then
  echo
  echo "Put your controller in pairing mode now. For most controllers, hold the pairing or"
  echo "share button (with the home button on some) until the light flashes quickly."
  read -r -p "Press Enter when it's flashing... " _
  say "Looking for controllers (${SCAN_SECONDS} s)"
  bt "scan on"
  sleep "$SCAN_SECONDS"

  # Gamepads first (BlueZ's icon "input-gaming"), then other devices that have a name.
  macs=() labels=()
  while read -r _ mac name; do
    valid_mac "$mac" || continue
    info=$(bluetoothctl info "$mac" 2>/dev/null || true)
    icon=$(sed -n 's/^[[:space:]]*Icon: //p' <<<"$info" | head -n 1)
    paired=$(sed -n 's/^[[:space:]]*Paired: //p' <<<"$info" | head -n 1)
    rank=1; tag=""
    if [ "$icon" = input-gaming ]; then rank=0; tag=" [controller]"; fi
    # Unnamed devices show their address as the name; they're rarely controllers.
    if [ "$name" = "${mac//:/-}" ] || [ -z "$name" ]; then rank=2; fi
    [ "$paired" = yes ] && tag="$tag [already paired]"
    printf '%s\t%s\t%s\n' "$rank" "$mac" "$name$tag"
  done < <(bluetoothctl devices 2>/dev/null) | sort -s -t $'\t' -k1,1n > "$SESSION_LOG.list"
  while IFS=$'\t' read -r _ mac label; do
    macs+=("$mac"); labels+=("$label")
  done < "$SESSION_LOG.list"
  rm -f "$SESSION_LOG.list"

  if [ ${#macs[@]} -eq 0 ]; then
    die "no Bluetooth devices found. Check the controller is in pairing mode (light flashing quickly) and run this again."
  fi
  echo
  echo "Devices found:"
  for i in "${!macs[@]}"; do
    printf '  %2d) %s  %s\n' $((i + 1)) "${macs[$i]}" "${labels[$i]}"
  done
  echo
  read -r -p "Number of your controller [1]: " choice
  choice=${choice:-1}
  [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#macs[@]} ] ||
    die "not a number from the list: $choice"
  MAC=${macs[$((choice - 1))]}
  bt "scan off"
fi

# 3. Pair, trust, connect ---------------------------------------------------------------
name=$(info_field "$MAC" Name)
say "Pairing ${name:-$MAC} ($MAC)"
if is_paired "$MAC"; then
  note "already paired"
else
  bt "pair $MAC"
  if ! wait_for "$PAIR_TIMEOUT" is_paired "$MAC"; then
    echo "bluetoothctl said:" >&2
    grep -iE "fail|error|not available" "$SESSION_LOG" | tail -n 5 | sed 's/^/    /' >&2 || true
    die "pairing didn't finish. Put the controller in pairing mode again and rerun this."
  fi
  note "paired"
fi

# Trusted devices may reconnect by themselves, which is what makes the controller work
# after a reboot without this script.
bluetoothctl trust "$MAC" >/dev/null
[ "$(info_field "$MAC" Trusted)" = yes ] || die "couldn't mark $MAC as trusted"
note "trusted (it will reconnect by itself after a reboot)"

if ! is_connected "$MAC"; then
  bluetoothctl connect "$MAC" >/dev/null 2>&1 || true
fi
if wait_for "$CONNECT_TIMEOUT" is_connected "$MAC"; then
  note "connected"
else
  echo "warning: the controller is paired and trusted but didn't connect. Press a button on it;" >&2
  echo "         if it keeps dropping, redeploy with ./deploy.sh --bt-ertm-fix (needs a reboot)." >&2
fi
if wait_for "$CONNECT_TIMEOUT" have_joystick; then
  note "game controller ready: $(compgen -G '/dev/input/js*' | paste -sd ' ' -)"
else
  echo "warning: no /dev/input/js* device appeared, so the game won't see this controller yet." >&2
fi

# 4. Game -------------------------------------------------------------------------------
if [ "$RESTART" = yes ] && command -v systemctl >/dev/null &&
  systemctl is-enabled --quiet gameboy 2>/dev/null; then
  say "Restarting the game so it uses the controller"
  systemctl restart gameboy
fi
say "Done: ${name:-$MAC} is paired"
