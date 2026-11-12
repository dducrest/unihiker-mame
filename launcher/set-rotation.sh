#!/bin/bash
# Sets the screen orientation in the X server's configuration (plans/landscape-display.md,
# option B: the board's fbdev display driver can't rotate at runtime with xrandr).
#
#   set-rotation.sh <left|right|inverted|normal>   write (or, for normal, remove) the X file
#   set-rotation.sh --from-config                  the same, for DISPLAY_ROTATION in board.conf
#
# The change takes effect the next time X starts (boot, or systemctl restart lightdm).
# Prints "changed" if it changed the file, nothing otherwise.
#
# Callers:
#   unihiker-gb-display.service   --from-config at every boot, before the desktop starts
#   install.sh                    after --rotate (then restarts the desktop if it changed)
#   start-gb.sh                   normal, when button B is held, then restarts the desktop
#                                 so the UNIHIKER menu appears in portrait for this boot
#
# Exit status: 0, or 2 for a value that isn't one of the four above. A bad DISPLAY_ROTATION
# in board.conf with --from-config only logs a warning and leaves the screen in portrait.
set -euo pipefail

BOARD_CONF=/etc/unihiker-gb/board.conf
XORG_FILE=/etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf

log() { echo "set-rotation: $*" >&2; }

want=${1:-}
if [ "$want" = --from-config ]; then
  want=normal
  if [ -f "$BOARD_CONF" ]; then
    # shellcheck disable=SC1090
    want=$(. "$BOARD_CONF" && printf '%s' "${DISPLAY_ROTATION:-normal}")
  fi
  case $want in
    left | right | inverted | normal) ;;
    *) log "warning: DISPLAY_ROTATION in $BOARD_CONF must be left, right, inverted or normal, not '$want'; using normal"
       want=normal ;;
  esac
fi

# The fbdev driver's names for the directions (xrandr's left = counter-clockwise).
case $want in
  left) rotate=CCW ;;
  right) rotate=CW ;;
  inverted) rotate=UD ;;
  normal) rotate="" ;;
  *) log "error: expected left, right, inverted or normal, got '$want'"; exit 2 ;;
esac

if [ -z "$rotate" ]; then
  if [ -e "$XORG_FILE" ]; then
    rm -f "$XORG_FILE"
    log "removed $XORG_FILE: portrait from the next X start"
    echo changed
  fi
  exit 0
fi

# The Device section repeats the board's own (DFRobot's 20-modesetting.conf, "Rockchip
# Graphics") with Rotate added. Files are read in name order and X uses the first Device
# section, so this one (10-) wins and DFRobot's file stays untouched.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
cat >"$tmp" <<EOF
# Written by /opt/unihiker-gb/set-rotation.sh (unihiker-gb): screen turned $want.
# Change it with ./deploy.sh --rotate. To undo by hand: delete this file and run
# "systemctl restart lightdm".
Section "Device"
    Identifier  "unihiker-gb rotated"
    Driver      "fbdev"
    Option      "fbdev"   "/dev/fb0"
    Option      "DRI"     "2"
    Option      "Rotate"  "$rotate"
EndSection
EOF
if [ -f "$XORG_FILE" ] && cmp -s "$tmp" "$XORG_FILE"; then
  exit 0
fi
mkdir -p "$(dirname "$XORG_FILE")"
install -m 0644 "$tmp" "$XORG_FILE"
log "wrote $XORG_FILE: turned $want from the next X start"
echo changed
