#!/bin/bash
# Boot flow for the Game Boy emulator (plans/initial-planning.md, manual step 5).
# Started by gameboy.service once the desktop is up:
#
#   1. check game.conf and the ROM          5. skip check: board button B held -> menu, exit
#   2. wait for X, keep the screen on       6. wait for a controller
#   3. splash screen (status-screen.py)     7. save-state shortcuts (hotkeys.py)
#   4. stop the built-in menu               8. mGBA, fullscreen, sound off
#
# Exit status 2 means a setting is wrong (missing ROM, bad game.conf). gameboy.service
# doesn't restart on it, and the built-in menu is left running so the board stays usable.
# Output goes to the journal: ./fetch-logs.sh on the Mac shows it.
set -euo pipefail

export DISPLAY=:0
export HOME=/root
export XAUTHORITY=/var/run/lightdm/root/:0   # X's access file (lightdm)
export XDG_RUNTIME_DIR=/run/user/0           # lets systemctl --user reach root's user manager
APP=/opt/unihiker-gb
MENU_UNIT=PyboardUI.service                  # the built-in UNIHIKER menu (a user service)
ROMS_DIR=/root/roms
SAVES_DIR=/root/saves
CONF=/etc/unihiker-gb/game.conf
MGBA=/usr/games/mgba

config_error() { echo "error: $*" >&2; exit 2; }

# 1. Settings. Checked before anything else, so a mistake leaves the menu running.
[ -f "$CONF" ] || config_error "missing $CONF (run ./deploy.sh again)"
# shellcheck source=../config/game.conf
. "$CONF"
if [ -f /etc/unihiker-gb/board.conf ]; then
  # shellcheck disable=SC1091 # optional, board-specific
  . /etc/unihiker-gb/board.conf
fi
case "${ROM_FILE:-}" in
  "" | */*) config_error "ROM_FILE in $CONF must be a filename in $ROMS_DIR: '${ROM_FILE:-}'" ;;
esac
ROM_PATH="$ROMS_DIR/$ROM_FILE"
[ -f "$ROM_PATH" ] ||
  config_error "ROM not found: $ROM_PATH (copy it with ./deploy.sh --rom, or pick another with set-rom.sh)"
[ -x "$MGBA" ] || config_error "mGBA isn't installed at $MGBA (run ./deploy.sh again)"
mkdir -p "$SAVES_DIR"

# 2. Wait for X, then keep the screen on during play (item 11).
echo "waiting for the display"
until xset q >/dev/null 2>&1; do sleep 1; done
xset s off
# The UNIHIKER starts X with -dpms, so the power-saving extension usually isn't there and
# xset complains; only turn it off where it exists.
if xset q | grep -q DPMS; then xset -dpms; fi

# 3. Splash, then the "connect a controller" prompt if none appears (items 12, 17).
python3 "$APP/status-screen.py" &
SCREEN=$!
close_screen() { kill "$SCREEN" 2>/dev/null || true; }

# 4. Stop the built-in menu for this boot (step 8). It's started by root's desktop login, so
# wait up to 20 s for root's user manager. An explicit stop doesn't trigger Restart=always.
for _ in $(seq 20); do
  [ -S "$XDG_RUNTIME_DIR/systemd/private" ] && break
  sleep 1
done
systemctl --user stop "$MENU_UNIT" || echo "warning: couldn't stop $MENU_UNIT"

# 5. Board button B held: skip the emulator for this boot (item 16). This runs after the
# menu is stopped, so the two don't share the co-processor connection.
if python3 "$APP/check-skip-button.py"; then
  echo "skip button held: starting the built-in menu for this boot"
  close_screen
  systemctl --user start "$MENU_UNIT"
  exit 0
fi

# 6. Wait for a controller. status-screen.py shows the prompt meanwhile.
if ! compgen -G '/dev/input/js*' >/dev/null; then
  echo "waiting for a controller"
  until compgen -G '/dev/input/js*' >/dev/null; do sleep 1; done
fi
echo "controller connected: $(compgen -G '/dev/input/js*' | tr '\n' ' ')"

# 7. Save-state shortcuts: L+R+Select saves, L+R+Start loads. Runs alongside mGBA and is
# stopped with it, because systemd stops every process in the service.
python3 "$APP/hotkeys.py" &

# 8. mGBA. No SDL_GAMECONTROLLERCONFIG: mGBA 0.7.0 reads raw joystick buttons, mapped in
# /root/.config/mgba/config.ini (item 14).
export SDL_AUDIODRIVER=dummy   # sound off (item 15)
echo "starting mGBA: $ROM_FILE"   # its journal timestamp is used to measure boot time (item 17)
close_screen
exec "$MGBA" -f -C savegamePath="$SAVES_DIR" -C savestatePath="$SAVES_DIR" "$ROM_PATH"
