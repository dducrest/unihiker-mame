#!/bin/bash
# Sets the ROM the board boots into, then restarts the emulator. Runs on the board, as root.
#
#   set-rom.sh <filename>
#
# <filename> must already be in /root/roms/ (copy it with ./deploy.sh --rom <file>).
set -euo pipefail

ROMS=/root/roms
CONF=/etc/unihiker-gb/game.conf
HERE=$(cd "$(dirname "$0")" && pwd)
# Installed layout: /opt/unihiker-gb/lib/rom-rules.sh; repo layout: scripts/lib/rom-rules.sh
# shellcheck source=lib/rom-rules.sh
. "$HERE/lib/rom-rules.sh"

if [ $# -ne 1 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
  sed -n '2,6s/^# \{0,1\}//p' "$0"
  exit 2
fi
name=$1

problems=$(rom_name_errors "$name")
if [ -n "$problems" ]; then
  printf "error: can't use '%s':\n" "$name" >&2
  printf '  %s\n' "$problems" >&2
  printf '  suggested name: %s (rename the file, then copy it again)\n' "$(rom_suggest_name "$name")" >&2
  exit 1
fi
[ -f "$ROMS/$name" ] || { echo "error: not found: $ROMS/$name" >&2; exit 1; }

[ -f "$CONF" ] && cp -p "$CONF" "$CONF.bak"
set_conf_var "$CONF" ROM_FILE "$name"
echo "Boot ROM set to $name"

if [ -d /run/systemd/system ]; then
  systemctl restart gameboy.service
  echo "Restarted gameboy.service"
fi
