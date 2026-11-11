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
