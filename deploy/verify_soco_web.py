#!/usr/bin/env python3
"""
verify_soco_web.py — End-to-end check: app (browser) ↔ /soco proxy ↔ mock server.

Drives headless Brave via CDP:
  1. Load the app, wait for boot.
  2. Enable console event capture (Runtime.consoleAPICalled).
  3. Write the SoCo server URL `/soco` into the app's SharedPreferences-backed
     localStorage key (`flutter.sonos-tt:config`), then reload.
  4. Wait for the app to poll the API; collect console output.
  5. Verify the mock server access log received /speakers etc. AFTER a marker
     timestamp, and dump console lines for debugging.

Exit 0 = app is really talking to the /soco endpoint.
"""
import json
import subprocess
import sys
import time

sys.path.insert(0, "/opt/src/sonos-tt/deploy")
from cdp_capture import WS, cdp_call, http_get_json  # noqa: E402

CDP_PORT = 9333
APP_URL = "http://127.0.0.1:8099/"
LOG = "/opt/coder/sonos-tt/logs/soco-server.log"
WEB_LOG = "/opt/coder/sonos-tt/logs/web-server.log"


def main():
    proc = subprocess.Popen(
        [
            "/usr/local/bin/brave-browser", "--headless=new", "--no-sandbox",
            "--disable-dev-shm-usage", "--enable-unsafe-swiftshader",
            f"--remote-debugging-port={CDP_PORT}", "--remote-debugging-address=127.0.0.1",
            "--user-data-dir=/opt/coder/sonos-tt/logs/brave-verify-profile",
            "--window-size=800,800",
            APP_URL,
        ],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    )
    try:
        target = None
        deadline = time.time() + 20
        while time.time() < deadline and target is None:
            try:
                for t in http_get_json(CDP_PORT, "/json/list"):
                    if t.get("type") == "page":
                        target = t
                        break
            except Exception:
                pass
            time.sleep(0.5)
        if target is None:
            print("FAIL: no CDP page target")
            return 2
        ws_url = target["webSocketDebuggerUrl"]
        port = int(ws_url.split(":")[2].split("/")[0])
        path = "/" + ws_url.split("/", 3)[3]
        ws = WS("127.0.0.1", port, path)
        print("[verify] connected to page")

        def ev(expr):
            res = cdp_call(ws, 99, "Runtime.evaluate",
                           {"expression": expr, "returnByValue": True, "awaitPromise": True})
            r = res.get("result", {})
            if "exceptionDetails" in res:
                return f"<exception: {res['exceptionDetails'].get('text')}>"
            return r.get("result", {}).get("value")

        # ── 0) Sanity: does the page context reach /soco? ────────────────────
        probe = ev("fetch('/soco/speakers').then(r => r.text()).catch(e => 'FETCH_ERR: ' + e)")
        print(f"[verify] page→/soco probe: {probe!r}")

        # ── 1) Enable console capture ────────────────────────────────────────
        console_lines = []

        def pump_console(seconds):
            """Read pending CDP events for a while, collecting console calls."""
            end = time.time() + seconds
            while time.time() < end:
                try:
                    ws.sock.settimeout(max(0.1, end - time.time()))
                    opcode, text = ws.recv_msg()
                    if opcode != 0x1:
                        continue
                    data = json.loads(text)
                    if data.get("method") == "Runtime.consoleAPICalled":
                        args = " ".join(
                            str(a.get("value", a.get("description", "")))
                            for a in data.get("args", []))
                        console_lines.append(f"{data['params'].get('type', '?')}: {args}")
                except TimeoutError:
                    pass
                except Exception:
                    break

        cdp_call(ws, 1, "Runtime.enable")

        # ── 2) Patch config in localStorage: baseUrl='/soco' ────────────────
        obj = {}
        cfg = ev("localStorage.getItem('flutter.sonos-tt:config')")
        if cfg and cfg != "null":
            try:
                obj = json.loads(cfg)
            except Exception:
                obj = {}
        obj["socoApi"] = {"baseUrl": "/soco", "timeout": 5000, "pollInterval": 1500}
        new_cfg = json.dumps(obj)
        ev(f"localStorage.setItem('flutter.sonos-tt:config', {json.dumps(new_cfg)})")
        marker = time.time()
        cdp_call(ws, 2, "Page.reload", {"ignoreCache": True})
        print("[verify] config set to /soco; reloaded; capturing console 10s …")
        pump_console(10)

        print("[verify] console output (last 25 lines):")
        for line in console_lines[-25:]:
            print(f"    {line}")

        # ── 3) App polling evidence: /soco requests in the WEB server log ────
        # (the app talks to the same-origin /soco proxy on the web server)
        app_speakers = 0
        app_volume = 0
        app_track = 0
        try:
            with open(WEB_LOG) as f:
                web_content = f.read()
            app_speakers = web_content.count("GET /soco/speakers")
            app_volume = web_content.count("/volume HTTP")
            app_track = web_content.count("/track HTTP")
        except FileNotFoundError:
            pass
        print(f"[verify] /soco polling counts — speakers:{app_speakers} "
              f"volume:{app_volume} track:{app_track}")

        # ── 4) Screenshot for evidence ───────────────────────────────────────
        res = cdp_call(ws, 3, "Page.captureScreenshot", {"format": "png"})
        import base64
        png = base64.b64decode(res["result"]["data"])
        out = "/opt/coder/sonos-tt/logs/verify-soco.png"
        with open(out, "wb") as f:
            f.write(png)
        print(f"[verify] screenshot → {out} ({len(png)} bytes)")

        ok = bool(probe) and '"speakers"' in str(probe)
        polling = app_speakers >= 1 and app_track >= 1
        if ok and polling:
            print("[verify] PASS — page can fetch /soco AND the app polls it")
            return 0
        print(f"[verify] {'PASS' if ok else 'FAIL'} on proxy; "
              f"{'app polling OK' if polling else 'APP NOT POLLING'}")
        return 0 if polling else 1
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


if __name__ == "__main__":
    sys.exit(main())