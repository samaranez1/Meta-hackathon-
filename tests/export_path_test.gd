extends Node
## Regression test: Android export plugins must return AAR paths relative to
## res://addons/ (Godot prepends it). A leading "addons/" doubles the path
## and Gradle fails with "Transform's input file does not exist".
## Run: godot --headless --path <project> res://tests/export_path_test.tscn
## Pass criteria: RESULT PASS with zero ERROR lines in the output.
## Exits 0 on success, 1 on any failure.

const Billing := preload("res://addons/google_play_billing/export_plugin.gd")
const AdMob := preload("res://addons/google_admob/export_plugin.gd")
const HmsIap := preload("res://addons/huawei_iap/export_plugin.gd")
const Petal := preload("res://addons/huawei_petal_ads/export_plugin.gd")

var _failures: Array = []
var _done := false


func _ready() -> void:
	_watchdog()
	_run()
	_finish()


# NOTE: EditorExportPlugin can only be instantiated by the editor, so this
# test pins the path contract via the scripts' constants (the exact values
# _get_android_libraries returns). Instance behavior is covered by review.
func _run() -> void:
	_check_plugin(Billing.AAR_EXPORT_PATH, Billing.AAR_RES_PATH,
		"google_play_billing")
	_check_plugin(AdMob.AAR_EXPORT_PATH, AdMob.AAR_RES_PATH, "google_admob")
	_check_plugin(HmsIap.AAR_EXPORT_PATH, HmsIap.AAR_RES_PATH, "huawei_iap")
	_check_plugin(Petal.AAR_EXPORT_PATH, Petal.AAR_RES_PATH,
		"huawei_petal_ads")


func _check_plugin(exp: String, res: String, plugin_dir: String) -> void:
	_check(not exp.begins_with("addons/"),
		"%s: export path has no leading addons/" % plugin_dir)
	_check(not exp.begins_with("res://"),
		"%s: export path is relative" % plugin_dir)
	_check(exp.ends_with(".aar"), "%s: export path names the AAR" % plugin_dir)
	_check(exp.begins_with(plugin_dir + "/"),
		"%s: export path stays in its plugin dir" % plugin_dir)
	_check(res == "res://addons/" + exp,
		"%s: res check and export path agree" % plugin_dir)


func _check(cond: bool, label: String) -> void:
	print("[export-test] %s: %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures.append(label)


func _watchdog() -> void:
	await get_tree().create_timer(60.0).timeout
	if not _done:
		print("[export-test] FAIL: timed out")
		_done = true
		get_tree().quit(1)


func _finish() -> void:
	_done = true
	await get_tree().process_frame
	if _failures.is_empty():
		print("[export-test] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[export-test] RESULT: FAIL (%d failures)" % _failures.size())
		for f in _failures:
			print("[export-test] failed: %s" % str(f))
		get_tree().quit(1)
