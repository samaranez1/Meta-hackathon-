# AI Wingman backend (Meta Model API)

Stdlib-only Python 3.8+ - no `pip install` needed.

## Run

```bash
# Offline mode (built-in fallback lines, nothing needed):
python3 ai/server.py

# Full AI mode (Meta Muse Spark via the Model API):
META_API_KEY='LLM|...' META_MODEL=muse-spark-1.3 python3 ai/server.py
```

Or copy `ai/.env.example` to `ai/.env` and paste your key there -
the server loads it automatically, no `export` needed:

```bash
cp ai/.env.example ai/.env   # then paste META_API_KEY=... into ai/.env
python3 ai/server.py
```

Get a key + $150 hackathon credits from the Meta Model API dashboard
(`https://api.meta.ai/v1`, OpenAI-compatible). The server listens on
`http://127.0.0.1:8765` (`AI_PORT` to change).

## Endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | `{ok, meta_configured, model}` |
| POST | `/briefing` | Mission briefing + boss taunt + tip |
| POST | `/director` | Bounded difficulty decision + tip |
| POST | `/coach` | Post-run coaching advice |
| POST | `/art/emblem` | Victory emblem via `muse-image-1.0` (bonus, optional) |

Quick check:

```bash
curl localhost:8765/health
curl -X POST localhost:8765/briefing -H 'Content-Type: application/json' \
  -d '{"level":1,"level_name":"NEON DRIFT","hp_pct":100,"kills":0}'
```

The Godot game auto-detects this server. If it is not running (or the key
is missing), the game keeps playing with the same offline fallback lines,
and the HUD shows `AI OFFLINE`.

## Web export + Vercel

The web build talks to same-origin `/api/*` (no localhost). The Vercel
functions in `api/` reuse the same logic via `ai/wingman_core.py`:

- `GET /api/health`, `POST /api/briefing`, `/api/director`, `/api/coach`
- `POST /api/art/emblem` (bonus, returns `b64_json`, no files)

Deploy:

1. In Godot: `Project -> Export... -> Web -> Export Project` to
   `build/web/index.html` (already set in `export_presets.cfg`).
2. `vercel` from the repo root (uses `vercel.json`, serves `build/web/`
   + `api/`). Or `vercel --prod` to go live.
3. In the Vercel dashboard: `Project -> Settings -> Environment Variables`,
   add `META_API_KEY=LLM|...` (and optional `META_MODEL`), then redeploy.
   Without the key the game still plays with fallback lines (`AI LOCAL`).

Local logic lives in `ai/wingman_core.py`; `ai/server.py` and `api/*.py`
are thin wrappers, so desktop and web never drift.

## Tests

```bash
python3 ai/test_server.py   # stdlib unittest: endpoints + disconnect regression
```
