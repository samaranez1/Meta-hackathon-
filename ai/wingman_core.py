"""Space Shooters: AI Wingman - shared logic for local server + Vercel.

This module holds all Meta Model API logic so both backends stay in sync:
  - ai/server.py (local ThreadingHTTPServer for desktop/Godot runs)
  - api/*.py (Vercel serverless functions for the web export)

Stdlib-only. Works without a key via fallback templates.
"""
from __future__ import annotations

import json
import os
import urllib.request


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

# META_API_URL is accepted as an alias (Vercel dashboard name); a set
# META_BASE_URL keeps precedence so existing deployments never change.
META_BASE_URL = (
    os.environ.get("META_BASE_URL")
    or os.environ.get("META_API_URL")
    or "https://api.meta.ai/v1"
).rstrip("/")
META_MODEL = os.environ.get("META_MODEL", "muse-spark-1.3")
META_API_KEY = os.environ.get("META_API_KEY", os.environ.get("META_MODEL_API_KEY", ""))
AI_PORT = int(os.environ.get("AI_PORT", "8765"))
LLM_TIMEOUT = float(os.environ.get("AI_LLM_TIMEOUT", "12"))
LLM_RETRIES = int(os.environ.get("AI_LLM_RETRIES", "2"))

# Vercel hobby functions time out after ~10s, so a slow 2x12s LLM retry
# would always 504. On Vercel: single short attempt, fast fallback.
if os.environ.get("VERCEL"):
    LLM_TIMEOUT = min(LLM_TIMEOUT, 7.0)
    LLM_RETRIES = min(LLM_RETRIES, 1)

BOSSES = {
    1: "VEX WARDEN", 2: "NEBULA TWINS", 3: "CHROMA HYDRA",
    4: "VOID REAPER", 5: "STAR EATER PRIME",
}


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


def s_int(v, default: int = 0, lo: int | None = None,
          hi: int | None = None) -> int:
    """Lenient int: garbage -> default, then range-clamped. Never raises."""
    try:
        n = int(v)
    except (TypeError, ValueError):
        return default
    if lo is not None:
        n = max(lo, n)
    if hi is not None:
        n = min(hi, n)
    return n


def s_float(v, default: float = 0.0, lo: float | None = None,
            hi: float | None = None) -> float:
    """Lenient float: garbage/NaN -> default, then range-clamped."""
    try:
        n = float(v)
    except (TypeError, ValueError):
        return default
    if n != n:  # NaN
        return default
    if lo is not None:
        n = max(lo, n)
    if hi is not None:
        n = min(hi, n)
    return n


def s_str(v, default: str = "", max_len: int = 64) -> str:
    """Lenient capped string: null/bool/empty -> default. Never raises."""
    if v is None or isinstance(v, bool):
        return default
    try:
        s = str(v).strip()
    except Exception:
        return default
    if not s:
        return default
    return s[:max_len]


def s_bool(v, default: bool = False) -> bool:
    """Lenient bool: parses 1/0/true/false/yes/no; else default."""
    if isinstance(v, bool):
        return v
    if v is None:
        return default
    if isinstance(v, (int, float)):
        return bool(v)
    if isinstance(v, str):
        t = v.strip().lower()
        if t in ("1", "true", "yes", "y", "on"):
            return True
        if t in ("0", "false", "no", "n", "off", ""):
            return False
    return default


def _chat_json(system: str, user: str, max_tokens: int, temp: float,
               what: str) -> tuple[dict | None, str | None]:
    """chat() + JSON extraction with retries. Returns (dict, raw)."""
    for attempt in range(max(1, LLM_RETRIES)):
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


def fallback_director(hp_frac: float, kills_per_min: float, deaths: int) -> dict:
    """Rule-grounded difficulty base. Mirrored in scripts/meta_ai.gd."""
    hp = clamp(s_float(hp_frac, 1.0), 0.0, 1.0)
    kpm = clamp(s_float(kills_per_min, 5.0), 0.0, 60.0)
    d = s_int(deaths, 0, 0, 1000000)
    if hp < 0.35 or d > 0:
        return {"spawn_interval_mult": 1.35, "enemy_scale_mult": 0.85,
                "tip": "Wingman easing pressure - grab shields and breathe.",
                "source": "fallback"}
    if hp > 0.8 and kpm > 12:
        return {"spawn_interval_mult": 0.85, "enemy_scale_mult": 1.15,
                "tip": "You are cruising - Wingman is turning up the heat.",
                "source": "fallback"}
    return {"spawn_interval_mult": 1.0, "enemy_scale_mult": 1.0,
            "tip": "Holding steady. Keep moving in small circles.",
            "source": "fallback"}


