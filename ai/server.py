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
"""
from __future__ import annotations

import json
import os
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def _load_dotenv() -> None:
    """Load ai/.env (next to this file) so a pasted key just works.
    Real environment variables take precedence over the file."""
    try:
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
        with open(path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip("'\"")
                if k and k not in os.environ:
                    os.environ[k] = v
    except Exception:
        pass


_load_dotenv()

META_BASE_URL = os.environ.get("META_BASE_URL", "https://api.meta.ai/v1").rstrip("/")
META_MODEL = os.environ.get("META_MODEL", "muse-spark-1.3")
META_API_KEY = os.environ.get("META_API_KEY", os.environ.get("META_MODEL_API_KEY", ""))
AI_PORT = int(os.environ.get("AI_PORT", "8765"))
LLM_TIMEOUT = float(os.environ.get("AI_LLM_TIMEOUT", "12"))

BOSSES = {
    1: "VEX WARDEN", 2: "NEBULA TWINS", 3: "CHROMA HYDRA",
    4: "VOID REAPER", 5: "STAR EATER PRIME",
}


# ---------------------------------------------------------------- LLM helper ---

def chat(system: str, user: str, max_tokens: int = 160, temp: float = 0.8) -> str | None:
    """One short chat completion via the Meta Model API. None on any failure."""
    if not META_API_KEY:
        return None
    body = json.dumps({
        "model": META_MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": max_tokens,
        "temperature": temp,
        # Muse Spark is a reasoning model: without this it spends the whole
        # token budget thinking and returns empty content.
        "reasoning_effort": "minimal",
    }).encode()
    req = urllib.request.Request(
        META_BASE_URL + "/chat/completions", data=body,
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + META_API_KEY},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=LLM_TIMEOUT) as r:
            data = json.loads(r.read().decode())
        content = data["choices"][0]["message"].get("content") or ""
        if isinstance(content, list):  # multipart content blocks
            content = "".join(
                p.get("text", "") for p in content if isinstance(p, dict))
        text = content.strip()
        return text or None
    except Exception:
        return None


def clamp(v: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, v))


def _chat_json(system: str, user: str, max_tokens: int, temp: float,
               what: str) -> tuple[dict | None, str | None]:
    """chat() + JSON extraction with one retry. Returns (dict, raw)."""
    for attempt in range(2):
        out = chat(system, user, max_tokens=max_tokens, temp=temp)
        if out:
            try:
                start, end = out.index("{"), out.rindex("}") + 1
                return json.loads(out[start:end]), out
            except Exception:
                print("[wingman] %s: bad LLM JSON (try %d); raw=%r"
                      % (what, attempt + 1, out[:150]), flush=True)
        else:
            print("[wingman] %s: LLM call failed (try %d)"
                  % (what, attempt + 1), flush=True)
    return None, None


# ------------------------------------------------------------------ logic ---

def fallback_briefing(level: int, level_name: str) -> dict:
    tips = {
        1: "Guns are automatic - focus on dodging and grab every P pickup.",
        2: "Snipers telegraph before firing. Strafe sideways, never sit still.",
        3: "Elites drop the best loot. Save one bomb for the HYDRA's spiral.",
        4: "The REAPER cloaks before it dashes. Watch for the shimmer.",
        5: "Final sector. Spend every bomb - there is nothing after this.",
    }
    taunts = {
        1: "VEX WARDEN: 'Your little ship amuses me. It will make fine debris.'",
        2: "NEBULA TWINS: 'Two minds. One crossfire. Zero survivors.'",
        3: "CHROMA HYDRA: 'Cut one pattern down and two more take its place.'",
        4: "VOID REAPER: 'I have already killed you. You are just catching up.'",
        5: "STAR EATER PRIME: 'I unmade a thousand suns. You are a spark.'",
    }
    return {
        "briefing": "SECTOR %d - %s. Wingman online. %s" % (level, level_name, tips.get(level, tips[1])),
        "taunt": taunts.get(level, taunts[1]),
        "tip": tips.get(level, tips[1]),
        "source": "fallback",
    }


def make_briefing(p: dict) -> dict:
    level = int(p.get("level", 1))
    level_name = str(p.get("level_name", "UNKNOWN"))
    boss = BOSSES.get(level, "UNKNOWN")
    fb = fallback_briefing(level, level_name)
    d, _raw = _chat_json(
        "You are the AI wingman computer of a retro arcade space shooter. "
        "Clean, family-friendly, punchy, under 25 words per field. Reply "
        "with EXACTLY this JSON object and no other text: "
        '{"briefing": "...", "taunt": "BOSS NAME: ...", "tip": "..."}.',
        "Level %d of 5, sector '%s', end boss '%s'. Player hull %s%%, kills %s. "
        "The taunt field must start with '%s: '." % (
            level, level_name, boss, p.get("hp_pct", 100), p.get("kills", 0), boss),
        500, 0.6, "briefing",
    )
    if d:
        return {"briefing": str(d.get("briefing", fb["briefing"]))[:220],
                "taunt": str(d.get("taunt", fb["taunt"]))[:220],
                "tip": str(d.get("tip", fb["tip"]))[:220],
                "source": "meta:" + META_MODEL}
    return fb


def make_director(p: dict) -> dict:
    """Adaptive difficulty. Numbers are ALWAYS safety-bounded; the LLM only
    tunes within bounds and writes the coaching tip."""
    hp = clamp(float(p.get("hp_frac", 1.0)), 0.0, 1.0)
    kpm = clamp(float(p.get("kills_per_min", 5.0)), 0.0, 60.0)
    deaths = int(p.get("deaths", 0))
    # Rule-grounded base: struggling -> easier, cruising -> spicier.
    if hp < 0.35 or deaths > 0:
        interval, scale = 1.35, 0.85
        tip = "Wingman easing pressure - grab shields and breathe."
    elif hp > 0.8 and kpm > 12:
        interval, scale = 0.85, 1.15
        tip = "You are cruising - Wingman is turning up the heat."
    else:
        interval, scale = 1.0, 1.0
        tip = "Holding steady. Keep moving in small circles."
    d, _raw = _chat_json(
        "You are the AI difficulty director of a family-friendly arcade "
        "space shooter. Reply with EXACTLY this JSON object and no other "
        "text: "
        '{"spawn_interval_mult": 0.8-1.4, "enemy_scale_mult": 0.8-1.2, "tip": "one short clean tip"}.',
        "Level %s, hull %.0f%%, kills/min %.1f, deaths %d. Base suggestion: "
        "interval x%.2f, scale x%.2f." % (
            p.get("level", 1), hp * 100, kpm, deaths, interval, scale),
        500, 0.5, "director",
    )
    if d:
        interval = clamp(float(d.get("spawn_interval_mult", interval)), 0.8, 1.4)
        scale = clamp(float(d.get("enemy_scale_mult", scale)), 0.8, 1.2)
        tip = str(d.get("tip", tip))[:160]
        return {"spawn_interval_mult": round(interval, 3),
                "enemy_scale_mult": round(scale, 3),
                "tip": tip, "source": "meta:" + META_MODEL}
    return {"spawn_interval_mult": interval, "enemy_scale_mult": scale,
            "tip": tip, "source": "fallback"}


def make_coach(p: dict) -> dict:
    victory = bool(p.get("victory", False))
    if victory:
        fb = ("Galaxy saved, pilot! Try a no-bomb run next - you clearly "
              "do not need the training wheels.")
    else:
        lvl = int(p.get("level_reached", 1))
        fb = ("Good run to sector %d. Spend coins on HULL in the Hangar, and "
              "dodge toward the gaps, not away from bullets.") % lvl
    out = chat(
        "You are the AI coach of a retro arcade space shooter. One or two "
        "short sentences, specific and encouraging, under 40 words, clean "
        "and family-friendly. Plain text only.",
        "Run over. Victory: %s. Score %s, kills %s, reached level %s of 5, "
        "deaths %s." % (victory, p.get("score", 0), p.get("kills", 0),
                        p.get("level_reached", 1), p.get("deaths", 0)),
        max_tokens=300,
    )
    return {"advice": (out[:300] if out else fb),
            "source": ("meta:" + META_MODEL) if out else "fallback"}


def make_emblem(p: dict) -> dict:
    """Bonus: victory emblem via Muse Image. Returns path or error; never fatal."""
    if not META_API_KEY:
        return {"ok": False, "error": "META_API_KEY not set"}
    prompt = ("Retro arcade victory emblem, pixel-art starship medal over a "
              "nebula, gold and cyan, no text. Sector: %s." % p.get("level_name", "deep space"))
    body = json.dumps({"model": "muse-image-1.0", "prompt": prompt,
                       "size": "1024x1024"}).encode()
    req = urllib.request.Request(
        META_BASE_URL + "/images/generations", data=body,
        headers={"Content-Type": "application/json",
                 "Authorization": "Bearer " + META_API_KEY},
        method="POST",
    )
    try:
        import base64
        with urllib.request.urlopen(req, timeout=60) as r:
            data = json.loads(r.read().decode())
        item = data["data"][0]
        out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                               "generated_images")
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, "ai_emblem.png")
        if "b64_json" in item:
            with open(path, "wb") as f:
                f.write(base64.b64decode(item["b64_json"]))
        elif "url" in item:
            with urllib.request.urlopen(item["url"], timeout=60) as r, open(path, "wb") as f:
                f.write(r.read())
        else:
            return {"ok": False, "error": "unexpected image response"}
        return {"ok": True, "path": path, "source": "meta:muse-image-1.0"}
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
            self._send(200, {"ok": True, "meta_configured": bool(META_API_KEY),
                             "model": META_MODEL})
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
