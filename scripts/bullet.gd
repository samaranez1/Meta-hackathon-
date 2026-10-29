extends Area2D
## Unified bullet for player (friendly) and enemies.
## Visuals are drawn with Polygon2D + glow so no extra assets are needed.

var velocity: Vector2 = Vector2(0, -600)
var damage: int = 1
var friendly: bool = true
var life: float = 3.0
var style: String = "bolt"
var radius: float = 6.0
var spin: float = 0.0
var pulse: float = 0.0

var _body: Polygon2D
var _glow: Polygon2D

const PLAYER_COLOR := Color(0.45, 0.9, 1.0)
const PLAYER_GLOW := Color(0.2, 0.6, 1.0, 0.45)
const ENEMY_COLOR := Color(1.0, 0.35, 0.5)
const ENEMY_GLOW := Color(1.0, 0.15, 0.4, 0.45)
const LASER_COLOR := Color(0.5, 1.0, 0.85)
const ORB_COLOR := Color(1.0, 0.7, 0.25)


func setup(p_pos: Vector2, p_vel: Vector2, p_friendly: bool, p_damage: int = 1, p_style: String = "bolt") -> void:
    position = p_pos
    velocity = p_vel
    friendly = p_friendly
    damage = p_damage
    style = p_style
    if not friendly:
        if style == "orb":
            radius = 8.0
        elif style == "laser":
            radius = 7.0
        elif style == "shard":
            radius = 6.0
        else:
            radius = 6.0
    else:
        radius = 7.0 if style == "bolt_big" else 6.0


func _ready() -> void:
    add_to_group("player_bullets" if friendly else "enemy_bullets")
    collision_layer = 2 if friendly else 8
    collision_mask = 4 if friendly else 1
    monitoring = true
    monitorable = true

    var shape := CollisionShape2D.new()
    var circle := CircleShape2D.new()
    circle.radius = radius * 0.7
    shape.shape = circle
    add_child(shape)

    _glow = Polygon2D.new()
    _glow.color = PLAYER_GLOW if friendly else ENEMY_GLOW
    add_child(_glow)
    _body = Polygon2D.new()
    add_child(_body)
    _build_shape()

    area_entered.connect(_on_area_entered)


func _build_shape() -> void:
    var pts := PackedVector2Array()
    var glow_pts := PackedVector2Array()
    var col := PLAYER_COLOR if friendly else ENEMY_COLOR
    var r := radius
    match style:
        "bolt", "bolt_big":
            var len := 16.0 if style == "bolt" else 20.0
            pts = PackedVector2Array([Vector2(0, -len), Vector2(r * 0.55, 0), Vector2(0, len * 0.6), Vector2(-r * 0.55, 0)])
            col = PLAYER_COLOR
        "orb":
            for i in range(10):
                var a := TAU * float(i) / 10.0
                pts.append(Vector2(cos(a), sin(a)) * r)
            col = ORB_COLOR
        "laser":
            pts = PackedVector2Array([Vector2(0, -r * 2.4), Vector2(r * 0.5, 0), Vector2(0, r * 2.4), Vector2(-r * 0.5, 0)])
            col = LASER_COLOR if not friendly else PLAYER_COLOR
        "shard":
            pts = PackedVector2Array([Vector2(0, -r * 1.6), Vector2(r * 0.8, r), Vector2(0, r * 0.4), Vector2(-r * 0.8, r)])
            col = Color(0.85, 0.4, 1.0)
        "needle":
            pts = PackedVector2Array([Vector2(0, -r * 2.0), Vector2(r * 0.35, r * 1.2), Vector2(-r * 0.35, r * 1.2)])
            col = Color(1.0, 0.9, 0.4)
        _:
            pts = PackedVector2Array([Vector2(0, -r), Vector2(r, r), Vector2(-r, r)])
    _body.polygon = pts
    _body.color = col
    for p in pts:
        glow_pts.append(p * 1.9)
    _glow.polygon = glow_pts
    # Align to travel direction.
    if velocity.length() > 1.0:
        var ang := velocity.angle() + PI * 0.5
        _body.rotation = ang
        _glow.rotation = ang


func _process(delta: float) -> void:
    position += velocity * delta
    life -= delta
    pulse += delta * 10.0
    if _body != null:
        var s := 1.0 + sin(pulse) * 0.08
        _body.scale = Vector2(s, s)
    if spin != 0.0 and _body != null:
        _body.rotation += spin * delta
        _glow.rotation += spin * delta
    var view := get_viewport_rect().size
    if life <= 0.0 or position.y < -60.0 or position.y > view.y + 60.0 or position.x < -60.0 or position.x > view.x + 60.0:
        queue_free()


func _on_area_entered(area: Area2D) -> void:
    if friendly:
        if area.is_in_group("enemies") or area.is_in_group("bosses"):
            if area.has_method("take_damage"):
                area.take_damage(damage, position)
            queue_free()
    else:
        if area.is_in_group("player"):
            if area.has_method("take_damage"):
                area.take_damage(damage)
            queue_free()
