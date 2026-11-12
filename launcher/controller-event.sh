#!/bin/bash
# Pauses mGBA when the last controller disconnects and resumes it when one reconnects
# (manual step 6, item 13). Called by the udev rule with "add" or "remove".
#
# Freezing the process (SIGSTOP/SIGCONT) pauses the game whatever mGBA is doing, and with
# sound off there's no audio glitch. udev runs this with a minimal environment and expects
# it to return quickly, so it only sends a signal and logs.
PATH=/usr/sbin:/usr/bin:/sbin:/bin
action=${1:-unknown}

log() { logger -t unihiker-gb "controller $action: $*"; }

# signal_mgba STOP|CONT: fails if mGBA isn't running. pidof is part of every Debian install
# (sysvinit-utils is essential); pkill isn't.
signal_mgba() {
  local pids
  pids=$(pidof mgba) || return 1
  # shellcheck disable=SC2086 # one or more PIDs
  kill -"$1" $pids
}

case $action in
  remove)
    if compgen -G '/dev/input/js*' >/dev/null; then
      log "another controller is still connected; game keeps running"
    elif signal_mgba STOP; then
      log "no controllers left; game paused"
    else
      log "no controllers left; mGBA isn't running"
    fi
    ;;
  add)
    if signal_mgba CONT; then
      log "game resumed"
    else
      log "mGBA isn't running"
    fi
    ;;
  *)
    log "unknown event, ignored"
    ;;
esac
exit 0
