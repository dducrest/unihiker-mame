#!/bin/bash
# Shows recent emulator logs from the UNIHIKER: controller connect/disconnect events,
# then the gameboy service log.
#
#   ./fetch-logs.sh [options]
#
#   --host <addr>   Board address (default: 10.1.2.3)
#   --lines <n>     How many recent lines of each log to show (default: 200)
#   --boot          Only show lines from the current boot
#   --follow        After the controller events, keep watching the service log until Ctrl+C
#   -h, --help      Show this help
#
# Runs on macOS, so it must stay bash 3.2 compatible.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/common.sh
. "$REPO/scripts/lib/common.sh"

usage() {
  sed -n '2,13s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

LINES=200
BOOT=""
FOLLOW=no

while [ $# -gt 0 ]; do
  case $1 in
    --host) [ $# -ge 2 ] || die "--host needs a value"; HOST=$2; shift ;;
    --lines) [ $# -ge 2 ] || die "--lines needs a value"; LINES=$2; shift ;;
    --boot) BOOT=-b ;;
    --follow) FOLLOW=yes ;;
    -h | --help) usage 0 ;;
    *) printf 'error: unknown option: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done

case $LINES in '' | *[!0-9]*) die "--lines must be a number" ;; esac

init_ssh_opts
ensure_ssh_access check

step "Controller events (last $LINES lines)"
board_ssh "journalctl -t unihiker-gb --no-pager -n $LINES $BOOT"

if [ "$FOLLOW" = yes ]; then
  step "gameboy service log (following; press Ctrl+C to stop)"
  board_ssh_tty "journalctl -u gameboy --no-pager -n $LINES $BOOT -f"
else
  step "gameboy service log (last $LINES lines)"
  board_ssh "journalctl -u gameboy --no-pager -n $LINES $BOOT"
fi
