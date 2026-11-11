# Initial plan: Game Boy emulator on the UNIHIKER M10

Parts of this plan have been checked on a real M10 (see "Board check results"). Items marked ⚠️ still need checking on the board.

## Goals

- **Deploying and configuring the board is as simple as possible:** one command from a Mac, no network setup on the board.
- A **USB or Bluetooth game controller is the main input device.** The board's own buttons and touchscreen aren't needed to play.
- At first the board boots straight into **one specific ROM**.
- Choosing the ROM is **configuration, not code.** Changing the game later, or adding a game picker, shouldn't mean rewriting the launch script or the service.

## Implementation status (2026-11-11)

| Part | Status |
|---|---|
| `deploy.sh`, `fetch-logs.sh`, `scripts/lib/common.sh` | Built. Tested on macOS against a buster container running sshd: first login with the default password, re-deploy, `--pull-saves`, clock, changed host key, `--forget-host`, unreachable board, bad ROM name. `fetch-logs.sh` reached the container but needs the board's systemd journal to show anything. |
| `scripts/check-roms.sh`, `scripts/lib/rom-rules.sh` | Built. Tested by `tests/test-check-roms.sh` on macOS's bash 3.2. |
| `scripts/fetch-packages.sh` | Built. Downloads 246 arm64 packages (82 MB), including `xdotool` for the save-state shortcuts. |
| `scripts/install.sh`, `scripts/set-rom.sh` | Built. `scripts/test-in-docker.sh` runs `install.sh` twice in an arm64 buster container: all checks pass and the second run changes nothing. Run on the board with `deploy.sh --no-start`: packages, program files and the mGBA config install, and mGBA runs. Starting the service, and the udev and Bluetooth steps in use, are untested until the real launcher exists. |
| CI (`.github/workflows/ci.yml`) | Built and passing on GitHub. shellcheck, Python syntax check, ROM filename tests, and the Docker install test under arm64 emulation. |
| Config files, `gameboy.service`, udev rule, `assets/splash.png` | Built (splash is a placeholder). `config/mgba-config.ini` has the controller mapping confirmed on the board. |
| `launcher/hotkeys.py` | Built and working on the board: L+R+Select saves the game state, L+R+Start loads it. Covered by the Docker test (installed, reads the mapping). |
| Other `launcher/*` scripts, `scripts/pair-bluetooth.sh` | **Placeholders.** They install cleanly but do nothing yet. The board checks they depend on are done (button pins, controller mapping, speed, save states), except pause/resume. |
| `docs/recovery.md` | Not written yet. |

## Board check results (2026-11-11)

First checks on a real UNIHIKER M10:

| Check | Result |
|---|---|
| USB connection from macOS | Works, after setting System Settings → Privacy & Security → **Allow accessories to connect** to **Always** for the first connection. The "Allow" prompt disappears too quickly to click, probably because the board reconnects while setting up its USB network. After the first connection the setting can go back to "Ask for new accessories". |
| Package architecture | `arm64`, which matches the downloaded packages. |
| `pinpong` and buttons | Preinstalled. Connects to the co-processor on `/dev/ttyS3` in 0.9 s (with the menu stopped). Button A is `P27`, button B is `P28`; both read **0 when pressed**, 1 when released. The extension's `button_a` / `button_b` also work but lag one reading behind the pins. |
| Bluetooth | Onboard adapter present (`bluetoothctl list` shows a default controller). |
| CPU frequency | Exposed. Governors: `ondemand`, `userspace`, `interactive` (no `performance`). |
| `xset`, `xrandr` | Both preinstalled in `/usr/bin`. |
| Built-in menu | `PyboardUI.service`, a systemd **user** service in root's user manager (`/lib/systemd/user/PyboardUI.service`, `Restart=always`, empty `[Install]` section). It isn't enabled: `/root/.xsessionrc` starts it when lightdm logs root in. The web interface (`startServer.py`) runs separately. |
| Display | X is started by `lightdm.service` (a system service), which logs root in automatically (`autologin-user=root`). X runs with `-dpms` and the access file `/var/run/lightdm/root/:0`; `/root/.Xauthority` also exists. Root's user manager runs only while that login is active (`Linger=no`). |
| Stopping the menu | Works: `XDG_RUNTIME_DIR=/run/user/0 systemctl --user stop PyboardUI.service` clears it from the screen, and `... start ...` brings it back (step 8). |
| Controller in mGBA | Works with the mapping in `config/mgba-config.ini`: A = button 1, B = 2, Start = 9, Select = 8, D-pad = axes 0/1. mGBA 0.7.0 ignores SDL's controller database (item 14), so the database was removed. |
| mGBA speed | Runs smoothly at the default CPU settings. |
| In-game saves | Work: `-C savegamePath=/root/saves` is honored. The `.sav` file is written to `/root/saves/`, not next to the ROM, and loads on the next start. |
| Save-state shortcuts | Work: L+R+Select saves and L+R+Start loads, through `launcher/hotkeys.py` and `xdotool`. L = button 4, R = button 5. |
| Clock | Wrong at boot (showed 2023-05-29), so the board doesn't keep the time. `deploy.sh` sets it on every deploy (item 2). |

## Next steps

1. **Write the real launcher** (step 5), replacing the placeholders. Every input it needs is now known from the board checks:
   - `check-skip-button.py`: reads `P27`/`P28` with pinpong (active-low).
   - `start-gb.sh`: waits for X, stops the menu, runs the skip check, waits for a controller, then starts mGBA with no `SDL_GAMECONTROLLERCONFIG`.
   - `status-screen.py`: the splash and "connect a controller" screen.
   - `start-gb.sh` also starts `hotkeys.py` in the background before mGBA (already written and tested).
   - Add `lightdm.service` to `After=` in `systemd/gameboy.service`.
   Then deploy without `--no-start` and run the boot-flow tests (step 9). These also time the boot (item 17).
2. **Pause on disconnect** (step 6): check SIGSTOP/SIGCONT on the board, then write `controller-event.sh`.
3. **`pair-bluetooth.sh`** and **`docs/recovery.md`**.

## What you're working with

| Spec | Why it matters |
|---|---|
| Rockchip RK3308, 4× Cortex-A35 @ 1.2 GHz, 512 MB RAM | Fast enough for Game Boy / Game Boy Color with a native (C) emulator. Python emulators will struggle. |
| 2.8" 240×320 touchscreen, portrait | The Game Boy screen is 160×144, so it scales to 240×216 and leaves room at the bottom. The splash screen is 240×320. |
| Debian 10 (buster), X server on `:0` | Packages are installed **offline** from `.deb` files prepared on the Mac (item 1). GUI apps run with `DISPLAY=:0`. Python is 3.7. Package architecture: `arm64` (confirmed). |
| USB-A port, Wi-Fi + Bluetooth 4.0 | A USB controller plugs in directly. A Bluetooth controller pairs through BlueZ with the onboard adapter (confirmed). |
| Only buttons A and B, wired to a co-processor | No D-pad, which is why an external controller is required. The buttons are still used once, at boot, to skip the emulator (item 16). |
| No speaker (⚠️ may have only a buzzer) | Sound is turned off (item 15). |

