# Building the store plugin AARs

This folder is a plain Android Gradle project that compiles the four Godot
bridge libraries (Huawei ads + IAP, AdMob, Play Billing). You need a JDK (17+),
the Android SDK (compileSdk 34), and either Android Studio or the Gradle wrapper.
It is built ONCE per plugin change - not on every game export.

## Steps

1. Open a terminal in THIS folder (`android-plugins/`).
2. Resolve the Godot engine dependency (pick ONE):
   - **Option A (recommended)**: follow the official Godot Android plugin
     template for your exact editor version (Godot docs: Engine development >
     Android plugins), then copy the `*.java` files from
     `petal-ads/src/...`, `huawei-iap/src/...`, `admob/src/...` and
     `google-play-billing/src/...` into that template's modules.
     The template already wires the correct `godot-lib`.
   - **Option B**: keep this project and fix the `godotLib` coordinates in
     `build.gradle` to the artifact matching your editor (Help > About).
     The default `org.godotengine:godot:4.7.2.stable` is verified on Maven
     Central - a wrong coordinate fails the build with "could not resolve",
     which is your cue to correct it, not a code bug.
3. Confirm SDK versions in `build.gradle` (`hmsAdsVersion`, `hmsIapVersion`,
   `gmaAdsVersion`, `playBillingVersion`) against the Huawei developer docs
   (HMS Core > Ads Kit / In-App Purchases > Version Change History) and the
   Google docs (AdMob Android, Play Billing release notes). Gradle fails fast
   on versions that don't exist.
4. Build:
   `./gradlew :petal-ads:assembleRelease :huawei-iap:assembleRelease :admob:assembleRelease :google-play-billing:assembleRelease`
   (On Windows: `gradlew.bat ...`. First run downloads the Android Gradle
   Plugin and SDK components.)
5. Copy outputs into the Godot project:
   - `petal-ads/build/outputs/aar/petal-ads-release.aar`
     -> `addons/huawei_petal_ads/android/petal-ads-release.aar`
   - `huawei-iap/build/outputs/aar/huawei-iap-release.aar`
     -> `addons/huawei_iap/android/huawei-iap-release.aar`
   - `admob/build/outputs/aar/admob-release.aar`
     -> `addons/google_admob/android/admob-release.aar`
   - `google-play-billing/build/outputs/aar/google-play-billing-release.aar`
     -> `addons/google_play_billing/android/google-play-billing-release.aar`
6. Back in Godot: enable the plugins you need (Project Settings > Plugins), set
   the package name in the Android export preset to match the store console,
   add `agconnect-services.json` via a custom build for the Huawei plugins,
   and export.

## Notes

- The Huawei Maven repo (`https://developer.huawei.com/repo/`) is already in
  `settings.gradle` - HMS dependencies resolve from there.
- `minSdk 21` matches Godot 4 Android exports; `compileSdk 34` matches the
  current export templates. Align both if your templates differ.
- Rebuild an AAR only when its Java code changes. GDScript-only changes
  (prices, ad IDs, cooldowns) need just a normal game export.
