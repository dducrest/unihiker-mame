#!/usr/bin/env python3
"""Boot screen (manual step 5, items 12 and 17): the splash image, then a prompt to
connect a controller if none has appeared after PROMPT_AFTER seconds.

Started in the background by start-gb.sh, which closes it (SIGTERM) when mGBA starts or
the skip button is held. Fullscreen and on top, so it also covers the built-in menu
until that has stopped.

    status-screen.py [--splash FILE]

The splash is splash.png (240x320) on a portrait screen and splash-landscape.png (320x240)
on a landscape one (the screen is rotated by set-rotation.sh), falling back to splash.png
if the landscape image is missing. --splash overrides both.

Must stay compatible with Python 3.7 (Debian buster, Tk 8.6).
"""
import argparse
import glob
import os
import signal
import sys
import tkinter as tk

PROMPT_AFTER = 5.0  # seconds
POLL_MS = 500
BG = "black"
FG = "white"
PROMPT = (
    "No controller found.\n\n"
    "Turn on or plug in a controller.\n\n"
    "To use the UNIHIKER menu instead: power off, then hold button B while "
    "powering on until the menu appears."
)


def controller_connected():
    return bool(glob.glob("/dev/input/js*"))


def default_splash(folder, width, height):
    portrait = os.path.join(folder, "splash.png")
    if width > height:
        landscape = os.path.join(folder, "splash-landscape.png")
        if os.path.isfile(landscape):
            return landscape
    return portrait


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--splash", help="splash image (default: chosen by screen shape)")
    args = ap.parse_args()

    root = tk.Tk()
    root.title("unihiker-gb")
    root.configure(bg=BG, cursor="none")
    root.attributes("-fullscreen", True)
    root.attributes("-topmost", True)
    width, height = root.winfo_screenwidth(), root.winfo_screenheight()
    splash_file = args.splash or default_splash(here, width, height)

    # Tk's PhotoImage reads PNG from Tk 8.6 on. Without the image, the screen is just black.
    splash = None
    try:
        splash = tk.PhotoImage(file=splash_file)
    except tk.TclError as e:
        print("status-screen: no splash image (%s)" % e, file=sys.stderr, flush=True)
    image_label = tk.Label(root, image=splash, bg=BG, bd=0) if splash else tk.Label(root, bg=BG)
    image_label.place(relx=0.5, rely=0.5, anchor="center")

    prompt_label = tk.Label(
        root, text=PROMPT, bg=BG, fg=FG, justify="center",
        font=("DejaVu Sans", 12), wraplength=max(width - 24, 100),
    )
    state = {"elapsed": 0.0, "prompt": False, "stopping": False}

    def show(prompt):
        if prompt == state["prompt"]:
            return
        state["prompt"] = prompt
        (image_label if prompt else prompt_label).place_forget()
        (prompt_label if prompt else image_label).place(relx=0.5, rely=0.5, anchor="center")

    def poll():
        if state["stopping"]:
            return
        state["elapsed"] += POLL_MS / 1000.0
        # Prompt only after PROMPT_AFTER seconds without a controller; back to the splash
        # if one appears, until start-gb.sh closes this window.
        show(state["elapsed"] >= PROMPT_AFTER and not controller_connected())
        root.after(POLL_MS, poll)

    def on_sigterm(*_):
        # Tk only runs Python signal handlers between events; the poll timer keeps the event
        # loop waking up, so this runs within POLL_MS.
        state["stopping"] = True
        root.quit()

    signal.signal(signal.SIGTERM, on_sigterm)
    root.after(POLL_MS, poll)
    root.geometry("%dx%d+0+0" % (width, height))
    root.mainloop()
    root.destroy()


if __name__ == "__main__":
    main()
