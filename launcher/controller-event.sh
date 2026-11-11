#!/bin/bash
# PLACEHOLDER. Called by the udev rule with "add" or "remove" when a controller connects
# or disconnects. The real version (manual step 6) pauses and resumes mGBA.
logger -t unihiker-gb "controller ${1:-unknown} (placeholder handler, no action taken)"
exit 0
