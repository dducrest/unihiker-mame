# unihiker-mame
Repo: @dducrest/unihiker-mame

Project to deploy the mGBA Game Boy emulator to a Unihiker M10

This project contains a collection of setup scripts to install the mGBA emulator on a Unihiker M10. 

The Unihiker will use a USB or bluetooth controller as the primary input device. 
## Connecting the Unihiker to macOS

The Unihiker connects to your Mac over USB as an accessory and creates a virtual network interface (the deploy scripts reach the board at `10.1.2.3` by default).

macOS does not automatically allow new USB accessories to connect. When you plug in the Unihiker, look for an **"Allow accessory to connect?"** modal and click **Allow**.

If the modal appears and then disappears before you can click it, change the accessory setting so the device can connect:

1. Open **System Settings → Privacy & Security**.
2. Find **Allow accessories to connect** and set it to **Always**.
3. Unplug the Unihiker and plug it back in.

### Troubleshooting: verify the connection

To confirm the Unihiker is connected as an accessory and has created its virtual network interface:

1. Open **System Settings → Network**.
2. Look for a network service named **unihiker** in the list.
3. If it's there and shows as connected, the device is ready and you can run `./deploy.sh`.

If no `unihiker` network appears, check the accessory setting above, try a different USB cable (some cables are power-only) or port, and reconnect the board.

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
| Third-party Bluetooth controller sold as a Nintendo Switch 2 replacement | Bluetooth | Identifies itself as **"Xbox Wireless Controller"**, although it isn't a Microsoft controller. Needs its own button mapping and link-level security; see below. |

#### The "Xbox Wireless Controller" (Switch 2 replacement)

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
