# Demo video script (90 seconds)

Record the game at 480x854 with mic audio. Total: ~90 s.

| Time | Shot | Narration |
|---|---|---|
| 0:00-0:10 | Terminal: `python3 ai/server.py` + `curl /health` showing `"meta_configured": true`. | "Space Shooters AI Wingman, built for the Meta Global AI Hackathon on the Meta Model API with Muse Spark." |
| 0:10-0:20 | Godot F5, main menu. Point at HUD badge flipping to `AI META`. | "The game auto-detects the AI server - the badge shows exactly what is powering it." |
| 0:20-0:35 | Start run, Sector 1. AI briefing line appears. | "Every sector opens with a fresh AI briefing aware of your hull and kills." |
| 0:35-0:50 | Boss 1 spawns, AI taunt shows. Fight 10 s. | "Bosses taunt you with generated lines - never the same run twice." |
| 0:50-1:05 | Take damage on purpose; `WINGMAN:` tip appears, spawns ease off. | "The AI Director watches my skill and adapts difficulty inside safety bounds - struggling players get relief, cruising players get heat." |
| 1:05-1:20 | Die or win; `COACH:` advice on the end screen. | "And the AI Coach tells me exactly how to do better next run." |
| 1:20-1:30 | Terminal: emblem curl + show `generated_images/ai_emblem.png`. | "Bonus: victory medals from Muse Image. Fully offline-safe - the game never breaks without a key." |

Tips: enable key display, keep music low under narration, end card with
repo URL + "Track: Indie / Theme: Build for Your World".
