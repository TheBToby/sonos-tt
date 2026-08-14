#!/usr/bin/env python3
"""
cdp_capture.py — Dependency-free CDP client for smoke-testing web pages.

Brave/Chromium headless's `--screenshot` waits for the page "load complete"
event, which Flutter web apps (infinite animation loop) never emit. This tool
instead drives the browser via the DevTools protocol:

    1. Browser must run with --remote-debugging-port=PORT
    2. We fetch the page target's WebSocket URL from /json/list
    3. Over a raw stdlib WebSocket we call:
         Runtime.evaluate  → document.documentElement.outerHTML
         Page.captureScreenshot → PNG (base64 payload)

Usage:
    python3 cdp_capture.py --port 9333 --wait 12 \
        --dom-out dom.html --png-out shot.png [--marker flutter-view]

Exits 0 if the page returned a DOM and (if --marker given) contains it.
"""
import argparse
import base64
import hashlib
import json
import os
import secrets
import socket
import struct
import sys
import time
import urllib.request

API = "http://127.0.0.1"


def http_get_json(port, path):
    with urllib.request.urlopen(f"{API}:{port}{path}", timeout=5) as r:
        return json.loads(r.read().decode())


class WS:
    """Minimal RFC6455 WebSocket client (text frames only) — stdlib only."""

    def __init__(self, host, port, path):
        self.sock = socket.create_connection((host, port), timeout=30)
        key = base64.b64encode(secrets.token_bytes(16)).decode()
        req = (
            f"GET {path} HTTP/1.1\r\n"
            f"Host: {host}:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(req.encode())
        # Read handshake response headers
        buf = b""
        while b"\r\n\r\n" not in buf:
            chunk = self.sock.recv(4096)
            if not chunk:
                raise ConnectionError("WebSocket handshake failed (empty)")
            buf += chunk
        status = buf.split(b"\r\n", 1)[0].decode()
        if "101" not in status:
            raise ConnectionError(f"WebSocket handshake rejected: {status}")
        self.buf = buf.split(b"\r\n\r\n", 1)[1]

    def _read_exact(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("socket closed")
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send_text(self, text):
        payload = text.encode()
        mask = secrets.token_bytes(4)
        header = bytes([0x81])  # FIN + text opcode
        n = len(payload)
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(header + mask + masked)

    def recv_msg(self):
        """Read one complete message (handles fragmentation minimally)."""
        msgs = b""
        while True:
            b1, b2 = self._read_exact(2)
            opcode = b1 & 0x0F
            fin = b1 & 0x80
            n = b2 & 0x7F
            if n == 126:
                (n,) = struct.unpack(">H", self._read_exact(2))
            elif n == 127:
                (n,) = struct.unpack(">Q", self._read_exact(8))
            msgs += self._read_exact(n)
            if fin:
                return opcode, msgs.decode("utf-8", "replace")

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def cdp_call(ws, msg_id, method, params=None):
    ws.send_text(json.dumps(
        {"id": msg_id, "method": method, "params": params or {}}))
    while True:
        opcode, text = ws.recv_msg()
        if opcode == 0x8:  # close
            raise ConnectionError("WebSocket closed by peer")
        data = json.loads(text)
        if data.get("id") == msg_id:
            return data


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--wait", type=float, default=10.0,
                    help="seconds to let the page boot before capturing")
    ap.add_argument("--dom-out")
    ap.add_argument("--png-out")
    ap.add_argument("--marker",
                    help="string that must appear in the DOM (e.g. flutter-view)")
    args = ap.parse_args()

    # Find the page target
    target = None
    deadline = time.time() + 15
    while time.time() < deadline:
        try:
            for t in http_get_json(args.port, "/json/list"):
                if t.get("type") == "page":
                    target = t
                    break
            if target:
                break
        except Exception:
            pass
        time.sleep(0.5)
    if not target:
        print("ERROR: no page target found via CDP", file=sys.stderr)
        return 2

    ws_url = target["webSocketDebuggerUrl"]
    host = "127.0.0.1"
    port = int(ws_url.split(":")[2].split("/")[0])
    path = "/" + ws_url.split("/", 3)[3]

    ws = WS(host, port, path)
    print(f"[cdp] connected to page target: {target.get('title', '?')}")

    # Give the app time to boot (engine download + first frames)
    print(f"[cdp] waiting {args.wait:.0f}s for app boot …")
    time.sleep(args.wait)

    ok = True

    # 1) DOM
    if args.dom_out:
        res = cdp_call(ws, 1, "Runtime.evaluate",
                       {"expression": "document.documentElement.outerHTML",
                        "returnByValue": True})
        dom = res.get("result", {}).get("result", {}).get("value", "")
        with open(args.dom_out, "w") as f:
            f.write(dom)
        print(f"[cdp] DOM → {args.dom_out} ({len(dom)} bytes)")
        if args.marker:
            if args.marker in dom:
                print(f"[cdp] ✓ DOM contains marker '{args.marker}'")
            else:
                print(f"[cdp] ✗ DOM MISSING marker '{args.marker}'")
                ok = False

    # 2) Screenshot
    if args.png_out:
        res = cdp_call(ws, 2, "Page.captureScreenshot", {"format": "png"})
        b64 = res.get("result", {}).get("data")
        if b64:
            png = base64.b64decode(b64)
            with open(args.png_out, "wb") as f:
                f.write(png)
            print(f"[cdp] PNG → {args.png_out} ({len(png)} bytes)")
        else:
            print("[cdp] ✗ screenshot failed", file=sys.stderr)
            ok = False

    ws.close()
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())