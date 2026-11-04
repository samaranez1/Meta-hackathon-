extends Area2D
## Five stylish multi-pattern bosses, all drawn in code (no assets needed).
## 1 VEX WARDEN, 2 NEBULA TWINS, 3 CHROMA HYDRA, 4 VOID REAPER, 5 STAR EATER PRIME.

signal killed(boss: Area2D)
signal hp_changed(hp: int, max_hp: int)

const BulletScript := preload("res://scripts/bullet.gd")
const ExplosionScript := preload("res://scripts/explosion.gd")
const PowerupScript := preload("res://scripts/powerup.gd")
const EnemyScript := preload("res://scripts/enemy.gd")

var boss_id: int = 1
var boss_name: String = "BOSS"
var max_hp: int = 500
var hp: int = 500
var radius: float = 60.0
var score_value: int = 5000
var coins: int = 100
var phase: int = 1

var world: Node2D
var audio: Node

var _t: float = 0.0
var _fire_cd: float = 2.0
var _pattern_cd: float = 3.0
var _summon_cd: float = 6.0
var _pattern_idx: int = 0
var _entering: bool = true
var _flash: float = 0.0
var _dash: Vector2 = Vector2.ZERO
var _dash_time: float = 0.0
var _cloak: float = 0.0

var _root: Node2D
var _spinners: Array[Node2D] = []
var _cores: Array[Polygon2D] = []
var _rings: Array[Line2D] = []

const DEFS := {
    1: {"name": "VEX WARDEN", "hp": 500, "score": 5000, "coins": 100, "radius": 58.0},
    2: {"name": "NEBULA TWINS", "hp": 750, "score": 8000, "coins": 150, "radius": 62.0},
    3: {"name": "CHROMA HYDRA", "hp": 1050, "score": 12000, "coins": 200, "radius": 66.0},
    4: {"name": "VOID REAPER", "hp": 1350, "score": 16000, "coins": 260, "radius": 64.0},
    5: {"name": "STAR EATER PRIME", "hp": 1900, "score": 25000, "coins": 350, "radius": 78.0},
}


func setup(p_id: int, p_world: Node2D, p_audio: Node) -> void:
    boss_id = clampi(p_id, 1, 5)
    world = p_world
    audio = p_audio
    var d: Dictionary = DEFS[boss_id]
    boss_name = String(d["name"])
    max_hp = int(d["hp"])
    hp = max_hp
    score_value = int(d["score"])
    coins = int(d.get("coins", 100))
    radius = float(d["radius"])
    var view := Vector2(480, 854)
    position = Vector2(view.x * 0.5, -120.0)


func _ready() -> void:
    add_to_group("bosses")
    collision_layer = 4
    collision_mask = 3
    monitoring = true
    monitorable = true
    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius * 0.8
    shape.shape = circle
    add_child(shape)
    _root = Node2D.new()
    add_child(_root)
    match boss_id:
        1:
            _build_warden()
        2:
            _build_twins()
        3:
            _build_hydra()
        4:
            _build_reaper()
        5:
            _build_eater()
    hp_changed.emit(hp, max_hp)


# ---------------------------------------------------------------- visuals ---

func _poly(parent: Node, pts: PackedVector2Array, col: Color) -> Polygon2D:
    var p := Polygon2D.new()
    p.polygon = pts
    p.color = col
    parent.add_child(p)
    return p


func _ring(parent: Node, r: float, col: Color, w: float = 3.0) -> Line2D:
    var l := Line2D.new()
    l.width = w
    l.default_color = col
    var pts := PackedVector2Array()
    for i in range(49):
        var a := TAU * float(i) / 48.0
        pts.append(Vector2(cos(a), sin(a)) * r)
    l.points = pts
    parent.add_child(l)
    return l


func _core(parent: Node, r: float, col: Color) -> Polygon2D:
    var cpts := PackedVector2Array()
    for i in range(8):
        var a := TAU * float(i) / 8.0
        cpts.append(Vector2(cos(a), sin(a)) * r)
    var c := _poly(parent, cpts, col)
    _cores.append(c)
    return c


