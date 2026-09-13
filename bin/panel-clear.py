#!/usr/bin/env python3
"""Fullscreen white (then optional black) to help clear LCD image retention.

Does not permanently repair the panel. Esc or q quits early.
"""

from __future__ import annotations

import argparse
import sys


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Fullscreen panel-clear helper for IPS image retention."
    )
    parser.add_argument(
        "--minutes",
        type=float,
        default=5.0,
        help="Minutes of white screen (default: 5)",
    )
    parser.add_argument(
        "--black-seconds",
        type=float,
        default=30.0,
        help="Seconds of black after white (default: 30; 0 to skip)",
    )
    args = parser.parse_args()

    try:
        import gi

        gi.require_version("Gtk", "3.0")
        gi.require_version("Gdk", "3.0")
        from gi.repository import Gdk, GLib, Gtk
    except Exception as exc:  # noqa: BLE001
        print(
            "panel-clear needs PyGObject/GTK 3 (python3-gi, gir1.2-gtk-3.0).",
            file=sys.stderr,
        )
        print(f"Import error: {exc}", file=sys.stderr)
        return 1

    white_ms = max(0, int(args.minutes * 60 * 1000))
    black_ms = max(0, int(args.black_seconds * 1000))

    window = Gtk.Window(type=Gtk.WindowType.TOPLEVEL)
    window.set_title("panel-clear — Esc or q to quit")
    window.fullscreen()
    window.set_keep_above(True)

    css = Gtk.CssProvider()
    css.load_from_data(b"* { background-color: #ffffff; }")
    Gtk.StyleContext.add_provider_for_screen(
        Gdk.Screen.get_default(),
        css,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION,
    )

    label = Gtk.Label(
        label="Panel clear in progress\nEsc or q to quit early"
    )
    label.set_justify(Gtk.Justification.CENTER)
    label.set_name("hint")
    hint_css = Gtk.CssProvider()
    hint_css.load_from_data(
        b"#hint { color: #666666; font-size: 18px; background-color: transparent; }"
    )
    label.get_style_context().add_provider(
        hint_css, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    )
    window.add(label)

    phase = {"name": "white"}

    def set_bg(color: str) -> None:
        css.load_from_data(f"* {{ background-color: {color}; }}".encode())

    def quit_app(_=None) -> bool:
        Gtk.main_quit()
        return False

    def to_black() -> bool:
        phase["name"] = "black"
        set_bg("#000000")
        label.set_text("Black phase\nEsc or q to quit")
        if black_ms > 0:
            GLib.timeout_add(black_ms, quit_app)
        else:
            quit_app()
        return False

    def on_key(_widget, event) -> bool:
        key = Gdk.keyval_name(event.keyval)
        if key in ("Escape", "q", "Q"):
            quit_app()
            return True
        return False

    window.connect("key-press-event", on_key)
    window.connect("destroy", quit_app)
    window.show_all()

    if white_ms > 0:
        GLib.timeout_add(white_ms, to_black)
    else:
        to_black()

    print(
        f"panel-clear: white {args.minutes:g} min, "
        f"then black {args.black_seconds:g} s (Esc/q to quit)",
        flush=True,
    )
    Gtk.main()
    return 0


if __name__ == "__main__":
    sys.exit(main())
