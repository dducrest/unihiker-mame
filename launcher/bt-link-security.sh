#!/bin/bash
# Makes the Bluetooth adapter authenticate and encrypt each connection while setting it up
# (link-level security, `hciconfig hci0 auth encrypt`). Run at boot by
# unihiker-gb-bluetooth.service after bluetooth.service, and by pair-bluetooth.sh.
#
# Why: on this board (kernel 4.4, Realtek UART adapter) a paired Xbox Wireless Controller
# couldn't reconnect. It opens its controller channel a few milliseconds before the board
# has registered that the link is encrypted, the kernel refuses it ("security block"), and
# the controller gives up. With link-level security the link is already encrypted when the
# controller asks, so it connects straight away (confirmed with btmon on the board,
# 2026-11-12). The setting is lost on reboot, hence this script.
#
#   bt-link-security.sh [adapter]      (default hci0)
#
# Exits 0 if the board has no Bluetooth adapter, so it never blocks anything else.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
ADAPTER=${1:-hci0}
WAIT_SECONDS=${BT_WAIT_SECONDS:-30}   # for the adapter to appear and be switched on

log() { echo "bt-link-security: $*"; }

# bluetoothd switches the adapter on shortly after it starts; the setting needs it on.
up=no
for _ in $(seq "$WAIT_SECONDS"); do
  if hciconfig "$ADAPTER" 2>/dev/null | grep -q "UP RUNNING"; then up=yes; break; fi
  sleep 1
done
if [ "$up" = no ]; then
  if [ -e "/sys/class/bluetooth/$ADAPTER" ]; then
    log "warning: $ADAPTER isn't switched on; link security not set"
  else
    log "no Bluetooth adapter $ADAPTER; nothing to do"
  fi
  exit 0
fi

if ! hciconfig "$ADAPTER" auth encrypt; then
  log "warning: couldn't set link security on $ADAPTER"
  exit 0
fi
flags=$(hciconfig "$ADAPTER" | grep -o "UP RUNNING.*")
case $flags in
  *AUTH*ENCRYPT* | *ENCRYPT*AUTH*) log "$ADAPTER: authentication and encryption on ($flags)" ;;
  *) log "warning: $ADAPTER flags after setting: $flags" ;;
esac
exit 0
