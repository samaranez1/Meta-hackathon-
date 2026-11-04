extends Node
## AI Wingman client: talks to ai/server.py (Meta Model API via Muse Spark).
## Fully optional - every call falls back to built-in offline lines, so the
## game plays identically with no server, no key, and no network.

signal health_ready(online: bool, source: String)
signal briefing_ready(data: Dictionary)
signal director_ready(data: Dictionary)
signal coach_ready(text: String, source: String)

const DEFAULT_URL := "http://127.0.0.1:8765"
# Generous: live Meta answers can take 10-30 s (LLM + one retry). A dead
# server still fails fast (connection refused), so this only waits on slow
# replies instead of abandoning them mid-generation (server broken pipe).
const TIMEOUT := 40.0

var base_url: String = DEFAULT_URL
var online: bool = false
var model: String = ""
var use_ai: bool = true

var _busy: Dictionary = {"health": false, "briefing": false, "director": false, "coach": false}


func _ready() -> void:
	var cfg := str(ProjectSettings.get_setting("space_shooters/ai_url", ""))
	if cfg != "":
		base_url = cfg
	else:
		var env := OS.get_environment("SPACE_AI_URL")
		if env != "":
			base_url = env
	check_health()


func check_health() -> void:
	if _busy["health"]:
		return
	_busy["health"] = true
	var http := _spawn()
	http.request_completed.connect(_on_health.bind(http))
	if http.request(base_url + "/health", [], HTTPClient.METHOD_GET) != OK:
		_on_health(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), http)


func request_briefing(level: int, level_name: String, hp_pct: int, kills: int) -> void:
	var fb := _fb_briefing(level, level_name)
	if not use_ai:
		briefing_ready.emit(fb)
		return
	if not _begin("briefing"):
		return
	var http := _spawn()
	http.request_completed.connect(_on_briefing.bind(http, fb))
	_post_or_fallback(http, "/briefing",
		{"level": level, "level_name": level_name, "hp_pct": hp_pct, "kills": kills},
		_on_briefing.bind(http, fb))


func request_director(level: int, hp_frac: float, kills_per_min: float, deaths: int) -> void:
	var fb := {"spawn_interval_mult": 1.0, "enemy_scale_mult": 1.0,
		"tip": "", "source": "fallback"}
	if not use_ai:
		director_ready.emit(fb)
		return
	if not _begin("director"):
		return
	var http := _spawn()
	http.request_completed.connect(_on_director.bind(http, fb))
	_post_or_fallback(http, "/director",
		{"level": level, "hp_frac": hp_frac, "kills_per_min": kills_per_min, "deaths": deaths},
		_on_director.bind(http, fb))


func request_coach(score: int, kills: int, level_reached: int, deaths: int, victory: bool) -> void:
	var fb := _fb_coach(level_reached, victory)
	if not use_ai:
		coach_ready.emit(fb, "fallback")
		return
	if not _begin("coach"):
		return
	var http := _spawn()
	http.request_completed.connect(_on_coach.bind(http, fb))
	_post_or_fallback(http, "/coach",
		{"score": score, "kills": kills, "level_reached": level_reached,
			"deaths": deaths, "victory": victory},
		_on_coach.bind(http, fb))


# ------------------------------------------------------------------ internals ---

func _spawn() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	add_child(http)
	return http


func _begin(kind: String) -> bool:
	if bool(_busy.get(kind, false)):
		return false
	_busy[kind] = true
	return true


func _post_or_fallback(http: HTTPRequest, path: String, payload: Dictionary, cb: Callable) -> void:
	var err := http.request(base_url + path, ["Content-Type: application/json"],
		HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		cb.call(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray())


func _finish(http: HTTPRequest, kind: String) -> void:
	_busy[kind] = false
	if is_instance_valid(http):
		http.queue_free()


func _parse(body: PackedByteArray) -> Dictionary:
	if body.is_empty():
		return {}
	var v: Variant = JSON.parse_string(body.get_string_from_utf8())
	return v if typeof(v) == TYPE_DICTIONARY else {}


func _on_health(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest) -> void:
	var d := _parse(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else {}
	online = result == HTTPRequest.RESULT_SUCCESS and code == 200 and bool(d.get("ok", true))
	model = str(d.get("model", "")) if online else ""
	var src := "meta" if bool(d.get("meta_configured", false)) else "offline"
	_finish(http, "health")
	print("[ai] health: online=%s source=%s model=%s" % [online, src, model])
	health_ready.emit(online, src)


func _on_briefing(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest, fb: Dictionary) -> void:
	var d := _parse(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else {}
	var out := {
		"briefing": str(d.get("briefing", fb["briefing"])),
		"taunt": str(d.get("taunt", fb["taunt"])),
		"tip": str(d.get("tip", fb["tip"])),
		"source": str(d.get("source", "fallback")),
	}
	_finish(http, "briefing")
	briefing_ready.emit(out)


func _on_director(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest, fb: Dictionary) -> void:
	var d := _parse(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else {}
	var out := {
		"spawn_interval_mult": clampf(float(d.get("spawn_interval_mult", 1.0)), 0.8, 1.4),
		"enemy_scale_mult": clampf(float(d.get("enemy_scale_mult", 1.0)), 0.8, 1.2),
		"tip": str(d.get("tip", "")),
		"source": str(d.get("source", "fallback")),
	}
	_finish(http, "director")
	director_ready.emit(out)


func _on_coach(result: int, code: int, _h: PackedStringArray, body: PackedByteArray, http: HTTPRequest, fb: String) -> void:
	var d := _parse(body) if result == HTTPRequest.RESULT_SUCCESS and code == 200 else {}
	var text := str(d.get("advice", fb))
	var src := str(d.get("source", "fallback"))
	_finish(http, "coach")
	coach_ready.emit(text, src)


# ------------------------------------------------------------------ fallbacks ---

func _fb_briefing(level: int, level_name: String) -> Dictionary:
	var tips := {
		1: "Guns are automatic - focus on dodging and grab every P pickup.",
		2: "Snipers telegraph before firing. Strafe sideways, never sit still.",
		3: "Elites drop the best loot. Save one bomb for the HYDRA's spiral.",
		4: "The REAPER cloaks before it dashes. Watch for the shimmer.",
		5: "Final sector. Spend every bomb - there is nothing after this.",
	}
	var taunts := {
		1: "VEX WARDEN: 'Your little ship amuses me. It will make fine debris.'",
		2: "NEBULA TWINS: 'Two minds. One crossfire. Zero survivors.'",
		3: "CHROMA HYDRA: 'Cut one pattern down and two more take its place.'",
		4: "VOID REAPER: 'I have already killed you. You are just catching up.'",
		5: "STAR EATER PRIME: 'I unmade a thousand suns. You are a spark.'",
	}
	var tip := str(tips.get(level, tips[1]))
	return {
		"briefing": "SECTOR %d - %s. Wingman online. %s" % [level, level_name, tip],
		"taunt": str(taunts.get(level, taunts[1])),
		"tip": tip,
		"source": "fallback",
	}


func _fb_coach(level_reached: int, victory: bool) -> String:
	if victory:
		return "Galaxy saved, pilot! Try a no-bomb run next - you clearly do not need the training wheels."
	return "Good run to sector %d. Spend coins on HULL in the Hangar, and dodge toward the gaps, not away from bullets." % level_reached
