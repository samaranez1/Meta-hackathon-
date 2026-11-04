# Google AdMob plugin (Godot 4.x)

Android bridge for Google AdMob: banner, interstitial and rewarded ads. It
mirrors the Huawei Petal Ads contract, and the game picks providers
automatically: **Huawei ads when HMS Core is present, otherwise AdMob**.
Debug builds use Google's official sample ad units, so test ads work on any
device with zero console setup.

## Contents

```
addons/google_admob/
  plugin.cfg / admob_editor.gd / export_plugin.gd  Editor + Android export hook
  admob.gd                GDScript bridge (Engine singleton "GoogleAdMob")
  android/                Drop admob-release.aar here (built from android-plugins/)
```

Java source lives in `android-plugins/admob/`. Game logic is shared with
Huawei in `scripts/ads_manager.gd` (rewarded free coins, post-boss
interstitials, menu banner).

## Setup

1. **Build the AAR**: follow `android-plugins/README.md`, then copy
   `admob-release.aar` into `addons/google_admob/android/`.
2. **Enable the plugin**: Project > Project Settings > Plugins >
   check `GoogleAdMob`. The export hook injects the Play Services Ads SDK and
   the `APPLICATION_ID` manifest entry automatically.
3. **Test**: export a debug Android build - sample ads serve immediately.
4. **Release**: create real ad units in the AdMob console, put them in
   `scripts/ads_manager.gd` (`ADMOB_*_ID`), and replace `ADMOB_APP_ID` in
   `export_plugin.gd` with your real app ID (AdMob console > App settings).
   Never ship the sample IDs.

## Desktop / missing-AAR behavior

Without the AAR, `Engine.has_singleton("GoogleAdMob")` is false and the game
falls back to Huawei ads when HMS Core exists, else no ads. The game is fully
playable in all cases.

## Files to verify before release

- Play Services Ads version in `android-plugins/build.gradle` and
  `export_plugin.gd` (`23.0.0` at time of writing - confirm at
  https://developers.google.com/admob/android ).
- Real ad unit IDs in `scripts/ads_manager.gd` and real app ID in
  `export_plugin.gd`; never ship sample IDs.
