#!/usr/bin/env python3
"""Serve the MineAttack web export locally.

Godot 4 web builds require cross-origin isolation headers (COOP/COEP),
which python's plain http.server does not send — hence this tiny wrapper.

Usage:
    python3 tools/serve_web.py [port]     # default port 8080

Then open http://localhost:8080/MineAttack.html
"""

import http.server
import sys
from functools import partial

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
DIRECTORY = "build"


class GodotWebHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        super().end_headers()


if __name__ == "__main__":
    handler = partial(GodotWebHandler, directory=DIRECTORY)
    with http.server.ThreadingHTTPServer(("", PORT), handler) as server:
        print(f"Serving {DIRECTORY}/ at http://localhost:{PORT}/MineAttack.html")
        server.serve_forever()
