extends Area2D
## Player ship using player.png (magenta background removed via chroma shader).
## Auto-fires, moves with keyboard / mouse-hold / touch-drag.

signal hp_changed(hp: int, max_hp: int)
signal power_changed(power: int)
signal bombs_changed(bombs: int)
signal died
signal bombed

const BulletScript := preload("res://scripts/bullet.gd")
const ExplosionScript := preload("res://scripts/explosion.gd")

var speed: float = 340.0
var max_hp: int = 5
var hp: int = 3
var power: int = 1
var bombs: int = 3
var shields: int = 0
var rate_level: int = 0
var speed_level: int = 0
var alive: bool = true

var fire_interval: float = 0.14
var _fire_cd: float = 0.0
var _iframe: float = 0.0
var _tilt: float = 0.0
var _bob: float = 0.0

var world: Node2D
var audio: Node

var _sprite: Sprite2D
var _shield_ring: Line2D
var _engine: CPUParticles2D
var _touch_target: Vector2 = Vector2.INF
var _has_touch_target: bool = false


func setup(p_world: Node2D, p_audio: Node) -> void:
    world = p_world
    audio = p_audio


func _ready() -> void:
    add_to_group("player")
    collision_layer = 1
    collision_mask = 28 # enemy + enemy bullet + powerup
    monitoring = true
    monitorable = true

    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = 10.0 # small forgiving hitbox for bullet-hell
    shape.shape = circle
    add_child(shape)

    # Ship sprite from player.png with magenta removed.
    _sprite = Sprite2D.new()
    var tex: Texture2D = load("res://player.png")
    if tex != null:
        _sprite.texture = tex
        var w := float(tex.get_width())
        if w > 1.0:
            var s := 68.0 / w
            _sprite.scale = Vector2(s, s)
    _sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    var chroma: Shader = load("res://shaders/chroma_key.gdshader")
    if chroma != null:
        var mat := ShaderMaterial.new()
        mat.shader = chroma
        _sprite.material = mat
    add_child(_sprite)

    # Engine glow particles.
    _engine = CPUParticles2D.new()
    _engine.amount = 18
    _engine.lifetime = 0.35
    _engine.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
    _engine.emission_sphere_radius = 5.0
    _engine.direction = Vector2(0, 1)
    _engine.spread = 18.0
    _engine.initial_velocity_min = 140.0
    _engine.initial_velocity_max = 260.0
    _engine.gravity = Vector2.ZERO
    _engine.scale_amount_min = 2.0
    _engine.scale_amount_max = 4.0
    _engine.color = Color(0.4, 0.85, 1.0, 0.8)
    _engine.position = Vector2(0, 30)
    add_child(_engine)

    # Shield ring (hidden unless shields > 0).
    _shield_ring = Line2D.new()
    _shield_ring.width = 3.0
    _shield_ring.default_color = Color(0.4, 1.0, 0.7, 0.9)
    var rpts := PackedVector2Array()
    for i in range(33):
        var a := TAU * float(i) / 32.0
        rpts.append(Vector2(cos(a), sin(a)) * 34.0)
    _shield_ring.points = rpts
    _shield_ring.visible = false
    add_child(_shield_ring)

    area_entered.connect(_on_area_entered)
    hp_changed.emit(hp, max_hp)
    power_changed.emit(power)
    bombs_changed.emit(bombs)


func _input(event: InputEvent) -> void:
    if not alive:
        return
    if event is InputEventScreenTouch:
        var t := event as InputEventScreenTouch
        if t.pressed:
            # Convert screen coords via canvas transform.
            _touch_target = get_canvas_transform().affine_inverse() * t.position
            _has_touch_target = true
        else:
            _has_touch_target = false
    elif event is InputEventScreenDrag:
        var d := event as InputEventScreenDrag
        _touch_target = get_canvas_transform().affine_inverse() * d.position
        _has_touch_target = true
    elif event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
            use_bomb()


