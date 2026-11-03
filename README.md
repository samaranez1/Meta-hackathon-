# Space Shooters: AI Wingman (Godot 4.7)

> Meta Global AI Developer Hackathon entry - Indie track, "Build for Your
> World". See [HACKATHON.md](HACKATHON.md) for the submission and
> [DEMO_SCRIPT.md](DEMO_SCRIPT.md) for the demo video plan.
>
> Built by **Samuel Arañez** — Hilongos, Leyte, Philippines.

A fast vertical space shooter: fight through **5 sectors**, each ending in a
stylish multi-pattern **boss**, now with an **AI Wingman** powered by Meta's
**Muse Spark** through the **Meta Model API**: fresh mission briefings and
boss taunts, a skill-aware **AI Director** that retunes difficulty live, a
post-run **AI Coach** (taunts, tips and advice also spoken aloud via
on-device voiceover - `VOX` button), and a bonus **Muse Image** victory emblem. The HUD
badge shows `AI META` / `AI LOCAL` / `AI OFF`, and the game plays fully
offline if the server or key is missing - start it with
`python3 ai/server.py` (stdlib-only, no pip installs; set `META_API_KEY`
for full AI mode - see `ai/README.md`).

The player ship uses `player.png`
(its magenta background is removed at runtime by a chroma-key shader, so you
don't need to edit the image).

## Run it

1. Open Godot **4.7** (any 4.x should also work).
2. `Project -> Import...` and select `project.godot` in this folder.
3. Press **F5** (or the Play button). Main scene is `scenes/main.tscn`.

No addons or extra assets needed - enemies, bosses, bullets, backgrounds,
sound effects and music are all generated in code.

## Controls

| Action | Input |
|---|---|
| Move | WASD / Arrows / hold left mouse / touch-drag |
| Guns | Automatic |
| Bomb (clears bullets, big damage) | SPACE / X / B / right-click / BOMB button |
| Pause | P / ESC or II button |
| Confirm / start | ENTER |

## Game structure

- **Levels 1-5**: timed waves with formations (line, V, column, arc), then a boss.
  Survive the waves -> kill the boss -> heal + bonus -> next sector.
- **Bosses**: VEX WARDEN, NEBULA TWINS, CHROMA HYDRA, VOID REAPER
  (cloaking dasher), STAR EATER PRIME (3-phase final). All have a health bar,
  phase changes, radial/spiral/laser patterns and minion summons.
- **Pickups**: P power (5 gun levels), S shield, + heal, B bomb, * score, C coins.
- **Coins + Hangar**: kills, bosses and C pickups earn coins kept forever;
  spend them in the main-menu Hangar on permanent guns, fire rate, hull,
  engine, shield and bomb upgrades applied to every run.
- **Huawei plugins**: Petal Ads (rewarded free coins, post-boss interstitials,
  menu banner) and IAP Kit coin packs (500/1300/3000/8000) in the Hangar store.
  Desktop builds no-op safely; see `addons/huawei_petal_ads/README.md`,
  `addons/huawei_iap/README.md` and `android-plugins/README.md` for the
  one-time AAR build + AppGallery Connect setup.
- **Google AdMob**: mirrors the ad formats with sample test IDs and is used
  automatically when HMS Core is absent (Huawei hidden); see
  `addons/google_admob/README.md`.
- **Google Play Billing**: mirrors the coin packs as Play consumables and is
  used automatically when Huawei IAP is absent; see
  `addons/google_play_billing/README.md` for the one-time AAR build + Play
  Console setup.
- **Microsoft Store ready**: Windows Desktop export preset, MSIX manifest +
  packaging script (`store/windows/Build-Msix.ps1`), auto-generated Store
  assets, privacy template, submission guide, and gamepad support
  (stick/D-pad move, A bomb, Start confirm/pause).
- **Score**: kills + boss bounties + level-clear bonus; best score is saved to
  `user://space_shooters_save.cfg`.

## Files

```
project.godot          Godot 4.7 project (portrait 480x854, GL Compatibility)
player.png             Player ship sprite (magenta bg removed via shader)
icon.svg               Project icon
scenes/main.tscn       Boot scene (everything else is built in code)
shaders/chroma_key.gdshader   Magenta-removal for player.png
scripts/
  main.gd          Game manager: levels, waves, bosses, score, saves
  player.gd        Ship: movement, auto-fire, bombs, shields, i-frames
  enemy.gd         7 enemy types with distinct AI + visuals
  boss.gd          5 stylish bosses, phases, bullet patterns
  bullet.gd        Player + enemy bullets (bolt/orb/laser/shard/needle)
  powerup.gd       Pickups with magnet effect
  starfield.gd     Parallax stars + per-level nebula tint
  hud.gd           HUD, boss bar, banners, menus, touch buttons
  audio_manager.gd Procedural SFX + looping music + per-boss taunt stings (no audio files)
  explosion.gd     Flash + shockwave + sparks, screen shake hookup
  meta_ai.gd        AI Wingman client (Meta Model API, offline fallback)
  voiceover.gd      On-device TTS for taunts, tips, coach advice
ai/server.py        AI backend: briefing/director/coach/emblem
ai/test_server.py   Backend regression tests (`python3 ai/test_server.py`)
tests/ai_test.tscn  Headless AI integration test
tests/powerup_test.tscn  Headless pickup physics regression test
HACKATHON.md        Hackathon submission doc
DEMO_SCRIPT.md      90-second demo video plan
```

## Tips for tweaking

- Difficulty: `LEVELS` in `scripts/main.gd` (duration, spawn interval, pool, scale).
- Boss HP/patterns: `DEFS` + `_fire_main` / `_fire_pattern` in `scripts/boss.gd`.
- Player: speed, fire rate, power levels in `scripts/player.gd`.
- Ship size: the `68.0 / width` scale in `player.gd`; chroma threshold in
  `shaders/chroma_key.gdshader`.

## Author

**Samuel Arañez** — Hilongos, Leyte, Philippines.