## Recommended stack

**mGBA (SDL build) + USB/Bluetooth controller + a config file that names the ROM + a systemd service + offline packages**

mGBA plays `.gb`, `.gbc` and `.gba`, so changing the ROM later won't mean changing the emulator.

## Architecture

```
/etc/unihiker-gb/game.conf              <- which ROM to run, by filename (the only file you edit to change games)
/etc/unihiker-gb/board.conf             <- optional board overrides (e.g. MENU_UNIT); not needed by default
/etc/unihiker-gb/version                <- git commit and date of the last deploy
/opt/unihiker-gb/start-gb.sh            <- boot flow: splash, skip-button check, wait for controller, launch mGBA
/opt/unihiker-gb/status-screen.py       <- splash image, then the "connect a controller" prompt
/opt/unihiker-gb/check-skip-button.py   <- exits 0 if a board button is held at boot
/opt/unihiker-gb/hotkeys.py             <- controller shortcuts for save states (L+R+Select / L+R+Start)
/opt/unihiker-gb/controller-event.sh    <- pauses/resumes mGBA when the controller disconnects/reconnects
/opt/unihiker-gb/set-rom.sh             <- changes the boot ROM
/opt/unihiker-gb/pair-bluetooth.sh      <- pairs a Bluetooth controller
/opt/unihiker-gb/lib/rom-rules.sh       <- ROM filename rules used by set-rom.sh
/opt/unihiker-gb/splash.png
/opt/unihiker-gb/packages/              <- offline .deb packages and their index
/etc/udev/rules.d/99-unihiker-gb-controller.rules
/etc/systemd/system/gameboy.service
/root/.config/mgba/config.ini           <- mGBA settings and any per-controller mapping overrides
/root/roms/                             <- ROM library (can hold many ROMs)
/root/saves/                            <- game saves, kept apart from ROMs
```

Each piece does one job:
- **The ROM is chosen in one place.** `game.conf` sets `ROM_FILE`, a filename inside `/root/roms/`, and nothing else hard-codes a ROM.
- **The launcher doesn't care which game it runs.** It runs whatever `game.conf` names and fails with a clear message if the file is missing.
- **Controller setup is separate from game setup.** Button mappings live in mGBA's config, so they stay the same when the ROM changes.
- **Saves are separate from ROMs.** Copying, replacing or removing ROMs can never touch a save.
- **Plan for later:** a game picker only needs to write `ROM_FILE` into `game.conf` and run `systemctl restart gameboy`. The launcher and the service stay as they are.

### Boot flow

1. systemd starts `gameboy.service` once the desktop (X) is up.
2. `start-gb.sh` turns off screen blanking and shows the **splash screen** (`status-screen.py` in the background).
3. **Stop the built-in menu:** lightdm's automatic login has already started the UNIHIKER menu (`PyboardUI.service`). The launcher stops it for this boot (`systemctl --user stop`), so it may show for a moment before the splash covers it. Nothing is disabled, so the board's own setup is never changed.
4. **Skip check:** if a board button is held, the launcher closes the splash, starts the menu again, and exits.
5. **Wait for a controller.** If none is found after a few seconds, the screen switches to a prompt:
   > No controller found. Turn on or plug in a controller.
   > To use the UNIHIKER menu instead: power off, then hold button B while powering on until the menu appears.
6. When a controller appears, the prompt closes and mGBA starts the ROM in fullscreen, with sound off.
7. **During play:** if the controller disconnects (unplugged, or a Bluetooth controller goes to sleep), mGBA is paused. It resumes when the controller reconnects.

## Repository layout

These are the scripts and files this repo will contain. Most of them are installed on the board. The ones marked "Mac" run on the computer doing the deploy.

```
deploy.sh                          # Mac: checks ROMs, sets up SSH, pushes this repo to the board, runs install.sh
fetch-logs.sh                      # Mac: shows recent emulator logs from the board
assets/splash.png                  # placeholder 240×320 splash image, installed to /opt/unihiker-gb/
config/game.conf                   # default ROM selection
config/mgba-config.ini             # mGBA settings; per-controller overrides added after step 3 if needed
config/99-unihiker-gb-controller.rules  # udev rule that calls controller-event.sh
config/bluetooth.conf              # modprobe option for the ERTM workaround (installed only if asked for)
launcher/start-gb.sh
launcher/status-screen.py
launcher/check-skip-button.py
launcher/hotkeys.py
launcher/controller-event.sh
systemd/gameboy.service
scripts/lib/common.sh              # Mac: shared settings for deploy.sh and fetch-logs.sh (host, SSH key, known-hosts file)
scripts/lib/rom-rules.sh           # Mac and board: ROM filename rules shared by check-roms.sh, install.sh and set-rom.sh
scripts/check-roms.sh              # Mac: flags ROM filenames that will cause problems (run by deploy.sh, or on its own)
scripts/fetch-packages.sh          # Mac (needs Docker): downloads the .deb packages into packages/
scripts/test-in-docker.sh          # Mac or CI: runs install.sh in an arm64 buster container
scripts/install.sh                 # board: installs packages and files, enables the service
scripts/pair-bluetooth.sh          # board: interactive helper for pairing a controller
scripts/set-rom.sh                 # board: set-rom.sh <filename> updates game.conf, restarts the service
docs/recovery.md                   # how to restore the board's factory image (item 6)
tests/test-check-roms.sh           # Mac or CI: tests check-roms.sh with good and bad filenames
.github/workflows/ci.yml           # shellcheck + test-in-docker on every push
.shellcheckrc                      # lets shellcheck find the shared libraries
packages/                          # offline .deb packages; contents are gitignored
packages/.gitignore
roms/                              # local ROM library to deploy; contents are gitignored
roms/.gitignore                    # keeps the folder in git while ignoring everything else in it
saves/                             # save backups pulled from the board; contents are gitignored
saves/.gitignore
```

**The `roms/` folder.** Put ROM files here on your computer, and `deploy.sh` copies them to `/root/roms/` on the board. The folder itself is committed so the layout is the same in every clone, but ROM files are never committed: they're large, and most can't legally be shared. `roms/.gitignore` contains:
```gitignore
# Ignore everything in this folder except this file
*
!.gitignore
```
This rule lives inside `roms/`, so it travels with the folder and doesn't depend on a root `.gitignore`. Before the first commit, run `git status` and check that a test file dropped into `roms/` doesn't show up.

**The `packages/` and `saves/` folders** work the same way, with the same `.gitignore`. `scripts/fetch-packages.sh` fills `packages/`, and anyone can regenerate it, so the `.deb` files don't need to be in git. `deploy.sh --pull-saves` fills `saves/`.

**The splash image.** `assets/splash.png` starts as a simple placeholder (a 240×320 image with the project name), committed to the repo and replaced with real artwork later. `install.sh` copies whatever is there, so swapping the artwork needs no code change.

