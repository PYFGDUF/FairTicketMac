"""Click helper for GUI verification (screen coordinates, top-left origin).

Used while checking the window by hand: `python3 script/gui_click.py X Y [X Y ...]`.
AppleScript's `click at` does not land where it says it does for this app, and a
real mouse event through Quartz is the only reliable way to focus a field.
"""
import sys
import time

import Quartz

TAP = Quartz.kCGHIDEventTap
BUTTON = Quartz.kCGMouseButtonLeft


def click(x: float, y: float) -> None:
    point = (x, y)
    for event_type in (
        Quartz.kCGEventMouseMoved,
        Quartz.kCGEventLeftMouseDown,
        Quartz.kCGEventLeftMouseUp,
    ):
        event = Quartz.CGEventCreateMouseEvent(None, event_type, point, BUTTON)
        Quartz.CGEventPost(TAP, event)
        time.sleep(0.08)


if __name__ == "__main__":
    args = sys.argv[1:]
    for index in range(0, len(args), 2):
        click(float(args[index]), float(args[index + 1]))