func _build_warden() -> void:
    # Heavy crimson cruiser with side pods.
    var r := radius
    _poly(_root, PackedVector2Array([Vector2(-r * 1.5, r * 0.4), Vector2(-r * 0.5, -r * 0.6), Vector2(r * 0.5, -r * 0.6), Vector2(r * 1.5, r * 0.4), Vector2(r * 0.8, r * 0.9), Vector2(-r * 0.8, r * 0.9)]), Color(0.22, 0.08, 0.12))
    _poly(_root, PackedVector2Array([Vector2(-r * 1.1, r * 0.35), Vector2(0, -r * 0.45), Vector2(r * 1.1, r * 0.35), Vector2(0, r * 0.65)]), Color(0.55, 0.12, 0.18))
    _poly(_root, PackedVector2Array([Vector2(-r * 0.25, -r * 0.5), Vector2(r * 0.25, -r * 0.5), Vector2(r * 0.15, r * 0.6), Vector2(-r * 0.15, r * 0.6)]), Color(1.0, 0.35, 0.4))
    _core(_root, 14.0, Color(1.0, 0.3, 0.35))
    # Pods.
    for sx in [-1.0, 1.0]:
        var pod := Node2D.new()
        pod.position = Vector2(sx * r * 1.15, r * 0.3)
        _root.add_child(pod)
        _poly(pod, PackedVector2Array([Vector2(-16, -22), Vector2(16, -22), Vector2(20, 22), Vector2(-20, 22)]), Color(0.3, 0.1, 0.14))
        _core(pod, 8.0, Color(1.0, 0.5, 0.3))
    _rings.append(_ring(_root, r * 1.15, Color(1.0, 0.3, 0.4, 0.5), 2.5))


func _build_twins() -> void:
    # Two orbiting violet cores around a central eye.
    _poly(_root, PackedVector2Array([Vector2(0, 46), Vector2(40, 10), Vector2(26, -34), Vector2(-26, -34), Vector2(-40, 10)]), Color(0.14, 0.1, 0.26))
    _core(_root, 16.0, Color(0.75, 0.45, 1.0))
    _rings.append(_ring(_root, 74.0, Color(0.7, 0.4, 1.0, 0.6), 2.5))
    var orb := Node2D.new()
    _root.add_child(orb)
    _spinners.append(orb)
    for i in range(2):
        var twin := Node2D.new()
        twin.position = Vector2(cos(PI * float(i)), sin(PI * float(i))) * 74.0
        orb.add_child(twin)
        _poly(twin, PackedVector2Array([Vector2(0, 26), Vector2(20, 6), Vector2(12, -20), Vector2(-12, -20), Vector2(-20, 6)]), Color(0.25, 0.12, 0.4))
        _core(twin, 10.0, Color(0.85, 0.55, 1.0))


func _build_hydra() -> void:
    # Triple-headed emerald hydra: center + two neck heads.
    var r := radius
    _poly(_root, PackedVector2Array([Vector2(-r * 1.2, r * 0.8), Vector2(-r * 0.6, -r * 0.4), Vector2(r * 0.6, -r * 0.4), Vector2(r * 1.2, r * 0.8)]), Color(0.06, 0.22, 0.16))
    for sx in [-1.0, 0.0, 1.0]:
        var neck := Node2D.new()
        neck.position = Vector2(sx * r * 0.62, r * 0.35)
        _root.add_child(neck)
        _poly(neck, PackedVector2Array([Vector2(-10, -34), Vector2(10, -34), Vector2(16, 18), Vector2(-16, 18)]), Color(0.08, 0.32, 0.22))
        _poly(neck, PackedVector2Array([Vector2(0, 34), Vector2(18, 4), Vector2(10, -26), Vector2(-10, -26), Vector2(-18, 4)]), Color(0.1, 0.45, 0.3))
        _core(neck, 9.0, Color(0.4, 1.0, 0.6))
    _core(_root, 13.0, Color(0.5, 1.0, 0.7))
    _rings.append(_ring(_root, r * 1.1, Color(0.35, 1.0, 0.6, 0.45), 2.5))


