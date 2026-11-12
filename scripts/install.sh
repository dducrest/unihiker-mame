#!/bin/bash
# Sets up the Game Boy emulator on a UNIHIKER M10. Runs on the board, as root.
# deploy.sh copies the repo to /tmp/unihiker-gb on the board and runs this script.
#
#   install.sh [--src <dir>] [--rom-file <name>] [--rotate <direction>] [--bt-ertm-fix]
#              [--no-start]
#
#   --src <dir>                Repo files to install from (default: the repo this script is in)
#   --rom-file <name>          Set the boot ROM: a filename that is already in /root/roms/
#   --rotate <direction>       Screen orientation: left, right, inverted or normal
#                              (portrait). Without it, the board keeps its setting
#                              (DEFAULT_ROTATION on the first install). A change restarts
#                              the desktop (with --no-start: from the next boot)
#   --bt-ertm-fix              Install the Bluetooth ERTM workaround
#   --no-start                 Don't start/restart the emulator service
#
# The built-in UNIHIKER menu (PyboardUI.service) is not disabled here: the launcher stops it
# at each boot, so nothing on the board needs restoring later.
#
# Safe to re-run: each step checks first and only changes what's needed.
# Without systemd (the Docker test), the systemd and udev steps are reported as skipped.
set -euo pipefail

SRC=$(cd "$(dirname "$0")/.." && pwd)
ROM_FILE_ARG=""
ROTATE_ARG=""
ERTM_FIX=no
NO_START=no

# Keep in sync with PACKAGES in scripts/fetch-packages.sh.
PACKAGES="mgba-sdl bluez joystick python3-tk xdotool"

APP=/opt/unihiker-gb
ETC=/etc/unihiker-gb
ROMS=/root/roms
SAVES=/root/saves
MGBA_CONF=/root/.config/mgba/config.ini
APT_LIST=/etc/apt/sources.list.d/unihiker-gb.list
UNIT_FILE=/etc/systemd/system/gameboy.service
BT_UNIT_FILE=/etc/systemd/system/unihiker-gb-bluetooth.service
DISPLAY_UNIT_FILE=/etc/systemd/system/unihiker-gb-display.service
UDEV_RULE=/etc/udev/rules.d/99-unihiker-gb-controller.rules
MODPROBE_CONF=/etc/modprobe.d/unihiker-gb-bluetooth.conf
MIN_FREE_MB=300
# Debian installs mgba to /usr/games, which isn't on root's PATH.
MGBA=/usr/games/mgba
BOARD_CONF=$ETC/board.conf
# Screen orientation on a board that has no DISPLAY_ROTATION yet (plans/landscape-display.md).
DEFAULT_ROTATION=right

usage() {
  sed -n '2,21s/^# \{0,1\}//p' "$0"
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case $1 in
    --src) [ $# -ge 2 ] || usage 2; SRC=$2; shift ;;
    --rom-file) [ $# -ge 2 ] || usage 2; ROM_FILE_ARG=$2; shift ;;
    --rotate)
      [ $# -ge 2 ] || usage 2
      case $2 in
        left | right | inverted | normal) ROTATE_ARG=$2 ;;
        *) printf 'error: --rotate must be left, right, inverted or normal, not %s\n' "$2" >&2; exit 2 ;;
      esac
      shift
      ;;
    --bt-ertm-fix) ERTM_FIX=yes ;;
    --no-start) NO_START=yes ;;
    -h | --help) usage 0 ;;
    *) printf 'error: unknown option: %s\n\n' "$1" >&2; usage 2 ;;
  esac
  shift
done

# shellcheck source=lib/rom-rules.sh
. "$SRC/scripts/lib/rom-rules.sh"

# --- output helpers ------------------------------------------------------------
CHANGES=0
RESULTS=()   # "PASS|WARN|FAIL|SKIP<tab>message" lines for the summary
FAILED=no

step() { printf '==> %s\n' "$*"; }
changed() { printf '    changed: %s\n' "$*"; CHANGES=$((CHANGES + 1)); }
note() { printf '    %s\n' "$*"; }
warn() { printf '    warning: %s\n' "$*"; RESULTS+=("WARN	$*"); }
skip() { printf '    skipped: %s\n' "$*"; RESULTS+=("SKIP	$*"); }
pass() { RESULTS+=("PASS	$*"); }
fail() { printf '    FAILED: %s\n' "$*"; RESULTS+=("FAIL	$*"); FAILED=yes; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }
trap 'printf "error: install.sh stopped at line %s\n" "$LINENO" >&2' ERR

