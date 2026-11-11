# Plan: landscape (horizontal) display

Revises [initial-planning.md](initial-planning.md) so the game is shown on a horizontal screen. The UNIHIKER boots in portrait (240×320).

Status: **draft**. Nothing here has been tested on an M10 yet. Phase 0 is a short session on the board that decides how the rotation is done; the rest of the plan depends on it.

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
- **The escape hatch is unaffected:** when a board button is held at boot, the built-in UNIHIKER menu still appears in portrait, the way it was designed, with the touchscreen working normally.
- Turning the rotation off is a single setting, without re-flashing.
- Deploying stays one command: `./deploy.sh --rotate left`.

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

Run over SSH with the board connected:
```bash
export DISPLAY=:0
grep -iE 'driver|fbdev|modesetting|fbturbo' /var/log/Xorg.0.log | head    # which X display driver
ls /etc/X11/xorg.conf /etc/X11/xorg.conf.d /usr/share/X11/xorg.conf.d 2>/dev/null
command -v xrandr xinput xdpyinfo                                       # are the tools installed?
xrandr -q                                                               # output name and supported rotations
xrandr -o left;  sleep 5; xdpyinfo | grep dimensions                    # expect 320x240, and look at the screen
xrandr -o right; sleep 5
xrandr -o normal
xinput list                                                             # touchscreen device name (only needed for option B)
```
Then, rotated, run mGBA for a minute (`/usr/games/mgba -f <rom>`) and compare its CPU use in `top` with the same game in portrait. Rotation copies every frame through a shadow buffer, so it costs some CPU.