The manual steps below describe what the scripts automate. Do them by hand once on a real board to confirm each one before writing them into `install.sh`. See [Setup script](#setup-script) for how the scripts fit together.

## Steps

### 1. Prepare packages on the Mac, then connect and install
```bash
# On the Mac (needs Docker Desktop)
scripts/fetch-packages.sh            # fills packages/ with arm64 buster .debs and a package index

# Over USB, the board shows up at 10.1.2.3. First connection only: set System Settings →
# Privacy & Security → Allow accessories to connect → Always (see Board check results)
ssh root@10.1.2.3                    # default password: dfrobot (change it)
dpkg --print-architecture            # must match the packages: arm64 (confirmed on the board)
```
Create the folders, copy the packages and ROMs over, then install from the local folder (no internet needed):
```bash
ssh root@10.1.2.3 'mkdir -p /root/roms /root/saves /etc/unihiker-gb /opt/unihiker-gb'
scp -r packages root@10.1.2.3:/opt/unihiker-gb/
scp roms/game.gb root@10.1.2.3:/root/roms/      # homebrew or dumps of cartridges you own
# on the board:
echo 'deb [trusted=yes] file:/opt/unihiker-gb/packages ./' > /etc/apt/sources.list.d/unihiker-gb.list
apt-get update -o Dir::Etc::sourcelist=sources.list.d/unihiker-gb.list -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0
apt-get install -y --no-install-recommends -o Dir::Etc::sourcelist=sources.list.d/unihiker-gb.list -o Dir::Etc::sourceparts=- \
  mgba-sdl bluez joystick python3-tk xdotool
```
Pointing apt at the local folder only is the same idea as `dpkg -i`, but apt works out the install order and skips packages the board already has.

### 2. Connect the controller

**USB:** plug it in and check that the board sees it:
```bash
ls /dev/input/js*            # a js device should appear
jstest /dev/input/js0        # press buttons and move the D-pad to confirm
```

**Bluetooth:** pair once and mark the controller as trusted, so it reconnects on its own after a reboot. (`deploy.sh --pair` automates this; see [Setup script](#setup-script).)
```bash
bluetoothctl
  power on
  agent on
  default-agent
  scan on                    # put the controller in pairing mode, then wait for its MAC
  pair XX:XX:XX:XX:XX:XX
  trust XX:XX:XX:XX:XX:XX
  connect XX:XX:XX:XX:XX:XX
  quit
systemctl enable bluetooth
```
- ⚠️ Some controllers (Xbox-style ones in particular) won't stay connected unless ERTM is turned off: `echo 1 > /sys/module/bluetooth/parameters/disable_ertm`. To keep that setting across reboots, add `options bluetooth disable_ertm=1` to `/etc/modprobe.d/bluetooth.conf`.
- ✅ The onboard Bluetooth adapter shows up in `bluetoothctl list` (board, 2026-11-11).

### 3. Test manually and check the controller mapping
```bash
XDG_RUNTIME_DIR=/run/user/0 systemctl --user stop PyboardUI.service   # clear the menu off the screen

DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0 SDL_AUDIODRIVER=dummy \
  /usr/games/mgba -f -C savegamePath=/root/saves -C savestatePath=/root/saves /root/roms/game.gb
```
Run it from SSH with `DISPLAY` and `XAUTHORITY` set, as the launcher does. The controller mapping comes from `config.ini` (see below). An earlier version passed the whole controller database in `SDL_GAMECONTROLLERCONFIG`; that exceeds Linux's 128 KB limit for one environment variable ("Argument list too long"), and mGBA doesn't use it anyway.

Debian installs mGBA (version 0.7.0 in buster) to `/usr/games/mgba`, which isn't on root's `PATH`, so always use the full path.
Check that it runs at full speed, the screen fills properly and the controller responds with the right buttons. `SDL_AUDIODRIVER=dummy` turns sound off.

- ✅ **Controller database: not used.** mGBA 0.7.0's SDL build reads raw joystick button numbers (SDL's joystick API, not its game-controller API), so `SDL_GAMECONTROLLERCONFIG` and `gamecontrollerdb.txt` have no effect (checked in the 0.7.0 source, 2026-11-11). By default only the D-pad works (axes 0/1 and hat 0); A, B, Select and Start are unmapped. Map them in `[gba.input.SDLB]` of `/root/.config/mgba/config.ini` (the SDL build uses the `gba` section names even for Game Boy games), using `keyA=N` etc. with button numbers from `jstest`. A per-model section `[gba.input-profile.<joystick name>]` overrides it. Commit the mapping to `config/mgba-config.ini`. Board result (2026-11-11): A = button 1, B = 2, Start = 9, Select = 8, D-pad = axes 0/1 (the default); committed to `config/mgba-config.ini`.
- **Save-state shortcuts:** L+R+Select saves the game state, L+R+Start loads it. mGBA 0.7.0's SDL build has no controller hotkeys; its save-state keys are keyboard only (Shift+F1 saves slot 1, F1 loads slot 1; checked in the source). `launcher/hotkeys.py` reads the controller from `/dev/input/js*` alongside mGBA and sends those keys with `xdotool` (added to the packages). It takes the L, R, Select and Start button numbers from `[gba.input.SDLB]` in mGBA's config. Saving always uses slot 1, so loading restores the most recent state. `-C savestatePath=` puts the state files (`*.ss1`) in `/root/saves/`, so `--pull-saves` backs them up. ✅ Confirmed on the board (2026-11-11): L = button 4, R = button 5, mGBA receives `xdotool`'s keys, and saving and loading both work.
- ✅ **`savegamePath` is honored** (board, 2026-11-11): with `-C savegamePath=/root/saves`, the in-game save (`.sav`) is written to `/root/saves/`, not next to the ROM, and loads on the next start.
- ⚠️ Bluetooth controllers often connect *after* the emulator has started. The boot flow waits for a controller before starting mGBA, but check that mGBA still picks up a controller that reconnects mid-game (see step 9).

### 4. ROM selection: `/etc/unihiker-gb/game.conf`
```bash
# Filename of the ROM launched at boot, inside /root/roms/. Change it with scripts/set-rom.sh.
ROM_FILE="game.gb"
```
The ROM is chosen by filename only, never by path (item 10). `set-rom.sh` writes this line with `printf %q`, so any filename it accepts can be read back safely.

### 5. Launch script: `/opt/unihiker-gb/start-gb.sh`
```bash
#!/bin/bash
set -euo pipefail
export DISPLAY=:0
export HOME=/root
export XAUTHORITY=/var/run/lightdm/root/:0   # X's access file (lightdm)
export XDG_RUNTIME_DIR=/run/user/0           # lets systemctl --user reach root's user manager
APP=/opt/unihiker-gb
MENU_UNIT=PyboardUI.service                  # the built-in UNIHIKER menu (a user service)
ROMS_DIR=/root/roms
SAVES_DIR=/root/saves

CONF=/etc/unihiker-gb/game.conf
[ -f "$CONF" ] || { echo "missing $CONF" >&2; exit 1; }
. "$CONF"
[ -f /etc/unihiker-gb/board.conf ] && . /etc/unihiker-gb/board.conf
case "${ROM_FILE:-}" in ""|*/*) echo "ROM_FILE must be a filename in $ROMS_DIR: '${ROM_FILE:-}'" >&2; exit 1;; esac
ROM_PATH="$ROMS_DIR/$ROM_FILE"
[ -f "$ROM_PATH" ] || { echo "ROM not found: $ROM_PATH" >&2; exit 1; }

# Wait for X to be up, then keep the screen on during play (item 11)
until xset q >/dev/null 2>&1; do sleep 1; done
xset s off -dpms

# Splash, then the "connect a controller" prompt if none appears (items 12, 17)
python3 "$APP/status-screen.py" &
SCREEN=$!

# Stop the built-in menu for this boot (step 8). It's started by root's desktop login, so wait
# up to 20 s for root's user manager. An explicit stop doesn't trigger its Restart=always.
for _ in $(seq 20); do [ -S "$XDG_RUNTIME_DIR/systemd/private" ] && break; sleep 1; done
systemctl --user stop "$MENU_UNIT" || echo "warning: couldn't stop $MENU_UNIT"

# Board button held at boot: skip the emulator for this boot (item 16). This runs after the
# menu is stopped, because the menu probably uses the same co-processor connection as pinpong.
if python3 "$APP/check-skip-button.py"; then
  echo "skip button held: starting the built-in menu for this boot"
  kill "$SCREEN" 2>/dev/null || true
  systemctl --user start "$MENU_UNIT"
  exit 0
fi

# Wait for a controller
until compgen -G '/dev/input/js*' >/dev/null; do sleep 1; done
kill "$SCREEN" 2>/dev/null || true

export SDL_AUDIODRIVER=dummy     # sound off (item 15)
# item 14: no SDL_GAMECONTROLLERCONFIG. mGBA 0.7.0 reads raw joystick buttons; the
# mapping is in /root/.config/mgba/config.ini (from config/mgba-config.ini).
echo "starting mGBA: $ROM_FILE"  # this timestamp in the journal is used to measure boot time (item 17)
# Save-state shortcuts (L+R+Select saves, L+R+Start loads). Runs alongside mGBA and is
# stopped with it, because systemd stops every process in the service.
/opt/unihiker-gb/hotkeys.py &
exec /usr/games/mgba -f -C savegamePath="$SAVES_DIR" -C savestatePath="$SAVES_DIR" "$ROM_PATH"
```
`chmod +x /opt/unihiker-gb/start-gb.sh`

**`status-screen.py`** (Tk, fullscreen, Python 3.7): shows `splash.png`. If no `/dev/input/js*` device has appeared after about 5 seconds, it shows the prompt from the [boot flow](#boot-flow) instead. The launcher closes it.

**`check-skip-button.py`** (uses DFRobot's preinstalled `pinpong` library; Python 3.7): exits 0 if button B is held, 1 otherwise.
- Connects with `Board("UNIHIKER").begin()` (0.9 s, confirmed), then reads `Pin(Pin.P28, Pin.IN).read_digital()` directly. B reads **0 when pressed** (confirmed). The pins are used rather than the extension's `button_b`, which lags one reading behind.
- Samples for about 0.5 s and only counts the button as held if every reading is 0, so a single glitchy reading can't skip the emulator.
- Runs after the menu is stopped (step 8), so the two don't compete for the co-processor connection on `/dev/ttyS3`.
- If `pinpong` fails to connect, it exits 1 (not held) and logs a warning, so a problem with the button never stops the game from starting.
- Total cost at boot: about 1.5 s (connect plus sampling). "Hold until the menu appears" in the prompt covers it.

### 6. Pause when the controller disconnects (item 13)

`/etc/udev/rules.d/99-unihiker-gb-controller.rules`:
```
ACTION=="remove", SUBSYSTEM=="input", KERNEL=="js[0-9]*", RUN+="/opt/unihiker-gb/controller-event.sh remove"
ACTION=="add",    SUBSYSTEM=="input", KERNEL=="js[0-9]*", RUN+="/opt/unihiker-gb/controller-event.sh add"
```
`controller-event.sh` logs each event with `logger -t unihiker-gb`, so `fetch-logs.sh` can show it, then:
- `remove`: if no `/dev/input/js*` devices are left, freeze mGBA with `pkill -STOP -x mgba`.
- `add`: resume it with `pkill -CONT -x mgba`.

Freezing the process pauses the game whatever mGBA's own pause key is, and with sound off there's no audio glitch.
- ⚠️ Test that mGBA (SDL) notices the reconnected controller after it resumes. If it doesn't, the fallback is to send mGBA's pause key with `xdotool` instead of freezing the process (`xdotool` is installed, and sending keys to mGBA works: see the save-state shortcuts in step 3).

### 7. systemd service: `/etc/systemd/system/gameboy.service`
```ini
[Unit]
Description=Game Boy emulator
After=graphical.target lightdm.service bluetooth.target
Wants=bluetooth.target

[Service]
ExecStart=/opt/unihiker-gb/start-gb.sh
Restart=on-failure
RestartSec=3
User=root

[Install]
WantedBy=graphical.target
```
```bash
systemctl daemon-reload
systemctl enable --now gameboy.service
```
When the skip button is held, `start-gb.sh` exits normally, so `Restart=on-failure` doesn't start the emulator again.

### 8. The built-in menu
The UNIHIKER's on-screen menu is `PyboardUI.service`, a systemd **user** service run by root's user manager. It isn't enabled; `/root/.xsessionrc` starts it each time lightdm logs root in (see [Board check results](#board-check-results-2026-11-11)).

**Decision: stop it at each boot; don't disable, mask or edit anything.**
- `systemctl --user disable` would do nothing, because the unit has no `[Install]` section.
- Masking it would make `.xsessionrc`'s start command fail. Debian's `/etc/X11/Xsession` runs with `set -e` and reads `.xsessionrc`, so that failure could end the whole desktop session.
- Editing `.xsessionrc` changes DFRobot's own setup and could be undone by their updates.

So `start-gb.sh` runs `systemctl --user stop PyboardUI.service` after the splash appears, and `systemctl --user start PyboardUI.service` when the skip button is held. Both need `XDG_RUNTIME_DIR=/run/user/0`, because the launcher runs as a system service. Nothing is left changed on the board, so there's nothing to restore on uninstall, and the menu comes back by itself if `gameboy.service` is disabled.

Confirmed on the board (2026-11-11): stopping the menu clears it from the screen, and starting it brings it back. The commands:
```bash
cat /root/.xsessionrc                                   # confirm how the menu is started
XDG_RUNTIME_DIR=/run/user/0 systemctl --user stop PyboardUI.service    # menu disappears
XDG_RUNTIME_DIR=/run/user/0 systemctl --user start PyboardUI.service   # menu comes back
```
Keep SSH access and the USB web UI (`startServer.py`, not affected) so you can always recover.

### 9. Test the boot flow
- Power on with no controller: the splash appears, then the prompt.
- Turn on or plug in the controller: the game starts.
- Normal power-on: the UNIHIKER menu shows for at most a moment, then the splash covers it and the menu stops (`XDG_RUNTIME_DIR=/run/user/0 systemctl --user is-active PyboardUI.service` reports `inactive`).
- Power on holding button B: the UNIHIKER menu appears instead. The next normal boot starts the game again.
- Mid-game, turn off or unplug the controller: the game freezes. Reconnect: it resumes and the controller works.
- Leave the game running without input for longer than the screen-blanking timeout: the screen stays on.
- Save in-game: the `.sav` file appears in `/root/saves/`.
- **Measure boot time** from power-on to gameplay with a stopwatch, and compare it with `systemd-analyze` and the "starting mGBA" line in `./fetch-logs.sh`. Record the result in this plan.

### 10. Change the ROM (now and later)
```bash
scripts/set-rom.sh "other game.gbc"
# checks the file exists in /root/roms/, writes ROM_FILE to game.conf, runs: systemctl restart gameboy
```

## Setup script

The goal: take a fresh UNIHIKER M10 to the configuration above with one command, and re-run that command safely at any time to apply changes.

### Scripts

| Script | Runs on | Job |
|---|---|---|
| `scripts/fetch-packages.sh` | The Mac, with Docker | Downloads the `.deb` packages once into `packages/`. Re-run only when the package list changes. |
| `deploy.sh` | The Mac | Checks ROM filenames, sets up SSH access, sets the board's clock, copies the repo files, packages and ROMs to the board, runs `install.sh` there, and optionally pairs a controller. Also pulls save backups. |
| `fetch-logs.sh` | The Mac | Shows recent emulator logs from the board. |
| `scripts/check-roms.sh` | The Mac | Flags ROM filenames that will cause problems. `deploy.sh` runs it first; it can also be run on its own. |
| `scripts/install.sh` | The UNIHIKER, as root | Does the actual system setup. Can also be run by hand on the board, or in Docker for testing. |

Keeping all the board-side logic in `install.sh` means it can be tested directly over SSH. `deploy.sh` only checks, moves files and runs it. `deploy.sh` and `fetch-logs.sh` share their host and SSH settings through `scripts/lib/common.sh`.

### `fetch-packages.sh`
Runs an arm64 Debian buster container and downloads the packages with their **full** dependency tree (about 240 packages, 80 MB):
- Uses archive.debian.org for buster, buster-updates and the buster security updates. The base image's core libraries are at security-update versions, so those sources are needed.
- Downloads the whole dependency tree (`apt-cache depends --recurse`, then `apt-get download`), not just what the container lacks. A plain `--download-only` skips libraries the container already has, such as `libc6`, and the install would then fail on a board with older versions of them.
- Writes a flat apt repository index (`Packages` and `Release`, with `apt-ftparchive`) and `packages/manifest.txt` (architecture, package list, date, git commit).
- ⚠️ If the board reports `armhf` rather than `arm64`, use `--platform linux/arm/v7`.
- Apt skips packages the board already has at the same or a newer version, and `install.sh` installs with `--no-install-recommends` to match what was downloaded.

### SSH access (items 3 and 4)
`scripts/lib/common.sh` gives every Mac script the same SSH settings:
```bash
HOST="${HOST:-10.1.2.3}"
KEY="$HOME/.ssh/unihiker-gb_ed25519"
KNOWN_HOSTS="$HOME/.ssh/unihiker-gb_known_hosts"
SSH_OPTS=(-i "$KEY" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile="$KNOWN_HOSTS")
```
- **Its own known-hosts file:** the board's key is remembered in a separate file, so the shared address 10.1.2.3 never clashes with entries in `~/.ssh/known_hosts`. `accept-new` trusts a board the first time without asking.
- **Re-flashed or different board:** its key changes, and SSH refuses to connect, as it should. `deploy.sh` recognizes this error and tells you to re-run with `--forget-host` if you've just re-flashed or swapped the board. `--forget-host` runs `ssh-keygen -R <host> -f "$KNOWN_HOSTS"`.
- **First login:** if the key is missing, `deploy.sh` creates it (`ssh-keygen -t ed25519 -N "" -f "$KEY"`). If the board doesn't accept the key yet (`ssh -o BatchMode=yes ... true` fails), it runs `ssh-copy-id` with that key. You type the default password (`dfrobot`) once; after that, no more password prompts.
- **Root password:** `--set-password` runs `ssh -t root@<host> passwd` so you can change it from the default.
- **Port:** the board uses port 22. The `UNIHIKER_SSH_PORT` environment variable overrides it, which is only needed for testing `deploy.sh` against a container.

### ROM filename check (item 10)
`scripts/check-roms.sh <file or folder>...` checks every ROM about to be deployed:
- **Stops the deploy:** quotes (`'` `"`), backticks, `$`, backslashes, control characters or newlines; a leading `-`; a `/` in the name; names over 255 bytes; two names that differ only in upper/lower case (fine on the Mac, two different files on the board).
- **Warns and continues:** spaces or brackets (they work, but are awkward to type in a shell); non-ASCII characters (macOS and Linux can store accented letters differently, so one name can turn into two files); extensions other than `.gb`, `.gbc` or `.gba`.

For each problem it prints the file and a suggested rename. `set-rom.sh` on the board applies the same "stop" rules, so a bad name can't get into `game.conf` by any route.

### Usage
```bash
./deploy.sh [options]

  --host <addr>         Board address (default: 10.1.2.3, the USB-network address)
  --rom <file>          Local ROM to copy to /root/roms/ and set as the boot game
  --roms-dir <dir>      Copy a whole folder of ROMs, e.g. ./roms (the boot game stays as it is unless --rom is given)
  --pair                After installing, pair a Bluetooth controller interactively (runs pair-bluetooth.sh)
  --bt-ertm-fix         Install the Bluetooth ERTM workaround (only for controllers that need it)
  --no-start            Install everything but don't start/restart the emulator service
  --set-password        Change the board's root password (interactive)
  --forget-host         Forget the board's SSH key first (after a re-flash or when switching boards)
  --pull-saves          Copy the board's saves into saves/<date-time>/ and stop; nothing is installed
```
Typical first run:
```bash
scripts/fetch-packages.sh                      # once, or when the package list changes
./deploy.sh --rom roms/game.gb --set-password --pair   # leave out --pair for a USB controller
```
Changing the game later:
```bash
./deploy.sh --rom roms/other-game.gbc          # copies the ROM, updates game.conf, restarts the service
```
Backing up saves, and reading logs:
```bash
./deploy.sh --pull-saves                       # saves/2026-11-11-153000/...
./fetch-logs.sh                                # last 200 lines; --follow to watch live, --lines <n>, --boot for this boot only
```

### What `deploy.sh` does
1. **ROM check:** runs `scripts/check-roms.sh` on the `--rom` and `--roms-dir` files and stops if any filename would cause problems.
2. **SSH access:** with `--forget-host`, forgets the old key first. Creates the SSH key if needed, checks that the board is reachable, and installs the key with `ssh-copy-id` if the board doesn't accept it yet (see [SSH access](#ssh-access-items-3-and-4)). If the board can't be reached, it prints how to connect (USB cable, address) and stops.
3. **Root password:** with `--set-password`, runs `passwd` on the board interactively.
4. **Clock (item 2):** sets the board's clock from the Mac: `ssh root@<host> "date -u -s @$(date -u +%s)"`.
5. **Saves (item 8):** with `--pull-saves`, copies `/root/saves/` from the board into a new `saves/<YYYY-MM-DD-HHMMSS>/` folder, using `tar` over SSH, then stops. Each backup goes to a new folder, so earlier backups are never overwritten.
6. **Staging:** checks that `packages/` contains a package index (`Packages`); if not, it tells you to run `scripts/fetch-packages.sh` and stops. (This check comes after the saves step, so `--pull-saves` works without packages.) Then writes a `VERSION` file (output of `git describe --always --dirty` and the date in UTC), then streams the repo files to a staging folder on the board, using `tar` over SSH so the board doesn't need `rsync`:
   `tar -czf - VERSION assets config launcher systemd scripts packages | ssh root@<host> 'rm -rf /tmp/unihiker-gb && mkdir -p /tmp/unihiker-gb && tar -xzf - -C /tmp/unihiker-gb'`
7. **ROMs:** copies ROMs with `scp` into `/root/roms/`, if `--rom` or `--roms-dir` was given. It never deletes anything on the board.
8. **Install:** runs `ssh root@<host> 'bash /tmp/unihiker-gb/scripts/install.sh <flags>'`, passing the matching flags through (including `--rom-file "<filename>"` when `--rom` was given).
9. **Pairing:** with `--pair`, runs `ssh -t root@<host> /opt/unihiker-gb/pair-bluetooth.sh` so you can pair from the terminal.
10. Prints `install.sh`'s summary and exits with its exit code.

### What `install.sh` does
Each step checks first and only changes what's needed, so re-running it is safe.

1. **Preflight:** must be root; check `/etc/os-release` says Debian 10, and warn (don't fail) if not; check that `dpkg --print-architecture` matches the packages, and fail if not; check there's enough free disk space. If systemd isn't running (the Docker test), say so: steps that need systemd or udev are then reported as "skipped" instead of failing.
2. **Packages (offline):** copy `packages/` to `/opt/unihiker-gb/packages/`, add the local source `/etc/apt/sources.list.d/unihiker-gb.list`, and install `mgba-sdl bluez joystick python3-tk xdotool` with apt pointed at that source only (see step 1 of the manual steps). No internet needed. Skip packages that are already installed. The board's own `sources.list` isn't touched.
3. **Folders:** create `/etc/unihiker-gb`, `/opt/unihiker-gb`, `/root/roms`, `/root/saves`, `/root/.config/mgba`.
4. **Move old saves:** move any `.sav` files from `/root/roms/` into `/root/saves/`, unless a file with the same name is already there (in that case, leave both and print a warning).
5. **Program files** (always overwritten, since they come from the repo):
   - into `/opt/unihiker-gb/`: `start-gb.sh`, `status-screen.py`, `check-skip-button.py`, `hotkeys.py`, `controller-event.sh`, `set-rom.sh`, `pair-bluetooth.sh` (scripts made executable), plus `splash.png`; an old `gamecontrollerdb.txt` from earlier versions is removed
   - `gameboy.service` into `/etc/systemd/system/`
   - the udev rule into `/etc/udev/rules.d/`, then `udevadm control --reload`
6. **Settings files** (never silently overwritten, since the user may have edited them on the board):
   - `game.conf`: install the default only if none exists. If `--rom-file` was given, write `ROM_FILE` with the same rules and quoting as `set-rom.sh`.
   - `mgba-config.ini`: install only if no mGBA config exists. If one exists and differs, save the repo version alongside it as `config.ini.repo` and print a notice.
7. **Version (item 19):** write `/etc/unihiker-gb/version` from the staged `VERSION` file plus the package manifest.
8. **Bluetooth:** `systemctl enable bluetooth`. With `--bt-ertm-fix`, install `config/bluetooth.conf` as `/etc/modprobe.d/unihiker-gb-bluetooth.conf` and set the option for the current boot too.
9. **Built-in menu:** nothing to do. The launcher stops the menu at each boot (step 8), so nothing on the board is disabled.
10. **Service:** `systemctl daemon-reload`, `systemctl enable gameboy.service`, then `systemctl restart gameboy.service` unless `--no-start`.
11. **Verify and summarize:** check that the ROM named in `game.conf` exists; that `systemctl is-active gameboy` reports active (after a few seconds' wait); that `python3 -c 'import pinpong'` works (warn only: without it the skip button doesn't work, but the game still runs); and whether a controller is visible (`/dev/input/js*`; warn only, since a Bluetooth controller may not be connected yet). Print the installed version and a short pass/warn/fail list, plus the last lines of `journalctl -u gameboy` if the service failed.

### `fetch-logs.sh` (item 22)
Runs on the Mac, with the same `--host` option and SSH settings as `deploy.sh`. It shows the controller events (`journalctl -t unihiker-gb --no-pager`) followed by the `gameboy` service log (`journalctl -u gameboy --no-pager`), so the service log can be followed live at the end.
- `--lines <n>`: how many recent lines of each (default 200).
- `--boot`: only this boot (`-b`).
- `--follow`: keep watching the service log live (`-f`) until Ctrl+C.

### `pair-bluetooth.sh`
Needs a person: put the controller in pairing mode, pick it from a list. `deploy.sh --pair` runs it at the end of a deploy, and it can also be run on its own later to pair a new controller. It runs a `bluetoothctl` scan for about 15 seconds, lists the devices it found, asks which one to use, then runs `pair`, `trust` and `connect` on it. Afterwards it restarts `gameboy.service` so mGBA sees the controller.

### Script conventions
- **Board scripts:** `#!/bin/bash` with `set -euo pipefail`, bash 5.0 (buster). Python scripts must run on Python 3.7.
- **Mac scripts:** must also run on the bash 3.2 that ships with macOS. That rules out associative arrays, `mapfile` and `${var,,}`. Plain arrays are fine.
- Only tools already on the board or in the packages above, and on the Mac only what macOS ships plus Docker for `fetch-packages.sh` and `test-in-docker.sh`.
- Every step prints a one-line `==> ...` header, so a failure is easy to locate.
- Nothing is deleted except the `/tmp/unihiker-gb` staging folder. Files that get replaced are backed up first.
- SSH and the USB web UI are never touched, so the board stays recoverable.
- Quote every path, even though `check-roms.sh` filters out the worst filenames.
- Check with `shellcheck` before committing (CI enforces it).

### Later: `uninstall.sh`
Stop and disable `gameboy.service`, remove `/opt/unihiker-gb`, the unit file, the udev rule and the local apt source. The built-in menu was never disabled, so it comes back on the next boot. Leave ROMs, saves and `/etc/unihiker-gb` alone unless `--purge` is given.

### Testing the scripts (item 21)
**Without hardware:** `scripts/test-in-docker.sh` starts an arm64 Debian buster container (the same kind `fetch-packages.sh` uses), with the repo and `packages/` mounted, and runs `install.sh` twice. The first run must pass, apart from the systemd/udev steps reported as skipped and the `pinpong` and controller warnings. The second run must change nothing.

**CI** (`.github/workflows/ci.yml`, GitHub Actions, on every push and pull request):
- `shellcheck` on every `.sh` file.
- `python3 -m py_compile` on the launcher's Python scripts.
- `scripts/check-roms.sh` against a set of test filenames (good and bad ones, as empty files).
- `fetch-packages.sh` and `test-in-docker.sh`, with arm64 emulation via `docker/setup-qemu-action`. This is the slow job, since it downloads packages from archive.debian.org and runs under emulation.

**On a real board:**
- Run `install.sh` twice in a row. The second run should change nothing and report everything as passing.
- Test a fresh board (or a re-flashed image) from start to finish, with no Wi-Fi configured, to confirm the install is fully offline. This also covers the first-login key setup and `--forget-host`.
- Test `./deploy.sh --rom` with a second ROM and confirm the board switches games without a reboot.
- Test `./deploy.sh --pair` with a Bluetooth controller.
- Test `./deploy.sh --pull-saves` and `./fetch-logs.sh`.
- Run the boot-flow checks in step 9, including measuring boot time.

## Recovery (item 6)

`docs/recovery.md` documents how to get a board back, from least to most drastic:
1. **Skip the emulator for one boot:** hold button B at power-on (item 16).
2. **Turn the emulator off:** `ssh root@10.1.2.3 'systemctl disable --now gameboy'`. The built-in menu comes back on the next boot, or straight away with `XDG_RUNTIME_DIR=/run/user/0 systemctl --user start PyboardUI.service`.
3. **Restore the factory image** (last resort):
   - First, back up saves with `./deploy.sh --pull-saves` if the board still boots. Re-flashing erases ROMs and saves.
   - ⚠️ Fill in from DFRobot's UNIHIKER documentation: where to download the official image, which flashing tool runs on macOS, how to put the board into flashing mode, and how long it takes.
   - Afterwards, on the Mac: `./deploy.sh --forget-host` with the usual first-run options, then copy saves back into `/root/saves/` if needed.

## Considerations

The project's goal is to make deploying and configuring the UNIHIKER as simple as possible. As of 2026-11-11, every item below has a decision, and each one says where it's built into the plan.

### Controller pairing

| Option | How it works | How simple |
|---|---|---|
| **A. During deploy** | `deploy.sh --pair` runs `pair-bluetooth.sh` over `ssh -t` at the end. The user puts the controller in pairing mode and picks it from a list in the terminal. | Simple; one command does everything |
| **B. Auto-pair on the board** | At boot, if no trusted controller is found, the board scans for gamepads in pairing mode (Bluetooth devices that identify as gamepads) and pairs and trusts the first one. The screen shows "Hold your controller's pairing button". | Simplest; no computer needed after deploy |
| **C. Button trigger** | Holding the board's onboard A or B button at boot starts pairing mode (this uses `pinpong`). | Good for swapping controllers later |

**Decision:** **A** for the first version (built into `deploy.sh --pair`), **B** as the long-term default (listed under [Future improvements](#future-improvements)). B also covers a lost or replaced controller without needing a computer. Its downside is that a nearby gamepad in pairing mode could get paired instead, which is acceptable at home. USB controllers need no pairing.

### Deployment

1. **No internet over USB.** The USB connection probably only reaches the computer it's plugged into, so downloading packages on the board would fail.
   **Decision:** offline packages. `scripts/fetch-packages.sh` downloads the arm64 buster `.deb` files on the Mac with Docker, into `packages/` (gitignored), and `install.sh` installs them from that local folder. No network setup needed, and installs come out the same every time.
2. **Wrong clock.** The board may boot with a wrong date, which affects log timestamps and file dates.
   **Decision:** `deploy.sh` sets the board's clock from the Mac on every deploy (`deploy.sh` step 4).
3. **SSH host keys.** Every board, and every re-flash, uses the same address, 10.1.2.3, so SSH refuses the connection with a "host key changed" warning.
   **Decision:** the Mac scripts use `StrictHostKeyChecking=accept-new` with their own known-hosts file, and `--forget-host` clears it after a re-flash (see [SSH access](#ssh-access-items-3-and-4)).
4. **First login.** `ssh-copy-id` asks for the default password.
   **Decision:** `deploy.sh` creates a dedicated SSH key and installs it on the board itself, and `--set-password` optionally changes the root password (see [SSH access](#ssh-access-items-3-and-4)).
5. **The computer running deploy.**
   **Decision:** macOS only. The board's USB network connection works on macOS without a driver (confirmed), but the first connection needs "Allow accessories to connect" set to "Always", because the "Allow" prompt disappears too quickly to click. Mac scripts must run on macOS's bash 3.2.
6. **Re-flash path.**
   **Decision:** document how to restore the board's factory image, as the last-resort recovery, in `docs/recovery.md` (see [Recovery](#recovery-item-6)).

### Game saves and data

7. **Saves sit next to ROMs.** By default mGBA writes `.sav` files into `/root/roms/`.
   **Decision:** keep saves in a separate folder, `/root/saves/`, set with mGBA's `savegamePath` option in the launcher. `install.sh` moves existing saves there. `deploy.sh` never deletes anything on the board.
8. **Backups.**
   **Decision:** `deploy.sh --pull-saves` copies saves back to the Mac, into a new dated folder under `saves/` (gitignored) each time.
9. **Power loss.** The board will probably just get unplugged.
   **Decision:** do nothing. The risk of losing the most recent in-game save is accepted.
10. **Awkward filenames.**
    **Decision:** ROMs are chosen by filename (`ROM_FILE`), not by path. `scripts/check-roms.sh` flags troublesome filenames before every deploy, and `set-rom.sh` applies the same rules on the board (see [ROM filename check](#rom-filename-check-item-10)).

### Playing the game

11. **Screen blanking.** X may blank the screen during play when no input reaches it.
    **Decision:** the launcher turns blanking off with `xset s off -dpms` (step 5).
12. **No controller connected.**
    **Decision** (follows from item 16): show a prompt on screen ("Connect a controller") instead of starting a game nobody can control. Built into the [boot flow](#boot-flow) and `status-screen.py`.
13. **Controller goes to sleep.**
    **Decision:** mGBA pauses when the controller disconnects and resumes when it reconnects. Built in as a udev rule plus `controller-event.sh` (step 6). Testing reconnect is in step 9.
14. **Mapping differs by controller model.**
    **Decision:** use SDL's community controller database ([`gamecontrollerdb.txt`](https://github.com/gabomdq/SDL_GameControllerDB)), which maps most common gamepads automatically. A copy is kept in `config/` and loaded by the launcher. ⚠️ Check that buster's mGBA honors it (step 3); if not, fall back to per-controller sections in `mgba-config.ini`.
    **Result (2026-11-11):** it doesn't. mGBA 0.7.0 ignores the database, so mappings live in `config/mgba-config.ini` (`[gba.input.SDLB]`, plus `[gba.input-profile.<name>]` per controller model). `gamecontrollerdb.txt` has been removed from the repo; install.sh deletes a copy left on the board by earlier versions.
15. **Audio.** ⚠️ The M10 may have only a buzzer, not a speaker.
    **Decision:** sound off (which also saves CPU), using `SDL_AUDIODRIVER=dummy` in the launcher.
16. **Getting back to the UNIHIKER menu.** The launcher stops the built-in menu at each boot, so without a skip option there's no way back except SSH.
    **Decision:** holding a board button at boot skips the emulator for one boot, and the no-controller prompt explains how. Built in as `check-skip-button.py`, which starts `PyboardUI.service` again (step 8). Confirmed: `pinpong` is preinstalled, connects in 0.9 s, and button B is `P28` (0 when pressed).
17. **Boot time and progress.**
    **Decision:** measure the time from power-on to playing (step 9), and show a splash screen while it starts so the screen isn't blank. A placeholder `assets/splash.png` is committed to the repo and installed on every deploy.
18. **CPU speed.**
    **Decision:** no change up front. It's documented under [Likely problems](#likely-problems), to be addressed if stuttering actually happens.

### Maintenance

19. **Version stamp.**
    **Decision:** `deploy.sh` records the git commit (marked if there are uncommitted changes) and the deploy date, and `install.sh` writes them, with the package manifest, to `/etc/unihiker-gb/version`.
20. **More than one board.**
    **Decision:** ignore for now. Moved to [Future improvements](#future-improvements).
21. **Testing without hardware.**
    **Decision:** run `install.sh` in an arm64 Debian buster Docker container (`scripts/test-in-docker.sh`), and run `shellcheck` and the Docker test in GitHub Actions CI (see [Testing the scripts](#testing-the-scripts-item-21)).
22. **Logs.**
    **Decision:** a `fetch-logs.sh` script on the Mac shows recent `gameboy` service logs and controller events (see [`fetch-logs.sh`](#fetch-logssh-item-22)).

## Decided

| Decision | Choice |
|---|---|
| **Main input** | USB or Bluetooth controller. Both appear as `/dev/input/js*`. |
| **Game selection** | One ROM, chosen by filename in `game.conf` (item 10). |
| **Deploy computer** | macOS only (item 5). |
| **Packages** | Installed offline from `.deb` files downloaded on the Mac with Docker (item 1). |
| **SSH** | Dedicated key and known-hosts file, set up by `deploy.sh`; `--forget-host` after a re-flash (items 3, 4). |
| **Clock** | Set from the Mac on every deploy (item 2). |
| **Pairing** | `deploy.sh --pair` for now; auto-pair on the board later. |
| **Controller mapping** | Button numbers in `config/mgba-config.ini`; mGBA 0.7.0 ignores SDL's controller database (item 14). |
| **Save states** | L+R+Select saves, L+R+Start loads (slot 1), through `launcher/hotkeys.py` and `xdotool`; state files go to `/root/saves/`. |
| **Controller disconnect** | Pause mGBA, resume on reconnect (item 13). |
| **Audio** | Off (item 15). |
| **Screen blanking** | Off during play (item 11). |
| **Boot screens** | Splash image, then a "connect a controller" prompt that explains the skip button (items 12, 17). |
| **Escape hatch** | Hold a board button at boot to start the UNIHIKER menu for one boot (item 16). |
| **Built-in menu** | `PyboardUI.service` (a user service) is stopped by the launcher at each boot; never disabled, masked or edited (step 8). |
| **Saves** | Kept in `/root/saves/`; backed up with `deploy.sh --pull-saves`; no protection against power loss (items 7, 8, 9). |
| **Version stamp** | `/etc/unihiker-gb/version` (item 19). |
| **Testing** | Docker test plus shellcheck in GitHub Actions (item 21). |
| **Logs** | `fetch-logs.sh` (item 22). |
| **Recovery** | `docs/recovery.md` (item 6). |

## Future improvements

| Item | Notes |
|---|---|
| **Auto-pair on the board** | Pairing option B: pair the first gamepad in pairing mode when no trusted controller is found at boot. |
| **Game picker** | A menu that lists `/root/roms`, is driven by the controller, writes `ROM_FILE` to `game.conf` and restarts the service. |
| **More than one board** | Per-board settings (for example `boards/<name>.conf`) and a `--host` value per board (item 20). |
| **Exit / switch-game combo** | Map a controller button combo (e.g. Select+Start held) to quit mGBA. The service would then bring up the picker. |
| **Onboard A/B buttons as game input** | `pinpong` is now used at boot for the skip check (item 16). Using the buttons during play, through a `uinput` bridge, stays low priority. |
| **Real splash artwork** | Replace the placeholder `assets/splash.png`. |
| **`uninstall.sh`** | See [Later: `uninstall.sh`](#later-uninstallsh). |

## Likely problems
- **Mac can't reach 10.1.2.3 (`ssh` times out):** check System Settings → Network for the board's USB interface. If there isn't one, macOS hasn't allowed the accessory: see Board check results. With a VPN on, traffic goes through the VPN until that interface exists.
- **Packages don't match the board:** if `install.sh` fails its architecture check or apt reports missing dependencies, re-run `fetch-packages.sh` with the right `--platform`, and check whether the board has DFRobot-modified versions of the packages.
- **"Host key changed" when deploying:** expected after a re-flash or when switching boards. Re-run with `--forget-host`.
- **Bluetooth reconnects:** if the controller doesn't come back after a reboot, check that it's `trust`ed and that `bluetooth.service` is enabled.
- **Controller not seen by mGBA:** confirm it works in `jstest` first. If it does, the problem is the mapping in `/root/.config/mgba/config.ini` (`[gba.input.SDLB]`), not the device.
- **Game doesn't resume after reconnect:** see the fallback in step 6.
- **Performance (item 18):** if mGBA stutters, first keep the CPU at full speed. The board has no `performance` governor (only `ondemand`, `userspace` and `interactive`), so use `userspace` fixed at the top frequency:
  ```bash
  cd /sys/devices/system/cpu/cpu0/cpufreq
  echo userspace > scaling_governor && cat scaling_max_freq > scaling_setspeed
  ```
  (Alternative: keep `ondemand` and run `cat scaling_max_freq > scaling_min_freq`.) If that fixes it, add it to the launcher. If not, try `gnuboy`, which is lighter. Sound is already off.
- **Emulator or splash can't open the display** ("cannot open display" or "No protocol specified" in `./fetch-logs.sh`): check that `XAUTHORITY` in the launcher points at a file that exists (`/var/run/lightdm/root/:0`, or `/root/.Xauthority`).
- **Menu not stopped** ("couldn't stop PyboardUI.service"): root's user manager wasn't running yet. Check `ls /run/user/0/systemd/private` and raise the 20-second wait in the launcher.
- **Screen orientation:** if the picture comes out rotated or stretched, check the X screen settings before blaming mGBA.