func _process(delta: float) -> void:
    if not alive:
        return
    _bob += delta
    # --- Movement: keyboard ---
    var dir := Vector2.ZERO
    if Input.is_action_pressed("ui_left") or Input.is_key_pressed(KEY_A):
        dir.x -= 1.0
    if Input.is_action_pressed("ui_right") or Input.is_key_pressed(KEY_D):
        dir.x += 1.0
    if Input.is_action_pressed("ui_up") or Input.is_key_pressed(KEY_W):
        dir.y -= 1.0
    if Input.is_action_pressed("ui_down") or Input.is_key_pressed(KEY_S):
        dir.y += 1.0
    # Gamepad: left stick (analog) + D-pad.
    var joy := Vector2(Input.get_joy_axis(0, JOY_AXIS_LEFT_X), Input.get_joy_axis(0, JOY_AXIS_LEFT_Y))
    if joy.length() > 0.25:
        dir = joy.normalized() * minf(1.0, joy.length())
    if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_LEFT):
        dir.x = -1.0
    if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_RIGHT):
        dir.x = 1.0
    if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_UP):
        dir.y = -1.0
    if Input.is_joy_button_pressed(0, JOY_BUTTON_DPAD_DOWN):
        dir.y = 1.0
    if dir.length() > 0.0:
        dir = dir.normalized()
        position += dir * speed * delta
        _has_touch_target = false
    elif _has_touch_target:
        var to: Vector2 = _touch_target - position
        if to.length() > 6.0:
            position += to.normalized() * minf(speed * 1.4, to.length() * 10.0) * delta
    elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
        # Mouse-hold steering (disabled while clicking HUD buttons handled by gui).
        var mp := get_global_mouse_position()
        var to2: Vector2 = mp - position
        if to2.length() > 8.0:
            position += to2.normalized() * minf(speed * 1.3, to2.length() * 9.0) * delta

    var view := get_viewport_rect().size
    position.x = clampf(position.x, 26.0, view.x - 26.0)
    position.y = clampf(position.y, view.y * 0.25, view.y - 40.0)

    # Banking tilt + bob.
    var target_tilt := clampf(dir.x * 0.22, -0.3, 0.3)
    _tilt = lerpf(_tilt, target_tilt, minf(1.0, delta * 10.0))
    if _sprite != null:
        _sprite.rotation = _tilt
        _sprite.position.y = sin(_bob * 3.0) * 2.0
    if _shield_ring != null and _shield_ring.visible:
        _shield_ring.rotation += delta * 2.0

    # Invincibility blink.
    if _iframe > 0.0:
        _iframe -= delta
        _sprite.modulate.a = 0.35 if int(_bob * 14.0) % 2 == 0 else 1.0
    else:
        _sprite.modulate.a = 1.0

    # Auto-fire.
    _fire_cd -= delta
    if _fire_cd <= 0.0:
        _fire_cd = fire_interval
        _fire()

    # Bomb keys (edge-triggered in _poll_bomb_keys).
    _poll_bomb_keys()


var _bomb_key_held: bool = false

func _poll_bomb_keys() -> void:
    var held := Input.is_key_pressed(KEY_X) or Input.is_key_pressed(KEY_B) or Input.is_key_pressed(KEY_SPACE) or Input.is_joy_button_pressed(0, JOY_BUTTON_A)
    if held and not _bomb_key_held:
        use_bomb()
    _bomb_key_held = held


func _fire() -> void:
    if world == null or not is_inside_tree():
        return
    var muzzle := position + Vector2(0, -34)
    var spd := 640.0
    var patterns: Array = []
    match power:
        1:
            patterns = [[Vector2(0, -spd), "bolt"]]
        2:
            patterns = [[Vector2(-14, -spd), "bolt"], [Vector2(14, -spd), "bolt"]]
        3:
            patterns = [[Vector2(0, -spd), "bolt_big"], [Vector2(-160, -spd), "bolt"], [Vector2(160, -spd), "bolt"]]
        4:
            patterns = [[Vector2(-14, -spd), "bolt_big"], [Vector2(14, -spd), "bolt_big"], [Vector2(-220, -spd), "bolt"], [Vector2(220, -spd), "bolt"]]
        _:
            patterns = [[Vector2(0, -spd), "bolt_big"], [Vector2(-14, -spd), "bolt_big"], [Vector2(14, -spd), "bolt_big"], [Vector2(-260, -spd), "bolt"], [Vector2(260, -spd), "bolt"]]
    for p in patterns:
        var b: Area2D = BulletScript.new()
        var off := Vector2(p[0].x * 0.03, 0)
        b.call("setup", muzzle + off, p[0], true, 1, p[1])
        world.add_child(b)
    if audio != null and audio.has_method("play_laser"):
        audio.call("play_laser")


