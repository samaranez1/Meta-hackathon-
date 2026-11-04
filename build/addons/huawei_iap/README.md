# Huawei IAP plugin (Godot 4.x) - coin packs

Android bridge for Huawei IAP Kit selling **consumable coin packs**. The Hangar
"GET COINS" section lists the packs with live AppGallery Connect prices:

| Product ID (create exactly) | Coins |
|---|---|
| `coin_pack_small` | 500 |
| `coin_pack_medium` | 1300 |
| `coin_pack_large` | 3000 |
| `coin_pack_mega` | 8000 |

## Contents

```
addons/huawei_iap/
  plugin.cfg / hms_iap_editor.gd / export_plugin.gd  Editor + Android export hook
  hms_iap.gd              GDScript bridge (Engine singleton "HuaweiIap")
  android/                Drop huawei-iap-release.aar here (built from android-plugins/)
```

Java source lives in `android-plugins/huawei-iap/`. Game logic is in
`scripts/iap_manager.gd` (catalog, prices, purchase flow).

## Purchase safety

- The Java side **consumes the purchase token before** emitting
  `purchase_completed`, so a completed purchase is always consumable exactly
  once - no double grants.
- Every launch queries owned purchases and delivers + consumes anything left
  pending (e.g. the app died mid-purchase), so coins are never lost either.
- Granted coins are added to the persistent wallet and saved immediately.

## Setup

1. **AppGallery Connect**: create 4 CONSUMABLE products with the exact IDs above,
   set prices, and activate them. Add sandbox test accounts for testing.
2. **agconnect-services.json**: same requirement as the ads plugin - add it via
   a custom Android build or IAP calls fail.
3. **Build the AAR**: follow `android-plugins/README.md`, then copy
   `huawei-iap-release.aar` into `addons/huawei_iap/android/`.
4. **Enable the plugin**: Project > Project Settings > Plugins >
   check `HuaweiIap`.
5. **Export + test**: Android preset, package name matching step 1, on a Huawei
   device signed into a sandbox test account. Desktop builds show
   "Coin store needs the Android build with HMS." and stay fully playable.

## Files to verify before release

- HMS IAP SDK version in `android-plugins/build.gradle` and `export_plugin.gd`
  (`6.4.0.300` at time of writing - confirm in the Huawei developer docs under
  "HMS Core > In-App Purchases > Version Change History").
- Product IDs in `scripts/iap_manager.gd` match the console exactly.
