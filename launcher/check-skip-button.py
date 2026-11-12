#!/usr/bin/env python3
"""Boot-time skip check (manual step 5, item 16): is board button B held?

Exit status 0 means "button B is held: skip the emulator", 1 means "not held".
Any problem (pinpong missing, no connection, timeout) also exits 1, so a fault with the
button can never stop the game from starting.

Reads pin P28 through DFRobot's preinstalled pinpong library. B reads 0 when pressed
(confirmed on the board). The pin is read directly because pinpong's button_b lags one
reading behind. The button only counts as held if every reading over SAMPLE_SECONDS is 0,
so one glitchy reading can't skip the emulator.
Must stay compatible with Python 3.7 (Debian buster).
"""
import contextlib
import io
import os
import signal
import sys
import time

SAMPLE_SECONDS = 0.5
SAMPLE_INTERVAL = 0.05
TIMEOUT_SECONDS = 10  # connecting normally takes about 1 s


def log(msg):
    # sys.__stdout__: the real output, even while pinpong's banner is being hidden.
    print("check-skip-button: " + msg, file=sys.__stdout__, flush=True)


def done(code):
    # os._exit: pinpong leaves a serial reader thread running that would keep Python alive.
    sys.__stdout__.flush()
    os._exit(code)


def on_timeout(signum, frame):
    log("warning: timed out talking to the co-processor; not skipping")
    done(1)


def main():
    signal.signal(signal.SIGALRM, on_timeout)
    signal.alarm(TIMEOUT_SECONDS)
    try:
        # pinpong prints a banner while importing and connecting; keep it out of the journal.
        with contextlib.redirect_stdout(io.StringIO()):
            from pinpong.board import Board, Pin
            Board("UNIHIKER").begin()
            pin = Pin(Pin.P28, Pin.IN)
            readings = []
            end = time.monotonic() + SAMPLE_SECONDS
            while time.monotonic() < end:
                readings.append(pin.read_digital())
                time.sleep(SAMPLE_INTERVAL)
    except Exception as e:  # any failure: start the game as normal
        log("warning: couldn't read button B (%s: %s); not skipping" % (type(e).__name__, e))
        done(1)
    signal.alarm(0)

    held = bool(readings) and all(r == 0 for r in readings)
    log("button B %s (%d readings)" % ("held" if held else "not held", len(readings)))
    done(0 if held else 1)


if __name__ == "__main__":
    main()
