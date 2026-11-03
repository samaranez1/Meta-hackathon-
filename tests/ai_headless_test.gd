extends Node
## Headless end-to-end test for the AI Wingman (scripts/meta_ai.gd plus the
## hooks in scripts/main.gd and scripts/hud.gd).
## Run: godot --headless --path <project> res://tests/ai_test.tscn
## Needs ai/server.py running on 127.0.0.1:8765 (with or without META_API_KEY).
## Covers: health/badge, briefing + taunt announce, director bounds + tip,
## coach on game over, and the use_ai=false offline fallback.
## Exits 0 on success, 1 on any failure.

const MetaAiScript := preload("res://scripts/meta_ai.gd")
const MainScene := preload("res://scenes/main.tscn")

var _failures: Array = []
var _done := false
var _ai: Node
var _got_health := {}
var _got_briefing := {}
var _got_director := {}
var _got_coach := {}
var _main: Node2D


func _ready() -> void:
	_watchdog()
	_run()


func _run() -> void:
	print("[ai-test] phase A: direct client against live server")
	_ai = MetaAiScript.new()
	_ai.connect("health_ready", _rec_health)
	_ai.connect("briefing_ready", _rec_briefing)
	_ai.connect("director_ready", _rec_director)
	_ai.connect("coach_ready", _rec_coach)
	add_child(_ai)
	_check(await _wait_until(func() -> bool: return not _got_health.is_empty(), 15.0),
		"health resolved (is ai/server.py running on 127.0.0.1:8765?)")
	_check(bool(_got_health.get("online", false)),
		"server reachable, source=%s" % str(_got_health.get("source", "?")))
	_got_briefing = {}
	_ai.call("request_briefing", 3, "CHROMA STORM", 60, 25)
	_check(await _wait_until(func() -> bool: return not _got_briefing.is_empty(), 30.0),
		"briefing arrived")
	_check(str(_got_briefing.get("briefing", "")) != "", "briefing non-empty")
	_check(str(_got_briefing.get("taunt", "")) != "", "taunt non-empty")
	_check(str(_got_briefing.get("tip", "")) != "", "tip non-empty")
	_got_director = {}
	_ai.call("request_director", 3, 0.2, 4.0, 1)
	_check(await _wait_until(func() -> bool: return not _got_director.is_empty(), 30.0),
		"director arrived")
	var iv := float(_got_director.get("spawn_interval_mult", -1.0))
	var sc := float(_got_director.get("enemy_scale_mult", -1.0))
	_check(iv >= 0.8 and iv <= 1.4, "interval mult bounded (%.3f)" % iv)
	_check(sc >= 0.8 and sc <= 1.2, "scale mult bounded (%.3f)" % sc)
	_got_coach = {}
	_ai.call("request_coach", 9000, 40, 3, 1, false)
	_check(await _wait_until(func() -> bool: return not _got_coach.is_empty(), 30.0),
		"coach arrived")
	_check(str(_got_coach.get("text", "")) != "", "coach advice non-empty")

	print("[ai-test] phase B: offline sync fallback (use_ai=false)")
	_ai.set("use_ai", false)
	_got_briefing = {}
	_ai.call("request_briefing", 1, "NEON DRIFT", 100, 0)
	_check(not _got_briefing.is_empty() and str(_got_briefing.get("source", "")) == "fallback",
		"sync fallback briefing")
	_got_director = {}
	_ai.call("request_director", 1, 1.0, 5.0, 0)
	_check(not _got_director.is_empty(), "sync fallback director")

	print("[ai-test] phase C: full game integration across frames")
	_main = MainScene.instantiate()
	add_child(_main)
	await get_tree().process_frame
	await get_tree().process_frame
	var hud: CanvasLayer = _main.get("hud")
	_check(hud != null, "hud built")
	var vnode: Node = _main.get("voice")
	_check(vnode != null, "voice node built")
	_check(bool(vnode.call("toggle")) == false, "voice toggles off")
	_check(bool(vnode.call("toggle")) == true, "voice toggles on")
	vnode.call("speak", "voice check", 1.0, 1.0)
	vnode.call("stop")
	var ai_label: Label = hud.get("_ai_label")
	var ann: Label = hud.get("_announce_label")
	_check(await _wait_until(func() -> bool: return ai_label.text != "AI ...", 15.0),
		"badge resolved (got '%s')" % ai_label.text)
	_check(ai_label.text == "AI META" or ai_label.text == "AI LOCAL",
		"badge shows live server (%s)" % ai_label.text)
	_main.call("start_game")
	await get_tree().process_frame
	_main.get("player").set("hp", 999) # survive stray bullets during live AI waits
	_check(await _wait_until(func() -> bool: return str(_main.get("_ai_taunt")) != "", 30.0),
		"briefing reached game (taunt stored)")
	print("[ai-test] announce after briefing: '%s'" % ann.text)
	_check(ann.text != "", "briefing announced on screen")
	# Director adjustment: wound the player, request, watch announce + mults.
	var player: Area2D = _main.get("player")
	_check(is_instance_valid(player), "player spawned")
	_main.set("_boss_spawned", false) # keep tip path deterministic
	player.set("hp", 1) # struggling pilot -> director should ease off
	_main.call("_request_director") # reads hp synchronously into the request
	player.set("hp", 999) # restore at once; the 0.2 snapshot is already sent
	_check(await _wait_until(func() -> bool: return ann.text.begins_with("WINGMAN:"), 30.0),
		"director tip announced")
	var miv := float(_main.get("_ai_interval_mult"))
	var msc := float(_main.get("_ai_scale_mult"))
	_check(miv >= 0.8 and miv <= 1.4 and msc >= 0.8 and msc <= 1.2,
		"director mults applied in bounds (%.3f / %.3f)" % [miv, msc])
	# Boss taunt path (announced synchronously on spawn).
	_main.call("_spawn_boss")
	_check(ann.text == str(_main.get("_ai_taunt")) and ann.text != "",
		"boss taunt announced")
	print("[ai-test] boss announce: '%s'" % ann.text)
	# Coach path on game over (1.4 s death beat, then live advice).
	_main.call("_on_player_died")
	_check(await _wait_until(func() -> bool: return ann.text.begins_with("COACH:"), 30.0),
		"coach announced on end screen")
	_finish()


