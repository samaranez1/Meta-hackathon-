extends Node
## Regression test: upgrades are per-player, new players start at level 0,
## and Reset deletes the save. Fully hermetic: only temp user:// test files
## are touched, never the real id.cfg / save.cfg / legacy save.
## Run: godot --headless --path <project> res://tests/save_progress_test.tscn
## Pass criteria: RESULT PASS with zero ERROR lines in the output.
## Exits 0 on success, 1 on any failure.

const SaveManager := preload("res://scripts/save_manager.gd")

const TEST_SAVE := "user://test_save_progress_save.cfg"
const TEST_ID := "user://test_save_progress_id.cfg"
const TEST_LEGACY := "user://test_save_progress_legacy.cfg"
const TEST_MIG_SAVE := "user://test_save_progress_mig_save.cfg"

var _failures: Array = []
var _done := false


func _ready() -> void:
	_watchdog()
	_run()
	_finish()


func _run() -> void:
	_cleanup()
	# 1. Defaults are all locked.
	var fresh: Dictionary = SaveManager.default_meta()
	_check(fresh.size() == 6, "default meta has 6 upgrades")
	var all_zero := true
	for key in fresh.keys():
		if int(fresh[key]) != 0:
			all_zero = false
	_check(all_zero, "default upgrades all start at level 0")
	# 2. Player ID is minted once and persists.
	var id_a := SaveManager.get_player_id(TEST_ID)
	_check(id_a != "", "player ID minted on first launch")
	var id_a2 := SaveManager.get_player_id(TEST_ID)
	_check(id_a == id_a2, "player ID stable across launches")
	# 3. Legacy migration: the old shared save imports once into the slot.
	_write_legacy()
	var data_m: Dictionary = SaveManager.load_progress("migrated-player", TEST_MIG_SAVE, TEST_LEGACY)
	_check(int((data_m["meta"] as Dictionary).get("power", -1)) == 3, "legacy upgrades migrate into player slot")
	_check(int(data_m.get("hi_score", -1)) == 777 and int(data_m.get("coins", -1)) == 111, "legacy score/coins migrate")
	_check(bool(data_m.get("voice", true)) == false, "legacy voice setting migrates")
	_check(not FileAccess.file_exists(TEST_LEGACY), "legacy file removed after migration")
	var data_m2: Dictionary = SaveManager.load_progress("migrated-player", TEST_MIG_SAVE, TEST_LEGACY)
	_check(int((data_m2["meta"] as Dictionary).get("power", -1)) == 3, "migrated slot persists in per-player save")
	# 4. Unknown player loads fresh zeros (no leak, no legacy).
	var data_b: Dictionary = SaveManager.load_progress("nobody-yet", TEST_SAVE, TEST_LEGACY)
	_check(_meta_sum(data_b) == 0, "new player starts at level 0")
	_check(int(data_b.get("coins", -1)) == 0 and int(data_b.get("hi_score", -1)) == 0, "new player starts with 0 coins/hi-score")
	# 5. Per-player isolation: A's upgrades never appear for B.
	var data_a: Dictionary = SaveManager.default_progress()
	data_a["coins"] = 500
	(data_a["meta"] as Dictionary)["power"] = 4
	(data_a["meta"] as Dictionary)["hull"] = 2
	_check(SaveManager.save_progress(id_a, data_a, TEST_SAVE) == OK, "player A progress saves")
	var data_b2: Dictionary = SaveManager.load_progress("someone-else", TEST_SAVE, TEST_LEGACY)
	_check(_meta_sum(data_b2) == 0, "player B unaffected by player A upgrades")
	var data_a2: Dictionary = SaveManager.load_progress(id_a, TEST_SAVE, TEST_LEGACY)
	_check(int((data_a2["meta"] as Dictionary).get("power", -1)) == 4, "player A upgrades round-trip")
	_check(int(data_a2.get("coins", -1)) == 500, "player A coins round-trip")
	# 6. Reset deletes the save; the next load is zeros again.
	SaveManager.reset_progress(TEST_SAVE)
	_check(not FileAccess.file_exists(TEST_SAVE), "reset deletes the save file")
	var data_a3: Dictionary = SaveManager.load_progress(id_a, TEST_SAVE, TEST_LEGACY)
	_check(_meta_sum(data_a3) == 0, "post-reset load starts at level 0")
	_cleanup()


func _write_legacy() -> void:
	var legacy := ConfigFile.new()
	legacy.set_value("game", "hi_score", 777)
	legacy.set_value("game", "coins", 111)
	legacy.set_value("game", "voice", false)
	legacy.set_value("meta", "power", 3)
	legacy.set_value("meta", "rate", 1)
	legacy.save(TEST_LEGACY)


func _meta_sum(data: Dictionary) -> int:
	var total := 0
	var meta: Dictionary = data.get("meta", {})
	for key in meta.keys():
		total += int(meta[key])
	return total


func _cleanup() -> void:
	for path in [TEST_SAVE, TEST_ID, TEST_LEGACY, TEST_MIG_SAVE]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _check(cond: bool, label: String) -> void:
	print("[save-test] %s: %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures.append(label)


func _watchdog() -> void:
	await get_tree().create_timer(60.0).timeout
	if not _done:
		print("[save-test] FAIL: timed out")
		_done = true
		get_tree().quit(1)


func _finish() -> void:
	_done = true
	await get_tree().process_frame
	if _failures.is_empty():
		print("[save-test] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[save-test] RESULT: FAIL (%d failures)" % _failures.size())
		for f in _failures:
			print("[save-test] failed: %s" % str(f))
		get_tree().quit(1)
