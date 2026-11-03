extends Node2D
## Space Shooters - game manager: 5 levels, waves, bosses, score, screens.

const PlayerScript := preload("res://scripts/player.gd")
const EnemyScript := preload("res://scripts/enemy.gd")
const BossScript := preload("res://scripts/boss.gd")
const StarfieldScript := preload("res://scripts/starfield.gd")
const HudScript := preload("res://scripts/hud.gd")
const AudioScript := preload("res://scripts/audio_manager.gd")
const ExplosionScript := preload("res://scripts/explosion.gd")
const AdsManagerScript := preload("res://scripts/ads_manager.gd")
const IapManagerScript := preload("res://scripts/iap_manager.gd")
const MetaAiScript := preload("res://scripts/meta_ai.gd")
const VoiceScript := preload("res://scripts/voiceover.gd")

enum State { MENU, PLAYING, LEVEL_CLEAR, GAME_OVER, VICTORY }

var state: int = State.MENU
var level: int = 1
var score: int = 0
var hi_score: int = 0
var kills: int = 0
var coins: int = 0

var world: Node2D
var starfield: Node2D
var hud: CanvasLayer
var audio: Node
var player: Area2D
var camera: Camera2D
var ads: Node
var iap: Node
var ai: Node
var voice: Node
var voice_on := true
var _shop_poll_cd := 0.0
var flash_rect: ColorRect

var _level_time: float = 0.0
var _spawn_cd: float = 0.0
var _boss: Area2D
var _boss_spawned: bool = false
var _clear_cd: float = 0.0
var _shake: float = 0.0
var _flash_a: float = 0.0
var _enemies: Array = []
var _ai_interval_mult := 1.0
var _ai_scale_mult := 1.0
var _ai_taunt := ""
var _director_cd := 12.0
var _run_start_msec := 0
var _run_deaths := 0

const SAVE_PATH := "user://space_shooters_save.cfg"

const LEVELS := [
	{"name": "NEON DRIFT", "duration": 38.0, "interval": 2.2, "scale": 1.0,
	 "pool": ["drone", "drone", "weaver", "kamikaze"]},
	{"name": "CRIMSON BELT", "duration": 44.0, "interval": 1.9, "scale": 1.25,
	 "pool": ["drone", "weaver", "weaver", "kamikaze", "sniper", "tank"]},
	{"name": "CHROMA STORM", "duration": 50.0, "interval": 1.7, "scale": 1.5,
	 "pool": ["weaver", "sniper", "kamikaze", "tank", "elite", "drone"]},
	{"name": "VOID EDGE", "duration": 56.0, "interval": 1.5, "scale": 1.8,
	 "pool": ["sniper", "tank", "gunship", "elite", "kamikaze", "weaver"]},
	{"name": "STAR EATER'S MAW", "duration": 62.0, "interval": 1.3, "scale": 2.1,
	 "pool": ["gunship", "elite", "tank", "sniper", "weaver", "kamikaze"]},
]

const SHOP := [
	{"id": "power", "name": "GUNS", "desc": "start runs with +1 stream", "max": 4, "costs": [120, 260, 450, 700]},
	{"id": "rate", "name": "FIRE RATE", "desc": "guns cycle faster", "max": 5, "costs": [80, 170, 300, 470, 680]},
	{"id": "hull", "name": "HULL", "desc": "+1 max HP every run", "max": 5, "costs": [100, 200, 330, 500, 700]},
	{"id": "engine", "name": "ENGINE", "desc": "+ship speed", "max": 5, "costs": [60, 130, 230, 360, 520]},
	{"id": "shield", "name": "SHIELD", "desc": "start with +1 shield", "max": 3, "costs": [150, 300, 500]},
	{"id": "bomb", "name": "BOMB", "desc": "start with +1 bomb", "max": 2, "costs": [120, 280]},
]

var meta := {"power": 0, "rate": 0, "hull": 0, "engine": 0, "shield": 0, "bomb": 0}


