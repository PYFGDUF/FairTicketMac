"""Print the window id of a running app's main window, for `screencapture -l`.

Region captures (`screencapture -R`) grab whatever is visible at those coordinates, so
they silently return another app's window whenever something is on top — which is exactly
what happens while the machine is in use.  Capturing by window id is z-order independent:
it works with the window completely covered and needs no focus change, so a capture never
costs the user their desktop.

Windows are matched by owning process, not by owner name: the name the window server
reports comes from `CFBundleName` ("12306 Fair Ticket"), which has nothing to do with the
executable SwiftPM produces.  Comparing names therefore found nothing at all, and the
caller quietly fell back to the region capture this script exists to avoid.

The list is queried with `kCGWindowListOptionAll`, not `...OnScreenOnly`.  `preview.sh`
launches its instance hidden and in the background (`open -n -g -j -F`) so that nothing
appears over the user's work, and the window server reports those windows as *not on
screen* — while `screencapture -l` still captures them from the window's own backing
store.  Filtering to on-screen windows is what would make the probe "never see" a window
that is perfectly capturable.

    python3 script/window_id.py FairTicketMac
    python3 script/window_id.py FairTicketMac --bounds
    python3 script/window_id.py --pid 12345 --min-width 600
"""
import subprocess
import sys

import Quartz

DEFAULT_APP = "FairTicketMac"

# The window server also reports the thin strips a window owns (title bar, toolbar
# shadow planes).  Anything narrower than this is never the window a caller wants.
DEFAULT_MIN_WIDTH = 300


def owning_pids(app: str) -> set:
    result = subprocess.run(["pgrep", "-x", app], capture_output=True, text=True)
    return {int(line) for line in result.stdout.split() if line.strip()}


def main_window(pids: set, min_width: float = DEFAULT_MIN_WIDTH):
    """The largest layer-0 window of `pids`, as (id, bounds).  None if there is none."""
    if not pids:
        return None

    windows = Quartz.CGWindowListCopyWindowInfo(
        Quartz.kCGWindowListOptionAll | Quartz.kCGWindowListExcludeDesktopElements,
        Quartz.kCGNullWindowID,
    )
    # (area, number, bounds) — largest layer-0 window wins.  Comparing against the
    # bounds instead of the area only shows up once the app owns a second window (an
    # alert panel, say), because with one candidate the comparison never runs.
    best = None
    for window in windows or []:
        if window.get("kCGWindowOwnerPID") not in pids:
            continue
        # Layer 0 is the normal window plane; skip panels, shadows and menus.
        if window.get("kCGWindowLayer") != 0:
            continue
        bounds = window.get("kCGWindowBounds") or {}
        width = float(bounds.get("Width", 0))
        height = float(bounds.get("Height", 0))
        if width < min_width or height <= 0:
            continue
        area = width * height
        if best is None or area > best[0]:
            best = (area, window.get("kCGWindowNumber"), bounds)

    if best is None:
        return None
    return best[1], best[2]


def main(argv) -> int:
    app = DEFAULT_APP
    pid = None
    min_width = DEFAULT_MIN_WIDTH
    show_bounds = False

    index = 0
    while index < len(argv):
        arg = argv[index]
        if arg == "--bounds":
            show_bounds = True
        elif arg == "--pid":
            index += 1
            pid = int(argv[index])
        elif arg == "--min-width":
            index += 1
            min_width = float(argv[index])
        else:
            app = arg
        index += 1

    pids = {pid} if pid is not None else owning_pids(app)
    found = main_window(pids, min_width=min_width)
    if found is None:
        return 1
    number, bounds = found
    if show_bounds:
        print(
            "%s %d %d %d %d"
            % (
                number,
                int(bounds.get("X", 0)),
                int(bounds.get("Y", 0)),
                int(bounds.get("Width", 0)),
                int(bounds.get("Height", 0)),
            )
        )
    else:
        print(number)
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
