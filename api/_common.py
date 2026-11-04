"""Shared helpers for the Vercel serverless functions (api/*.py).

Underscore prefix: Vercel does not route this file as an endpoint, and it
defines no `handler` entrypoint, so it can only ever be imported.
Stdlib-only.
"""
from __future__ import annotations

import json
import time
from collections import deque

MAX_BODY = 16 * 1024  # refuse absurd payloads before parsing
RATE_MAX = 30  # requests ...
RATE_WINDOW = 60.0  # ... per seconds, per client IP, per function instance
RETRY_AFTER = 60

# NOTE: this bucket lives in instance memory, so it resets on cold starts
# and is not shared across Vercel instances. It stops casual abuse and
# runaway clients; use Vercel Firewall / WAF rules for hard limits.
_hits: dict[str, deque] = {}


def client_ip(handler) -> str:
    """Best-effort client key. Vercel sets X-Forwarded-For."""
    fwd = handler.headers.get("X-Forwarded-For", "")
    if fwd:
        return fwd.split(",")[0].strip() or "anon"
    try:
        return handler.client_address[0] or "anon"
    except Exception:
        return "anon"


def rate_limited(ip: str, now: float | None = None) -> bool:
    """Sliding-window gate. True = reject this request (429)."""
    now = time.monotonic() if now is None else now
    q = _hits.setdefault(ip, deque())
    while q and now - q[0] > RATE_WINDOW:
        q.popleft()
    if len(q) >= RATE_MAX:
        return True
    q.append(now)
    return False


def reset_rate_limit() -> None:
    """Tests only: clear all buckets."""
    _hits.clear()


def read_json(handler, max_body: int = MAX_BODY) -> dict:
    """Capped, never-raising JSON body parser. Garbage -> {}."""
    try:
        length = int(handler.headers.get("Content-Length", 0))
    except (TypeError, ValueError):
        return {}
    if length <= 0 or length > max_body:
        return {}
    try:
        data = json.loads(handler.rfile.read(length).decode() or "{}")
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def send_json(handler, code: int, obj: dict,
              extra: dict | None = None) -> None:
    raw = json.dumps(obj).encode()
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(raw)))
    handler.send_header("Access-Control-Allow-Origin", "*")
    if extra:
        for k, v in extra.items():
            handler.send_header(k, v)
    handler.end_headers()
    handler.wfile.write(raw)


def send_options(handler) -> None:
    handler.send_response(204)
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.end_headers()


def guard(handler) -> bool:
    """Rate-limit gate. False = already answered 429, stop handling."""
    if rate_limited(client_ip(handler)):
        send_json(handler, 429, {"ok": False, "error": "rate limited"},
                  {"Retry-After": str(RETRY_AFTER)})
        return False
    return True


def serve_result(handler, result: dict) -> None:
    """200 for live Meta answers, 503 when only fallback is available.

    The game treats any non-200 as offline and uses its own (identical)
    fallback lines, so a keyless/broken deployment degrades loudly in
    status but silently in gameplay.
    """
    if isinstance(result, dict) and result.get("source") == "fallback":
        send_json(handler, 503,
                  {"ok": False, "error": "AI unavailable",
                   "source": "fallback"})
    else:
        send_json(handler, 200, result)