func _ready() -> void:
	add_to_group("game")
	_load_hi()
	# Background.
	starfield = StarfieldScript.new()
	add_child(starfield)
	# World container for entities.
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	# Camera + shake.
	camera = Camera2D.new()
	camera.position = get_viewport_rect().size * 0.5
	add_child(camera)
	camera.make_current()
	# Screen flash overlay.
	flash_rect = ColorRect.new()
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.color = Color(1, 1, 1, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var flash_layer := CanvasLayer.new()
	flash_layer.layer = 90
	flash_layer.add_child(flash_rect)
	add_child(flash_layer)
	# Audio.
	audio = AudioScript.new()
	add_child(audio)
	# Store services (ads + IAP, Huawei or Google); safe no-ops on desktop.
	ads = AdsManagerScript.new()
	add_child(ads)
	iap = IapManagerScript.new()
	add_child(iap)
	# AI Wingman (Meta Model API; offline-safe, game never depends on it).
	ai = MetaAiScript.new()
	add_child(ai)
	ai.connect("health_ready", _on_ai_health)
	ai.connect("briefing_ready", _on_ai_briefing)
	ai.connect("director_ready", _on_ai_director)
	ai.connect("coach_ready", _on_ai_coach)
	# Voiceover for AI lines (on-device TTS; silent no-op if unsupported).
	voice = VoiceScript.new()
	add_child(voice)
	voice.set("enabled", voice_on)
	# HUD.
	hud = HudScript.new()
	hud.call("setup", audio, voice)
	add_child(hud)
	hud.connect("start_requested", start_game)
	hud.connect("restart_requested", start_game)
	hud.connect("resume_requested", func() -> void: pass)
	hud.connect("quit_to_menu_requested", to_menu)
	hud.connect("upgrade_bought", buy_upgrade)
	hud.connect("shop_closed", close_shop)
	hud.connect("shop_requested", open_shop)
	hud.connect("free_coins_requested", _on_free_coins_requested)
	hud.connect("coin_pack_requested", _on_pack_requested)
	hud.connect("voice_toggled", _on_voice_toggled)
	iap.connect("packs_updated", _on_packs_updated)
	iap.connect("purchase_completed", _on_coins_purchased)
	iap.connect("purchase_failed", _on_purchase_failed)
	ads.connect("reward_granted", _on_reward_granted)
	hud.call("show_menu")
	hud.call("set_voice_enabled", voice_on)
	hud.call("set_score", 0, hi_score)
	hud.call("set_coins", coins)
	ads.call("show_menu_banner")


func _process(delta: float) -> void:
	# Global keys (edge-triggered).
	_poll_pause_key()
	if state == State.MENU or state == State.GAME_OVER or state == State.VICTORY:
		_poll_confirm_key()
	_poll_shop_extras(delta)
	# Camera shake decay.
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 30.0)
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
	else:
		camera.offset = camera.offset.lerp(Vector2.ZERO, minf(1.0, delta * 8.0))
	# Flash decay.
	if _flash_a > 0.0:
		_flash_a = maxf(0.0, _flash_a - delta * 1.8)
		var c := flash_rect.color
		c.a = _flash_a
		flash_rect.color = c
	if state != State.PLAYING and state != State.LEVEL_CLEAR:
		return
	_level_time += delta
	if state == State.PLAYING:
		_director_cd -= delta
		if _director_cd <= 0.0:
			_director_cd = 12.0
			_request_director()
	var cfg: Dictionary = LEVELS[level - 1]
	if state == State.PLAYING and not _boss_spawned:
		_spawn_cd -= delta
		if _spawn_cd <= 0.0:
			_spawn_cd = float(cfg["interval"]) * randf_range(0.8, 1.15) * _ai_interval_mult
			_spawn_formation(cfg)
		if _level_time >= float(cfg["duration"]):
			_spawn_boss()
	elif state == State.LEVEL_CLEAR:
		_clear_cd -= delta
		if _clear_cd <= 0.0:
			_next_level()


var _pause_held: bool = false
func _poll_pause_key() -> void:
	var held := Input.is_key_pressed(KEY_P) or Input.is_key_pressed(KEY_ESCAPE) or Input.is_joy_button_pressed(0, JOY_BUTTON_START)
	if held and not _pause_held:
		if state == State.PLAYING and not get_tree().paused:
			get_tree().set_pause(true)
			var pm: Control = hud.get("_pause_menu")
			if pm != null:
				pm.visible = true
	_pause_held = held


var _confirm_held: bool = false
func _poll_confirm_key() -> void:
	var held := Input.is_key_pressed(KEY_ENTER) or Input.is_key_pressed(KEY_KP_ENTER) or Input.is_joy_button_pressed(0, JOY_BUTTON_START) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
	if held and not _confirm_held:
		start_game()
	_confirm_held = held


# --- game flow ---