func _build_reaper() -> void:
    # Sleek cloaking assassin with scythe wings + rotating blades.
    var r := radius
    _poly(_root, PackedVector2Array([Vector2(0, r), Vector2(r * 0.4, 0), Vector2(r * 0.25, -r * 0.8), Vector2(-r * 0.25, -r * 0.8), Vector2(-r * 0.4, 0)]), Color(0.08, 0.08, 0.14))
    for sx in [-1.0, 1.0]:
        _poly(_root, PackedVector2Array([Vector2(sx * r * 0.3, -r * 0.2), Vector2(sx * r * 1.5, -r * 0.9), Vector2(sx * r * 1.3, r * 0.5), Vector2(sx * r * 0.4, r * 0.6)]), Color(0.16, 0.16, 0.26))
        _poly(_root, PackedVector2Array([Vector2(sx * r * 0.45, 0), Vector2(sx * r * 1.35, -r * 0.55), Vector2(sx * r * 1.2, r * 0.3)]), Color(0.5, 0.9, 1.0, 0.85))
    _core(_root, 12.0, Color(0.55, 0.95, 1.0))
    var blades := Node2D.new()
    _root.add_child(blades)
    _spinners.append(blades)
    for i in range(3):
        var b := Node2D.new()
        b.rotation = TAU * float(i) / 3.0
        blades.add_child(b)
        _poly(b, PackedVector2Array([Vector2(26, -4), Vector2(66, -4), Vector2(66, 4), Vector2(26, 4)]), Color(0.5, 0.9, 1.0, 0.7))
    _rings.append(_ring(_root, 84.0, Color(0.5, 0.9, 1.0, 0.4), 2.0))


func _build_eater() -> void:
    # Final boss: massive golden crowned devourer with ring + orbiting orbs.
    var r := radius
    _poly(_root, PackedVector2Array([Vector2(-r * 1.3, r * 0.5), Vector2(-r * 0.7, -r * 0.7), Vector2(0, -r * 1.0), Vector2(r * 0.7, -r * 0.7), Vector2(r * 1.3, r * 0.5), Vector2(r * 0.6, r * 0.9), Vector2(-r * 0.6, r * 0.9)]), Color(0.25, 0.16, 0.08))
    _poly(_root, PackedVector2Array([Vector2(-r * 0.9, r * 0.4), Vector2(0, -r * 0.7), Vector2(r * 0.9, r * 0.4), Vector2(0, r * 0.7)]), Color(0.6, 0.38, 0.12))
    # Crown spikes.
    for i in range(5):
        var x := lerpf(-r * 0.6, r * 0.6, float(i) / 4.0)
        _poly(_root, PackedVector2Array([Vector2(x - 9, -r * 0.55), Vector2(x, -r * 1.05 - (10.0 if i == 2 else 0.0)), Vector2(x + 9, -r * 0.55)]), Color(1.0, 0.75, 0.3))
    _core(_root, 20.0, Color(1.0, 0.6, 0.2))
    _rings.append(_ring(_root, r * 1.05, Color(1.0, 0.7, 0.3, 0.55), 3.0))
    var orbs := Node2D.new()
    _root.add_child(orbs)
    _spinners.append(orbs)
    for i in range(4):
        var o := Node2D.new()
        o.position = Vector2(cos(TAU * float(i) / 4.0), sin(TAU * float(i) / 4.0)) * r * 1.05
        orbs.add_child(o)
        _core(o, 9.0, Color(1.0, 0.8, 0.35))


# ---------------------------------------------------------------- update ---

