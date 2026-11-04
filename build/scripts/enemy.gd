extends Area2D
## Stylish code-drawn enemies with distinct movement + attack patterns.
## Types: drone, weaver, kamikaze, sniper, tank, gunship, elite.

signal killed(enemy: Area2D, score_value: int)

const BulletScript := preload("res://scripts/bullet.gd")
const ExplosionScript := preload("res://scripts/explosion.gd")
const PowerupScript := preload("res://scripts/powerup.gd")

var type_id: String = "drone"
var hp: int = 2
var max_hp: int = 2
var score_value: int = 100
var coins: int = 5
var speed: float = 120.0
var fire_interval: float = 2.2
var damage: int = 1
var radius: float = 18.0

var world: Node2D
var audio: Node
var level_scale: float = 1.0

var _t: float = 0.0
var _fire_cd: float = 1.0
var _base_x: float = 0.0
var _entered: bool = false
var _flash: float = 0.0
var _body: Polygon2D
var _wing_l: Polygon2D
var _wing_r: Polygon2D
var _core: Polygon2D
var _dive_dir: Vector2 = Vector2.ZERO

const STATS := {
	"drone": {"hp": 2, "score": 100, "coins": 4, "speed": 120.0, "fire": 2.4, "radius": 16.0},
	"weaver": {"hp": 3, "score": 150, "coins": 5, "speed": 170.0, "fire": 2.0, "radius": 16.0},
	"kamikaze": {"hp": 1, "score": 80, "coins": 3, "speed": 260.0, "fire": 99.0, "radius": 14.0},
	"sniper": {"hp": 4, "score": 200, "coins": 7, "speed": 70.0, "fire": 2.8, "radius": 17.0},
	"tank": {"hp": 14, "score": 300, "coins": 12, "speed": 55.0, "fire": 2.6, "radius": 26.0},
	"gunship": {"hp": 22, "score": 500, "coins": 18, "speed": 65.0, "fire": 1.8, "radius": 28.0},
	"elite": {"hp": 8, "score": 350, "coins": 14, "speed": 150.0, "fire": 1.5, "radius": 18.0},
}


func setup(p_type: String, p_pos: Vector2, p_world: Node2D, p_audio: Node, p_level_scale: float = 1.0) -> void:
	type_id = p_type
	position = p_pos
	world = p_world
	audio = p_audio
	level_scale = p_level_scale
	_base_x = p_pos.x
	var st: Dictionary = STATS.get(type_id, STATS["drone"])
	max_hp = int(float(st["hp"]) * level_scale)
	hp = max_hp
	score_value = int(st["score"])
	coins = int(st.get("coins", 5))
	speed = float(st["speed"])
	fire_interval = float(st["fire"])
	radius = float(st["radius"])
	_fire_cd = randf_range(0.6, fire_interval)


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 4
	collision_mask = 3 # player + player bullets
	monitoring = true
	monitorable = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius * 0.85
	shape.shape = circle
	add_child(shape)
	_build_visuals()
	area_entered.connect(_on_area_entered)


func _build_visuals() -> void:
	var hull := Color(0.16, 0.18, 0.28)
	var trim := Color(1.0, 0.3, 0.45)
	var glow := Color(1.0, 0.3, 0.45)
	match type_id:
		"drone":
			trim = Color(1.0, 0.35, 0.5)
		"weaver":
			trim = Color(0.7, 0.4, 1.0)
			glow = trim
		"kamikaze":
			trim = Color(1.0, 0.55, 0.2)
			glow = trim
		"sniper":
			trim = Color(0.35, 1.0, 0.7)
			glow = trim
		"tank":
			trim = Color(1.0, 0.25, 0.3)
			hull = Color(0.25, 0.12, 0.16)
		"gunship":
			trim = Color(0.35, 0.8, 1.0)
			glow = trim
		"elite":
			trim = Color(1.0, 0.85, 0.3)
			glow = trim
	var r := radius
	_wing_l = Polygon2D.new()
	_wing_l.polygon = PackedVector2Array([Vector2(-r * 0.3, -r * 0.4), Vector2(-r * 1.25, r * 0.9), Vector2(-r * 0.35, r * 0.7)])
	_wing_l.color = trim.darkened(0.35)
	add_child(_wing_l)
	_wing_r = Polygon2D.new()
	_wing_r.polygon = PackedVector2Array([Vector2(r * 0.3, -r * 0.4), Vector2(r * 1.25, r * 0.9), Vector2(r * 0.35, r * 0.7)])
	_wing_r.color = trim.darkened(0.35)
	add_child(_wing_r)
	_body = Polygon2D.new()
	_body.polygon = PackedVector2Array([
		Vector2(0, r * 1.1), Vector2(r * 0.55, r * 0.3),
		Vector2(r * 0.45, -r * 0.7), Vector2(0, -r * 1.0),
		Vector2(-r * 0.45, -r * 0.7), Vector2(-r * 0.55, r * 0.3),
	])
	_body.color = hull
	add_child(_body)
	var stripe := Polygon2D.new()
	stripe.polygon = PackedVector2Array([Vector2(0, r * 1.0), Vector2(r * 0.16, 0), Vector2(0, -r * 0.9), Vector2(-r * 0.16, 0)])
	stripe.color = trim
	add_child(stripe)
	_core = Polygon2D.new()
	var cpts := PackedVector2Array()
	for i in range(6):
		var a := TAU * float(i) / 6.0
		cpts.append(Vector2(cos(a), sin(a)) * r * 0.28)
	_core.polygon = cpts
	_core.color = glow
	add_child(_core)


