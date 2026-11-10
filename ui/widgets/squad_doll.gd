extends Control
## Strength diagram for infantry: a platoon is a block of pips, one per trooper, the fallen dark;
## a battle armour squad is one tile per suit with its armor left and a cross through a dead one.
## Same calls as the paper doll and the vehicle doll (set_design, set_live).

const W := 130.0
const H := 120.0

var scale_f := 1.0
var design: VehicleDesign
var armor: Dictionary = {}
var internal: Dictionary = {}
var _flash: Dictionary = {}


func _init(s := 1.0) -> void:
	scale_f = s
	custom_minimum_size = Vector2(W, H) * s
	mouse_filter = Control.MOUSE_FILTER_PASS


func set_design(d: VehicleDesign, condition := {}) -> void:
	design = d
	armor = d.armor.duplicate()
	internal = VehicleConstruction.internal_points(d)
	var ca: Dictionary = condition.get("armor", {})
	for k in ca:
		armor[k] = int(ca[k])
	var ci: Dictionary = condition.get("internal", {})
	for k in ci:
		internal[k] = int(ci[k])
	custom_minimum_size = Vector2(W, H if d.is_battle_armor() else 34.0 + ceil(d.troopers / 7.0) * 15.0) * scale_f
	queue_redraw()


func set_live(a: Dictionary, i: Dictionary) -> void:
	var changed := false
	for k in internal:
		var na := float(a.get(k, 0))
		var ni := float(i.get(k, 0))
		if na < float(armor.get(k, 0)) - 0.01 or ni < float(internal.get(k, 0)) - 0.01:
			_flash[k] = 1.0
		if na != float(armor.get(k, 0)) or ni != float(internal.get(k, 0)):
			changed = true
		armor[k] = na
		internal[k] = ni
	if changed or not _flash.is_empty():
		queue_redraw()


func _process(delta: float) -> void:
	if _flash.is_empty():
		return
	for k in _flash.keys():
		_flash[k] = float(_flash[k]) - delta * 2.5
		if float(_flash[k]) <= 0.0:
			_flash.erase(k)
	queue_redraw()


func alive() -> int:
	if design == null:
		return 0
	if not design.is_battle_armor():
		return maxi(0, int(ceil(float(internal.get("PL", 0)))))
	var n := 0
	for loc in design.locs():
		if float(internal.get(loc, 0)) > 0.0:
			n += 1
	return n


func _draw() -> void:
	if design == null:
		return
	var s := scale_f
	var font := UI.font("cond_semi")
	var left := alive()
	var head := "%d / %d %s" % [left, design.troopers, "suits" if design.is_battle_armor() else "troopers"]
	draw_string(font, Vector2(0, 14 * s), head, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s), UI.frac_color(left / maxf(1.0, design.troopers)))
	if design.is_battle_armor():
		var locs := design.locs()
		var tw := minf(38.0, (W - 4.0 * (locs.size() - 1)) / locs.size()) * s
		for q in locs.size():
			var loc: String = locs[q]
			var r := Rect2(Vector2(q * (tw + 4.0 * s), 24 * s), Vector2(tw, 78 * s))
			var dead := float(internal.get(loc, 0)) <= 0.0
			var mx := maxf(1.0, float(design.armor.get(loc, 1)))
			var f := clampf(float(armor.get(loc, 0)) / mx, 0.0, 1.0)
			var col := Color(0.12, 0.13, 0.15) if dead else UI.frac_color(f).darkened(0.25)
			if _flash.has(loc):
				col = col.lerp(Color(1, 1, 1), float(_flash[loc]) * 0.7)
			# helmet, shoulders, body: enough to read as a suit
			draw_rect(Rect2(r.position + Vector2(tw * 0.3, 0), Vector2(tw * 0.4, 14 * s)), col)
			draw_rect(Rect2(r.position + Vector2(0, 16 * s), Vector2(tw, 16 * s)), col)
			draw_rect(Rect2(r.position + Vector2(tw * 0.14, 34 * s), Vector2(tw * 0.72, 22 * s)), col)
			draw_rect(Rect2(r.position + Vector2(tw * 0.14, 58 * s), Vector2(tw * 0.3, 20 * s)), col)
			draw_rect(Rect2(r.position + Vector2(tw * 0.56, 58 * s), Vector2(tw * 0.3, 20 * s)), col)
			if dead:
				draw_line(r.position + Vector2(2, 2), r.end - Vector2(2, 2), UI.BAD, 2.0 * s)
				draw_line(Vector2(r.end.x - 2, r.position.y + 2), Vector2(r.position.x + 2, r.end.y - 2), UI.BAD, 2.0 * s)
			else:
				draw_string(font, r.position + Vector2(0, 50 * s), str(int(ceil(float(armor.get(loc, 0))))), HORIZONTAL_ALIGNMENT_CENTER, tw, int(13 * s), Color(0.04, 0.05, 0.06))
		return
	var hit := _flash.has("PL")
	for q in design.troopers:
		var p := Vector2((q % 7) * 17.0 + 7.0, 30.0 + (q / 7) * 15.0) * s
		var up := q < left
		var col2 := UI.GOOD.darkened(0.15) if up else Color(0.16, 0.17, 0.19)
		if hit and not up and q < left + 6:
			col2 = col2.lerp(UI.BAD, float(_flash["PL"]))
		draw_circle(p, 5.0 * s, col2)