func _process(delta: float) -> void:
    _t += delta
    var view := get_viewport_rect().size
    var target_y := 168.0
    if _entering:
        position.y = lerpf(position.y, target_y, minf(1.0, delta * 1.6))
        position.x = lerpf(position.x, view.x * 0.5, minf(1.0, delta * 2.0))
        if absf(position.y - target_y) < 6.0:
            _entering = false
    else:
        _move(delta, view)

    # Animate spinners + pulsing cores.
    var spin_speed := 1.2
    if boss_id == 4:
        spin_speed = 3.2
    elif boss_id == 5:
        spin_speed = 0.9
    for s in _spinners:
        if is_instance_valid(s):
            s.rotation += spin_speed * delta
    for c in _cores:
        if is_instance_valid(c):
            var sc := 1.0 + sin(_t * 5.0) * 0.15
            c.scale = Vector2(sc, sc)

    if _flash > 0.0:
        _flash -= delta
        var f := 1.0 + _flash * 5.0
        modulate = Color(f, f, f, _cloak_alpha())
    else:
        modulate = Color(1, 1, 1, _cloak_alpha())

    # Phase thresholds.
    var frac := float(hp) / float(maxi(1, max_hp))
    var new_phase := 1
    if frac < 0.33:
        new_phase = 3
    elif frac < 0.66:
        new_phase = 2
    if new_phase != phase:
        phase = new_phase
        _on_phase_change()

    if _entering:
        return
    _fire_cd -= delta
    _pattern_cd -= delta
    _summon_cd -= delta
    if _fire_cd <= 0.0:
        _fire_cd = _base_interval()
        _fire_main()
    if _pattern_cd <= 0.0:
        _pattern_cd = _pattern_interval()
        _pattern_idx += 1
        _fire_pattern()
    if _summon_cd <= 0.0:
        _summon_cd = _summon_interval()
        _summon()


func _cloak_alpha() -> float:
    if boss_id == 4 and _cloak > 0.0:
        return 0.35
    return 1.0


func _base_interval() -> float:
    match boss_id:
        1:
            return 1.1 if phase < 3 else 0.8
        2:
            return 0.9
        3:
            return 1.0 if phase < 3 else 0.75
        4:
            return 0.85
        5:
            return [0.0, 0.95, 0.7, 0.55][phase]
    return 1.0


func _pattern_interval() -> float:
    return 4.2 if phase == 1 else (3.4 if phase == 2 else 2.7)


func _summon_interval() -> float:
    match boss_id:
        1:
            return 9.0
        5:
            return 8.0 if phase >= 2 else 12.0
        _:
            return 14.0
    return 14.0


func _move(delta: float, view: Vector2) -> void:
    match boss_id:
        1:
            position.x = view.x * 0.5 + sin(_t * 0.8) * 110.0
            position.y = 168.0 + sin(_t * 1.7) * 12.0
        2:
            position.x = view.x * 0.5 + sin(_t * 1.1) * 130.0
            position.y = 168.0 + sin(_t * 2.3) * 22.0
        3:
            position.x = view.x * 0.5 + sin(_t * 0.6) * 90.0
            position.y = 175.0 + sin(_t * 1.3) * 16.0
        4:
            _move_reaper(delta, view)
        5:
            if phase == 3:
                position.x = view.x * 0.5 + sin(_t * 1.6) * 140.0
                position.y = 175.0 + sin(_t * 3.0) * 26.0
            else:
                position.x = view.x * 0.5 + sin(_t * 0.7) * 100.0
                position.y = 168.0 + sin(_t * 1.4) * 14.0


func _move_reaper(delta: float, view: Vector2) -> void:
    # Cloak + dash assassin movement.
    if _cloak > 0.0:
        _cloak -= delta
    if _dash_time > 0.0:
        _dash_time -= delta
        position += _dash * delta
        position.x = clampf(position.x, 70.0, view.x - 70.0)
        position.y = clampf(position.y, 90.0, view.y * 0.55)
        if _dash_time <= 0.0:
            _cloak = 0.0
    else:
        position.x = view.x * 0.5 + sin(_t * 1.2) * 140.0
        position.y = 168.0 + sin(_t * 2.0) * 20.0
        # Start a dash every ~5s aimed near the player.
        if fmod(_t, 5.0) < delta:
            var p := _player_pos()
            _dash = (Vector2(p.x, 260.0) - position).normalized() * 520.0
            _dash_time = 0.55
            _cloak = 1.2
            if audio != null and audio.has_method("play_dash"):
                audio.call("play_dash")


func _on_phase_change() -> void:
    if world != null:
        ExplosionScript.spawn(world, position, radius * 2.0, Color(1, 1, 1), false)
    if audio != null:
        if phase >= 3 and audio.has_method("play_boss_taunt"):
            audio.call("play_boss_taunt", boss_id)
        elif audio.has_method("play_boss_warn"):
            audio.call("play_boss_warn")
    var main := get_tree().get_first_node_in_group("game")
    if main != null and main.has_method("announce"):
        if boss_id == 5:
            main.call("announce", "STAR EATER - PHASE %d" % phase)
        else:
            main.call("announce", "%s ENRAGED" % boss_name)