func _process(delta: float) -> void:
	_t += delta
	var view := get_viewport_rect().size
	if _flash > 0.0:
		_flash -= delta
		var f := 1.0 + _flash * 4.0
		modulate = Color(f, f, f)
	else:
		modulate = Color.WHITE

	match type_id:
		"drone":
			position.y += speed * delta
			position.x = _base_x + sin(_t * 2.0) * 50.0
		"weaver":
			position.y += speed * 0.55 * delta
			position.x = _base_x + sin(_t * 3.4) * 110.0
		"kamikaze":
			_update_kamikaze(delta)
		"sniper":
			if position.y < 150.0:
				position.y += speed * delta
			else:
				position.x = _base_x + sin(_t * 1.2) * 130.0
				position.y = 150.0 + sin(_t * 2.0) * 14.0
		"tank":
			if position.y < 190.0:
				position.y += speed * delta
			else:
				position.x = _base_x + sin(_t * 0.7) * 90.0
		"gunship":
			if position.y < 130.0:
				position.y += speed * delta
			else:
				position.x = _base_x + sin(_t * 1.0) * 150.0
		"elite":
			position.y += speed * 0.4 * delta
			position.x = _base_x + sin(_t * 4.2) * 90.0

	if position.y > 10.0:
		_entered = true
	if _core != null:
		var s := 1.0 + sin(_t * 6.0) * 0.18
		_core.scale = Vector2(s, s)

	_fire_cd -= delta
	if _fire_cd <= 0.0 and _entered and position.y < view.y * 0.7:
		_fire_cd = fire_interval * randf_range(0.85, 1.2)
		_fire()

	if position.y > view.y + 60.0 or position.x < -80.0 or position.x > view.x + 80.0:
		queue_free()


func _update_kamikaze(delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if _t < 0.7:
		position.y += speed * 0.6 * delta
		if player != null:
			_dive_dir = (player.global_position - global_position).normalized()
	else:
		if _dive_dir == Vector2.ZERO:
			_dive_dir = Vector2(0, 1)
		# Slight homing.
		if player != null:
			var want: Vector2 = (player.global_position - global_position).normalized()
			_dive_dir = (_dive_dir * 3.0 + want).normalized()
		position += _dive_dir * speed * delta
		rotation = _dive_dir.angle() - PI * 0.5


func _player_pos() -> Vector2:
	var player := get_tree().get_first_node_in_group("player") as Node2D
	if player != null:
		return player.global_position
	return Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y - 100.0)


func _fire() -> void:
	if world == null:
		return
	var from := position + Vector2(0, radius)
	var target := _player_pos()
	var dir: Vector2 = (target - from).normalized()
	if dir.length() < 0.1:
		dir = Vector2(0, 1)
	match type_id:
		"drone":
			_spawn_bullet(from, dir * 260.0, "orb")
		"weaver":
			for a in [-0.28, 0.0, 0.28]:
				_spawn_bullet(from, dir.rotated(a) * 280.0, "shard")
		"sniper":
			_spawn_bullet(from, dir * 430.0, "needle")
			if audio != null and audio.has_method("play_enemy_laser"):
				audio.call("play_enemy_laser")
		"tank":
			for i in range(5):
				var a2 := lerpf(-0.5, 0.5, float(i) / 4.0)
				_spawn_bullet(from, Vector2(0, 1).rotated(a2) * 230.0, "orb")
		"gunship":
			for i in range(8):
				var a3 := TAU * float(i) / 8.0 + _t
				var gv := Vector2(cos(a3), absf(sin(a3)) * 0.7 + 0.4).normalized()
				_spawn_bullet(from, gv * 210.0, "orb")
			_spawn_bullet(from, dir * 330.0, "needle")
		"elite":
			for a in [-0.2, 0.0, 0.2]:
				_spawn_bullet(from, dir.rotated(a) * 330.0, "shard")
		"kamikaze":
			pass # no shots, it IS the shot
	if audio != null and audio.has_method("play_enemy_laser") and type_id != "sniper":
		if randf() < 0.4:
			audio.call("play_enemy_laser")


func _spawn_bullet(pos: Vector2, vel: Vector2, style: String) -> void:
	var b: Area2D = BulletScript.new()
	b.call("setup", pos, vel, false, damage, style)
	world.add_child(b)


func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO) -> void:
	hp -= amount
	_flash = 0.12
	if hp <= 0:
		_die()


func _die() -> void:
	killed.emit(self, score_value)
	if world != null:
		ExplosionScript.spawn(world, position, radius * 3.2, Color(1.0, 0.5, 0.25), type_id == "tank" or type_id == "gunship")
		_maybe_drop()
	queue_free()


func _maybe_drop() -> void:
	var chance := 0.10
	if type_id == "tank":
		chance = 0.55
	elif type_id == "gunship":
		chance = 0.7
	elif type_id == "elite":
		chance = 0.4
	elif type_id == "sniper":
		chance = 0.16
	if randf() > chance:
		return
	var roll := randf()
	var kind := "power"
	if roll < 0.30:
		kind = "power"
	elif roll < 0.45:
		kind = "coins"
	elif roll < 0.58:
		kind = "score"
	elif roll < 0.72:
		kind = "shield"
	elif roll < 0.86:
		kind = "bomb"
	else:
		kind = "heal"
	var p: Area2D = PowerupScript.new()
	p.call("setup", kind, position)
	# Death runs inside a physics callback: defer the add so the pickup's
	# Area2D flags apply outside the flush (else "Function blocked" errors).
	world.call_deferred("add_child", p)


func _on_area_entered(area: Area2D) -> void:
	# Player bullets are handled by the bullet itself; nothing needed here.
	pass
