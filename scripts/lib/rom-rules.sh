# shellcheck shell=bash
# ROM filename rules, shared by:
#   scripts/check-roms.sh   (Mac, bash 3.2)
#   scripts/install.sh      (board, bash 5)
#   scripts/set-rom.sh      (board, bash 5)
# Keep this file bash 3.2 compatible: no associative arrays, no mapfile, no ${var,,}.

ROM_EXTENSIONS="gb gbc gba"

# rom_name_errors NAME
# Prints one line per problem that must stop a deploy. Prints nothing if the name is OK.
rom_name_errors() {
  local name=$1 bytes stripped
  if [ -z "$name" ]; then
    echo "the name is empty"
    return 0
  fi
  case $name in */*) echo "contains '/'" ;; esac
  case $name in -*) echo "starts with '-'" ;; esac
  case $name in *\'* | *\"*) echo "contains a quote" ;; esac
  case $name in *\`*) echo "contains a backtick" ;; esac
  case $name in *\$*) echo "contains '\$'" ;; esac
  case $name in *\\*) echo "contains a backslash" ;; esac
  stripped=$(printf '%s' "$name" | LC_ALL=C tr -d '[:cntrl:]')
  if [ "$stripped" != "$name" ]; then
    echo "contains a control character or newline"
  fi
  bytes=$(printf '%s' "$name" | wc -c | tr -d ' ')
  if [ "$bytes" -gt 255 ]; then
    echo "is longer than 255 bytes"
  fi
  return 0
}

# rom_name_warnings NAME
# Prints one line per problem that works but is awkward. Prints nothing if the name is OK.
rom_name_warnings() {
  local name=$1 ext ok e
  case $name in *' '*) echo "contains spaces (works, but awkward to type in a shell)" ;; esac
  case $name in *[\(\)\[\]\{\}]*) echo "contains brackets (works, but awkward to type in a shell)" ;; esac
  if printf '%s' "$name" | LC_ALL=C grep -q '[^ -~]'; then
    echo "contains non-ASCII characters (macOS and Linux may store them differently)"
  fi
  ext=$(printf '%s' "${name##*.}" | tr '[:upper:]' '[:lower:]')
  ok=no
  case $name in
    *.*)
      for e in $ROM_EXTENSIONS; do
        [ "$ext" = "$e" ] && ok=yes
      done
      ;;
  esac
  if [ "$ok" = no ]; then
    echo "extension is not .gb, .gbc or .gba"
  fi
  return 0
}

# rom_suggest_name NAME
# Prints a safer version of NAME: unsafe characters become '_', leading '-' is removed.
rom_suggest_name() {
  local name=$1 safe
  safe=$(printf '%s' "$name" | LC_ALL=C tr -c 'A-Za-z0-9._ ()[]-' '_')
  while :; do
    case $safe in -*) safe=${safe#-} ;; *) break ;; esac
  done
  printf '%s\n' "${safe:-rom.gb}"
}

# set_conf_var FILE VAR VALUE
# Sets VAR="VALUE" in a shell-style config file, quoting VALUE with printf %q so the
# file can be sourced safely. Replaces an existing VAR= line, or appends one.
# Board-side only (bash 5); not used on the Mac.
set_conf_var() {
  local file=$1 var=$2 value=$3 line newline tmp found=no
  newline="$var=$(printf '%q' "$value")"
  tmp="$file.tmp.$$"
  : >"$tmp"
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case $line in
        "$var="*)
          printf '%s\n' "$newline" >>"$tmp"
          found=yes
          ;;
        *) printf '%s\n' "$line" >>"$tmp" ;;
      esac
    done <"$file"
  fi
  [ "$found" = yes ] || printf '%s\n' "$newline" >>"$tmp"
  mv "$tmp" "$file"
}
