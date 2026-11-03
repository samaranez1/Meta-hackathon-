@tool
extends EditorExportPlugin
## Bundles the Petal Ads bridge AAR + HMS Ads SDK into Android exports.
## Build the AAR first (see android-plugins/README.md) and copy it to
## addons/huawei_petal_ads/android/. Without it, exports still succeed
## but ads are unavailable and the game uses no-op fallbacks.

const AAR_RES_PATH := "res://addons/huawei_petal_ads/android/petal-ads-release.aar"
// _get_android_libraries paths are relative to res://addons/ (or res://-absolute).
const AAR_EXPORT_PATH := "huawei_petal_ads/android/petal-ads-release.aar"
# Verify against https://developer.huawei.com/consumer/en/doc/ before release builds.
const HMS_ADS_DEP := "com.huawei.hms:ads-lite:13.4.62.300"


func _get_name() -> String:
    return "HuaweiPetalAds"


func _supports_platform(platform: EditorExportPlatform) -> bool:
    return platform != null and platform.get_os_name() == "Android"


func _has_aar() -> bool:
    return FileAccess.file_exists(AAR_RES_PATH)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
    if not _has_aar():
        push_warning("HuaweiPetalAds: missing %s. Build it from android-plugins/ (see addons/huawei_petal_ads/README.md); exporting without ads." % AAR_RES_PATH)
        return PackedStringArray()
    return PackedStringArray([AAR_EXPORT_PATH])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
    if not _has_aar():
        return PackedStringArray()
    return PackedStringArray([HMS_ADS_DEP])