# ---------------------------------------------------------------- attacks ---

func _player_pos() -> Vector2:
    var player := get_tree().get_first_node_in_group("player") as Node2D
    if player != null:
        return player.global_position
    return Vector2(get_viewport_rect().size.x * 0.5, get_viewport_rect().size.y - 100.0)


func _spawn(pos: Vector2, vel: Vector2, style: String) -> void:
    if world == null:
        return
    var b: Area2D = BulletScript.new()
    b.call("setup", pos, vel, false, 1, style)
    world.add_child(b)


func _fire_main() -> void:
    var from := position + Vector2(0, radius * 0.7)
    var target := _player_pos()
    var dir: Vector2 = (target - from).normalized()
    match boss_id:
        1:
            var n := 3 if phase == 1 else 5
            for i in range(n):
                var a := lerpf(-0.45, 0.45, float(i) / float(maxi(1, n - 1)))
                _spawn(from, dir.rotated(a) * 250.0, "orb")
        2:
            # Twin spiral from the two orbiting cores.
            for k in range(2):
                var ang := _t * 2.4 + PI * float(k)
                var src := position + Vector2(cos(ang), sin(ang)) * 74.0
                var d2: Vector2 = (target - src).normalized()
                _spawn(src, d2.rotated(0.15) * 265.0, "shard")
                _spawn(src, d2.rotated(-0.15) * 265.0, "shard")
        3:
            # Three heads fire aimed triples.
            for sx in [-1.0, 0.0, 1.0]:
                var head := position + Vector2(sx * radius * 0.62, radius * 0.6)
                var dh: Vector2 = (target - head).normalized()
                for a in [-0.18, 0.0, 0.18]:
                    _spawn(head, dh.rotated(a) * 270.0, "laser")
        4:
            if _cloak > 0.0:
                return # silent while cloaked
            for a in [-0.3, -0.15, 0.0, 0.15, 0.3]:
                _spawn(from, dir.rotated(a) * 300.0, "needle")
        5:
            var n5 := 3 + phase * 2
            for i in range(n5):
                var a5 := lerpf(-0.55, 0.55, float(i) / float(maxi(1, n5 - 1)))
                _spawn(from, dir.rotated(a5) * (260.0 + float(phase) * 20.0), "orb" if phase < 3 else "laser")
    if audio != null and audio.has_method("play_enemy_laser"):
        audio.call("play_enemy_laser")


