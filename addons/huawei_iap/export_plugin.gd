@tool
extends EditorExportPlugin
## Bundles the Huawei IAP bridge AAR + HMS IAP SDK into Android exports.
## Build the AAR first (see android-plugins/README.md) and copy it to
## addons/huawei_iap/android/. Without it, exports still succeed but the
## coin store shows as unavailable.

const AAR_RES_PATH := "res://addons/huawei_iap/android/huawei-iap-release.aar"
const AAR_EXPORT_PATH := "addons/huawei_iap/android/huawei-iap-release.aar"
# Verify against https://developer.huawei.com/consumer/en/doc/ before release builds.
const HMS_IAP_DEP := "com.huawei.hms:iap:6.4.0.300"


func _get_name() -> String:
    return "HuaweiIap"


func _supports_platform(platform: EditorExportPlatform) -> bool:
    return platform != null and platform.get_os_name() == "Android"


func _has_aar() -> bool:
    return FileAccess.file_exists(AAR_RES_PATH)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
    if not _has_aar():
        push_warning("HuaweiIap: missing %s. Build it from android-plugins/ (see addons/huawei_iap/README.md); exporting without in-app purchases." % AAR_RES_PATH)
        return PackedStringArray()
    return PackedStringArray([AAR_EXPORT_PATH])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
    if not _has_aar():
        return PackedStringArray()
    return PackedStringArray([HMS_IAP_DEP])