func start_game() -> void:
	get_tree().set_pause(false)
	_clear_world()
	state = State.PLAYING
	level = 1
	score = 0
	kills = 0
	_run_start_msec = Time.get_ticks_msec()
	_run_deaths = 0
	_ai_interval_mult = 1.0
	_ai_scale_mult = 1.0
	_ai_taunt = ""
	_director_cd = 12.0
	hud.call("hide_menu")
	hud.call("set_score", score, hi_score)
	hud.call("set_coins", coins)
	ads.call("hide_menu_banner")
	voice.call("stop")
	_start_level()


func to_menu() -> void:
	get_tree().set_pause(false)
	_clear_world()
	state = State.MENU
	_save_game()
	hud.call("show_menu")
	hud.call("set_score", score, hi_score)
	hud.call("set_coins", coins)
	voice.call("stop")
	ads.call("show_menu_banner")


func _start_level() -> void:
	var cfg: Dictionary = LEVELS[level - 1]
	_level_time = 0.0
	_spawn_cd = 1.2
	_boss_spawned = false
	_boss = null
	starfield.call("set_level", level)
	hud.call("set_level", level)
	hud.call("hide_boss_bar")
	hud.call("show_banner", "LEVEL %d\n%s" % [level, String(cfg["name"])])
	hud.call("announce", "Boss approaching - survive!" if level == 1 else "Sector %d - good luck!" % level)
	if player == null or not is_instance_valid(player):
		_spawn_player()
	else:
		player.call("heal_full")
	_request_briefing()


func _next_level() -> void:
	if level >= 5:
		_victory()
		return
	level += 1
	state = State.PLAYING
	_start_level()


func _spawn_player() -> void:
	var view := get_viewport_rect().size
	player = PlayerScript.new()
	player.call("setup", world, audio)
	player.position = Vector2(view.x * 0.5, view.y - 120.0)
	world.add_child(player)
	player.call("apply_meta", meta)
	player.connect("hp_changed", func(h: int, m: int) -> void: hud.call("set_hp", h, m); hud.call("set_shields", int(player.get("shields"))))
	player.connect("power_changed", func(p: int) -> void: hud.call("set_power", p))
	player.connect("bombs_changed", func(b: int) -> void: hud.call("set_bombs", b))
	player.connect("died", _on_player_died)
	player.connect("bombed", func() -> void: add_shake(8.0))
	hud.call("set_hp", int(player.get("hp")), int(player.get("max_hp")))
	hud.call("set_power", int(player.get("power")))
	hud.call("set_bombs", int(player.get("bombs")))
	hud.call("set_shields", int(player.get("shields")))


func _on_player_died() -> void:
	_run_deaths += 1
	add_shake(16.0)
	flash_screen(Color(1, 0.2, 0.2, 0.5))
	await get_tree().create_timer(1.4).timeout
	if state == State.PLAYING or state == State.LEVEL_CLEAR:
		state = State.GAME_OVER
		_save_hi()
		hud.call("show_end", false, score, hi_score, level)
		_request_coach(false)


func _victory() -> void:
	state = State.VICTORY
	add_score(5000)
	_save_hi()
	hud.call("show_end", true, score, hi_score, 5)
	_request_coach(true)


func _clear_world() -> void:
	_enemies.clear()
	_boss = null
	if world != null:
		for c in world.get_children():
			c.queue_free()
	player = null
	get_tree().set_pause(false)


# --- waves ---

func _spawn_formation(cfg: Dictionary) -> void:
	var view := get_viewport_rect().size
	var pool: Array = cfg["pool"]
	var scalef := float(cfg["scale"]) * _ai_scale_mult
	var kind := randi() % 4
	var n := randi_range(3, 4 + mini(level, 3))
	for i in range(n):
		var t := String(pool[randi() % pool.size()])
		var pos := Vector2.ZERO
		match kind:
			0: # top line
				pos = Vector2(view.x * (0.15 + 0.7 * float(i) / float(maxi(1, n - 1))), -30.0 - float(i % 2) * 34.0)
			1: # V formation
				var mid := float(n - 1) * 0.5
				pos = Vector2(view.x * 0.5 + (float(i) - mid) * 64.0, -30.0 - absf(float(i) - mid) * 40.0)
			2: # staggered dive column
				pos = Vector2(view.x * randf_range(0.15, 0.85), -30.0 - float(i) * 56.0)
			3: # arc
				var a := PI * float(i) / float(maxi(1, n - 1))
				pos = Vector2(view.x * 0.5 + cos(a) * view.x * 0.38, 90.0 - sin(a) * 120.0)
		var e: Area2D = EnemyScript.new()
		e.call("setup", t, pos, world, audio, scalef)
		world.add_child(e)
		track_enemy(e)


