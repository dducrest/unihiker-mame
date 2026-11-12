# Plan: landscape (horizontal) display

Revises [initial-planning.md](initial-planning.md) so the game is shown on a horizontal screen. The UNIHIKER boots in portrait (240×320).

## Status (2026-11-13)

**Option B built and running on the board.** Phase 0 showed the board's display driver can't rotate at runtime, so option A doesn't work there ([Phase 0 results](#phase-0-results-2026-11-13)). Option B, rotation in the X server configuration, works and was deployed with `./deploy.sh`: the splash, the prompt and the game are landscape (320×240, turned `right`).

| Part | Status |
|---|---|
| `launcher/set-rotation.sh` | Built, option B. Writes `/etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf` (the board's fbdev Device section plus `Option "Rotate"`), or removes it for `normal`. `--from-config` reads `DISPLAY_ROTATION` from `board.conf`; a bad value means portrait, with a warning. Prints `changed` when it changed the file. Takes effect when X next starts. |
| `systemd/unihiker-gb-display.service` | Built. Runs `set-rotation.sh --from-config` at every boot, before the desktop starts. That restores the rotation after a skip-button boot. Ran under systemd on the board. |
| `start-gb.sh` | The screen is already rotated when X starts, so the launcher doesn't rotate. **Skip button:** if the screen was rotated, it removes the rotation and restarts the desktop (`systemctl restart --no-block lightdm`). The new desktop login starts the menu in portrait. Without rotation, it starts the menu as before. **Works on the board (2026-11-13):** holding B at power-on brought up the menu in portrait, and the next boot was landscape again. |
| `gameboy.service` | Unchanged from before this plan: no `ExecStopPost`. Stopping the service leaves the desktop rotated. |
| `status-screen.py`, `assets/splash-landscape.png` | Built. Picks the splash by screen shape. Landscape prompt seen on the board; both splashes checked on virtual displays. |
| mGBA scaling | **Stretched, accepted (2026-11-13).** mGBA 0.7.0's SDL build fills the whole 320×240 and ignores `lockAspectRatio`, both in the config file and with `-C`, so Game Boy games are about 20% too wide. The setting was removed from `config/mgba-config.ini`. |
| `deploy.sh --rotate`, `install.sh --rotate` | Built. `install.sh` writes `board.conf` and the X file, enables `unihiker-gb-display.service`, and restarts the desktop when the X file changed (stopping the game first). With `--no-start`, the change applies from the next boot. The verify step checks the screen size with `xrandr -q`: `PASS screen orientation: right (320 x 240)` on the board. |
| Docker test | Covers `--rotate` (each direction's `Rotate` value, `normal` removes the file, `.bak`, no change on re-run, bad value refused), `set-rotation.sh` (`--from-config`, bad setting) and both skip-button paths (rotated: desktop restart and next boot rotates again; portrait: menu started). The stand-in `xrandr` from option A was removed. |
| Default direction | **`right`** (`DEFAULT_ROTATION` in `install.sh`), chosen 2026-11-12. |
| On-board tests (2026-11-13) | Skip button: menu in portrait. Reboot: landscape again. Game Boy play speed: good. Touch works in the menu after the skip-button restart. Boot time unchanged from portrait (28 s). |

The rest of this section is from the plan's revision before building option A. It explains how the plan was matched to the code that existed then.

This revision brings the plan in line with what the initial plan has built since the first draft. The launcher, splash and prompt, skip button, controller pause, save-state shortcuts and Bluetooth all work on the board now (see the initial plan's [Implementation status](initial-planning.md#implementation-status-2026-11-11)). What that changes here:

| Then (first draft) | Now | Effect on this plan |
|---|---|---|
| `start-gb.sh` was a sketch | Built, with eight numbered steps (config check, wait for X, splash, stop the menu, skip check, wait for a controller, hotkeys, mGBA) | The changes below refer to those steps by number. |
| Unknown whether `xrandr` was installed | `xset` and `xrandr` are preinstalled in `/usr/bin` (Board check results) | `xrandr` doesn't need packaging. `xdpyinfo` is no longer needed: `set-rotation.sh` reads the size from `xrandr -q`. |
| `status-screen.py` might hard-code 240×320 | It already reads the screen size and wraps the prompt to the width | Only the choice of splash image is left to add. |
| `install.sh` left an existing mGBA config alone (`config.ini.repo`) | The repo's `config/mgba-config.ini` is installed on every deploy, with a dated backup of hand edits | The aspect-ratio settings reach the board with a normal deploy; no manual copying. |
| `board.conf` was planned | `start-gb.sh` reads it if present, but `install.sh` never writes it | `--rotate` will be the first thing that creates it. |
| mGBA speed unknown | Runs smoothly in portrait at default CPU settings | That's the baseline to compare the rotated speed against. |
| Boot time unknown | 28 s from power-on to playable; the launcher's part is about 2 s | Re-measure after rotation; it should add well under a second. |

## Why

| | Portrait 240×320 (today) | Landscape 320×240 |
|---|---|---|
| Game Boy / Color (160×144) | Scaled 1.5×, to 240×216 | Scaled 1.67×, to 266×240: about 23% bigger |
| Game Boy Advance (240×160) | Shown at 1×, 240×160 | Scaled 1.33×, to 320×213: about 78% bigger |
| Empty screen area | 104 px band at the bottom | Two narrow side bars |
| Held with a controller | Tall, unlike a TV or handheld | Wide, like a TV or handheld |

## Goals

- While the emulator runs, the screen is horizontal: the splash, the "connect a controller" prompt and the game.
- The rotation direction (90° left or right) is a setting, because which way is "up" depends on how the board is mounted or stood up.
- **The escape hatch is unaffected:** when button B is held at boot, the built-in UNIHIKER menu still appears in portrait, the way it was designed, with the touchscreen working normally. (Option B: after a desktop restart.)
- Turning the rotation off is a single setting, without re-flashing.
- Deploying stays one command: `./deploy.sh --rotate right`.

## Non-goals

- Rotating the boot console text that appears before the desktop starts. It's only on screen for a few seconds, and changing it means changing the kernel or device tree.
- Rotating the built-in UNIHIKER menu.
- Touch input during play. Nothing in the emulator flow uses the touchscreen.

## How the rotation could be done

| Option | How it works | Affects only the emulator? | Risk |
|---|---|---|---|
| **A. Rotate at runtime with `xrandr`** (recommended) | `start-gb.sh` runs `xrandr -o left` before the splash, and turns it back to `normal` when the emulator stops or the skip button is used. | **Yes.** The menu and touch stay as they are. | Works only if the board's X display driver supports RandR rotation. ⚠️ Phase 0 finds out. |
| **B. Rotate in the X server configuration** (fallback) | A file in `/etc/X11/xorg.conf.d/` sets the display driver's `Rotate` option (`CCW` or `CW`). X starts rotated. | **No.** Everything on the desktop is rotated, including the built-in menu. The touchscreen needs a matching transform with `xinput`, or touches land in the wrong place. | Changing it needs X to restart. The menu is probably laid out for portrait only. |
| **C. Rotate in the kernel display driver** | A rotation option for the panel's kernel driver (device tree or module option). | **No.** The whole system, including the boot console. | Board-specific, may need a re-flash to undo, easy to make the board unbootable. **Rejected.** |
| **D. Rotate inside the apps** | mGBA and the Tk status screen draw rotated output themselves. | Yes | mGBA 0.7.0 (SDL build) has no option for rotated output. **Rejected.** |

**Recommendation:** A if Phase 0 shows it works, otherwise B. Only the chosen option gets built; the other stays documented here.

## Phase 0: board checks (about 15 minutes)

Over SSH with the board connected. Stop the emulator first, so it doesn't hold the screen or restart in the middle of the checks:
```bash
systemctl stop gameboy
export DISPLAY=:0 XAUTHORITY=/var/run/lightdm/root/:0                   # same as start-gb.sh
grep -iE 'driver|fbdev|modesetting|fbturbo' /var/log/Xorg.0.log | head  # which X display driver
ls /etc/X11/xorg.conf /etc/X11/xorg.conf.d /usr/share/X11/xorg.conf.d 2>/dev/null
command -v xinput                                                       # only needed for option B
xrandr -q                                                               # output name, supported rotations, "current W x H"
xrandr -o left;  sleep 5; xrandr -q | head -1                           # expect "current 320 x 240", and look at the screen
xrandr -o right; sleep 5
xrandr -o normal
xinput list                                                             # touchscreen device name (option B only)
```
Then, rotated (`xrandr -o left`), run mGBA by hand the way the launcher does, and play for a minute:
```bash
SDL_AUDIODRIVER=dummy /usr/games/mgba -f -C savegamePath=/root/saves -C savestatePath=/root/saves /root/roms/<rom>
```
Compare its CPU use in `top` with the same game in portrait. Rotation copies every frame through a shadow buffer, so it costs some CPU. While it runs, also check:
- **Scaling:** does the game fill the 240-pixel height without stretching? If not, try again with `-C lockAspectRatio=1` (and `-C lockIntegerScaling=0`) on the command line. The `-C` mechanism is known to work with this mGBA (the launcher already uses it for the save paths), so this tests whether 0.7.0's SDL renderer honors the keys.
- **Portrait, for reference:** note whether today's portrait picture already keeps its aspect ratio (240×216 with a band at the bottom) or is stretched to 240×320. That shows what mGBA does by default.
- **Save-state shortcuts and pause** still work rotated (L+R+Select, L+R+Start; unplug the controller). They don't depend on the screen, but it's a one-minute check.

Finish with `xrandr -o normal` and `systemctl start gameboy`.

| Result | Decision |
|---|---|
| `xrandr -o left` turns the picture and `xrandr -q` reports `current 320 x 240` | **Option A** |
| `xrandr` reports no rotations, or the picture doesn't change | Try option B by hand: add the driver's `Rotate` option to an `xorg.conf.d` file, then restart X (or reboot). If that works, **option B** |
| Neither works | Stop. Landscape isn't available on this board without kernel changes; record that here. |
| Rotated mGBA uses so much CPU that the game stutters | Try the other option; if both stutter, see [Risks](#risks) |

Also record:
- **Which direction is "up"** for how the board will actually be used (where the USB port, the A/B buttons and the cable end up). The default is `right`; if that's upside down in use, change `DEFAULT_ROTATION` in `install.sh`.
- The results, as new rows in the initial plan's [Board check results](initial-planning.md#board-check-results-2026-11-11): display driver, supported rotations, rotated CPU use, scaling.

### Phase 0 results (2026-11-13)

| Check | Result |
|---|---|
| X display driver | `fbdev` on `/dev/fb0` (panel `fb_ili9341`, 16-bit), with a shadow framebuffer. Configured by DFRobot's `/etc/X11/xorg.conf.d/20-modesetting.conf` (Device "Rockchip Graphics"). Touch: `tslib` driver, calibration in `99-ns2009-cal.conf`. |
| Option A (`xrandr -o right`) | **Fails.** `xrandr --verbose` lists only `normal`; the driver has no runtime rotation. |
| Option B (`Option "Rotate" "CW"`, X restarted) | **Works.** X starts at 320×240, turned clockwise ("rotating screen clockwise" in the X log). A file named `10-…` is read before DFRobot's `20-…` file, and X uses the first Device section, so DFRobot's file stays untouched. |
| CPU, rotated | mGBA uses one core (~100% of it), X ~22% of another; the board is ~68% idle overall. No portrait figure to compare against yet. |
| mGBA scaling | Stretched to the full 320×240. `lockAspectRatio=1` is ignored in the config file and with `-C`. |
| UNIHIKER menu, rotated | **Not usable:** it's drawn for 240×320, so it's cut off at the bottom ("Long press HOME butto…"). Hence the skip button restarts the desktop in portrait. |

## Design (option A; not used: the board can't rotate at runtime)

### Setting
`/etc/unihiker-gb/board.conf` gets a new value, written by `install.sh`:
```bash
DISPLAY_ROTATION=right     # left | right | inverted | normal
```
- `normal` turns rotation off. A missing value also means `normal`, so boards deployed before this change keep working unchanged.
- **Default:** `right` (decided 2026-11-12), applied on the first deploy if no value is set yet. Later deploys only change it when `--rotate` is given, like `--rom-file` for `game.conf`.
- `board.conf` doesn't exist on boards today. `set_conf_var` (in `scripts/lib/rom-rules.sh`) already creates the file if it's missing, so no new helper is needed.

### Boot flow changes
The launcher's steps (see [`launcher/start-gb.sh`](../launcher/start-gb.sh) and the initial plan's [step 5](initial-planning.md#5-launch-script-optunihiker-gbstart-gbsh)), with the changes in bold:

1. Check `game.conf`, the ROM and mGBA (exit 2 on a problem). **Unchanged: nothing is rotated yet, so a config error leaves the menu in portrait.**
2. Wait for X and turn off screen blanking, **then rotate the screen to `DISPLAY_ROTATION`**.
3. Splash screen (`status-screen.py`), **with the image that matches the rotated screen**.
4. Stop the built-in menu. Unchanged.
5. Skip check: if button B is held, close the splash, **rotate the screen back to `normal`**, start the built-in menu, exit 0.
6. Wait for a controller (the prompt is laid out for the rotated screen).
7. Save-state shortcuts (`hotkeys.py`). Unchanged: `xdotool` sends keys, which doesn't depend on orientation.
8. mGBA starts in fullscreen and **fills the 320×240 screen, keeping the game's aspect ratio**.
9. **New: when the service stops** (for any reason, including `systemctl stop`, a crash, or `install.sh` restarting it), the screen is rotated back to `normal`.

The splash is shown only after rotating, so it never flashes up in portrait first. The cost: the built-in menu, which lightdm has already started, is on screen rotated for the moment between step 2 and the splash covering it. That's the same brief flash as today, only sideways. Rotating after step 4 instead would avoid it, but then the splash would appear in portrait first.

The rotation needs no change to `controller-event.sh` (it only freezes and resumes the mGBA process) or to the udev rule.

### New script: `launcher/set-rotation.sh`
`set-rotation.sh <left|right|inverted|normal>`, installed to `/opt/unihiker-gb/`:
1. Rejects any other value (exit 2).
2. Sets `DISPLAY=:0` and `XAUTHORITY=/var/run/lightdm/root/:0` if they aren't set, so `ExecStopPost` and SSH sessions can call it as is.
3. Does nothing if the screen is already in that orientation, so it's safe to call twice (it is called twice after a skip-button boot: step 5, then `ExecStopPost`).
4. Runs `timeout 5 xrandr -o <value>`. The timeout matters at shutdown, when `ExecStopPost` can run after X is gone.
5. Checks the result from `xrandr -q` (`current 320 x 240` for `left`/`right`, `current 240 x 320` for `normal`/`inverted`).
6. If the rotation failed, logs a warning to stderr (the journal, so `./fetch-logs.sh` shows it) and **exits 0**. A failed rotation leaves the game in portrait; it must never stop the game from starting.

Keeping it as its own script means `start-gb.sh`, the service's stop hook and a person debugging over SSH all rotate the same way.

### `start-gb.sh` (changes only)
```bash
# step 2, after the xset lines:
"$APP/set-rotation.sh" "${DISPLAY_ROTATION:-normal}"

# step 5, in the skip-button branch, after close_screen and before starting the menu:
"$APP/set-rotation.sh" normal
```
`board.conf` is already sourced in step 1, so `DISPLAY_ROTATION` is available. Update the step list in the script's header comment to match.

### `gameboy.service` (change only)
```ini
[Service]
ExecStopPost=/opt/unihiker-gb/set-rotation.sh normal
```
`ExecStopPost` runs however the service ends, so the desktop is never left sideways. It also runs after an exit 2 (config error) or a skip-button boot; `set-rotation.sh` does nothing there because the screen is already in portrait. With `Restart=on-failure`, a crash briefly turns the screen to portrait before the restart turns it back; that's acceptable. Update the copy of the unit in the initial plan's step 7.

### Splash and status screen
- **Assets:** keep `assets/splash.png` (240×320) for portrait and add `assets/splash-landscape.png` (320×240), a placeholder with the project name like the portrait one, until there's real artwork (initial plan, Future improvements).
- **`status-screen.py`:** it already reads the screen size (`winfo_screenwidth()`/`winfo_screenheight()`) and wraps the prompt to the width. Add: when the screen is wider than tall, use `splash-landscape.png` from the same folder, falling back to `splash.png` if it's missing. `--splash` still overrides both. If rotation failed, the screen is portrait, so the portrait splash shows correctly.
- ⚠️ The prompt (font size 12, five short paragraphs) was checked to fit on a virtual 240×320 display. Check it on a virtual 320×240 display too: it's wider but 80 px shorter.

### mGBA scaling
In `config/mgba-config.ini`, in the `[ports.sdl]` section, which exists but is empty today:
```ini
[ports.sdl]
lockAspectRatio=1
lockIntegerScaling=0
```
- Fills the 240-pixel height at 1.67× for Game Boy games, with bars at the sides, and doesn't stretch the picture.
- Every deploy installs the repo's mGBA config (with a dated backup of any hand edits), so no manual step is needed on the board.
- ⚠️ Phase 0 shows whether mGBA 0.7.0 honors these keys. If it only honors them on the command line, add `-C lockAspectRatio=1 -C lockIntegerScaling=0` to the `exec` line in `start-gb.sh` instead, and update the Docker test's exact-match check on mGBA's command line.
- If Phase 0 shows mGBA already keeps the aspect ratio by default, write the keys anyway, so the behavior doesn't depend on a default.

### Deploy and install
- **`deploy.sh`:** new option `--rotate <left|right|inverted|normal>`, checked with `need_value` and passed through `INSTALL_ARGS`. Add it to the help comment at the top, and widen the `sed -n '2,21…'` range in `usage()` to match.
- **`install.sh`:**
  - New option `--rotate`. It checks the value; if it differs from what's in `board.conf`, it keeps a `board.conf.bak` (like `game.conf.bak`) and writes `DISPLAY_ROTATION` with `set_conf_var`. On the first deploy with no value set, it writes the default. Add it to the help comment and widen `usage()`'s `sed` range (`2,16`).
  - Installs `set-rotation.sh` and `splash-landscape.png` with the other program files (step 5 of `install.sh`).
  - **Packages:** none to add for option A: `xrandr` is preinstalled. (Option B would add `xinput`, in both `install.sh` and `scripts/fetch-packages.sh`, which must stay in sync.)
  - **Verify step:** if `xrandr -q` works (X running, so not in Docker), check that it lists the configured direction among the supported rotations. Warn (don't fail) if it doesn't: the game still runs, in portrait. Report `DISPLAY_ROTATION` in the summary.
- **`set-rom.sh`, `pair-bluetooth.sh`, `fetch-logs.sh`, `hotkeys.py`, `controller-event.sh`:** no changes.
- **README:** document `--rotate` with the other deploy options.

## Design (option B, built)

What changes compared with option A:
- **`set-rotation.sh` writes the X config instead of calling `xrandr`.** It writes `/etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf`, with the display driver's `Rotate` option (`CCW` for left, `CW` for right, `UD` for inverted) in a copy of the board's Device section. `normal` removes the file. The change takes effect when X restarts, so `install.sh` restarts the desktop (`lightdm`) when the file changed, after stopping the game.
- **`unihiker-gb-display.service`** (oneshot, before `lightdm`) runs `set-rotation.sh --from-config` at every boot.
- **Escape hatch:** the menu is cut off when rotated (Phase 0), so the skip-button branch removes the rotation file and restarts the desktop; the new login starts the menu in portrait. The next boot, `unihiker-gb-display.service` writes the file again. The cost is a few seconds and an X restart, on the skip path only.
- **Touchscreen:** not needed. Touch is only used in the menu, which is always portrait.
- **No `ExecStopPost`:** the rotation is fixed while X runs. Stopping `gameboy.service` leaves the desktop rotated; `./deploy.sh --rotate normal` turns it off.

## Changes to `initial-planning.md`

Once Phase 0 picks an option, update the existing plan:

| Section | Change |
|---|---|
| Goals | Add: the screen is horizontal while the emulator runs. |
| Implementation status | Add rows for `set-rotation.sh`, the landscape splash and `--rotate`. |
| Board check results | Add the Phase 0 results (driver, rotations, CPU use, scaling, direction). |
| Next steps | Add the on-board tests below while they're pending. |
| What you're working with | Display row: "240×320 portrait; rotated to 320×240 landscape while the emulator runs". Game Boy scaling: 1.67×, to 266×240. The splash comes in two sizes. |
| Architecture | Add `set-rotation.sh` and `splash-landscape.png`. Change the `board.conf` line: it now holds `DISPLAY_ROTATION` (and optional overrides such as `MENU_UNIT`). |
| Boot flow | The changes listed under [Boot flow changes](#boot-flow-changes). |
| Repository layout | Add `launcher/set-rotation.sh` and `assets/splash-landscape.png`; the splash note (240×320 placeholder) mentions the landscape one. |
| Step 5 (launch script) | Rotation in steps 2 and 5; `status-screen.py` picks the splash by screen shape. |
| Step 7 (systemd service) | `ExecStopPost`. |
| Step 9 (test the boot flow) | Add the on-board tests below. |
| Setup script | `--rotate` in Usage, `deploy.sh` and `install.sh`. |
| Decided | New row: **Display orientation**: landscape while the emulator runs, direction set by `--rotate`. |
| Future improvements | "Real splash artwork": both sizes. |
| Likely problems | Replace the "Screen orientation" entry with the rotation problems under [Risks](#risks). |

## Testing

**Without the board** (Docker test and CI):
- `install.sh --rotate left` writes `DISPLAY_ROTATION=left` to `board.conf`. A second run changes nothing (the existing "second run changes nothing" check covers it). `--rotate sideways` is refused. A run without `--rotate` keeps an existing value.
- Boot flow in `scripts/test-in-docker.sh`: add an `xrandr` stand-in next to the `xset` one, logging to the same calls file and answering `xrandr -q` with a `current … x …` line. Check that a normal boot calls `xrandr -o left` before the splash starts, that a skip-button boot ends with `xrandr -o normal`, and that a missing-ROM boot never calls `xrandr`.
- `set-rotation.sh`: rejects invalid values; skips the call when already rotated; exits 0 with a warning when the rotation doesn't take effect, and when `xrandr` can't reach a display.
- `status-screen.py` passes the Python syntax check (already in CI). On a virtual 320×240 display: the landscape splash shows, the prompt fits, and with `splash-landscape.png` missing it falls back to `splash.png`.
- shellcheck covers `set-rotation.sh` automatically (CI checks every `*.sh`).

**On the board** (added to step 9):
- Power on with no controller: the splash and the prompt appear **horizontally**, and the splash never shows in portrait first.
- The game fills the screen height with the correct aspect ratio (no stretching), for a Game Boy and a Game Boy Color ROM.
- Save-state shortcuts and pause on controller disconnect still work, with both the USB and the Bluetooth controller.
- Hold button B at power-on: the built-in menu appears **in portrait** and touch works.
- `systemctl stop gameboy`: the desktop returns to portrait.
- `./deploy.sh --rotate normal`: the next start is in portrait. `./deploy.sh --rotate left`: the picture turns the other way.
- Compare CPU use and smoothness with portrait, and re-measure boot time (28 s in portrait).

## Risks

| Risk | What to do |
|---|---|
| The X driver can't rotate (neither option A nor B works) | Stay in portrait. Record it here; kernel-level rotation (option C) is out of scope. |
| Rotation costs too much CPU and the game stutters | Try the CPU setting from the initial plan's "Likely problems" (`userspace` governor at the top frequency). Then try the other option (A or B). As a last resort, stay in portrait. |
| mGBA stretches the picture | Happens: mGBA 0.7.0 ignores `lockAspectRatio`. Accepted (2026-11-13). |
| X doesn't start with the rotation file (black screen after a deploy or boot) | Over SSH: `rm /etc/X11/xorg.conf.d/10-unihiker-gb-rotate.conf && systemctl restart lightdm`, then `./deploy.sh --rotate normal` so the boot service doesn't write it again. |
| A DFRobot update changes the display's Device section | `set-rotation.sh` copies its settings (fbdev, `/dev/fb0`, DRI 2). Compare with `20-modesetting.conf` if the display changes after an update. |
| The skip-button desktop restart doesn't bring the menu back | Over SSH: `XDG_RUNTIME_DIR=/run/user/0 systemctl --user start PyboardUI.service`. |

## Open questions

1. ~~**Which direction is "up"** in actual use?~~ **Decided (2026-11-12): `right`.**
2. ~~**Should landscape be the default** for every deploy?~~ **Decided: yes**, `right` on the first deploy that finds no setting. Boards deployed before this change turn on their next deploy.
3. ~~**Option B only:** is the built-in menu acceptable when rotated?~~ **Decided (2026-11-13): no.** The skip button restarts the desktop in portrait.