func _rec_health(online: bool, source: String) -> void:
	_got_health = {"online": online, "source": source}
	print("[ai-test] health: online=%s source=%s" % [online, source])


func _rec_briefing(data: Dictionary) -> void:
	_got_briefing = data
	print("[ai-test] briefing (%s): %s" % [str(data.get("source", "?")), str(data.get("briefing", ""))])
	print("[ai-test] taunt: %s" % str(data.get("taunt", "")))


func _rec_director(data: Dictionary) -> void:
	_got_director = data
	print("[ai-test] director (%s): interval x%.3f scale x%.3f tip: %s" % [
		str(data.get("source", "?")),
		float(data.get("spawn_interval_mult", 0.0)),
		float(data.get("enemy_scale_mult", 0.0)),
		str(data.get("tip", ""))])


func _rec_coach(text: String, source: String) -> void:
	_got_coach = {"text": text, "source": source}
	print("[ai-test] coach (%s): %s" % [source, text])


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t := 0.0
	while t < timeout_s:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return bool(cond.call())


func _check(cond: bool, label: String) -> void:
	print("[ai-test] %s: %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures.append(label)


func _watchdog() -> void:
	await get_tree().create_timer(240.0).timeout
	if not _done:
		print("[ai-test] FAIL: timed out")
		_done = true
		get_tree().quit(1)


func _finish() -> void:
	_done = true
	if _ai != null:
		_ai.queue_free()
	if _main != null:
		_main.queue_free()
	await get_tree().process_frame # flush freed nodes before quit
	if _failures.is_empty():
		print("[ai-test] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[ai-test] RESULT: FAIL (%d failures)" % _failures.size())
		for f in _failures:
			print("[ai-test] failed: %s" % str(f))
		get_tree().quit(1)
