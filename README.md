# unihiker-mame

Turns a [UNIHIKER M10](https://www.unihiker.com/) into a single-game Game Boy console. It powers on straight into a Game Boy or Game Boy Color game, running in the mGBA emulator and played with a USB or Bluetooth controller. One command on a Mac sets up a new board.

## Features

**On the UNIHIKER**
- **Boots straight into a game.** No menu, keyboard or touchscreen needed. The game is chosen by filename, and changing it is one command.
- **Landscape or portrait screen.** By default the screen is turned to landscape (320×240). The direction is a deploy option. See [Screen orientation](#screen-orientation).
- **Splash screen at start-up**, then a "connect a controller" prompt if no controller is found.
- **USB and Bluetooth controllers.** A paired Bluetooth controller reconnects by itself after a reboot. Button mappings are kept per controller model.
- **Save states from the controller:** L + R + Select saves, L + R + Start loads. In-game saves work too.
- **Pause on disconnect.** If the controller is unplugged or goes to sleep, the game freezes, and it resumes when the controller comes back.
- **Escape hatch.** Hold board button B at power-on to get the UNIHIKER's own menu, in portrait, for that boot. The board's own setup is never disabled.
- **Screen stays on** during play. Sound is off.

**On the developer's Mac**
- **One-command deploy** (`./deploy.sh`): sets up SSH access, sets the board's clock, copies ROMs, installs everything and starts the game. Safe to re-run: each run changes only what's needed.
- **Offline install.** Packages are downloaded once on the Mac, so the board never needs internet access.
- **ROM filename check** before copying, so names that would cause problems are caught on the Mac.
- **Save backups** (`./deploy.sh --pull-saves`) and **logs** (`./fetch-logs.sh`) from the Mac.
- **Tests** in an arm64 Debian container, run in GitHub Actions on every push.

## Requirements

### Developer machine

| Requirement | Why | Notes |
|---|---|---|
| **macOS** | `deploy.sh` and `fetch-logs.sh` are written for macOS (its built-in bash 3.2 and its USB accessory handling). | Linux would probably work but isn't tested. |
| **[Docker Desktop](https://www.docker.com/products/docker-desktop/)**, running | `scripts/fetch-packages.sh` downloads the board's packages inside an arm64 Debian 10 container. `scripts/test-in-docker.sh` uses it too. | Needed once per clone, and again when the package list changes. Not needed for everyday deploys. |
| **Internet access** | For `fetch-packages.sh` only (Debian's archive and Docker's image registry). | The board itself never needs internet. |
| **git** | To clone the repo. `deploy.sh` also records the deployed commit on the board. | Included with the Xcode Command Line Tools (`xcode-select --install`). |
| **OpenSSH tools**: `ssh`, `scp`, `ssh-keygen`, `ssh-copy-id` | Every connection to the board. | Built into macOS. `ssh-copy-id` is included from macOS 12 on; on older versions, install it with Homebrew (`brew install ssh-copy-id`). |
| **About 100 MB free disk space** | The downloaded packages (about 82 MB) in `packages/`. | Plus the Debian image Docker pulls. |
| **A USB data cable** | The board connects to the Mac over USB and appears as a network device at `10.1.2.3`. | Some cables carry power only. If the board doesn't appear, try another cable. |
| **macOS accessory permission** | macOS must allow the board to connect as a USB accessory. | See [Connecting the UNIHIKER to macOS](#connecting-the-unihiker-to-macos). |
| **ROM files** | The games to play (`.gb` or `.gbc`). | Not included. Use homebrew games or dumps of cartridges you own. Put them in `roms/`, which git ignores. |

shellcheck isn't needed to deploy. It's only used for linting, and CI runs it.

### UNIHIKER board

- A **UNIHIKER M10** with DFRobot's stock system image: Debian 10 (buster), arm64. `install.sh` checks both and refuses packages for the wrong architecture.
- At least **300 MB free** on the root filesystem.
- The **default root password** (`dfrobot`) or one you know. You're asked for it once, on the first deploy, which then sets up key-based SSH. `--set-password` changes it.
- A **game controller**: any USB gamepad, or a Bluetooth controller. See [Tested controllers](#tested-controllers).

## Deploying to a new UNIHIKER

1. **Clone the repo and download the packages.** This needs Docker Desktop running and takes a few minutes:
   ```bash
   git clone https://github.com/dducrest/unihiker-mame.git
   cd unihiker-mame
   scripts/fetch-packages.sh        # fills packages/; run again only when the package list changes
   ```
2. **Add a ROM.** Copy a game into `roms/`, for example `roms/game.gb`.
3. **Connect the board** to the Mac with a USB data cable, power it on and wait about a minute for it to boot. The first time, macOS asks to allow the accessory. See [Connecting the UNIHIKER to macOS](#connecting-the-unihiker-to-macos).
4. **Deploy:**
   ```bash
   ./deploy.sh --rom roms/game.gb --set-password          # USB controller
   ./deploy.sh --rom roms/game.gb --set-password --pair   # Bluetooth controller: pair it at the end
   ```
   On the first run, enter the board's root password (`dfrobot`) once when asked. The SSH key is stored as `~/.ssh/unihiker-gb_ed25519`, so later deploys don't ask. `--set-password` then asks for a new root password.
5. The board restarts its screen in landscape and starts the game. The summary at the end lists each check as `PASS`, `WARN` or `FAIL`.

After a re-flash, or when switching to another board, add `--forget-host`. It makes the Mac forget the old board's SSH key.

### Everyday commands

```bash
./deploy.sh                          # re-deploy after changing the repo (keeps the board's settings)
./deploy.sh --rom roms/other.gbc     # copy another game and boot into it
./deploy.sh --roms-dir roms          # copy every ROM in roms/ (the boot game stays the same)
./deploy.sh --rotate normal          # portrait; or left / right / inverted
./deploy.sh --pull-saves             # copy the board's saves to saves/<date-time>/
./fetch-logs.sh                      # recent logs; --follow to watch live, --boot for this boot only
./deploy.sh --help                   # every option
```

Run `--pull-saves` before re-flashing a board. Saves live only on the board until you back them up.

## Connecting the UNIHIKER to macOS

The UNIHIKER connects to your Mac over USB as an accessory and creates a virtual network interface. The deploy scripts reach the board at `10.1.2.3` by default.

macOS doesn't automatically allow new USB accessories to connect. When you plug in the UNIHIKER, look for an **"Allow accessory to connect?"** prompt and click **Allow**.

If the prompt appears and then disappears before you can click it, change the accessory setting so the device can connect:

1. Open **System Settings → Privacy & Security**.
2. Find **Allow accessories to connect** and set it to **Always**.
3. Unplug the UNIHIKER and plug it back in.

After the first connection, the setting can go back to "Ask for new accessories".

### Troubleshooting: verify the connection

To confirm the UNIHIKER is connected as an accessory and has created its virtual network interface:

1. Open **System Settings → Network**.
2. Look for a network service named **unihiker** in the list.
3. If it's there and shows as connected, the device is ready and you can run `./deploy.sh`.

If no `unihiker` network appears, check the accessory setting above, try a different USB cable (some cables are power-only) or port, and reconnect the board. With a VPN on, traffic may go through the VPN until that interface exists.

## Controllers

A USB or Bluetooth game controller is the main input. Board button B is used only at power-on, to skip the game (see below).

- **USB:** plug it in. No setup needed.
- **Bluetooth:** pair it once, then it reconnects by itself whenever the board and the controller are on:
  ```bash
  ./deploy.sh --pair                                          # deploy, then pair
  ssh -t root@10.1.2.3 /opt/unihiker-gb/pair-bluetooth.sh     # pair only
  ```
  Put the controller in pairing mode when asked, then pick it from the list (controllers are listed first and tagged `[controller]`; the tag isn't part of its name).

### Buttons and shortcuts

| Controller | Does |
|---|---|
| D-pad, A, B, Start, Select | The Game Boy buttons |
| L + R + Select | Save the game state |
| L + R + Start | Load the last saved state |

The game's own save (its in-game save option) also works. Saves and save states are stored in `/root/saves/` on the board; `./deploy.sh --pull-saves` copies them to the Mac.

To get the UNIHIKER's own menu instead of the game, hold **button B** on the board while powering on until the menu appears.

### Tested controllers

| Controller | Connection | Notes |
|---|---|---|
| Generic USB gamepad | USB | Uses the default mapping. |
| Third-party Bluetooth controller sold as a Nintendo Switch 2 replacement | Bluetooth | Identifies itself as **"Xbox Wireless Controller"**, although it isn't a Microsoft controller. Needs its own button mapping and link-level security; see below and [CONTROLLER.md](CONTROLLER.md). |

#### The "Xbox Wireless Controller" (Switch 2 replacement)

To put it in Bluetooth pairing mode, hold **B** and **HOME** together until LED2 and LED3 flash. [CONTROLLER.md](CONTROLLER.md) has the maker's pairing instructions and button-mode shortcuts.

If the buttons suddenly seem swapped, check whether one of the controller's own mode shortcuts was pressed: **Capture + L3** (held about 1 s, the controller vibrates once) switches the D-pad and left stick, and **Capture + R3** switches A/B and X/Y. The modes cycle, so press the same shortcut again until the buttons are back. (The maker documents these for Android, iOS and Windows; they're untested here.) The mapping in this repo assumes the controller's default mode.

This controller reports the name and device type of an Xbox controller, so Linux, SDL and mGBA all treat it as one. Three things follow from that:

1. **Its own button mapping.** Its buttons are numbered differently from the USB gamepad (A = 1, B = 0, L = 4, R = 5, Select = 6, Start = 7; the D-pad is a hat, which mGBA maps by default). The mapping is in the `[gba.input-profile.Xbox Wireless Controller]` section of [`config/mgba-config.ini`](config/mgba-config.ini), which mGBA picks by the controller's name. Because the name is borrowed, a genuine Microsoft Xbox controller would get this same mapping, and its buttons might not match.
2. **Reconnecting needs link-level security.** Without it, the controller pairs fine but can't reconnect after a reboot: it opens its controller channel a few milliseconds before the board's old Linux kernel (4.4) has registered that the link is encrypted, the board refuses it, and the controller gives up. The deploy installs `unihiker-gb-bluetooth.service`, which turns on link-level security (`hciconfig hci0 auth encrypt`) every time Bluetooth starts, so the link is encrypted before the controller asks. Nothing to do by hand.
3. **No ERTM workaround needed.** `./deploy.sh --bt-ertm-fix` is often recommended for Xbox controllers on Linux. It didn't help with this one, because the problem above happens before ERTM matters.

### Adding a controller with a different layout

If the buttons are wrong on a new controller:

1. On the board, read its button numbers with `jstest /dev/input/js0` and its name with `cat /sys/class/input/js*/device/name`.
2. Add a section named after it to [`config/mgba-config.ini`](config/mgba-config.ini), like the Xbox one: `[gba.input-profile.<exact name>]` with `keyA`, `keyB`, `keyL`, `keyR`, `keySelect` and `keyStart`. Any controller without its own section uses `[gba.input.SDLB]`.
3. Run `./deploy.sh`. Every deploy installs the repo's mGBA config (the board's old copy is kept as a dated backup).

The save-state shortcuts read the same sections, so they follow the controller automatically.

## Screen orientation

The screen is turned to landscape (320×240), which shows Game Boy games larger than the board's native portrait (240×320). Games are stretched to fill the screen (mGBA 0.7.0 can't keep their aspect ratio). The direction is a setting:

```bash
./deploy.sh --rotate right     # or left, inverted, normal (portrait, no rotation)
```

The first deploy sets `right`; later deploys keep the board's setting unless `--rotate` is given. It's stored as `DISPLAY_ROTATION` in `/etc/unihiker-gb/board.conf` on the board.

The board's display can only rotate when the desktop starts, so changing `--rotate` restarts the board's desktop. When button B is held at power-on, the desktop restarts once more in portrait, so the UNIHIKER menu appears the way it was designed; the next normal boot is landscape again. Details: [plans/landscape-display.md](plans/landscape-display.md).
