extends Node
## Regression test: enemy drops and the boss death shower spawn Area2D
## pickups from inside a physics callback (bullet hit -> take_damage -> _die).
## The spawn is deferred so the pickup's Area2D flags apply outside the
## flush; without the deferral the engine logs "Function blocked during
## in/out signal" errors (log-only: Area2D defaults match, so gameplay is
## unaffected either way).
## Run: godot --headless --path <project> res://tests/powerup_test.tscn
## Pass criteria: RESULT PASS with zero ERROR lines in the output.
## Exits 0 on success, 1 on any failure.

const EnemyScript := preload("res://scripts/enemy.gd")
const BossScript := preload("res://scripts/boss.gd")

var _failures: Array = []
var _done := false
var _world: Node2D
var _enemy: Area2D
var _boss: Area2D
var _fired := false


func _ready() -> void:
	_watchdog()
	_run()


func _run() -> void:
	_world = Node2D.new()
	_world.name = "World"
	add_child(_world)
	_enemy = EnemyScript.new()
	_enemy.call("setup", "tank", Vector2(240, 400), _world, null, 1.0)
	_world.add_child(_enemy)
	_enemy.set_process(false)
	_boss = BossScript.new()
	_boss.call("setup", 1, _world, null)
	_world.add_child(_boss)
	_boss.set_process(false)
	# Overlapping trigger pair: the entered callback runs inside the
	# physics flush, exactly like a bullet striking an enemy.
	var t1 := _trigger(1, 2)
	t1.connect("area_entered", _on_trigger)
	_world.add_child(t1)
	_world.add_child(_trigger(2, 1))
	if not await _wait_until(func() -> bool: return _fired, 10.0):
		_check(false, "physics callback fired")
		_finish()
		return
	for i in range(5):
		await get_tree().physics_frame
	var drops := get_tree().get_nodes_in_group("powerups")
	_check(drops.size() >= 5, "enemy drop + 4 boss shower spawned (%d)" % drops.size())
	var bad := 0
	for p in drops:
		if not is_instance_valid(p):
			continue
		var a: Area2D = p
		if a.collision_layer != 16 or a.collision_mask != 1:
			bad += 1
		if not a.monitoring or not a.monitorable:
			bad += 1
		var has_shape := false
		for c in a.get_children():
			if c is CollisionShape2D and (c as CollisionShape2D).shape is CircleShape2D:
				has_shape = true
		if not has_shape:
			bad += 1
	_check(bad == 0, "all pickups fully configured (layer/mask/monitor/shape)")
	_finish()


func _on_trigger(_area: Area2D) -> void:
	if _fired:
		return
	_fired = true
	# Tank drops at 55%: 20 rolls inside the flush makes a spawn certain.
	for i in range(20):
		_enemy.call("_maybe_drop")
	_boss.call("take_damage", 99999)


func _trigger(layer: int, mask: int) -> Area2D:
	var a := Area2D.new()
	a.collision_layer = layer
	a.collision_mask = mask
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	a.add_child(shape)
	return a


func _wait_until(cond: Callable, timeout_s: float) -> bool:
	var t := 0.0
	while t < timeout_s:
		if bool(cond.call()):
			return true
		await get_tree().process_frame
		t += get_process_delta_time()
	return bool(cond.call())


func _check(cond: bool, label: String) -> void:
	print("[drop-test] %s: %s" % ["PASS" if cond else "FAIL", label])
	if not cond:
		_failures.append(label)


func _watchdog() -> void:
	await get_tree().create_timer(60.0).timeout
	if not _done:
		print("[drop-test] FAIL: timed out")
		_done = true
		get_tree().quit(1)


func _finish() -> void:
	_done = true
	await get_tree().process_frame
	if _failures.is_empty():
		print("[drop-test] RESULT: PASS")
		get_tree().quit(0)
	else:
		print("[drop-test] RESULT: FAIL (%d failures)" % _failures.size())
		for f in _failures:
			print("[drop-test] failed: %s" % str(f))
		get_tree().quit(1)
