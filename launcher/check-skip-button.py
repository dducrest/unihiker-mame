#!/usr/bin/env python3
"""PLACEHOLDER for the boot-time skip button check (manual step 5, item 16).

Exit status 0 means "a board button is held: skip the emulator", 1 means "not held".
The real version reads button B through DFRobot's pinpong library, once the pins are
confirmed on a real board. Until then it always reports "not held".
Must stay compatible with Python 3.7 (Debian buster).
"""
import sys

sys.exit(1)
