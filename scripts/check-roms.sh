#!/bin/bash
# Flags ROM filenames that will cause problems on the board.
#
#   scripts/check-roms.sh <file or folder>...
#
# Folders are checked one level deep; hidden files (like .gitignore) are skipped.
# Exit status: 0 = no errors (warnings are OK), 1 = at least one error, 2 = usage problem.
# Runs on the Mac, so it must stay bash 3.2 compatible.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/rom-rules.sh
. "$HERE/lib/rom-rules.sh"

usage() {
  sed -n '2,8s/^# \{0,1\}//p' "$0"
  exit 2
}

[ $# -gt 0 ] || usage
case $1 in -h | --help) usage ;; esac

files=()
for arg in "$@"; do
  if [ -d "$arg" ]; then
    for f in "$arg"/*; do
      [ -f "$f" ] && files+=("$f")
    done
  elif [ -f "$arg" ]; then
    files+=("$arg")
  else
    printf 'error: not a file or folder: %s\n' "$arg" >&2
    exit 2
  fi
done

errors=0
warnings=0
checked=()      # files already checked (the same file can be given twice)
lower_names=()  # their names in lower case, same order

for f in ${files[@]+"${files[@]}"}; do
  # Skip a file that was already given (e.g. --rom roms/a.gb together with --roms-dir roms).
  seen=no
  for c in ${checked[@]+"${checked[@]}"}; do
    if [ "$f" -ef "$c" ]; then
      seen=yes
      break
    fi
  done
  [ "$seen" = yes ] && continue

  lower=$(printf '%s' "$(basename "$f")" | tr '[:upper:]' '[:lower:]')
  # Names that differ only in upper/lower case are one name on the Mac but two files on the board.
  i=0
  while [ "$i" -lt "${#lower_names[@]}" ]; do
    if [ "${lower_names[$i]}" = "$lower" ]; then
      printf 'ERROR  %s and %s differ only in upper/lower case\n' "${checked[$i]}" "$f"
      errors=$((errors + 1))
    fi
    i=$((i + 1))
  done
  checked+=("$f")
  lower_names+=("$lower")

  name=$(basename "$f")
  problems=$(rom_name_errors "$name")
  if [ -n "$problems" ]; then
    while IFS= read -r p; do
      printf 'ERROR  %s: %s\n' "$f" "$p"
      errors=$((errors + 1))
    done <<<"$problems"
    printf '       suggested name: %s\n' "$(rom_suggest_name "$name")"
  fi
  problems=$(rom_name_warnings "$name")
  if [ -n "$problems" ]; then
    while IFS= read -r p; do
      printf 'WARN   %s: %s\n' "$f" "$p"
      warnings=$((warnings + 1))
    done <<<"$problems"
  fi
done

printf 'Checked %d ROM(s): %d error(s), %d warning(s).\n' "${#checked[@]}" "$errors" "$warnings"
[ "$errors" -eq 0 ]