func _fire_pattern() -> void:
    var from := position + Vector2(0, 20)
    match boss_id:
        1:
            if _pattern_idx % 2 == 0:
                # Side pods: crossing streams.
                for sx in [-1.0, 1.0]:
                    var pod := position + Vector2(sx * radius * 1.15, radius * 0.3)
                    for i in range(4):
                        _spawn(pod + Vector2(0, i * 6), Vector2(-sx * 60.0, 300.0 + float(i) * 20.0), "orb")
            else:
                # Full radial (downward biased).
                for i in range(14):
                    var a := PI * float(i) / 13.0 # 0..PI (downward half)
                    _spawn(from, Vector2(cos(a), sin(a)) * 220.0, "orb")
        2:
            # Double helix rings.
            var count := 18
            for i in range(count):
                var a2 := TAU * float(i) / float(count) + _t
                var v := Vector2(cos(a2), sin(a2))
                v.y = absf(v.y) * 0.8 + 0.35
                _spawn(from, v.normalized() * 215.0, "shard")
        3:
            if _pattern_idx % 2 == 0:
                # Laser walls with a gap at the player.
                var px := _player_pos().x
                for x in range(40, 481, 44):
                    if absf(float(x) - px) < 50.0:
                        continue
                    _spawn(Vector2(float(x), position.y + 40.0), Vector2(0, 330.0), "laser")
            else:
                for i in range(12):
                    var a3 := TAU * float(i) / 12.0 + _t * 0.7
                    _spawn(from, Vector2(cos(a3), absf(sin(a3)) + 0.3).normalized() * 240.0, "orb")
        4:
            # Blade storm: fast rotating 3-arm spiral + aimed burst.
            for arm in range(3):
                for j in range(3):
                    var a4 := _t * 3.0 + TAU * float(arm) / 3.0 + float(j) * 0.12
                    _spawn(from, Vector2(cos(a4), absf(sin(a4)) * 0.9 + 0.25).normalized() * 280.0, "needle")
            var d: Vector2 = (_player_pos() - from).normalized()
            for k in range(3):
                _spawn(from, d.rotated((float(k) - 1.0) * 0.12) * 380.0, "laser")
        5:
            if phase == 1:
                for i in range(16):
                    var a6 := PI * float(i) / 15.0
                    _spawn(from, Vector2(cos(a6), sin(a6)) * 235.0, "orb")
            elif phase == 2:
                for i in range(22):
                    var a7 := TAU * float(i) / 22.0 + _t * 1.3
                    var v7 := Vector2(cos(a7), absf(sin(a7)) * 0.85 + 0.3).normalized()
                    _spawn(from, v7 * 250.0, "laser" if i % 2 == 0 else "orb")
            else:
                # Enrage: dense flower + aimed snakes.
                for i in range(26):
                    var a8 := TAU * float(i) / 26.0 + _t * 2.0
                    var v8 := Vector2(cos(a8), absf(sin(a8)) * 0.8 + 0.35).normalized()
                    _spawn(from, v8 * 265.0, "shard")
                var d8: Vector2 = (_player_pos() - from).normalized()
                for s in [-0.25, 0.0, 0.25]:
                    _spawn(from, d8.rotated(s) * 360.0, "needle")


func _summon() -> void:
    if world == null or _entering:
        return
    var view := get_viewport_rect().size
    var types: Array[String] = []
    match boss_id:
        1:
            types = ["drone", "drone"]
        2:
            types = ["weaver"]
        3:
            types = ["kamikaze", "kamikaze"] if phase >= 2 else ["drone"]
        4:
            types = ["sniper"] if phase >= 2 else ["weaver"]
        5:
            types = ["elite", "weaver"] if phase >= 2 else ["drone", "weaver"]
    for i in range(types.size()):
        var e: Area2D = EnemyScript.new()
        var x := view.x * (0.25 + 0.5 * float(i) / float(maxi(1, types.size() - 1))) if types.size() > 1 else view.x * 0.5
        e.call("setup", types[i], Vector2(x, -30.0), world, audio, 1.0)
        world.add_child(e)
        var main := get_tree().get_first_node_in_group("game")
        if main != null and main.has_method("track_enemy"):
            main.call("track_enemy", e)


# ---------------------------------------------------------------- damage ---

func take_damage(amount: int, from_pos: Vector2 = Vector2.ZERO) -> void:
    if hp <= 0:
        return
    hp -= amount
    _flash = 0.1
    hp_changed.emit(hp, max_hp)
    if hp <= 0:
        _die()


func _die() -> void:
    hp_changed.emit(0, max_hp)
    if world != null:
        # Cinematic multi-explosion.
        for i in range(10):
            var off := Vector2(randf_range(-radius, radius), randf_range(-radius, radius))
            ExplosionScript.spawn(world, position + off, randf_range(40.0, 100.0), Color(1.0, randf_range(0.4, 0.8), 0.25), i == 0)
        # Shower of pickups.
        for k in range(4):
            var kinds := ["power", "shield", "bomb", "heal"]
            var p: Area2D = PowerupScript.new()
            p.call("setup", kinds[k % kinds.size()], position + Vector2(randf_range(-60, 60), randf_range(-20, 40)))
            # Death runs inside a physics callback: defer the add so the
            # pickup's Area2D flags apply outside the flush.
            world.call_deferred("add_child", p)
        # Clear remaining enemy bullets for a breather.
        for b in get_tree().get_nodes_in_group("enemy_bullets"):
            if is_instance_valid(b):
                b.queue_free()
    killed.emit(self)
    queue_free()