func use_bomb() -> void:
    if not alive or bombs <= 0:
        return
    bombs -= 1
    bombs_changed.emit(bombs)
    bombed.emit()
    if audio != null and audio.has_method("play_bomb"):
        audio.call("play_bomb")
    if world == null:
        return
    # Flash + clear enemy bullets + damage everything.
    ExplosionScript.spawn(world, position, 220.0, Color(0.5, 0.9, 1.0), true)
    for b in get_tree().get_nodes_in_group("enemy_bullets"):
        if is_instance_valid(b):
            ExplosionScript.spawn(world, (b as Node2D).global_position, 24.0, Color(0.5, 0.9, 1.0), false)
            b.queue_free()
    for e in get_tree().get_nodes_in_group("enemies"):
        if is_instance_valid(e) and e.has_method("take_damage"):
            e.call("take_damage", 25, position)
    for boss in get_tree().get_nodes_in_group("bosses"):
        if is_instance_valid(boss) and boss.has_method("take_damage"):
            boss.call("take_damage", 60, position)
    var main := get_tree().get_first_node_in_group("game")
    if main != null and main.has_method("flash_screen"):
        main.call("flash_screen", Color(0.5, 0.9, 1.0, 0.5))


func take_damage(amount: int = 1) -> void:
    if not alive or _iframe > 0.0:
        return
    if shields > 0:
        shields -= 1
        _update_shield_ring()
        _iframe = 0.8
        if audio != null and audio.has_method("play_shield"):
            audio.call("play_shield")
        return
    hp -= amount
    hp_changed.emit(hp, max_hp)
    if audio != null and audio.has_method("play_hit"):
        audio.call("play_hit")
    if world != null:
        ExplosionScript.spawn(world, position, 50.0, Color(1.0, 0.4, 0.3), false)
    if hp <= 0:
        _die()
    else:
        _iframe = 1.5


func _die() -> void:
    alive = false
    if world != null:
        ExplosionScript.spawn(world, position, 130.0, Color(1.0, 0.55, 0.2), true)
    died.emit()
    queue_free()


func apply_powerup(kind: String) -> void:
    match kind:
        "power":
            power = mini(power + 1, 5)
            power_changed.emit(power)
        "shield":
            shields = mini(shields + 1, 3)
            _update_shield_ring()
        "heal":
            hp = mini(hp + 1, max_hp)
            hp_changed.emit(hp, max_hp)
        "bomb":
            bombs = mini(bombs + 1, 5)
            bombs_changed.emit(bombs)
        "score":
            var main := get_tree().get_first_node_in_group("game")
            if main != null and main.has_method("add_score"):
                main.call("add_score", 500)
        "coins":
            var game := get_tree().get_first_node_in_group("game")
            if game != null and game.has_method("add_coins"):
                game.call("add_coins", 25)


func heal_full() -> void:
    hp = mini(hp + 1, max_hp)
    hp_changed.emit(hp, max_hp)


func apply_meta(m: Dictionary) -> void:
    power = mini(1 + int(m.get("power", 0)), 5)
    rate_level = int(m.get("rate", 0))
    fire_interval = 0.14 - 0.012 * float(rate_level)
    max_hp = 5 + int(m.get("hull", 0))
    hp = mini(3 + int(m.get("hull", 0)), max_hp)
    speed_level = int(m.get("engine", 0))
    speed = 340.0 + 28.0 * float(speed_level)
    shields = clampi(int(m.get("shield", 0)), 0, 3)
    bombs = mini(3 + int(m.get("bomb", 0)), 5)
    _update_shield_ring()


func _update_shield_ring() -> void:
    if _shield_ring != null:
        _shield_ring.visible = shields > 0


func _on_area_entered(area: Area2D) -> void:
    if not alive:
        return
    if area.is_in_group("enemies") or area.is_in_group("bosses"):
        # Ram: damage the enemy too.
        if area.has_method("take_damage"):
            area.take_damage(3, position)
        take_damage(1)

