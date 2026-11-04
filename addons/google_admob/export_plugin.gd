@tool
extends EditorExportPlugin
## Bundles the AdMob bridge AAR + Play Services Ads SDK into Android exports,
## and injects the AdMob APPLICATION_ID manifest entry.
## Build the AAR first (see android-plugins/README.md) and copy it to
## addons/google_admob/android/. Without it, exports still succeed and the
## game falls back to Huawei ads (when HMS Core exists) or no ads.

const AAR_RES_PATH := "res://addons/google_admob/android/admob-release.aar"
const AAR_EXPORT_PATH := "addons/google_admob/android/admob-release.aar"
# Verify against https://developers.google.com/admob/android before release builds.
const GMA_DEP := "com.google.android.gms:play-services-ads:23.0.0"
# Google's sample app ID - lets test ads run with zero setup. Replace with
# your real AdMob app ID (AdMob console > App settings) before release.
const ADMOB_APP_ID := "ca-app-pub-3940256099942544~3347511713"


func _get_name() -> String:
    return "GoogleAdMob"


func _supports_platform(platform: EditorExportPlatform) -> bool:
    return platform != null and platform.get_os_name() == "Android"


func _has_aar() -> bool:
    return FileAccess.file_exists(AAR_RES_PATH)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
    if not _has_aar():
        push_warning("GoogleAdMob: missing %s. Build it from android-plugins/ (see addons/google_admob/README.md); exporting without AdMob." % AAR_RES_PATH)
        return PackedStringArray()
    return PackedStringArray([AAR_EXPORT_PATH])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
    if not _has_aar():
        return PackedStringArray()
    return PackedStringArray([GMA_DEP])


func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
    if not _has_aar():
        return ""
    return '<meta-data android:name="com.google.android.gms.ads.APPLICATION_ID" android:value="%s" />' % ADMOB_APP_ID