| Result | Decision |
|---|---|
| `xrandr -o left` turns the picture and `xdpyinfo` reports 320x240 | **Option A** |
| `xrandr` reports no rotations, or the picture doesn't change | Try option B by hand: add the driver's `Rotate` option to an `xorg.conf.d` file, then restart X (or reboot). If that works, **option B** |
| Neither works | Stop. Landscape isn't available on this board without kernel changes; record that here. |
| Rotated mGBA uses so much CPU that the game stutters | Try the other option; if both stutter, see [Risks](#risks) |

Also record:
- **Which direction is "up"** for how the board will actually be used (where the USB port, the A/B buttons and the cable end up). This sets the default for `--rotate`.
- Whether `xrandr`, `xinput` and `xdpyinfo` are already installed. They're in Debian's `x11-xserver-utils`, `xinput` and `x11-utils` packages. `xset`, which the launcher already uses, comes from `x11-xserver-utils` too.

## Design (option A)

### Setting
`/etc/unihiker-gb/board.conf` gets a new value, written by `install.sh`:
```bash
DISPLAY_ROTATION=left      # left | right | inverted | normal
```
- `normal` turns rotation off.
- **Default:** whichever direction Phase 0 records, applied on the first deploy if no value is set yet. Later deploys only change it when `--rotate` is given, like the other settings files.

### Boot flow changes
The steps from the existing plan's [boot flow](initial-planning.md#boot-flow), with the changes in bold:

1. systemd starts `gameboy.service` once the desktop (X) is up.
2. `start-gb.sh` turns off screen blanking, **rotates the screen to `DISPLAY_ROTATION`**, and shows the splash screen.
3. Skip check: if a board button is held, the launcher closes the splash, **rotates the screen back to `normal`**, starts the built-in menu for this boot only, and exits.
4. Wait for a controller (the prompt is laid out for the rotated screen).
5. mGBA starts in fullscreen and **fills the 320×240 screen, keeping the game's aspect ratio**.
6. **When the service stops** (for any reason, including `systemctl stop` or a crash), the screen is rotated back to `normal`.

The splash is shown only after rotating, so it never flashes up in portrait first.

### New script: `launcher/set-rotation.sh`
`set-rotation.sh <left|right|inverted|normal>`, installed to `/opt/unihiker-gb/`:
1. Rejects any other value.
2. Does nothing if the screen is already in that orientation, so it's safe to call twice.
3. Runs `xrandr -o <value>`.
4. Checks the result with `xdpyinfo`: 320x240 for `left`/`right`, 240x320 for `normal`/`inverted`.
5. If the rotation failed, logs a warning with `logger -t unihiker-gb` and **exits 0**. A failed rotation leaves the game in portrait; it must never stop the game from starting.

Keeping it as its own script means `start-gb.sh`, the service's stop hook and a person debugging over SSH all rotate the same way.

### `start-gb.sh` (changes only)
```bash
# after "xset s off -dpms":
"$APP/set-rotation.sh" "${DISPLAY_ROTATION:-normal}"

# in the skip-button branch, before starting the built-in menu:
"$APP/set-rotation.sh" normal
```

### `gameboy.service` (change only)
```ini
[Service]
ExecStopPost=/opt/unihiker-gb/set-rotation.sh normal
```
`ExecStopPost` runs however the service ends, so the desktop is never left sideways. It needs `DISPLAY=:0`; `set-rotation.sh` sets that itself.

### Splash and status screen
- **Assets:** keep `assets/splash.png` (240×320) for portrait and add `assets/splash-landscape.png` (320×240). Generate the landscape placeholder the same way as the portrait one.
- **`status-screen.py`:** read the actual screen size (`winfo_screenwidth()`/`winfo_screenheight()`) and pick the image that matches. Don't hard-code 240×320. Wrap the prompt text to the window width, so it works in both orientations. That way, if rotation fails, the portrait splash still shows correctly.

### mGBA scaling
In `config/mgba-config.ini`:
```ini
[ports.sdl]
lockAspectRatio=1
lockIntegerScaling=0
```
- Fills the 240-pixel height at 1.67× for Game Boy games, with bars at the sides, and doesn't stretch the picture.
- ⚠️ Check in Phase 0 that mGBA 0.7.0 recognizes these keys. If the game looks stretched or only uses 160×144 in the middle, try `-C lockAspectRatio=1` on the command line instead.
- `install.sh` doesn't overwrite an existing `/root/.config/mgba/config.ini` (it saves the repo version as `config.ini.repo` instead). On a board that already has the file, copy these two lines in by hand, or delete the file and re-deploy.

### Deploy and install
- **`deploy.sh`:** new option `--rotate <left|right|inverted|normal>`, passed through to `install.sh`.
- **`install.sh`:**
  - New option `--rotate`. It checks the value and writes `DISPLAY_ROTATION` to `board.conf` with `set_conf_var`, keeping a `.bak` like the other settings.
  - Installs `set-rotation.sh` and `splash-landscape.png` with the other program files.
  - **Packages:** if Phase 0 shows `xrandr` or `xdpyinfo` missing, add `x11-xserver-utils` and `x11-utils` to `PACKAGES` in both `install.sh` and `scripts/fetch-packages.sh` (they must stay in sync), then re-run `fetch-packages.sh`.
  - **Verify step:** if X is running, check that `xrandr -q` lists the configured direction among the supported rotations. Warn (don't fail) if it doesn't: the game still runs, in portrait. Skipped in Docker.
- **`set-rom.sh`, `pair-bluetooth.sh`, `fetch-logs.sh`:** no changes.

## Design (option B, only if option A doesn't work)

What changes compared with option A:
- **Install** `config/20-unihiker-gb-rotate.conf` into `/etc/X11/xorg.conf.d/`, with the display driver's `Rotate` option (`CCW` for left, `CW` for right, `UD` for inverted) and the driver and device names found in Phase 0. `--rotate normal` removes the file. Either way, the change takes effect when X restarts, so `install.sh` asks for a reboot instead of restarting the service.
- **Touchscreen:** a small `launcher/fix-touch.sh`, run at the start of `start-gb.sh`, applies the matching `Coordinate Transformation Matrix` to the touchscreen with `xinput`. Add `xinput` to the packages.
- **Escape hatch:** the built-in menu appears rotated. Phase 0 should check whether it's still usable that way. If it isn't, the skip-button branch would have to remove the rotation file and restart X, which adds a second reboot-like delay. Decide only if option B is chosen.
- **No `set-rotation.sh`** and no `ExecStopPost`: the rotation is fixed while X runs.

## Changes to `initial-planning.md`

Once Phase 0 picks an option, update the existing plan:

| Section | Change |
|---|---|
| Goals | Add: the screen is horizontal while the emulator runs. |
| Implementation status | Add rows for `set-rotation.sh`, the landscape splash and `--rotate`. |
| What you're working with | Display row: "240×320 portrait; rotated to 320×240 landscape while the emulator runs". Game Boy scaling: 1.67×, to 266×240. |
| Architecture | Add `set-rotation.sh` and `splash-landscape.png`. Add `DISPLAY_ROTATION` to the `board.conf` description. |
| Boot flow | The changes listed under [Boot flow changes](#boot-flow-changes). |
| Repository layout | Add `launcher/set-rotation.sh` and `assets/splash-landscape.png`. |
| Steps 5 and 7 | The `start-gb.sh` and `gameboy.service` changes above. |
| Step 9 (test the boot flow) | Add the on-board tests below. |
| Setup script | `--rotate` in Usage, `deploy.sh` and `install.sh`; the extra packages if needed. |
| Considerations, item 17 | The splash comes in two sizes. |
| Decided | New row: **Display orientation**: landscape while the emulator runs, direction set by `--rotate`. |
| Likely problems | Replace the "Screen orientation" entry with the rotation problems under [Risks](#risks). |

## Testing

**Without the board** (Docker test and CI):
- `install.sh --rotate left` writes `DISPLAY_ROTATION=left` to `board.conf`. A second run changes nothing. `--rotate sideways` is refused.
- `set-rotation.sh` rejects invalid values, and with stub `xrandr` and `xdpyinfo` commands on its `PATH`: calls `xrandr -o left`, skips the call when already rotated, and exits 0 with a warning when the rotation doesn't take effect.
- `status-screen.py` passes the Python syntax check and has no hard-coded screen size.

**On the board** (added to step 9):
- Power on with no controller: the splash and the prompt appear **horizontally**, and the splash never shows in portrait first.
- The game fills the screen height with the correct aspect ratio (no stretching).
- Hold button B at power-on: the built-in menu appears **in portrait** and touch works.
- `systemctl stop gameboy`: the desktop returns to portrait.
- `./deploy.sh --rotate normal`: the next start is in portrait. `./deploy.sh --rotate right`: the picture turns the other way.
- Compare CPU use and smoothness with the portrait measurements, and re-measure boot time (step 9).

## Risks

| Risk | What to do |
|---|---|
| The X driver can't rotate (neither option A nor B works) | Stay in portrait. Record it here; kernel-level rotation (option C) is out of scope. |
| Rotation costs too much CPU and the game stutters | Try the CPU performance mode from "Likely problems". Then try the other option (A or B). As a last resort, stay in portrait. |
| mGBA stretches the picture or doesn't fill the screen | Check the `lockAspectRatio` setting, or set it on the command line. |
| The screen is left sideways after a crash | `ExecStopPost` covers stops and crashes. If X itself restarts, it starts in portrait, and the launcher rotates it again. |
| The touchscreen is wrong after rotation (option B only) | `fix-touch.sh` with the matrix for the chosen direction. |

## Open questions

1. **Which direction is "up"** in actual use (left or right)? Phase 0 records it; it becomes the default.
2. **Should landscape be the default** for every deploy, or only when `--rotate` is given? The draft assumes default-on, using the direction from question 1.
3. **Option B only:** is the built-in menu acceptable when rotated, or must the skip button bring it up in portrait (which needs an X restart)?
