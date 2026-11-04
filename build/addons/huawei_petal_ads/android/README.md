# Petal Ads bridge AAR output

Build `petal-ads-release.aar` from `android-plugins/` (see its README) and copy
it into THIS folder. The export plugin (`../export_plugin.gd`) bundles it into
Android exports automatically. Without it, exports still succeed but all ads
are unavailable and the game uses no-op fallbacks.