HAVE_SYSTEMD=no
[ -d /run/systemd/system ] && HAVE_SYSTEMD=yes

# install_file SRC DEST MODE: copy only if missing or different. Returns 0 if it changed.
install_file() {
  local src=$1 dest=$2 mode=$3
  [ -f "$src" ] || die "missing file in the repo: ${src#"$SRC"/}"
  if [ -f "$dest" ] && cmp -s "$src" "$dest"; then
    chmod "$mode" "$dest"
    return 1
  fi
  install -D -m "$mode" "$src" "$dest"
  changed "$dest"
  return 0
}

# conf_value FILE VAR: print VAR's value from a shell-style config file (empty if unset).
conf_value() {
  [ -f "$1" ] || return 0
  # shellcheck disable=SC1090
  (. "$1" && printf '%s' "${!2:-}")
}

# 1. Preflight ------------------------------------------------------------------
step "Preflight checks"
[ "$(id -u)" -eq 0 ] || die "run install.sh as root"
# shellcheck disable=SC1091
version_id=$(. /etc/os-release && echo "${VERSION_ID:-unknown}")
if [ "$version_id" != 10 ]; then
  warn "expected Debian 10 (buster), found VERSION_ID=$version_id"
fi
[ -f "$SRC/packages/Packages" ] || die "no package index in $SRC/packages (run scripts/fetch-packages.sh on the Mac)"
pkg_arch=$(sed -n 's/^arch=//p' "$SRC/packages/manifest.txt" 2>/dev/null || true)
board_arch=$(dpkg --print-architecture)
if [ "$pkg_arch" != "$board_arch" ]; then
  die "the packages are for '${pkg_arch:-unknown}' but this board is '$board_arch'.
       Re-run scripts/fetch-packages.sh with the matching --platform."
fi
free_mb=$(df -Pm / | awk 'NR == 2 { print $4 }')
if [ "$free_mb" -lt "$MIN_FREE_MB" ]; then
  die "only ${free_mb} MB free on /; at least ${MIN_FREE_MB} MB needed"
fi
note "Debian $version_id, $board_arch, ${free_mb} MB free, systemd: $HAVE_SYSTEMD"

# 2. Packages (offline) -----------------------------------------------------------
step "Installing packages from the local folder (no internet needed)"
if [ -d "$APP/packages" ] && diff -rq "$SRC/packages" "$APP/packages" >/dev/null 2>&1; then
  :
else
  rm -rf "$APP/packages.new"
  mkdir -p "$APP"
  cp -a "$SRC/packages" "$APP/packages.new"
  rm -rf "$APP/packages"
  mv "$APP/packages.new" "$APP/packages"
  changed "$APP/packages/"
fi

apt_source="deb [trusted=yes] file:$APP/packages ./"
if [ "$(cat "$APT_LIST" 2>/dev/null || true)" != "$apt_source" ]; then
  printf '%s\n' "$apt_source" >"$APT_LIST"
  changed "$APT_LIST"
fi

missing=()
for p in $PACKAGES; do
  dpkg-query -W -f='${Status}' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
