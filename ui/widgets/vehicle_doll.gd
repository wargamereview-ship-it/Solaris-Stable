extends Control
## Armor diagram for a combat vehicle: top-down art for its motive type (tracked, wheeled, hover,
## VTOL; assets/dolls/veh_<motion>_*.png), front up, each location tinted by doll.gdshader from what
## is left of its armor, with a structure band along its edges. A design without a turret shows
## the turret as plain hull. Fresh hits flash.

const DD := preload("res://ui/widgets/doll_draw.gd")
const W := 130.0
const H := 210.0
const LOCS := {1: ["FR", "FR"], 2: ["LS", "LS"], 3: ["RS", "RS"], 4: ["RR", "RR"], 5: ["TU", "TU"], 6: ["RO", "RO"]}

var scale_f := 1.0
var design: VehicleDesign
var armor: Dictionary = {}
var internal: Dictionary = {}
var max_armor: Dictionary = {}
var max_internal: Dictionary = {}
var show_numbers := true
var highlight := "":
	set(v):
		highlight = v
		_paint()
var _flash: Dictionary = {}
var _art: TextureRect
var _labels: Control
var _key := ""


func _init(s := 1.0) -> void:
	scale_f = s
	custom_minimum_size = Vector2(W, H) * s
	mouse_filter = Control.MOUSE_FILTER_PASS
	_labels = Control.new()
	_labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_labels.draw.connect(_draw_labels)
	add_child(_labels)
	resized.connect(_layout)


func set_design(d: VehicleDesign, condition := {}) -> void:
	design = d
	max_armor = d.armor.duplicate()
	max_internal = VehicleConstruction.internal_points(d)
	armor = max_armor.duplicate()
	internal = max_internal.duplicate()
	var ca: Dictionary = condition.get("armor", {})
	for k in ca:
		armor[k] = int(ca[k])
	var ci: Dictionary = condition.get("internal", {})
	for k in ci:
		internal[k] = int(ci[k])
	var key := "veh_" + (d.motion if d.motion in ["tracked", "wheeled", "hover", "vtol"] else "tracked")
	if key != _key:
		_key = key
		if _art != null:
			_art.queue_free()
		_art = DD.art_layer(key)
		(_art.material as ShaderMaterial).set_shader_parameter("phase", randf())
		add_child(_art)
		move_child(_art, 0)
	_layout()


func set_live(a: Dictionary, i: Dictionary) -> void:
	DD.note_hits(_flash, armor, a)
	DD.note_hits(_flash, internal, i)
	for k in a:
		armor[k] = int(a[k])
	for k in i:
		internal[k] = int(i[k])
	_paint()


func _process(_delta: float) -> void:
	if not _flash.is_empty():
		_paint()
		var now := Time.get_ticks_msec()
		for k in _flash.keys():
			if now - int(_flash[k]) > 700:
				_flash.erase(k)


func _draw() -> void:
	DD.screen(self, Rect2(Vector2.ZERO, size), scale_f, design.motion_label().to_upper() if design != null and scale_f >= 0.8 else "")


func _layout() -> void:
	queue_redraw()
	if _art == null or _art.texture == null:
		return
	var m := Vector2(10, 14) * scale_f
	var r := DD.fit(Vector2(_art.texture.get_size()), Rect2(m, size - m * 2.0))
	_art.position = r.position
	_art.size = r.size
	_labels.position = Vector2.ZERO
	_labels.size = size
	_paint()


func _paint() -> void:
	if _art == null:
		return
	DD.paint(_art, LOCS, armor, max_armor, internal, max_internal, _flash, highlight)
	_labels.queue_redraw()


func _draw_labels() -> void:
	if not show_numbers or _art == null:
		return
	var an: Dictionary = DD.db().get(_key, {}).get("top", {})
	DD.numbers(_labels, _art, an, LOCS, armor, max_armor, internal, max_internal, int(round(13 * scale_f)))