def make_briefing(p: dict) -> dict:
    level = s_int(p.get("level", 1), 1, 1, 5)
    level_name = s_str(p.get("level_name", "UNKNOWN"), "UNKNOWN", 64)
    hp_pct = s_int(p.get("hp_pct", 100), 100, 0, 100)
    kills = s_int(p.get("kills", 0), 0, 0, 1000000)
    boss = BOSSES.get(level, "UNKNOWN")
    fb = fallback_briefing(level, level_name)
    d, _raw = _chat_json(
        "You are the AI wingman computer of a retro arcade space shooter. "
        "Clean, family-friendly, punchy, under 25 words per field. Reply "
        "with EXACTLY this JSON object and no other text: "
        '{"briefing": "...", "taunt": "BOSS NAME: ...", "tip": "..."}.',
        "Level %d of 5, sector '%s', end boss '%s'. Player hull %s%%, kills %s. "
        "The taunt field must start with '%s: '." % (
            level, level_name, boss, hp_pct, kills, boss),
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
    hp = clamp(s_float(p.get("hp_frac", 1.0), 1.0), 0.0, 1.0)
    kpm = clamp(s_float(p.get("kills_per_min", 5.0), 5.0), 0.0, 60.0)
    deaths = s_int(p.get("deaths", 0), 0, 0, 1000000)
    level = s_int(p.get("level", 1), 1, 1, 5)
    base = fallback_director(hp, kpm, deaths)
    interval, scale, tip = (base["spawn_interval_mult"],
                            base["enemy_scale_mult"], base["tip"])
    d, _raw = _chat_json(
        "You are the AI difficulty director of a family-friendly arcade "
        "space shooter. Reply with EXACTLY this JSON object and no other "
        "text: "
        '{"spawn_interval_mult": 0.8-1.4, "enemy_scale_mult": 0.8-1.2, "tip": "one short clean tip"}.',
        "Level %s, hull %.0f%%, kills/min %.1f, deaths %d. Base suggestion: "
        "interval x%.2f, scale x%.2f." % (
            level, hp * 100, kpm, deaths, interval, scale),
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
    victory = s_bool(p.get("victory", False))
    score = s_int(p.get("score", 0), 0, 0, 10000000)
    kills = s_int(p.get("kills", 0), 0, 0, 1000000)
    lvl = s_int(p.get("level_reached", 1), 1, 1, 5)
    deaths = s_int(p.get("deaths", 0), 0, 0, 1000000)
    if victory:
        fb = ("Galaxy saved, pilot! Try a no-bomb run next - you clearly "
              "do not need the training wheels.")
    else:
        fb = ("Good run to sector %d. Spend coins on HULL in the Hangar, and "
              "dodge toward the gaps, not away from bullets.") % lvl
    out = chat(
        "You are the AI coach of a retro arcade space shooter. One or two "
        "short sentences, specific and encouraging, under 40 words, clean "
        "and family-friendly. Plain text only.",
        "Run over. Victory: %s. Score %s, kills %s, reached level %s of 5, "
        "deaths %s." % (victory, score, kills, lvl, deaths),
        max_tokens=300,
    )
    return {"advice": (out[:300] if out else fb),
            "source": ("meta:" + META_MODEL) if out else "fallback"}


def make_emblem_data(p: dict) -> dict:
    """Victory emblem via Muse Image. Returns b64 (serverless-safe, no files).
    Never fatal: returns {"ok": False, ...} on any failure."""
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
        if "b64_json" in item:
            return {"ok": True, "b64_json": item["b64_json"],
                    "mime": "image/png", "source": "meta:muse-image-1.0"}
        if "url" in item:
            with urllib.request.urlopen(item["url"], timeout=60) as r:
                raw = r.read()
            return {"ok": True,
                    "b64_json": base64.b64encode(raw).decode(),
                    "mime": "image/png", "source": "meta:muse-image-1.0"}
        return {"ok": False, "error": "unexpected image response"}
    except Exception as e:
        return {"ok": False, "error": str(e)[:200]}


def health_payload() -> dict:
    return {"ok": True, "meta_configured": bool(META_API_KEY),
            "model": META_MODEL}
