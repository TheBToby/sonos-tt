#!/usr/bin/env python3
"""
soco-mock-server.py — SoCo-CLI-compatible API server for the TEST environment.

The Raspberry Pi deployment talks to the real SoCo-CLI HTTP API server
(`soco-http-api-server`, port 5001). In the Coder test environment there is
no Sonos hardware, and the workspace container cannot reach the home LAN —
so this server provides the same JSON contract on port 5001 with simulated
speakers:

    GET /speakers                        → {"speakers": ["Büro", ...], ...}
    GET /<spk>/volume                    → {"result": "27", "exit_code": 0}
    GET /<spk>/state                     → {"result": "PLAYING", "exit_code": 0}
    GET /<spk>/track                     → {"result": "Title | Artist | Album | 3732", ...}
    GET /<spk>/album_art                 → {"result": "", "exit_code": 0}
    GET /<spk>/queue                     → {"items": [...]}
    GET /<spk>/playlists                 → {"result": "name1\\nname2", ...} or {"items": [...]}
    GET /<spk>/play | pause | next | previous  → {"exit_code": 0, ...}
    GET /<spk>/volume/<n>                → sets volume
    GET /<spk>/group/<coord>, GET /<spk>/ungroup, clear_queue, add_playlist_to_queue/<name>,
        play_from_queue/<n>              → {"exit_code": 0}

Contract notes (mirrors lib/services/sonos_api.dart):
  - All responses are JSON objects with at least "result" (string) and
    "exit_code" (int; 0 = success).
  - /speakers → list of names under "speakers".
  - /track → "Title | Artist | Album | durationSeconds".
  - /playlists → newline-separated titles in "result" (parser splits on '\n').

Run:  python3 deploy/soco-mock-server.py [--port 5001] [--bind ::]
"""
import argparse
import json
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ─── Simulated Sonos state (same fixture as the app's built-in mock) ────────
LOCK = threading.Lock()
STATE = {
    "speakers": [
        {"name": "Büro", "volume": 27},
        {"name": "Finn", "volume": 35},
        {"name": "Lena", "volume": 20},
        {"name": "Lounge", "volume": 45},
        {"name": "Move", "volume": 30},
        {"name": "Nils", "volume": 25},
    ],
    "playback": {
        "state": "PAUSED_PLAYBACK",  # PLAYING | PAUSED_PLAYBACK | STOPPED
        "title": "5 Minuten Harry Podcast #30",
        "artist": "Coldmirror",
        "album": "5 Minuten Harry Podcast",
        "duration": 3732,
        "position": 120,
    },
    "queue": [
        {"title": "5 Min Harry Podcast #30", "artist": "Coldmirror"},
        {"title": "5 Min Harry Podcast #26", "artist": "Coldmirror"},
        {"title": "5 Min Harry Podcast #25", "artist": "Coldmirror"},
    ],
    "playlists": [
        "Bibi Kampf um Kartoffelbrei",
        "Claudia",
        "Finn Playlist von Lena",
        "Jan & Henry",
        "Kids Dance",
        "Maluna",
        "Samstag – Nachmittagsmix",
        "Sternenschweif",
        "Yakari",
    ],
    "groups": [],  # list of {"coordinator": str, "members": [str, ...]}
}

TRACK_HEADERS = ["title", "artist", "album", "duration"]


def speaker_names():
    return [s["name"] for s in STATE["speakers"]]


def find_speaker(name):
    for s in STATE["speakers"]:
        if s["name"] == name:
            return s
    return None


def tick():
    """Advance simulated playback (called under LOCK)."""
    pb = STATE["playback"]
    if pb["state"] == "PLAYING":
        pb["position"] += 1
        if pb["position"] >= pb["duration"]:
            pb["position"] = 0


class SocoMockHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    # ---- helpers ----------------------------------------------------------
    def _json(self, obj, status=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        # Permissive CORS: allows pointing the browser app at any origin
        # (useful when serving the app from the Coder proxy host).
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.end_headers()
        self.wfile.write(body)

    def _result(self, value=""):
        self._json({"result": value, "exit_code": 0, "error_msg": ""})

    def log_message(self, fmt, *args):
        print(f"[soco-mock] {self.address_string()} {fmt % args}", flush=True)

    def do_OPTIONS(self):
        self._result()

    # ---- routing ----------------------------------------------------------
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        parts = [urllib.parse.unquote(p) for p in parsed.path.split("/") if p]

        with LOCK:
            tick()
            if not parts:
                return self._json({"status": "ok", "server": "soco-mock"})
            if parts[0] == "speakers":
                return self._json({"speakers": speaker_names()})
            if parts[0] == "events":
                # Event WebSocket is optional; advertise nothing (app degrades gracefully).
                return self._json({"status": "no events"}, status=404)

            if len(parts) >= 2:
                speaker = parts[0]
                action = parts[1]
                spk = find_speaker(speaker)
                if spk is None:
                    return self._json(
                        {"result": "", "exit_code": 1,
                         "error_msg": f"unknown speaker {speaker!r}"},
                        status=404)

                pb = STATE["playback"]

                # ---- simple commands ------------------------------------
                if action == "play":
                    pb["state"] = "PLAYING"
                    return self._result("OK")
                if action == "pause":
                    pb["state"] = "PAUSED_PLAYBACK"
                    return self._result("OK")
                if action == "next" or action == "previous":
                    pb["position"] = 0
                    return self._result("OK")
                if action == "state":
                    return self._result(pb["state"])
                if action == "volume" and len(parts) == 2:
                    return self._result(str(spk["volume"]))
                if action == "volume" and len(parts) == 3:
                    try:
                        spk["volume"] = max(0, min(100, int(parts[2])))
                    except ValueError:
                        pass
                    return self._result(str(spk["volume"]))
                if action == "track":
                    # parseTrackResult() expects "key: value" lines.
                    pos = int(pb["position"])
                    dur = int(pb["duration"])
                    elapsed = f"{pos // 3600}:{(pos % 3600) // 60:02d}:{pos % 60:02d}"
                    total = f"{dur // 3600}:{(dur % 3600) // 60:02d}:{dur % 60:02d}"
                    return self._result(
                        f"title: {pb['title']}\n"
                        f"artist: {pb['artist']}\n"
                        f"album: {pb['album']}\n"
                        f"duration: {total}\n"
                        f"elapsed: {elapsed}")
                if action == "album_art":
                    return self._result("")
                if action == "queue":
                    # parseQueueResult() expects "N: Title" lines.
                    return self._result("\n".join(
                        f"{i + 1}: {q['title']}"
                        for i, q in enumerate(STATE["queue"])))
                if action == "playlists":
                    # parsePlaylistsResult() expects "N: Title" lines.
                    return self._result("\n".join(
                        f"{i + 1}: {p}" for i, p in enumerate(STATE["playlists"])))
                if action == "groups":
                    # parseGroupsResult() expects "Coordinator: member1, member2" lines.
                    return self._result("\n".join(
                        f"{g['coordinator']}: {', '.join(g['members'])}"
                        for g in STATE["groups"]))
                if action == "clear_queue":
                    STATE["queue"] = []
                    return self._result("OK")
                if action == "add_playlist_to_queue" and len(parts) == 3:
                    pl = urllib.parse.unquote(parsed.path.split("/")[-1])
                    STATE["queue"] = [{"title": f"{pl} – Song {i+1}",
                                       "artist": "soco-mock"}
                                      for i in range(5)]
                    return self._result("OK")
                if action == "play_from_queue" and len(parts) == 3:
                    pb["state"] = "PLAYING"
                    return self._result("OK")
                if action == "group" and len(parts) == 3:
                    coord = urllib.parse.unquote(parsed.path.split("/")[-1])
                    STATE["groups"].append({"coordinator": coord,
                                            "members": [speaker]})
                    return self._result("OK")
                if action == "ungroup":
                    STATE["groups"] = [g for g in STATE["groups"]
                                       if speaker not in g["members"]]
                    return self._result("OK")

            return self._json({"result": "", "exit_code": 1,
                               "error_msg": f"unknown path {self.path!r}"},
                              status=404)


class DualStackServer(ThreadingHTTPServer):
    """Binds IPv6 dual-stack (::) when possible → serves IPv4 AND IPv6."""
    address_family = __import__("socket").AF_INET6

    def server_bind(self):
        try:
            self.socket.setsockopt(__import__("socket").IPPROTO_IPV6, 18, 0)  # IPV6_V6ONLY=0
        except OSError:
            pass
        super().server_bind()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=5001)
    ap.add_argument("--bind", default="::")
    args = ap.parse_args()

    addr = ("::", args.port) if ":" in args.bind else (args.bind, args.port)
    srv = DualStackServer(addr, SocoMockHandler)
    print(f"[soco-mock] listening on {args.bind}:{args.port} (dual-stack)", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()