# Huawei Petal Ads plugin (Godot 4.x)

Android bridge for Huawei Petal Ads Kit with banner, interstitial and rewarded
ads, plus a desktop-safe GDScript API. The game uses it for:

- **Rewarded free coins** (+50 C per ad, 45 s cooldown) in the Hangar
- **Interstitial** after every boss kill
- **Banner** on the main menu (hidden during runs)

## Contents

```
addons/huawei_petal_ads/
  plugin.cfg / petal_ads_editor.gd / export_plugin.gd  Editor + Android export hook
  petal_ads.gd            GDScript bridge (Engine singleton "HuaweiPetalAds")
  android/                Drop petal-ads-release.aar here (built from android-plugins/)
```

Java source lives in `android-plugins/petal-ads/`.

## Setup

1. **AppGallery Connect**: create the app, note the package name, enable Ads Kit,
   and create 3 ad slots (banner, interstitial, rewarded). Put the real slot IDs
   in `scripts/ads_manager.gd` (`BANNER_ID`, `INTERSTITIAL_ID`, `REWARDED_ID`).
   Debug builds automatically use Huawei's official test IDs, so you can develop
   without real slots.
2. **agconnect-services.json**: download it from AppGallery Connect and add it to
   your Android export via a custom build (Godot docs: Exporting > Android >
   custom build template). HMS reads the app ID from it; without it, ads fail.
3. **Build the AAR**: follow `android-plugins/README.md`, then copy
   `petal-ads-release.aar` into `addons/huawei_petal_ads/android/`.
4. **Enable the plugin**: Project > Project Settings > Plugins >
   check `HuaweiPetalAds` (this activates the export hook).
5. **Export**: use the Android preset in `export_presets.cfg` (package name MUST
   match step 1). Test on a Huawei device with HMS Core installed.

## Desktop / missing-AAR behavior

`Engine.has_singleton("HuaweiPetalAds")` is false, so `ads_manager.gd` no-ops:
the free-coins button shows ADS UNAVAILABLE, and no interstitials/banners appear.
The game is fully playable without any of this setup.

On-device, Huawei ads additionally require HMS Core: `isHmsAvailable()` gates
them, and without HMS Core the game automatically uses Google AdMob instead
(see `addons/google_admob/README.md`). Rebuild the AAR after pulling this
change - older AARs lack `isHmsAvailable`.

## Files to verify before release

- HMS Ads SDK version in `android-plugins/build.gradle` and
  `export_plugin.gd` (`13.4.62.300` at time of writing - confirm in the
  Huawei developer docs under "HMS Core > Ads Kit > Version Change History").
- Real ad slot IDs in `scripts/ads_manager.gd`; never ship test IDs.
