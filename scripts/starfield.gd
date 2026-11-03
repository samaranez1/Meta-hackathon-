extends Node2D
## Parallax starfield + tinted nebula blobs. Tint changes per level.

var level_tint: Color = Color(0.25, 0.4, 1.0)
var speed_mult: float = 1.0

var _stars: Array = [] # each: {pos, speed, size, bright}
var _blobs: Array = [] # each: {pos, radius, hue_shift, drift}
var _size: Vector2 = Vector2(480, 854)

const TINTS := [
    Color(0.25, 0.45, 1.0), # L1 blue
    Color(1.0, 0.35, 0.35), # L2 crimson
    Color(0.45, 1.0, 0.6), # L3 green
    Color(0.7, 0.4, 1.0), # L4 violet
    Color(1.0, 0.7, 0.3), # L5 gold
]


func _ready() -> void:
    z_index = -100
    _size = get_viewport_rect().size
    for i in range(140):
        _stars.append({
            "pos": Vector2(randf() * _size.x, randf() * _size.y),
            "speed": randf_range(30.0, 260.0),
            "size": randf_range(1.0, 3.2),
            "bright": randf_range(0.35, 1.0),
        })
    for i in range(7):
        _blobs.append({
            "pos": Vector2(randf() * _size.x, randf() * _size.y),
            "radius": randf_range(90.0, 220.0),
            "hue": randf(),
            "drift": randf_range(6.0, 20.0),
        })


func set_level(level: int) -> void:
    var idx := clampi(level - 1, 0, TINTS.size() - 1)
    level_tint = TINTS[idx]


func _process(delta: float) -> void:
    _size = get_viewport_rect().size
    for s in _stars:
        var d: Dictionary = s
        var p: Vector2 = d["pos"]
        p.y += float(d["speed"]) * speed_mult * delta
        if p.y > _size.y + 4.0:
            p.y = -4.0
            p.x = randf() * _size.x
        d["pos"] = p
    for b in _blobs:
        var e: Dictionary = b
        var q: Vector2 = e["pos"]
        q.y += float(e["drift"]) * delta
        if q.y - float(e["radius"]) > _size.y:
            q.y = -float(e["radius"])
            q.x = randf() * _size.x
        e["pos"] = q
    queue_redraw()


func _draw() -> void:
    # Deep space background.
    draw_rect(Rect2(Vector2.ZERO, _size), Color(0.015, 0.02, 0.06))
    # Nebula blobs (layered translucent circles).
    for b in _blobs:
        var e: Dictionary = b
        var q: Vector2 = e["pos"]
        var r: float = e["radius"]
        var c := level_tint
        for k in range(3):
            var rr := r * (1.0 - float(k) * 0.25)
            var cc := Color(c.r, c.g, c.b, 0.05)
            draw_circle(q, rr, cc)
    # Stars.
    for s in _stars:
        var d: Dictionary = s
        var p: Vector2 = d["pos"]
        var br: float = d["bright"]
        var sz: float = d["size"]
        var tw := 0.75 + 0.25 * sin(Time.get_ticks_msec() * 0.003 + p.x)
        draw_circle(p, sz, Color(br, br, minf(1.0, br + 0.15), br * tw))
        if sz > 2.6:
            draw_line(p + Vector2(-sz * 2.2, 0), p + Vector2(sz * 2.2, 0), Color(1, 1, 1, 0.25 * br), 1.0)
