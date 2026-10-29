@tool
extends EditorExportPlugin
## Bundles the Play Billing bridge AAR + Billing Library into Android exports.
## Build the AAR first (see android-plugins/README.md) and copy it to
## addons/google_play_billing/android/. Without it, exports still succeed but
## the coin store falls back to Huawei IAP (when HMS Core exists) or shows as
## unavailable.

const AAR_RES_PATH := "res://addons/google_play_billing/android/google-play-billing-release.aar"
const AAR_EXPORT_PATH := "google_play_billing/android/google-play-billing-release.aar"
# Verify against https://developer.android.com/google/play/billing/release-notes
# before release builds. Google Play requires Billing 8+ for new apps/updates.
const BILLING_DEP := "com.android.billingclient:billing:8.2.0"


func _get_name() -> String:
	return "GooglePlayBilling"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform != null and platform.get_os_name() == "Android"


func _has_aar() -> bool:
	return FileAccess.file_exists(AAR_RES_PATH)


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not _has_aar():
		push_warning("GooglePlayBilling: missing %s. Build it from android-plugins/ (see addons/google_play_billing/README.md); exporting without Play Billing." % AAR_RES_PATH)
		return PackedStringArray()
	return PackedStringArray([AAR_EXPORT_PATH])


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if not _has_aar():
		return PackedStringArray()
	return PackedStringArray([BILLING_DEP])
