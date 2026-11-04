extends Area2D
## Drifting pickup: power / shield / heal / bomb / score.

var kind: String = "power"
var velocity: Vector2 = Vector2(0, 90)
var life: float = 9.0
var _t: float = 0.0
var _base_x: float = 0.0
var _label: Label
var _ring: Polygon2D

const COLORS := {
	"power": Color(0.35, 0.9, 1.0),
	"shield": Color(0.4, 1.0, 0.6),
	"heal": Color(1.0, 0.45, 0.6),
	"bomb": Color(1.0, 0.8, 0.3),
	"score": Color(0.8, 0.6, 1.0),
	"coins": Color(1.0, 0.85, 0.3),
}
const LETTERS := {
	"power": "P",
	"shield": "S",
	"heal": "+",
	"bomb": "B",
	"score": "*",
	"coins": "C",
}


func setup(p_kind: String, p_pos: Vector2) -> void:
	kind = p_kind
	position = p_pos
	_base_x = p_pos.x


func _ready() -> void:
	add_to_group("powerups")
	collision_layer = 16
	collision_mask = 1
	monitoring = true
	monitorable = true
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	add_child(shape)

	var col: Color = COLORS.get(kind, Color.WHITE)
	_ring = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in range(8):
		var a := TAU * float(i) / 8.0 + PI / 8.0
		pts.append(Vector2(cos(a), sin(a)) * 15.0)
	_ring.polygon = pts
	_ring.color = Color(col.r, col.g, col.b, 0.25)
	add_child(_ring)

	var core := Polygon2D.new()
	var cpts := PackedVector2Array()
	for i in range(8):
		var a2 := TAU * float(i) / 8.0 + PI / 8.0
		cpts.append(Vector2(cos(a2), sin(a2)) * 10.0)
	core.polygon = cpts
	core.color = col
	add_child(core)

	_label = Label.new()
	_label.text = LETTERS.get(kind, "?")
	_label.add_theme_font_size_override("font_size", 16)
	_label.add_theme_color_override("font_color", Color(0.02, 0.03, 0.08))
	_label.add_theme_color_override("font_outline_color", Color(1, 1, 1, 0.8))
	_label.add_theme_constant_override("outline_size", 4)
	_label.set_anchors_preset(Control.PRESET_CENTER)
	_label.position = Vector2(-8, -13)
	_label.z_index = 5
	add_child(_label)

	area_entered.connect(_on_area_entered)


func _process(delta: float) -> void:
	_t += delta
	life -= delta
	position += velocity * delta
	position.x = _base_x + sin(_t * 2.2) * 22.0
	if _ring != null:
		_ring.rotation += delta * 1.5
	# Magnet toward player when close.
	var player := get_tree().get_first_node_in_group("player")
	if player is Node2D:
		var d: Vector2 = (player as Node2D).global_position - global_position
		if d.length() < 130.0:
			position += d.normalized() * 260.0 * delta
	# Blink when expiring.
	if life < 2.0:
		visible = int(_t * 10.0) % 2 == 0
	if life <= 0.0:
		queue_free()
	var view := get_viewport_rect().size
	if position.y > view.y + 40.0:
		queue_free()


func _on_area_entered(area: Area2D) -> void:
	if area.is_in_group("player") and area.has_method("apply_powerup"):
		area.apply_powerup(kind)
		var audio := get_tree().get_first_node_in_group("audio")
		if audio != null and audio.has_method("play_powerup"):
			audio.call("play_powerup")
		queue_free()