func track_enemy(e: Area2D) -> void:
	if not _enemies.has(e):
		_enemies.append(e)
	if not e.is_connected("killed", _on_enemy_killed):
		e.connect("killed", _on_enemy_killed)


func _on_enemy_killed(enemy: Area2D, value: int) -> void:
	kills += 1
	add_score(value)
	if is_instance_valid(enemy):
		add_coins(int(enemy.get("coins")))


func _spawn_boss() -> void:
	_boss_spawned = true
	# Clear leftover small enemies (leave a clean arena).
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	_boss = BossScript.new()
	_boss.call("setup", level, world, audio)
	world.add_child(_boss)
	_boss.connect("killed", _on_boss_killed)
	_boss.connect("hp_changed", func(h: int, m: int) -> void: hud.call("update_boss_bar", h, m))
	hud.call("show_boss_bar", String(_boss.get("boss_name")), int(_boss.get("hp")), int(_boss.get("max_hp")))
	hud.call("show_banner", "WARNING\n%s" % String(_boss.get("boss_name")), 2.8)
	audio.call("play_boss_taunt", level)
	if _ai_taunt != "":
		hud.call("announce", _ai_taunt, 3.0)
		voice.call("speak", _ai_taunt, 0.75, 0.95)
	add_shake(10.0)


func _on_boss_killed(boss: Area2D) -> void:
	var value := int(boss.get("score_value"))
	add_score(value)
	add_score(level * 1000) # level-clear bonus
	add_coins(int(boss.get("coins")) + 40 * level)
	ads.call("notify_boss_defeated")
	hud.call("hide_boss_bar")
	hud.call("show_banner", "LEVEL %d CLEAR!" % level, 2.6)
	audio.call("play_powerup")
	add_shake(14.0)
	flash_screen(Color(1, 1, 1, 0.4))
	state = State.LEVEL_CLEAR
	_clear_cd = 3.2
	if player != null and is_instance_valid(player):
		player.call("heal_full")


# --- helpers ---

func add_score(v: int) -> void:
	score += v
	if score > hi_score:
		hi_score = score
	hud.call("set_score", score, hi_score)


func add_coins(v: int) -> void:
	coins += v
	hud.call("set_coins", coins)


func _shop_items() -> Array:
	var items: Array = []
	for entry in SHOP:
		var e: Dictionary = entry
		var lv := int(meta.get(String(e["id"]), 0))
		var cost := -1
		if lv < int(e["max"]):
			var costs: Array = e["costs"]
			cost = int(costs[lv])
		items.append({
			"id": String(e["id"]),
			"name": String(e["name"]),
			"desc": String(e["desc"]),
			"level": lv,
			"max": int(e["max"]),
			"cost": cost,
		})
	return items


func open_shop() -> void:
	hud.call("show_shop", coins, _shop_items())
	hud.call("refresh_packs", iap.call("get_packs"))
	_refresh_free_coins_button()


func close_shop() -> void:
	hud.call("hide_shop")


func buy_upgrade(id: String) -> void:
	for entry in SHOP:
		var e: Dictionary = entry
		if String(e["id"]) != id:
			continue
		var lv := int(meta.get(id, 0))
		if lv >= int(e["max"]):
			return
		var costs: Array = e["costs"]
		var cost := int(costs[lv])
		if coins < cost:
			audio.call("play_denied")
			return
		coins -= cost
		meta[id] = lv + 1
		hud.call("set_coins", coins)
		hud.call("refresh_shop", coins, _shop_items())
		audio.call("play_powerup")
		_save_game()
		return


func _on_free_coins_requested() -> void:
	ads.call("show_free_coins")


func _on_pack_requested(pack_id: String) -> void:
	iap.call("buy_pack", pack_id)


func _on_packs_updated() -> void:
	hud.call("refresh_packs", iap.call("get_packs"))


func _on_reward_granted(reward_coins: int) -> void:
	add_coins(reward_coins)
	_save_game()
	audio.call("play_powerup")
	hud.call("refresh_shop", coins, _shop_items())
	_refresh_free_coins_button()


