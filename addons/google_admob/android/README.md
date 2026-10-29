# AdMob bridge AAR output

Build `admob-release.aar` from `android-plugins/` (see its README) and copy it
into THIS folder. The export plugin (`../export_plugin.gd`) bundles it into
Android exports automatically, along with the Play Services Ads SDK and the
AdMob APPLICATION_ID manifest entry. Without it, exports still succeed but the
game falls back to Huawei ads (when HMS Core exists) or no ads.
