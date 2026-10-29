# Space Shooters: AI Wingman - Meta Global AI Developer Hackathon submission

**Track:** Indie Developer
**Theme:** Build for Your World
**One-liner:** A retro arcade space shooter with an AI wingman that briefs
you, taunts you, adapts difficulty to your skill, and coaches you after
every run - all powered by Meta's Muse Spark through the Meta Model API.

## The problem (why this wins on Impact, 30%)

Casual mobile players bounce off arcade shooters: too hard = quit, too
easy = bored. Static difficulty curves fit nobody. AI Wingman keeps every
player in flow with a skill-aware AI director, and keeps them coming back
with fresh AI mission briefings, boss taunts, and coaching - a problem I
know firsthand as a mobile arcade player.

## Meta AI usage (Creative use, 25%)

| Feature | Meta tech | What it does |
|---|---|---|
| Mission briefing + boss taunts | `muse-spark-1.3` via Model API | Fresh briefing, taunt, and tip per sector, aware of hull/kills |
| AI Director | `muse-spark-1.3` via Model API | Retunes spawn rate + enemy strength every 12 s inside safety bounds, with a coaching tip |
| Post-run Coach | `muse-spark-1.3` via Model API | Personalized advice on game over / victory |
| Victory emblem (bonus) | `muse-image-1.0` via Model API | Generates a victory medal into `generated_images/` |
| Built with | Muse Code | AI-assisted development |

- **Voiceover (bonus, on-device TTS):** boss taunts (deep pitch), wingman
  tips and coach advice are spoken aloud via Godot's text-to-speech while
  the text stays on screen; `VOX` button toggles it, preference is saved.

All calls go through the OpenAI-compatible endpoint `https://api.meta.ai/v1`
(see `ai/server.py`). The game shows a live HUD badge: `AI META` (Meta API),
`AI LOCAL` (server, no key), `AI OFF` (offline fallback - game always plays).

Safety note for judges: the Director's numbers are clamped server-side
(interval x0.8-1.4, strength x0.8-1.2) and re-clamped in the game, so the
LLM can never soft-lock or trivialize a run.

## Architecture (Technical depth, 20%)

```
Godot 4.7 game (GDScript)              Python backend (stdlib only)
+---------------------------+         +--------------------------------+
| main.gd  game flow        |  HTTP   | ai/server.py                   |
| meta_ai.gd  AI client +---+-------->| /briefing /director /coach     |
|   offline fallback        |  :8765  | /art/emblem  /health           |
| hud.gd  AI badge + lines  |         +------+-------------------------+
+---------------------------+                | OpenAI-compatible
                                             v
                                  Meta Model API (api.meta.ai/v1)
                                  muse-spark-1.3 / muse-image-1.0
```

Key files: `ai/server.py`, `scripts/meta_ai.gd`, AI hooks in
`scripts/main.gd`, AI badge in `scripts/hud.gd`.

## Run it (judge quickstart, < 3 min)

1. Start the AI server (works with no key):
   `python3 ai/server.py` - needs only Python 3.8+, zero pip installs.
2. Full AI mode: `META_API_KEY='LLM|...' python3 ai/server.py`
   (key + $150 credits from the Meta Model API dashboard).
3. Open this folder in Godot 4.7, press F5. Watch the HUD badge turn
   `AI META`, and play: briefing per sector, taunt per boss, difficulty
   adapting, coaching on the end screen.
4. Headless check (needs the server from step 1 running):
   `godot --headless --path . res://tests/ai_test.tscn` - 20 checks,
   exits 0 on success.
4. Bonus: `curl -X POST localhost:8765/art/emblem -d '{"level_name":"NEON
   DRIFT"}' -H 'Content-Type: application/json'` - victory medal via Muse Image.

No server? No key? No network? The game still runs end-to-end on identical
offline fallback lines - there is no way to break the demo.

## Demo video (Demo, 25%)

See [DEMO_SCRIPT.md](DEMO_SCRIPT.md) - 90-second shot list. Record at
480x854, capture: badge flip OFF->META, briefing, taunt, director tip,
coach screen, emblem.

## Future work

Hangar loadout advisor ("spend 300 coins on HULL, not ENGINE, because..."),
voice taunts, per-player memory across runs, Llama-powered endless mode
with generated sectors.