func _on_coins_purchased(_pack_id: String, pack_coins: int) -> void:
	add_coins(pack_coins)
	_save_game()
	audio.call("play_powerup")
	hud.call("refresh_shop", coins, _shop_items())
	hud.call("refresh_packs", iap.call("get_packs"))


func _on_purchase_failed(_reason: String) -> void:
	audio.call("play_denied")


func _refresh_free_coins_button() -> void:
	var st: Dictionary = ads.call("free_coins_status")
	hud.call("set_free_coins", bool(st.get("ready", false)), String(st.get("label", "")))


func _poll_shop_extras(delta: float) -> void:
	_shop_poll_cd -= delta
	if _shop_poll_cd > 0.0:
		return
	_shop_poll_cd = 0.5
	if bool(hud.call("is_shop_open")):
		_refresh_free_coins_button()


func announce(text: String) -> void:
	hud.call("announce", text)


func add_shake(amount: float) -> void:
	_shake = minf(_shake + amount, 22.0)


func flash_screen(c: Color) -> void:
	flash_rect.color = Color(c.r, c.g, c.b, c.a)
	_flash_a = c.a


func _load_hi() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		hi_score = int(cfg.get_value("game", "hi_score", 0))
		coins = int(cfg.get_value("game", "coins", 0))
		voice_on = bool(cfg.get_value("game", "voice", true))
		for key in meta.keys():
			meta[key] = int(cfg.get_value("meta", key, 0))


func _save_hi() -> void:
	_save_game()


func _save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("game", "hi_score", hi_score)
	cfg.set_value("game", "coins", coins)
	cfg.set_value("game", "voice", voice_on)
	for key in meta.keys():
		cfg.set_value("meta", key, int(meta[key]))
	cfg.save(SAVE_PATH)


# --- AI Wingman (Meta Model API; all async, all optional) ---

func _request_briefing() -> void:
	if ai == null:
		return
	var cfg: Dictionary = LEVELS[level - 1]
	var pct := 100
	if player != null and is_instance_valid(player):
		var m := maxi(1, int(player.get("max_hp")))
		pct = int(round(100.0 * float(player.get("hp")) / float(m)))
	ai.call("request_briefing", level, String(cfg["name"]), pct, kills)


func _on_ai_health(online: bool, source: String) -> void:
	if hud == null:
		return
	hud.call("set_ai_status", online, source)


func _on_ai_briefing(data: Dictionary) -> void:
	_ai_taunt = str(data.get("taunt", ""))
	print("[ai] briefing (%s): %s" % [str(data.get("source", "?")), str(data.get("briefing", ""))])
	if state == State.PLAYING:
		hud.call("announce", str(data.get("briefing", "")), 3.2)


func _request_director() -> void:
	if ai == null or state != State.PLAYING:
		return
	var hpf := 1.0
	if player != null and is_instance_valid(player):
		var m := maxi(1, int(player.get("max_hp")))
		hpf = clampf(float(player.get("hp")) / float(m), 0.0, 1.0)
	var elapsed := maxf(1.0, float(Time.get_ticks_msec() - _run_start_msec) / 60000.0)
	ai.call("request_director", level, hpf, float(kills) / elapsed, _run_deaths)


func _on_ai_director(data: Dictionary) -> void:
	_ai_interval_mult = clampf(float(data.get("spawn_interval_mult", 1.0)), 0.8, 1.4)
	_ai_scale_mult = clampf(float(data.get("enemy_scale_mult", 1.0)), 0.8, 1.2)
	var tip := str(data.get("tip", ""))
	print("[ai] director (%s): interval x%.2f scale x%.2f tip: %s" % [str(data.get("source", "?")), _ai_interval_mult, _ai_scale_mult, tip])
	if tip != "" and state == State.PLAYING and not _boss_spawned:
		hud.call("announce", "WINGMAN: " + tip, 3.0)
		voice.call("speak", tip, 1.0, 1.05)


func _request_coach(victory: bool) -> void:
	if ai == null:
		return
	ai.call("request_coach", score, kills, level, _run_deaths, victory)


func _on_ai_coach(text: String, source: String) -> void:
	print("[ai] coach (%s): %s" % [source, text])
	hud.call("announce", "COACH: " + text, 5.0)
	voice.call("speak", text)


func _on_voice_toggled(on: bool) -> void:
	voice_on = on
	_save_game()
