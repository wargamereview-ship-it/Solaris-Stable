extends Control
## Armor diagram for a 'Mech on the targeting screen: the 'Mech traced as line work (left side on
## the left, as on a record sheet) with every location glowing in its armor status color and a thin
## inner trace for its internal structure, plus a small rear-torso readout for the rear armor.
## Art: assets/dolls/mech_front_*.png and mech_rear_*.png (tools/dolls/build_doll_maps.py).

const DD := preload("res://ui/widgets/doll_draw.gd")
const W := 262.0
const H := 236.0
const FRONT := {1: ["HD", "HD"], 2: ["CT", "CT"], 3: ["LT", "LT"], 4: ["RT", "RT"], 5: ["LA", "LA"], 6: ["RA", "RA"],
	7: ["LL", "LL"], 8: ["RL", "RL"]}
const REAR := {9: ["CTR", "CT"], 10: ["LTR", "LT"], 11: ["RTR", "RT"]}

var armor: Dictionary = {}
var internal: Dictionary = {}
var max_armor: Dictionary = {}
var max_internal: Dictionary = {}
var scale_f := 1.0
var show_numbers := true
var rear := true
var highlight := "":
	set(v):
		highlight = v
		_paint()
var _flash: Dictionary = {}
var _front: TextureRect
var _rear: TextureRect
var _labels: Control


func _init(s := 1.0, with_rear := true) -> void:
	scale_f = s
	rear = with_rear and s > 0.55
	custom_minimum_size = Vector2(W if rear else 176.0, H) * s
	mouse_filter = Control.MOUSE_FILTER_PASS
	_front = DD.art_layer("mech_front")
	add_child(_front)
	if rear:
		_rear = DD.art_layer("mech_rear")
		add_child(_rear)
	for t in [_front, _rear]:
		if t != null:
			var m := t.material as ShaderMaterial
			m.set_shader_parameter("phase", randf())
	_labels = Control.new()
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.draw.connect(_draw_labels)
	add_child(_labels)
	resized.connect(_layout)


func set_design(d: MechDesign, condition := {}) -> void:
	max_armor = d.armor.duplicate()
	max_internal = Construction.internal_points(d.tons).duplicate()
	armor = max_armor.duplicate()
	internal = max_internal.duplicate()
	if not condition.is_empty():
		var ca: Dictionary = condition.get("armor", {})
		for k in ca:
			armor[k] = int(ca[k])
		var ci: Dictionary = condition.get("internal", {})
		for k in ci:
			internal[k] = int(ci[k])
	_layout()


func set_live(a: Dictionary, i: Dictionary) -> void:
	DD.note_hits(_flash, armor, a)
	DD.note_hits(_flash, internal, i)
	armor = a.duplicate()
	internal = i.duplicate()
	_paint()


func _process(_delta: float) -> void:
	if not _flash.is_empty():
		_paint()
		var now := Time.get_ticks_msec()
		for k in _flash.keys():
			if now - int(_flash[k]) > 700:
				_flash.erase(k)


## Left edge of the content when the widget is wider than it needs (kept centered).
func _ox() -> float:
	return maxf(0.0, (size.x - custom_minimum_size.x) / 2.0)


func _front_box() -> Rect2:
	var s := scale_f
	return Rect2(Vector2(_ox(), 0) + Vector2(6, 16) * s, Vector2(164.0 * s, size.y - 22.0 * s))


func _rear_box() -> Rect2:
	var s := scale_f
	return Rect2(Vector2(_ox(), 0) + Vector2(180, 30) * s, Vector2(76.0 * s, 70.0 * s))


func _layout() -> void:
	queue_redraw()
	if _front.texture == null:
		return
	var r := DD.fit(Vector2(_front.texture.get_size()), _front_box())
	_front.position = r.position
	_front.size = r.size
	if _rear != null and _rear.texture != null:
		var r2 := DD.fit(Vector2(_rear.texture.get_size()), _rear_box())
		_rear.position = Vector2(r2.position.x, _rear_box().position.y)
		_rear.size = r2.size
	_labels.position = Vector2.ZERO
	_labels.size = size
	_paint()


func _paint() -> void:
	if _front == null:
		return
	DD.paint(_front, FRONT, armor, max_armor, internal, max_internal, _flash, highlight)
	if _rear != null:
		DD.paint(_rear, REAR, armor, max_armor, internal, max_internal, _flash, highlight)
	if _labels != null:
		_labels.queue_redraw()


func _draw() -> void:
	var s := scale_f
	DD.screen(self, Rect2(Vector2.ZERO, size), s, "FRONT" if s >= 0.6 else "")
	if rear and s >= 0.6:
		var f := UI.font("mono")
		var fs := maxi(8, int(round(9 * s)))
		var g := DD.HUD_GREEN
		draw_string(f, Vector2(_rear_box().position.x + 2, _rear_box().position.y - 5 * s), "REAR", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(g.r, g.g, g.b, 0.6))
		draw_line(Vector2(_ox() + 176 * s, 12 * s), Vector2(_ox() + 176 * s, size.y - 12 * s), Color(g.r, g.g, g.b, 0.12), 1.0)


func _draw_labels() -> void:
	var s := scale_f
	if s >= 0.6:
		# which side is which (left on the left, as on a record sheet)
		var f := UI.font("mono")
		var fs := maxi(8, int(round(9 * s)))
		var c := Color(DD.HUD_GREEN.r, DD.HUD_GREEN.g, DD.HUD_GREEN.b, 0.45)
		var fb := _front_box()
		_labels.draw_string(f, Vector2(fb.position.x + 2, fb.end.y), "L", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
		_labels.draw_string(f, Vector2(fb.end.x - fs * 0.7, fb.end.y), "R", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, c)
	if not show_numbers:
		return
	var db: Dictionary = DD.db().get("mech", {})
	var fs2 := int(round(12 * s))
	DD.numbers(_labels, _front, db.get("front", {}), FRONT, armor, max_armor, internal, max_internal, fs2)
	if _rear != null:
		DD.numbers(_labels, _rear, db.get("rear", {}), REAR, armor, max_armor, internal, max_internal, maxi(9, fs2 - 1))
