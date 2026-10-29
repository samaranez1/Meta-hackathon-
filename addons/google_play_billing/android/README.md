# Play Billing bridge AAR output

Build `google-play-billing-release.aar` from `android-plugins/` (see its README)
and copy it into THIS folder. The export plugin (`../export_plugin.gd`) bundles
it into Android exports automatically. Without it, exports still succeed but the
coin store falls back to Huawei IAP (when HMS Core exists) or shows as
unavailable.
