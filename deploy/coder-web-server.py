#!/usr/bin/env python3
"""
coder-web-server.py — Static app server + same-origin /soco proxy (dual-stack).

Serves the published Flutter web build and proxies `/soco/*` to the SoCo
server (real SoCo-CLI on the Pi, soco-mock-server.py in the test environment).
Same-origin proxying avoids CORS and HTTPS→HTTP mixed-content blocking when
the app is accessed through the Coder workspace proxy (HTTPS).

Why dual-stack: Coder's workspace agent forwards proxied connections to the
agent's tailnet IPv6 address. A server bound to 0.0.0.0 (IPv4-only) refuses
those connections — it must listen on `::` (with IPV6_V6ONLY=0).

Routes:
  /                     → static files from PUBLISH_DIR
  /soco/<api path>      → http://127.0.0.1:5001/<api path>

Usage:
  python3 deploy/coder-web-server.py [--port 8099] [--publish-dir DIR] [--soco-url URL]
"""
import argparse
import socket
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PUBLISH_DIR = "/opt/coder/sonos-tt/publish/web"
SOCO_URL = "http://127.0.0.1:5001"
PROXY_PREFIX = "/soco"

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript; charset=utf-8",
    ".mjs": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8",
    ".json": "application/json; charset=utf-8",
    ".png": "image/png",
    ".jpg": "image/jpeg",
    ".svg": "image/svg+xml",
    ".wasm": "application/wasm",
    ".woff": "font/woff",
    ".woff2": "font/woff2",
    ".ttf": "font/ttf",
    ".otf": "font/otf",
}
DEFAULT_MIME = "application/octet-stream"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    publish_dir = PUBLISH_DIR
    soco_url = SOCO_URL

    # ---- helpers ----------------------------------------------------------
    def _send(self, body: bytes, ctype: str, status: int = 200, cache: str = "no-store"):
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print(f"[web] {self.address_string()} {fmt % args}", flush=True)

    # ---- /soco proxy ------------------------------------------------------
    def _proxy_soco(self, path: str):
        url = self.soco_url.rstrip("/") + path
        req = urllib.request.Request(url, headers={"Accept": "application/json"})
        # Forward the original query string if any.
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                body = r.read()
                ctype = r.headers.get("Content-Type", "application/json")
                self._send(body, ctype)
        except urllib.error.HTTPError as e:
            self._send(e.read() or b"{}", "application/json", status=e.code)
        except Exception as e:  # noqa: BLE001 — proxy must not crash the server
            self._send(
                f'{{"error": "soco unreachable: {e}"}}'.encode(),
                "application/json",
                status=502,
            )

    # ---- static files -----------------------------------------------------
    def _serve_static(self, path: str):
        import os

        if path in ("/", ""):
            path = "/index.html"
        # Prevent path traversal.
        fs_path = os.path.realpath(os.path.join(self.publish_dir, path.lstrip("/")))
        if not fs_path.startswith(os.path.realpath(self.publish_dir) + os.sep) and \
                fs_path != os.path.realpath(os.path.join(self.publish_dir, "index.html")):
            return self._send(b"forbidden", "text/plain", status=403)
        if not os.path.isfile(fs_path):
            # SPA fallback for unknown routes → index.html
            fs_path = os.path.join(self.publish_dir, "index.html")
        with open(fs_path, "rb") as f:
            body = f.read()
        import os.path

        ext = os.path.splitext(fs_path)[1].lower()
        # Cache hashed assets; never cache the shell.
        cache = "public, max-age=31536000, immutable" if (
            ext in MIME and ext not in (".html",) and ("." in os.path.basename(fs_path))) else "no-store"
        self._send(body, MIME.get(ext, DEFAULT_MIME), cache=cache)

    # ---- dispatch ---------------------------------------------------------
    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == PROXY_PREFIX or path.startswith(PROXY_PREFIX + "/"):
            api_path = path[len(PROXY_PREFIX):]  # keep leading slash
            if self.path.split("?", 1)[0] != path and "?" in self.path:
                api_path += "?" + self.path.split("?", 1)[1]
            return self._proxy_soco(api_path)
        return self._serve_static(path)

    def do_HEAD(self):
        # Minimal HEAD support (some proxies check availability with HEAD).
        self.send_response(200)
        self.send_header("Content-Length", "0")
        self.end_headers()


class DualStackServer(ThreadingHTTPServer):
    address_family = socket.AF_INET6
    daemon_threads = True

    def server_bind(self):
        try:
            self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
        except (AttributeError, OSError):
            pass
        super().server_bind()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8099)
    ap.add_argument("--publish-dir", default=PUBLISH_DIR)
    ap.add_argument("--soco-url", default=SOCO_URL)
    args = ap.parse_args()

    Handler.publish_dir = args.publish_dir
    Handler.soco_url = args.soco_url

    srv = DualStackServer(("::", args.port), Handler)
    ip = "localhost"
    print(f"[web] serving {args.publish_dir} on [::]:{args.port} (dual-stack)", flush=True)
    print(f"[web] proxying /soco/* → {args.soco_url}", flush=True)
    print(f"[web] app URL: http://{ip}:{args.port}/  (and http://<workspace-ip>:8099/)",
          flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()