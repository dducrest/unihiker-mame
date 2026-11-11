#!/bin/bash
# Deploys the Game Boy emulator setup from this Mac to a UNIHIKER M10 over USB.
#
#   ./deploy.sh [options]
#
#   --host <addr>              Board address (default: 10.1.2.3, the USB-network address)
#   --rom <file>               Local ROM to copy to /root/roms/ and set as the boot game
#   --roms-dir <dir>           Copy a whole folder of ROMs, e.g. ./roms (the boot game stays
#                              as it is unless --rom is given)
#   --pair                     After installing, pair a Bluetooth controller interactively
#   --bt-ertm-fix              Install the Bluetooth ERTM workaround (only for controllers
#                              that need it)
#   --no-start                 Install everything but don't start/restart the emulator service
#   --set-password             Change the board's root password (interactive)
#   --forget-host              Forget the board's SSH key first (after a re-flash or when
#                              switching boards)
#   --pull-saves               Copy the board's saves into saves/<date-time>/ and stop;
#                              nothing is installed
#   -h, --help                 Show this help
#
# Runs on macOS, so it must stay bash 3.2 compatible.
set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=scripts/lib/common.sh
. "$REPO/scripts/lib/common.sh"

STAGING=/tmp/unihiker-gb
STAGED_DIRS="assets config launcher systemd scripts packages"

usage() {
  sed -n '2,21s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

ROM=""
ROMS_DIR=""
PAIR=no
SET_PASSWORD=no
FORGET_HOST=no
PULL_SAVES=no
INSTALL_ARGS=()

need_value() { [ $# -ge 2 ] && [ -n "$2" ] || die "$1 needs a value (see --help)"; }

while [ $# -gt 0 ]; do
  case $1 in
    --host) need_value "$@"; HOST=$2; shift ;;
    --rom) need_value "$@"; ROM=$2; shift ;;
    --roms-dir) need_value "$@"; ROMS_DIR=$2; shift ;;
    --pair) PAIR=yes ;;
    --bt-ertm-fix) INSTALL_ARGS+=(--bt-ertm-fix) ;;
    --no-start) INSTALL_ARGS+=(--no-start) ;;
    --set-password) SET_PASSWORD=yes ;;
    --forget-host) FORGET_HOST=yes ;;
    --pull-saves) PULL_SAVES=yes ;;
    -h | --help) usage 0 ;;
    *) printf 'error: unknown option: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done

if [ -n "$ROM" ] && [ ! -f "$ROM" ]; then die "ROM not found: $ROM"; fi
if [ -n "$ROMS_DIR" ] && [ ! -d "$ROMS_DIR" ]; then die "not a folder: $ROMS_DIR"; fi

init_ssh_opts

# 1. ROM check -----------------------------------------------------------------
if [ -n "$ROM$ROMS_DIR" ]; then
  step "Checking ROM filenames"
  check_args=()
  [ -n "$ROM" ] && check_args+=("$ROM")
  [ -n "$ROMS_DIR" ] && check_args+=("$ROMS_DIR")
  "$REPO/scripts/check-roms.sh" "${check_args[@]}" ||
    die "fix the ROM filenames above (rename the files), then run deploy.sh again"
fi

# 2. SSH access ----------------------------------------------------------------
step "Connecting to the board at $HOST"
[ "$FORGET_HOST" = yes ] && forget_host
ensure_ssh_access install
note "connected"

# 3. Root password -------------------------------------------------------------
if [ "$SET_PASSWORD" = yes ]; then
  step "Changing the board's root password"
  board_ssh_tty passwd
fi

# 4. Clock ---------------------------------------------------------------------
step "Setting the board's clock from this Mac"
board_ssh "date -u -s @$(date -u +%s) >/dev/null"

# 5. Saves ---------------------------------------------------------------------
if [ "$PULL_SAVES" = yes ]; then
  dest="$REPO/saves/$(date +%Y-%m-%d-%H%M%S)"
  step "Copying saves from the board to ${dest#"$REPO"/}"
  if ! board_ssh 'test -d /root/saves'; then
    note "the board has no /root/saves folder yet; nothing to copy"
    exit 0
  fi
  mkdir -p "$dest"
  board_ssh 'tar -cf - -C /root/saves .' | tar -xf - -C "$dest"
  n=$(find "$dest" -type f | wc -l | tr -d ' ')
  note "copied $n file(s). Nothing was installed (--pull-saves only backs up saves)."
  exit 0
fi

# 6. Staging -------------------------------------------------------------------
step "Copying the setup files to the board"
[ -f "$REPO/packages/Packages" ] ||
  die "packages/ has no package index. Run scripts/fetch-packages.sh first (needs Docker)."
for d in $STAGED_DIRS; do
  [ -d "$REPO/$d" ] || die "missing folder in the repo: $d"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
{
  echo "commit=$(git -C "$REPO" describe --always --dirty 2>/dev/null || echo unknown)"
  echo "deployed=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} >"$tmp/VERSION"

# COPYFILE_DISABLE and --no-xattrs/--no-mac-metadata keep macOS metadata files out of the
# archive; --uname/--gname record root as the owner instead of the Mac's user name.
# shellcheck disable=SC2086 # STAGED_DIRS is a list of plain folder names
COPYFILE_DISABLE=1 tar --no-xattrs --no-mac-metadata \
  --uid 0 --gid 0 --uname root --gname root \
  -czf - -C "$REPO" $STAGED_DIRS -C "$tmp" VERSION |
  board_ssh "rm -rf $STAGING && mkdir -p $STAGING && tar -xzf - --no-same-owner -C $STAGING"

# 7. ROMs ----------------------------------------------------------------------
roms=()
if [ -n "$ROMS_DIR" ]; then
  for f in "$ROMS_DIR"/*; do
    [ -f "$f" ] && roms+=("$f")
  done
fi
if [ -n "$ROM" ]; then
  # Skip --rom if it's already in --roms-dir, so it isn't copied twice.
  in_dir=no
  for f in ${roms[@]+"${roms[@]}"}; do
    if [ "$f" -ef "$ROM" ]; then in_dir=yes; fi
  done
  [ "$in_dir" = yes ] || roms+=("$ROM")
fi
if [ ${#roms[@]} -gt 0 ]; then
  step "Copying ${#roms[@]} ROM file(s) to /root/roms/"
  board_ssh 'mkdir -p /root/roms'
  board_scp "${roms[@]}" /root/roms/
fi
[ -n "$ROM" ] && INSTALL_ARGS+=(--rom-file "$(basename "$ROM")")

# 8. Install -------------------------------------------------------------------
step "Running install.sh on the board"
remote_cmd=$(printf '%q ' bash "$STAGING/scripts/install.sh" --src "$STAGING" \
  ${INSTALL_ARGS[@]+"${INSTALL_ARGS[@]}"})
rc=0
board_ssh "$remote_cmd" || rc=$?

# 9. Pairing -------------------------------------------------------------------
if [ "$PAIR" = yes ]; then
  if [ "$rc" -eq 0 ]; then
    step "Pairing a Bluetooth controller"
    board_ssh_tty /opt/unihiker-gb/pair-bluetooth.sh || rc=$?
  else
    warn "skipping --pair because install.sh failed"
  fi
fi

# 10. Done ---------------------------------------------------------------------
if [ "$rc" -eq 0 ]; then
  step "Deploy finished"
else
  step "Deploy failed (exit code $rc). See the messages above, or run ./fetch-logs.sh."
fi
exit "$rc"
