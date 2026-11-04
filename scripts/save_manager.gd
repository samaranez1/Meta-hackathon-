extends RefCounted
## Per-player save system for Space Shooters.
##
## - Every install gets a unique player ID on first launch (user://id.cfg).
## - Progress + upgrades live in user://save.cfg, keyed by that player ID,
##   so one file can hold many players without leaking between them.
## - Fresh/unknown players always start with every upgrade at level 0.
## - One-time migration imports the legacy shared save
##   (user://space_shooters_save.cfg) into the current player's slot.

const ID_PATH := "user://id.cfg"
const SAVE_PATH := "user://save.cfg"
const LEGACY_PATH := "user://space_shooters_save.cfg"

const META_KEYS: Array[String] = ["power", "rate", "hull", "engine", "shield", "bomb"]


## Fresh all-locked upgrades. Always returns a new Dictionary.
static func default_meta() -> Dictionary:
	var meta := {}
	for key in META_KEYS:
		meta[key] = 0
	return meta


## Fresh progress for a new player.
static func default_progress() -> Dictionary:
	return {
		"hi_score": 0,
		"coins": 0,
		"voice": true,
		"meta": default_meta(),
	}


## This install's player ID, minting + persisting one on first launch.
static func get_player_id(id_path: String = ID_PATH) -> String:
	var cfg := ConfigFile.new()
	if cfg.load(id_path) == OK:
		var existing := str(cfg.get_value("player", "id", "")).strip_edges()
		if existing != "":
			return existing
	var fresh := _new_id()
	var out := ConfigFile.new()
	out.set_value("player", "id", fresh)
	out.save(id_path)
	return fresh


static func _new_id() -> String:
	randomize()
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in range(16):
		bytes[i] = randi() % 256
	var hex := ""
	for b in bytes:
		hex += "%02x" % b
	return "%d-%s" % [int(Time.get_unix_time_from_system()), hex]


static func player_section(player_id: String) -> String:
	return "player_" + player_id


static func meta_section(player_id: String) -> String:
	return "meta_" + player_id


## One player's progress. Unknown players get fresh all-zero defaults.
## If this player has no slot yet but a legacy shared save exists, it is
## imported once into this player's slot (then the legacy file is removed).
static func load_progress(player_id: String, save_path: String = SAVE_PATH, legacy_path: String = LEGACY_PATH) -> Dictionary:
	var data := default_progress()
	var cfg := ConfigFile.new()
	if cfg.load(save_path) == OK and cfg.has_section(player_section(player_id)):
		data["hi_score"] = int(cfg.get_value(player_section(player_id), "hi_score", 0))
		data["coins"] = int(cfg.get_value(player_section(player_id), "coins", 0))
		data["voice"] = bool(cfg.get_value(player_section(player_id), "voice", true))
		var meta: Dictionary = data["meta"]
		for key in META_KEYS:
			meta[key] = maxi(0, int(cfg.get_value(meta_section(player_id), key, 0)))
		return data
	_maybe_migrate_legacy(player_id, data, save_path, legacy_path)
	return data


static func _maybe_migrate_legacy(player_id: String, data: Dictionary, save_path: String, legacy_path: String) -> void:
	var legacy := ConfigFile.new()
	if legacy.load(legacy_path) != OK or not legacy.has_section("game"):
		return
	data["hi_score"] = int(legacy.get_value("game", "hi_score", 0))
	data["coins"] = int(legacy.get_value("game", "coins", 0))
	data["voice"] = bool(legacy.get_value("game", "voice", true))
	var meta: Dictionary = data["meta"]
	for key in META_KEYS:
		meta[key] = maxi(0, int(legacy.get_value("meta", key, 0)))
	if save_progress(player_id, data, save_path) == OK:
		DirAccess.remove_absolute(legacy_path)


## Save one player's progress, preserving other players' sections.
static func save_progress(player_id: String, data: Dictionary, save_path: String = SAVE_PATH) -> int:
	var cfg := ConfigFile.new()
	cfg.load(save_path) # Ignore errors: a missing file just starts fresh.
	var ps := player_section(player_id)
	var ms := meta_section(player_id)
	cfg.set_value(ps, "hi_score", maxi(0, int(data.get("hi_score", 0))))
	cfg.set_value(ps, "coins", maxi(0, int(data.get("coins", 0))))
	cfg.set_value(ps, "voice", bool(data.get("voice", true)))
	var meta: Dictionary = data.get("meta", {})
	for key in META_KEYS:
		cfg.set_value(ms, key, maxi(0, int(meta.get(key, 0))))
	return cfg.save(save_path)


## Delete the save file(s), returning fresh all-zero defaults.
## The player ID is kept: same player, fresh progress.
static func reset_progress(save_path: String = SAVE_PATH) -> Dictionary:
	DirAccess.remove_absolute(save_path)
	if save_path == SAVE_PATH:
		DirAccess.remove_absolute(LEGACY_PATH)
	return default_progress()
