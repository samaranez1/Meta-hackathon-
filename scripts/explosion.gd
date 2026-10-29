extends Node2D
## Lightweight juicy explosion: flash + shockwave ring + sparks. Auto-frees.

var max_size: float = 60.0
var color: Color = Color(1.0, 0.6, 0.2)
var life: float = 0.55
var _t: float = 0.0

var _flash: Polygon2D
var _ring: Line2D
var _sparks: CPUParticles2D


static func spawn(parent: Node, pos: Vector2, size: float = 60.0, col: Color = Color(1.0, 0.6, 0.2), big: bool = false) -> void:
    if parent == null:
        return
    var script: Script = load("res://scripts/explosion.gd")
    var e: Node2D = script.new()
    e.set("max_size", size)
    e.set("color", col)
    e.set("life", 0.9 if big else 0.55)
    e.position = pos
    parent.add_child(e)
    # Sound + shake via groups so explosion stays decoupled.
    var audio: Node = parent.get_tree().get_first_node_in_group("audio") if parent.is_inside_tree() else null
    if audio != null and audio.has_method("play_explosion"):
        audio.call("play_explosion", big)
    var main: Node = parent.get_tree().get_first_node_in_group("game") if parent.is_inside_tree() else null
    if main != null and main.has_method("add_shake"):
        main.call("add_shake", 10.0 if big else 4.0)


func _ready() -> void:
    z_index = 50
    _flash = Polygon2D.new()
    var pts := PackedVector2Array()
    for i in range(12):
        var a := TAU * float(i) / 12.0
        pts.append(Vector2(cos(a), sin(a)) * max_size * 0.5)
    _flash.polygon = pts
    _flash.color = Color(1, 1, 1, 0.95)
    add_child(_flash)

    _ring = Line2D.new()
    _ring.width = 6.0
    _ring.default_color = color
    _ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
    _ring.end_cap_mode = Line2D.LINE_CAP_ROUND
    var rpts := PackedVector2Array()
    for i in range(25):
        var a2 := TAU * float(i) / 24.0
        rpts.append(Vector2(cos(a2), sin(a2)) * 8.0)
    _ring.points = rpts
    add_child(_ring)

    _sparks = CPUParticles2D.new()
    _sparks.amount = 26
    _sparks.one_shot = true
    _sparks.explosiveness = 0.9
    _sparks.lifetime = 0.6
    _sparks.direction = Vector2(0, 0)
    _sparks.spread = 180.0
    _sparks.initial_velocity_min = max_size * 3.0
    _sparks.initial_velocity_max = max_size * 6.0
    _sparks.gravity = Vector2.ZERO
    _sparks.scale_amount_min = 2.0
    _sparks.scale_amount_max = 4.5
    _sparks.color = color
    add_child(_sparks)
    _sparks.emitting = true


func _process(delta: float) -> void:
    _t += delta
    var k := clampf(_t / life, 0.0, 1.0)
    if _flash != null:
        var fs := lerpf(0.4, 1.3, k)
        _flash.scale = Vector2(fs, fs)
        var fc := _flash.color
        fc.a = 1.0 - k
        _flash.color = fc
        _flash.color = Color(1.0, lerpf(1.0, 0.3, k), lerpf(1.0, 0.1, k), 1.0 - k)
    if _ring != null:
        var rr := lerpf(8.0, max_size * 1.4, k)
        var rpts := PackedVector2Array()
        for i in range(25):
            var a := TAU * float(i) / 24.0
            rpts.append(Vector2(cos(a), sin(a)) * rr)
        _ring.points = rpts
        var rc := color
        rc.a = 1.0 - k
        _ring.default_color = rc
        _ring.width = lerpf(6.0, 1.5, k)
    if k >= 1.0:
        queue_free()
