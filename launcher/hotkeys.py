#!/usr/bin/env python3
"""Controller shortcuts for mGBA's save states (started by start-gb.sh next to mGBA).

    L + R + Select   save the game state (slot 1)
    L + R + Start    load the game state from slot 1, i.e. the most recent save

mGBA 0.7.0's SDL build has no controller hotkeys; its save-state controls are keyboard
keys only (Shift+F1 saves slot 1, F1 loads it). This script reads the controller from
/dev/input/js* alongside mGBA and sends those keys to mGBA's window with xdotool.

The button numbers come from mGBA's own config (keyL, keyR, keySelect, keyStart in
[gba.input.SDLB]), so the mapping lives in one place. Needs DISPLAY and XAUTHORITY set.

    hotkeys.py [--config FILE] [--dry-run]

--dry-run prints the shortcuts instead of sending keys (for testing with jstest numbers).
Must stay compatible with Python 3.7 (Debian buster).
"""
import argparse
import configparser
import glob
import os
import struct
import subprocess
import sys
import time

JS_EVENT = struct.Struct("IhBB")  # time (ms), value, type, number
JS_EVENT_BUTTON = 0x01
JS_EVENT_INIT = 0x80

SAVE_KEY = "shift+F1"
LOAD_KEY = "F1"
SECTION = "gba.input.SDLB"
NEEDED = ("keyL", "keyR", "keySelect", "keyStart")


def log(msg):
    print("hotkeys: " + msg, flush=True)


def read_buttons(path):
    """Returns {name: button number} for NEEDED from mGBA's config, or exits."""
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str  # keep key case (keyL, not keyl)
    if not cp.read(path):
        sys.exit("hotkeys: can't read " + path)
    if not cp.has_section(SECTION):
        sys.exit("hotkeys: no [%s] section in %s" % (SECTION, path))
    buttons = {}
    for name in NEEDED:
        value = cp.get(SECTION, name, fallback="").strip()
        try:
            buttons[name] = int(value)
        except ValueError:
            sys.exit("hotkeys: %s is missing or not a number in [%s] of %s" % (name, SECTION, path))
    return buttons


def send(key, dry_run):
    if dry_run:
        log("would send " + key)
        return
    # --clearmodifiers stops a held modifier from changing the key mGBA sees.
    rc = subprocess.call(["xdotool", "key", "--clearmodifiers", key])
    if rc != 0:
        log("xdotool failed (exit %d) sending %s" % (rc, key))


def watch(device, combos, dry_run):
    """Reads one joystick until it disconnects."""
    pressed = set()
    with open(device, "rb") as js:
        log("watching " + device)
        while True:
            data = js.read(JS_EVENT.size)
            if len(data) < JS_EVENT.size:
                return
            _, value, kind, number = JS_EVENT.unpack(data)
            if not kind & JS_EVENT_BUTTON:
                continue
            if not value:
                pressed.discard(number)
                continue
            pressed.add(number)
            if kind & JS_EVENT_INIT:
                continue  # state report on open, not a real press
            # Fire only on the press that completes a combo, so holding it fires once.
            for combo, key, label in combos:
                if number in combo and combo <= pressed:
                    log(label)
                    send(key, dry_run)


def main():
    default_config = os.path.join(os.environ.get("HOME", "/root"), ".config/mgba/config.ini")
    ap = argparse.ArgumentParser(description="Controller shortcuts for mGBA save states.")
    ap.add_argument("--config", default=default_config, help="mGBA config.ini")
    ap.add_argument("--dry-run", action="store_true", help="print instead of sending keys")
    args = ap.parse_args()

    b = read_buttons(args.config)
    combos = [
        (frozenset((b["keyL"], b["keyR"], b["keySelect"])), SAVE_KEY, "L+R+Select: saving state"),
        (frozenset((b["keyL"], b["keyR"], b["keyStart"])), LOAD_KEY, "L+R+Start: loading state"),
    ]
    log("L=%(keyL)d R=%(keyR)d Select=%(keySelect)d Start=%(keyStart)d" % b)

    # Keep running across controller disconnects (Bluetooth sleeps, cable pulled).
    while True:
        devices = sorted(glob.glob("/dev/input/js*"))
        if not devices:
            time.sleep(1)
            continue
        try:
            watch(devices[0], combos, args.dry_run)
        except OSError as e:
            log("lost %s: %s" % (devices[0], e))
        time.sleep(1)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