done
if [ ${#missing[@]} -gt 0 ]; then
  # Point apt at the local source only, so it never tries to reach the internet.
  apt_opts=(
    -o Dir::Etc::sourcelist=sources.list.d/unihiker-gb.list
    -o Dir::Etc::sourceparts=-
    -o APT::Get::List-Cleanup=0
  )
  apt-get "${apt_opts[@]}" -qq update
  DEBIAN_FRONTEND=noninteractive apt-get "${apt_opts[@]}" -q -y install --no-install-recommends "${missing[@]}"
  changed "installed ${missing[*]}"
else
  note "already installed: $PACKAGES"
fi

# 3. Folders ----------------------------------------------------------------------
step "Creating folders"
for d in "$ETC" "$APP" "$APP/lib" "$ROMS" "$SAVES" "$(dirname "$MGBA_CONF")"; do
  if [ ! -d "$d" ]; then
    mkdir -p "$d"
    changed "$d/"
  fi
done

# 4. Move old saves -----------------------------------------------------------------
step "Moving saves out of $ROMS"
shopt -s nullglob
for f in "$ROMS"/*.sav; do
  name=$(basename "$f")
  if [ -e "$SAVES/$name" ]; then
    warn "$name is in both $ROMS and $SAVES; left both alone (check which one is newer)"
  else
    mv "$f" "$SAVES/$name"
    changed "moved $name to $SAVES/"
  fi
done
shopt -u nullglob

# 5. Program files ------------------------------------------------------------------
step "Installing program files"
install_file "$SRC/launcher/start-gb.sh" "$APP/start-gb.sh" 0755 || true
install_file "$SRC/launcher/status-screen.py" "$APP/status-screen.py" 0755 || true
install_file "$SRC/launcher/check-skip-button.py" "$APP/check-skip-button.py" 0755 || true
install_file "$SRC/launcher/hotkeys.py" "$APP/hotkeys.py" 0755 || true
install_file "$SRC/launcher/controller-event.sh" "$APP/controller-event.sh" 0755 || true
install_file "$SRC/launcher/set-rotation.sh" "$APP/set-rotation.sh" 0755 || true
install_file "$SRC/scripts/set-rom.sh" "$APP/set-rom.sh" 0755 || true
install_file "$SRC/scripts/pair-bluetooth.sh" "$APP/pair-bluetooth.sh" 0755 || true
install_file "$SRC/launcher/bt-link-security.sh" "$APP/bt-link-security.sh" 0755 || true
install_file "$SRC/scripts/lib/rom-rules.sh" "$APP/lib/rom-rules.sh" 0644 || true
install_file "$SRC/assets/splash.png" "$APP/splash.png" 0644 || true
install_file "$SRC/assets/splash-landscape.png" "$APP/splash-landscape.png" 0644 || true
# Earlier versions installed SDL's controller database, which mGBA 0.7.0 doesn't use.
if [ -e "$APP/gamecontrollerdb.txt" ]; then
  rm -f "$APP/gamecontrollerdb.txt"
  changed "removed the unused $APP/gamecontrollerdb.txt"
fi

UNIT_CHANGED=no
install_file "$SRC/systemd/gameboy.service" "$UNIT_FILE" 0644 && UNIT_CHANGED=yes
install_file "$SRC/systemd/unihiker-gb-bluetooth.service" "$BT_UNIT_FILE" 0644 && UNIT_CHANGED=yes
install_file "$SRC/systemd/unihiker-gb-display.service" "$DISPLAY_UNIT_FILE" 0644 && UNIT_CHANGED=yes

if install_file "$SRC/config/99-unihiker-gb-controller.rules" "$UDEV_RULE" 0644; then
  if [ "$HAVE_SYSTEMD" = yes ] && command -v udevadm >/dev/null; then
    udevadm control --reload
  else
    skip "udev reload (no systemd/udev running)"
  fi
fi

# 6. Settings files -------------------------------------------------------------------
step "Installing settings files"
if [ ! -f "$ETC/game.conf" ]; then
  install -m 0644 "$SRC/config/game.conf" "$ETC/game.conf"
  changed "$ETC/game.conf (default)"
fi

if [ -n "$ROM_FILE_ARG" ]; then
  problems=$(rom_name_errors "$ROM_FILE_ARG")
  [ -z "$problems" ] || die "can't use '$ROM_FILE_ARG' as the boot ROM: $problems"
  [ -f "$ROMS/$ROM_FILE_ARG" ] || die "ROM not found: $ROMS/$ROM_FILE_ARG (copy it there first; deploy.sh --rom does this)"
  if [ "$(conf_value "$ETC/game.conf" ROM_FILE)" != "$ROM_FILE_ARG" ]; then
    cp -p "$ETC/game.conf" "$ETC/game.conf.bak"
    set_conf_var "$ETC/game.conf" ROM_FILE "$ROM_FILE_ARG"
    changed "boot ROM set to $ROM_FILE_ARG"
  fi
fi

# Screen orientation, in board.conf (read by start-gb.sh). --rotate sets it; otherwise an
# existing value is kept, and a board without one gets DEFAULT_ROTATION.
rotation_now=$(conf_value "$BOARD_CONF" DISPLAY_ROTATION)
rotation=${ROTATE_ARG:-${rotation_now:-$DEFAULT_ROTATION}}
if [ "$rotation" != "$rotation_now" ]; then
  [ -f "$BOARD_CONF" ] && cp -p "$BOARD_CONF" "$BOARD_CONF.bak"
  set_conf_var "$BOARD_CONF" DISPLAY_ROTATION "$rotation"
  chmod 0644 "$BOARD_CONF"
  changed "screen orientation set to $rotation ($BOARD_CONF)"
fi
# The board's display driver only rotates when X starts, so the orientation is an X config
# file (plans/landscape-display.md, option B). The desktop is restarted in step 9 if it changed.
X_CHANGED=no
if [ -n "$("$APP/set-rotation.sh" "$rotation" 2>/dev/null)" ]; then
  X_CHANGED=yes
  changed "X display configuration for $rotation"
fi

# The repo's mGBA config (controller mappings) is the source of truth, so mapping changes
# reach the board with every deploy. mGBA 0.7.0's SDL build never writes this file, so the
# only other changes are edits by hand; those are kept in a dated backup.
if [ -f "$MGBA_CONF" ] && ! cmp -s "$SRC/config/mgba-config.ini" "$MGBA_CONF"; then
  backup="$MGBA_CONF.bak-$(date +%Y%m%d-%H%M%S)"
  cp -p "$MGBA_CONF" "$backup"
  note "the board's mGBA config differed from the repo; old copy saved as $backup"
fi
install_file "$SRC/config/mgba-config.ini" "$MGBA_CONF" 0644 || true
# Earlier versions saved the repo copy alongside instead of installing it.
if [ -e "$MGBA_CONF.repo" ]; then
  rm -f "$MGBA_CONF.repo"
  changed "removed the old $MGBA_CONF.repo"
fi

# 7. Version ----------------------------------------------------------------------------
step "Writing the version stamp"
version_tmp=$(mktemp)
{
  if [ -f "$SRC/VERSION" ]; then cat "$SRC/VERSION"; else echo "commit=unknown (install.sh run by hand)"; fi
  sed 's/^/packages_/' "$SRC/packages/manifest.txt"
} >"$version_tmp"
if [ -f "$ETC/version" ] && cmp -s "$version_tmp" "$ETC/version"; then
  rm -f "$version_tmp"
else
  install -m 0644 "$version_tmp" "$ETC/version"
  rm -f "$version_tmp"
  changed "$ETC/version"
fi

# 8. Bluetooth ----------------------------------------------------------------------------
step "Bluetooth"
if [ "$HAVE_SYSTEMD" = yes ]; then
  if systemctl cat bluetooth.service >/dev/null 2>&1; then
    if ! systemctl -q is-enabled bluetooth.service; then
      systemctl enable bluetooth.service
      changed "enabled bluetooth.service"
    fi
  else
    warn "bluetooth.service not found; Bluetooth controllers won't work"
  fi
else
  skip "enable bluetooth.service (no systemd)"
fi
# Link-level security, so paired controllers can reconnect (see bt-link-security.sh).
if [ "$HAVE_SYSTEMD" = yes ]; then
  [ "$UNIT_CHANGED" = yes ] && systemctl daemon-reload
  if ! systemctl -q is-enabled unihiker-gb-bluetooth.service; then
    systemctl enable unihiker-gb-bluetooth.service
    changed "enabled unihiker-gb-bluetooth.service (Bluetooth link security at boot)"
  fi
  if ! systemctl -q is-active unihiker-gb-bluetooth.service; then
    systemctl start unihiker-gb-bluetooth.service || warn "couldn't set Bluetooth link security now; see journalctl -u unihiker-gb-bluetooth"
  fi
else
  skip "enable unihiker-gb-bluetooth.service (no systemd)"
fi
if [ "$ERTM_FIX" = yes ]; then
  install_file "$SRC/config/bluetooth.conf" "$MODPROBE_CONF" 0644 || true
  param=/sys/module/bluetooth/parameters/disable_ertm
  if [ -w "$param" ]; then
    if [ "$(cat "$param")" != Y ]; then
      echo 1 >"$param"
      changed "turned off ERTM for this boot"
    fi
  else
    note "ERTM setting not available right now; it applies from the next boot"
  fi
fi

# 9. Service ------------------------------------------------------------------------------
step "Emulator service"
if [ "$X_CHANGED" = yes ]; then
  if [ "$HAVE_SYSTEMD" = yes ] && [ "$NO_START" = no ] && systemctl -q is-active lightdm.service; then
    # Stop the game first, so it doesn't crash and restart when X goes away.
    systemctl stop gameboy.service
    systemctl restart lightdm.service
    note "restarted the desktop for the new screen orientation"
  else
    note "the new screen orientation applies from the next boot"
  fi
fi
if [ "$HAVE_SYSTEMD" = yes ]; then
  # Restores the screen orientation at each boot after a skip-button boot (set-rotation.sh).
  if ! systemctl -q is-enabled unihiker-gb-display.service; then
    systemctl enable unihiker-gb-display.service
    changed "enabled unihiker-gb-display.service (screen orientation at boot)"
  fi
  if ! systemctl -q is-enabled gameboy.service; then
    systemctl enable gameboy.service
    changed "enabled gameboy.service"
  fi
  if [ "$NO_START" = yes ]; then
    note "not starting the service (--no-start)"
  else
    systemctl restart gameboy.service
    note "restarted gameboy.service"
  fi
else
  skip "enable and start gameboy.service (no systemd)"
fi

# 10. Verify and summarize -------------------------------------------------------------------
step "Checking the result"
rom=$(conf_value "$ETC/game.conf" ROM_FILE)
if [ -n "$rom" ] && [ -f "$ROMS/$rom" ]; then
  pass "boot ROM $rom is in $ROMS"
else
  fail "boot ROM '${rom}' is not in $ROMS (copy it with ./deploy.sh --rom <file>)"
fi

if [ -x "$MGBA" ]; then
  pass "mgba is installed ($MGBA)"
else
  fail "mgba is not installed ($MGBA missing)"
fi

if [ "$HAVE_SYSTEMD" = yes ] && [ "$NO_START" = no ]; then
  sleep 5
  if systemctl -q is-active gameboy.service; then
    pass "gameboy.service is running"
  else
    fail "gameboy.service is not running. Last log lines:"
    journalctl -u gameboy.service -n 15 --no-pager | sed 's/^/      /'
  fi
fi

# Screen orientation: check X came up the expected shape. Needs X, so not in Docker, and
# not with --no-start when the orientation changed (X hasn't restarted yet).
case $rotation in
  left | right) want_size="320 x 240" ;;
  *) want_size="240 x 320" ;;
esac
if ! command -v xrandr >/dev/null; then
  skip "screen orientation check (xrandr isn't installed)"
elif [ "$X_CHANGED" = yes ] && [ "$NO_START" = yes ]; then
  skip "screen orientation check (applies from the next boot)"
else
  size=""
  for _ in $(seq 15); do  # X may still be starting after the desktop restart
    size=$(DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 timeout 5 xrandr -q 2>/dev/null |
      sed -n '1s/.*current \([0-9]* x [0-9]*\).*/\1/p') || true
    [ -n "$size" ] && break
    sleep 1
  done
  if [ -z "$size" ]; then
    skip "screen orientation check (no display running)"
  elif [ "$size" = "$want_size" ]; then
    pass "screen orientation: $rotation ($size)"
  else
    warn "screen orientation is $rotation, but the screen is $size (expected $want_size); see plans/landscape-display.md"
  fi
fi

if python3 -c 'import pinpong' >/dev/null 2>&1; then
  pass "pinpong is available (skip button works)"
else
  warn "pinpong isn't available: the skip button won't work, but the game still runs"
fi

if compgen -G '/dev/input/js*' >/dev/null; then
  pass "a controller is connected"
else
  warn "no controller connected right now (fine if a Bluetooth controller isn't paired or on yet)"
fi

step "Summary"
sed 's/^/    /' "$ETC/version"
for r in "${RESULTS[@]}"; do
  printf '    %-5s %s\n' "${r%%	*}" "${r#*	}"
done
printf '    changes made: %d\n' "$CHANGES"
[ "$FAILED" = no ] || exit 1
