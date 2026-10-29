# Google Play Billing plugin (Godot 4.x) - coin packs

Android bridge for Google Play Billing selling **consumable coin packs**. The
Hangar "GET COINS" section lists the packs with live Play Console prices:

| Product ID (create exactly) | Coins |
|---|---|
| `coin_pack_small` | 500 |
| `coin_pack_medium` | 1300 |
| `coin_pack_large` | 3000 |
| `coin_pack_mega` | 8000 |

Same catalog as the Huawei IAP plugin, so one `scripts/iap_manager.gd` drives
either store: Huawei IAP is used when HMS Core answers, otherwise Play Billing
takes over automatically (mirroring how `scripts/ads_manager.gd` picks between
Petal Ads and AdMob).

## Contents

```
addons/google_play_billing/
  plugin.cfg / play_billing_editor.gd / export_plugin.gd  Editor + Android export hook
  play_billing.gd       GDScript bridge (Engine singleton "GooglePlayBilling")
  android/              Drop google-play-billing-release.aar here (built from android-plugins/)
```

Java source lives in `android-plugins/google-play-billing/`. Game logic is in
`scripts/iap_manager.gd` (catalog, prices, purchase flow). No manifest entries
or extra permissions are needed: the `com.android.vending.BILLING` permission
is merged automatically from the Billing Library's own manifest.

## Purchase safety

- The Java side **consumes the purchase token before** emitting
  `purchase_completed`, so a completed purchase is always consumable exactly
  once - no double grants.
- Every launch queries owned purchases and delivers + consumes anything left
  pending (e.g. the app died mid-purchase), so coins are never lost either.
- Granted coins are added to the persistent wallet and saved immediately.

## Setup

1. **Play Console**: create 4 IN-APP (one-time, consumable) products with the
   exact IDs above, set prices, and activate them.
2. **Build the AAR**: follow `android-plugins/README.md`, then copy
   `google-play-billing-release.aar` into `addons/google_play_billing/android/`.
3. **Enable the plugin**: Project > Project Settings > Plugins >
   check `GooglePlayBilling`.
4. **Export + test**: Android preset, package name matching step 1, on a device
   with Google Play signed into a license-test account (Play Console >
   Setup > License testing). Desktop builds show
   "Coin store needs the Android build." and stay fully playable.

## Headless test

`res://tests/iap_test.tscn` drives the real `scripts/iap_manager.gd` against
mock stores and exits 0 on success:

```
godot --headless --path <project> res://tests/iap_test.tscn
```

It covers init/env_ready, product queries, all 4 pack purchases, restore,
getVersion, both failure signals, Huawei-to-Google failover, and the desktop
no-op path.

## Files to verify before release

- Billing Library version in `android-plugins/build.gradle` and
  `export_plugin.gd` (`8.2.0` at time of writing - confirm in the release notes
  under "Google Play Billing Library > Release notes"). Google Play requires
  Billing 8+ for new apps and updates.
- Product IDs in `scripts/iap_manager.gd` match the console exactly.
