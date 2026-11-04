#!/usr/bin/env python3
"""Space Shooters: AI Wingman - backend on the Meta Model API.

Stdlib-only (no pip install needed):
    META_API_KEY=LLM|... python3 ai/server.py

Endpoints (all JSON):
    GET  /health          -> {"ok": true, "meta_configured": bool, "model": str}
    POST /briefing        -> mission briefing + boss taunt + tip
    POST /director        -> adaptive-difficulty decision (bounded) + tip
    POST /coach           -> post-run coaching advice
    POST /art/emblem      -> victory emblem via Muse Image (optional, saved to generated_images/)

Every endpoint works WITHOUT a key via built-in fallback templates, so the
game and judges can run fully offline. With META_API_KEY set, text comes
from Meta's Muse Spark model through the OpenAI-compatible Model API at
https://api.meta.ai/v1.

Web/Vercel: the same logic lives in ai/wingman_core.py and is reused by
api/*.py serverless functions (same-origin /api/* for the web export).
"""
from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

try:
    import ai.wingman_core as core  # Vercel / package import
except Exception:
    import wingman_core as core  # local: python3 ai/server.py / tests

# Re-exported for backward compat (tests patch server.chat / META_API_KEY).
META_BASE_URL = core.META_BASE_URL
META_MODEL = core.META_MODEL
META_API_KEY = core.META_API_KEY
AI_PORT = core.AI_PORT
LLM_TIMEOUT = core.LLM_TIMEOUT
BOSSES = core.BOSSES
chat = core.chat
clamp = core.clamp
fallback_briefing = core.fallback_briefing


def _sync_to_core() -> None:
    """Push server globals (possibly patched by tests) into the core module."""
    core.META_BASE_URL = META_BASE_URL
    core.META_MODEL = META_MODEL
    core.META_API_KEY = META_API_KEY
    core.LLM_TIMEOUT = LLM_TIMEOUT
    core.chat = chat


def make_briefing(p: dict) -> dict:
    _sync_to_core()
    return core.make_briefing(p)


def make_director(p: dict) -> dict:
    _sync_to_core()
    return core.make_director(p)


def make_coach(p: dict) -> dict:
    _sync_to_core()
    return core.make_coach(p)


def make_emblem(p: dict) -> dict:
    """Bonus: victory emblem via Muse Image. Saved to generated_images/."""
    _sync_to_core()
    data = core.make_emblem_data(p)
    if not data.get("ok"):
        return {"ok": False, "error": str(data.get("error", "failed"))[:200]}
    try:
        import base64
        out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                               "generated_images")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, "ai_emblem.png")
        with open(path, "wb") as f:
            f.write(base64.b64decode(data["b64_json"]))
        return {"ok": True, "path": path, "source": data.get("source", "")}
    except Exception as e:
        return {"ok": False, "error": str(e)[:200]}


ROUTES = {"/briefing": make_briefing, "/director": make_director,
          "/coach": make_coach, "/art/emblem": make_emblem}


class Handler(BaseHTTPRequestHandler):
    server_version = "AIWingman/1.0"

    def _send(self, code: int, obj: dict) -> None:
        # Clients (e.g. the game) may disconnect while a slow LLM call is
        # still running; a dead socket must stay silent, never a traceback.
        try:
            raw = json.dumps(obj).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(raw)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        if self.path.rstrip("/").endswith("/health") or self.path in ("/", "/health"):
            _sync_to_core()
            self._send(200, core.health_payload())
        else:
            self._send(404, {"ok": False, "error": "unknown endpoint"})

    def do_POST(self):
        fn = ROUTES.get(self.path.rstrip("/"))
        if fn is None:
            self._send(404, {"ok": False, "error": "unknown endpoint"})
            return
        try:
            length = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(length).decode() or "{}")
        except (BrokenPipeError, ConnectionResetError):
            return
        except Exception:
            payload = {}
        try:
            self._send(200, fn(payload if isinstance(payload, dict) else {}))
        except (BrokenPipeError, ConnectionResetError):
            pass
        except Exception as e:
            self._send(500, {"ok": False, "error": str(e)[:200]})

    def log_message(self, *a):
        pass


def main() -> None:
    srv = ThreadingHTTPServer(("127.0.0.1", AI_PORT), Handler)
    print("AI Wingman on http://127.0.0.1:%d  meta_configured=%s  model=%s"
          % (AI_PORT, bool(META_API_KEY), META_MODEL), flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
