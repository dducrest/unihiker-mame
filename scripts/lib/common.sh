# shellcheck shell=bash
# Shared settings and helpers for the Mac-side scripts (deploy.sh, fetch-logs.sh).
# Keep this file bash 3.2 compatible: macOS ships bash 3.2.

UNIHIKER_DEFAULT_HOST=10.1.2.3
HOST="${UNIHIKER_HOST:-$UNIHIKER_DEFAULT_HOST}"
# Only needed when the board isn't on port 22 (e.g. the container used to test deploy.sh).
PORT="${UNIHIKER_SSH_PORT:-22}"
KEY="$HOME/.ssh/unihiker-gb_ed25519"
KNOWN_HOSTS="$HOME/.ssh/unihiker-gb_known_hosts"
SSH_OPTS=()

step() { printf '==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# Call after HOST is final (i.e. after option parsing).
init_ssh_opts() {
  SSH_OPTS=(
    -o Port="$PORT"
    -i "$KEY"
    -o IdentitiesOnly=yes
    -o StrictHostKeyChecking=accept-new
    -o UserKnownHostsFile="$KNOWN_HOSTS"
    -o ConnectTimeout=5
    -o BatchMode=yes
  )
}

# board_ssh CMD...  - run a command on the board, non-interactively
# shellcheck disable=SC2029 # callers build remote commands on purpose
board_ssh() { ssh "${SSH_OPTS[@]}" "root@$HOST" "$@"; }

# board_ssh_tty CMD...  - run an interactive command on the board
# shellcheck disable=SC2029
board_ssh_tty() { ssh -t "${SSH_OPTS[@]}" "root@$HOST" "$@"; }

# board_scp SRC... DEST  - copy local files to the board (DEST is a remote path)
board_scp() {
  local n=$# dest
  dest=${!n}
  scp -q "${SSH_OPTS[@]}" "${@:1:n-1}" "root@$HOST:$dest"
}

# Forget the board's SSH host key (after a re-flash or when switching boards).
forget_host() {
  local entry=$HOST
  [ "$PORT" = 22 ] || entry="[$HOST]:$PORT"
  if [ -f "$KNOWN_HOSTS" ]; then
    ssh-keygen -R "$entry" -f "$KNOWN_HOSTS" >/dev/null 2>&1 || true
    rm -f "$KNOWN_HOSTS.old"
  fi
  note "forgot the SSH key for $HOST"
}

# Make sure the dedicated key exists and the board accepts it.
# With "install" as the first argument, installs the key with ssh-copy-id if needed.
ensure_ssh_access() {
  local mode=${1:-check} out rc

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  if [ ! -f "$KEY" ]; then
    note "creating SSH key $KEY"
    ssh-keygen -q -t ed25519 -N "" -C "unihiker-gb" -f "$KEY"
  fi

  rc=0
  out=$(board_ssh true 2>&1) || rc=$?
  [ "$rc" -eq 0 ] && return 0

  case $out in
    *"REMOTE HOST IDENTIFICATION HAS CHANGED"* | *"Host key verification failed"*)
      die "the board at $HOST has a different SSH key than last time.
       If you just re-flashed it or switched to another board, re-run with --forget-host."
      ;;
    *"Permission denied"*)
      if [ "$mode" != install ]; then
        die "the board doesn't accept this Mac's key yet. Run ./deploy.sh once to set up access."
      fi
      note "installing this Mac's key on the board."
      note "Enter the board's root password when asked (default: dfrobot)."
      ssh-copy-id -i "$KEY.pub" -p "$PORT" \
        -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o ConnectTimeout=5 \
        "root@$HOST" >/dev/null ||
        die "ssh-copy-id failed"
      board_ssh true >/dev/null 2>&1 || die "the board still doesn't accept the key"
      return 0
      ;;
    *)
      die "can't reach the board at $HOST:
       $out
       Check that the UNIHIKER is plugged into this Mac with a USB data cable and has
       finished booting (about a minute). Over USB its address is $UNIHIKER_DEFAULT_HOST."
      ;;
  esac
}
