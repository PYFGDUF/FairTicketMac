"""PyInstaller entry point for the frozen sidecar.

Packaging belongs to the app, so this launcher lives here rather than in the
engine checkout: the engine stays a plain importable package, and this is the only
file that knows it also gets frozen into a single executable.

The engine's own module entry point (`python -m ticket_app.sidecar`) cannot be used
directly because PyInstaller needs a real script path.
"""

import sys

from ticket_app.sidecar import main

if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))