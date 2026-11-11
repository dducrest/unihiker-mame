#!/bin/bash
# Tests scripts/check-roms.sh with good and bad ROM filenames (as empty files).
# Runs on macOS (bash 3.2) and in CI.
set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
CHECK="$REPO/scripts/check-roms.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0

# expect <ok|error> <description> <filename>...: put the files in a fresh folder and check it.
expect() {
  local want=$1 what=$2 dir rc
  shift 2
  dir=$(mktemp -d "$tmp/case.XXXX")
  for name in "$@"; do : >"$dir/$name"; done
  rc=0
  "$CHECK" "$dir" >"$dir.out" 2>&1 || rc=$?
  if { [ "$want" = ok ] && [ "$rc" -eq 0 ]; } || { [ "$want" = error ] && [ "$rc" -eq 1 ]; }; then
    echo "    ok:     $what"
  else
    echo "    FAILED: $what (exit $rc)"
    sed 's/^/            /' "$dir.out"
    fails=$((fails + 1))
  fi
}

# expect_warning <description> <filename>: must pass, but print a warning.
expect_warning() {
  local what=$1 dir
  dir=$(mktemp -d "$tmp/case.XXXX")
  : >"$dir/$2"
  if "$CHECK" "$dir" >"$dir.out" 2>&1 && grep -q '^WARN' "$dir.out"; then
    echo "    ok:     $what"
  else
    echo "    FAILED: $what"
    sed 's/^/            /' "$dir.out"
    fails=$((fails + 1))
  fi
}

echo "==> check-roms.sh"
expect ok "plain names pass" game.gb other-game.gbc advance_1.gba
expect ok "upper-case extension passes" GAME.GB
expect error "single quote" "Link's Awakening.gb"
expect error "double quote" 'say "hi".gb'
expect error "backtick" 'tick`.gb'
expect error "dollar sign" 'cash$.gb'
expect error "backslash" 'back\slash.gb'
expect error "leading dash" "-rf.gb"
expect error "newline in the name" "two
lines.gb"
# macOS can't create a filename over 255 bytes, so test that rule on the function directly.
# shellcheck source=../scripts/lib/rom-rules.sh
. "$REPO/scripts/lib/rom-rules.sh"
long="$(printf 'a%.0s' $(seq 1 253)).gb"
if rom_name_errors "$long" | grep -q '255 bytes' && [ -z "$(rom_name_errors "${long#a}")" ]; then
  echo "    ok:     name over 255 bytes (and exactly 255 is fine)"
else
  echo "    FAILED: name over 255 bytes"
  fails=$((fails + 1))
fi
expect_warning "spaces warn" "Test Game.gb"
expect_warning "brackets warn" "Game (USA) [!].gb"
expect_warning "non-ASCII warns" "Pokémon.gb"
expect_warning "other extension warns" "game.zip"

# Case-only duplicates can't exist in one folder on a Mac, so use two folders.
d1=$(mktemp -d "$tmp/dup1.XXXX")
d2=$(mktemp -d "$tmp/dup2.XXXX")
: >"$d1/Game.gb"
: >"$d2/game.gb"
if "$CHECK" "$d1" "$d2" >/dev/null 2>&1; then
  echo "    FAILED: names differing only in case"
  fails=$((fails + 1))
else
  echo "    ok:     names differing only in case"
fi

# The same file given twice (e.g. --rom roms/a.gb with --roms-dir roms) is not a duplicate.
if "$CHECK" "$d1/Game.gb" "$d1" >/dev/null 2>&1; then
  echo "    ok:     the same file given twice"
else
  echo "    FAILED: the same file given twice"
  fails=$((fails + 1))
fi

if "$CHECK" "$tmp/does-not-exist" >/dev/null 2>&1; then
  echo "    FAILED: missing path should be a usage error"
  fails=$((fails + 1))
else
  echo "    ok:     missing path is a usage error"
fi

if [ "$fails" -eq 0 ]; then echo "==> All checks passed"; else echo "==> $fails check(s) FAILED"; exit 1; fi
