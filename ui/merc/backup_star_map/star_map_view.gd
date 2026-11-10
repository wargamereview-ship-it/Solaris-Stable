extends Control
## The Inner Sphere at today's date: a starfield, faction territories (rendered once into a texture
## on the GPU, with lit borders), glowing systems, faction names, hiring halls, the contract world,
## the jump range, the route and the company itself. Drag to pan, wheel to zoom, click a system.

signal system_selected(i: int)

const LY_PER_PX := 2.0          # territory texture resolution
const DISC_LY := 21.0           # how far a world's influence reaches on the map
const SPACE_MIN := Vector2(-1900, -2020)
const SPACE_MAX := Vector2(1950, 1930)

var c: MercCampaign
var sm: StarMap
var center := Vector2.ZERO     # light years
var zoom := 0.9                # pixels per light year
var selected := -1
var route: Array = []
var _cols: PackedColorArray
var _cols_year := -1
var _drag := false
var _moved := 0.0
var _t := 0.0
var bg: ColorRect
var terr: Control
var fg: Control
var _vp: SubViewport
var _disc_node: Node2D
var _labels: Array = []         # [name, ly position, color] for the big factions


func setup(camp: MercCampaign) -> void:
	c = camp
	sm = camp.sm
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if c.location >= 0:
		center = sm.pos(c.location)
	zoom = 1.25
	bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bm := ShaderMaterial.new()
	bm.shader = load("res://ui/merc/starfield.gdshader")
	bg.material = bm
	add_child(bg)
	# territories: one opaque disc per owned world, drawn into an offscreen texture
	_vp = SubViewport.new()
	_vp.size = Vector2i(int((SPACE_MAX.x - SPACE_MIN.x) / LY_PER_PX), int((SPACE_MAX.y - SPACE_MIN.y) / LY_PER_PX))
	_vp.transparent_bg = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_vp.disable_3d = true
	_disc_node = Node2D.new()
	_disc_node.draw.connect(_draw_discs)
	_vp.add_child(_disc_node)
	add_child(_vp)
	terr = Control.new()
	terr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	terr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tm := ShaderMaterial.new()
	tm.shader = load("res://ui/merc/territory.gdshader")
	terr.material = tm
	terr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	terr.draw.connect(_draw_territory)
	add_child(terr)
	fg = Control.new()
	fg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fg.draw.connect(_draw_fg)
	add_child(fg)


func _process(delta: float) -> void:
	_t += delta
	(bg.material as ShaderMaterial).set_shader_parameter("offset", Vector2(center.x, -center.y) * 0.02)
	(bg.material as ShaderMaterial).set_shader_parameter("zoom", zoom)
	terr.queue_redraw()
	fg.queue_redraw()


func _colors() -> void:
	var y := c.year() * 4 + (c.month() - 1) / 3
	if y == _cols_year:
		return
	_cols_year = y
	_cols = PackedColorArray()
	_cols.resize(sm.systems.size())
	var yf := c.year_f()
	var cache := {}
	var sums := {}
	for i in sm.systems.size():
		var o := sm.owner(i, yf)
		if not cache.has(o):
			cache[o] = Color(0.35, 0.35, 0.37) if not sm.is_real_faction(o) or o == "IND" else sm.faction_color(o)
		_cols[i] = cache[o]
		if sm.is_real_faction(o) and o != "IND":
			var e: Array = sums.get(o, [Vector2.ZERO, 0])
			e[0] = (e[0] as Vector2) + sm.pos(i)
			e[1] = int(e[1]) + 1
			sums[o] = e
	_labels = []
	for o in sums:
		var n := int(sums[o][1])
		if n >= 40:
			_labels.append([sm.faction_name(o).to_upper(), (sums[o][0] as Vector2) / n, cache[o], n])
	_disc_node.queue_redraw()
	_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_discs() -> void:
	if _cols.size() != sm.systems.size():
		_colors()
	var yf := c.year_f()
	for i in sm.systems.size():
		var o := sm.owner(i, yf)
		if not sm.is_real_faction(o) or o == "IND":
			continue
		var p := (sm.pos(i) - SPACE_MIN) / LY_PER_PX
		p.y = _vp.size.y - p.y
		_disc_node.draw_circle(p, DISC_LY / LY_PER_PX, _cols[i])


func to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + Vector2(p.x - center.x, -(p.y - center.y)) * zoom


func to_ly(s: Vector2) -> Vector2:
	var d := (s - size / 2.0) / zoom
	return Vector2(center.x + d.x, center.y - d.y)


func _draw_territory() -> void:
	_colors()
	var tl := to_screen(Vector2(SPACE_MIN.x, SPACE_MAX.y))
	var br := to_screen(Vector2(SPACE_MAX.x, SPACE_MIN.y))
	(terr.material as ShaderMaterial).set_shader_parameter("texel", Vector2(1.0 / _vp.size.x, 1.0 / _vp.size.y))
	terr.draw_texture_rect(_vp.get_texture(), Rect2(tl, br - tl), false)


func _draw_fg() -> void:
	_colors()
	var font := UI.font("medium")
	var yf := c.year_f()
	var rect := Rect2(Vector2(-30, -30), size + Vector2(60, 60))
	# faction names over their space when zoomed out
	if zoom < 2.6:
		var lf := UI.spaced("cond", 4)
		for l in _labels:
			var lp := to_screen(l[1])
			if not rect.has_point(lp):
				continue
			var fs := int(clampf(8.0 + sqrt(float(l[3])) * 0.75 * zoom, 13.0, 34.0))
			var tw := lf.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var lc: Color = l[2]
			var fade := clampf((2.6 - zoom) / 0.8, 0.0, 1.0)
			fg.draw_string(lf, lp - Vector2(tw / 2.0, -2), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.6 * fade))
			fg.draw_string(lf, lp - Vector2(tw / 2.0, 0), l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(lc.lightened(0.25).r, lc.lightened(0.25).g, lc.lightened(0.25).b, 0.55 * fade))
	# jump range around the company
	if c.location >= 0 and not c.in_transit():
		var jp := to_screen(sm.pos(c.location))
		fg.draw_circle(jp, 30.0 * zoom, Color(0.4, 0.7, 1.0, 0.05))
		fg.draw_arc(jp, 30.0 * zoom, 0, TAU, 72, Color(0.5, 0.75, 1.0, 0.45), 1.5, true)
	# systems: a soft halo and a bright core, bigger for populous worlds
	var r := clampf(zoom * 1.05, 1.1, 4.2)
	for i in sm.systems.size():
		var sp := to_screen(sm.pos(i))
		if not rect.has_point(sp):
			continue
		var col := _cols[i]
		var pop := sm.population(i, yf)
		var big := 1.0 + clampf(log(maxf(1.0, pop / 1.0e8)) * 0.18, 0.0, 0.8)
		fg.draw_circle(sp, r * 2.4 * big, Color(col.r, col.g, col.b, 0.12))
		fg.draw_circle(sp, r * big, col.lightened(0.35))
	# route: animated dashes
	if route.size() > 1:
		_dash_route(route, Color(1.0, 0.85, 0.4, 0.9))
	if c.in_transit():
		_dash_route(c.travel["route"], Color(0.5, 0.9, 1.0, 0.9))
	# hiring halls, the contract world, labels
	var labels := 0
	var icons := UI.font("icons")
	for i in sm.systems.size():
		var sp2 := to_screen(sm.pos(i))
		if not rect.has_point(sp2):
			continue
		var hall := sm.hall(i, yf)
		if hall != "":
			var gs := 16 if hall in ["GREAT", "STANDARD"] else 12
			fg.draw_circle(sp2, 9.0, Color(1.0, 0.75, 0.25, 0.18))
			fg.draw_string(icons, sp2 + Vector2(-gs * 0.32, gs * 0.36), UI.ic("star"), HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(1.0, 0.8, 0.32))
		var show := zoom >= 4.0 or (zoom >= 2.2 and sm.population(i, yf) > 3000000000) or hall != "" or i == selected or i == c.location or (not c.contract.is_empty() and i == int(c.contract["system"]))
		if show and labels < 260:
			labels += 1
			var fs2 := 12 if zoom < 4.0 else 14
			var nm := sm.name_of(i)
			fg.draw_string(font, sp2 + Vector2(10, 6), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0, 0, 0, 0.75))
			fg.draw_string(font, sp2 + Vector2(9, 5), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0.92, 0.93, 0.95, 0.92) if hall == "" else Color(1.0, 0.85, 0.5))
	if not c.contract.is_empty():
		var cp := to_screen(sm.pos(int(c.contract["system"])))
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		fg.draw_arc(cp, 12.0 + pulse * 4.0, 0, TAU, 32, Color(UI.BAD.r, UI.BAD.g, UI.BAD.b, 0.9 - pulse * 0.5), 2.0, true)
		for q in 4:
			var a := q * PI / 2.0
			fg.draw_line(cp + Vector2.from_angle(a) * 8.0, cp + Vector2.from_angle(a) * 18.0, UI.BAD, 2.0)
		var lbl := "CONTRACT"
		fg.draw_string(UI.spaced("cond_semi", 2), cp + Vector2(20, -12), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.BAD)
	if selected >= 0:
		var sp3 := to_screen(sm.pos(selected))
		fg.draw_arc(sp3, 10.0, _t * 1.5, _t * 1.5 + PI * 1.4, 24, Color.WHITE, 2.0, true)
	# the company
	var here := sm.pos(c.location) if c.location >= 0 else Vector2.ZERO
	if c.in_transit():
		var tp := c.travel_position()
		here = sm.pos(int(tp["a"])).lerp(sm.pos(int(tp["b"])), float(tp["f"]))
	var hp := to_screen(here)
	var pl := fmod(_t * 0.8, 1.0)
	fg.draw_arc(hp, 8.0 + pl * 22.0, 0, TAU, 32, Color(c.color.r, c.color.g, c.color.b, 0.8 * (1.0 - pl)), 2.0, true)
	fg.draw_circle(hp, 7.0, c.color)
	fg.draw_arc(hp, 7.5, 0, TAU, 24, Color.WHITE, 2.0, true)
	fg.draw_string(icons, hp + Vector2(-6, -14), UI.ic("rocket"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	var legend := "%s  Drag to pan, wheel to zoom, click a system      %s  Hiring hall      %s  One jump (30 ly)" % [UI.ic("arrow_right"), UI.ic("star"), UI.ic("dot")]
	fg.draw_string(font, Vector2(12, size.y - 12), legend, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.65, 0.7, 0.76))


func _dash_route(r: Array, col: Color) -> void:
	var off := fmod(_t * 18.0, 14.0)
	for k in range(1, r.size()):
		var a := to_screen(sm.pos(int(r[k - 1])))
		var b := to_screen(sm.pos(int(r[k])))
		var d := a.distance_to(b)
		var dir := (b - a) / maxf(d, 0.001)
		var s := -off
		while s < d:
			var s0 := maxf(0.0, s)
			var s1 := minf(d, s + 8.0)
			if s1 > s0:
				fg.draw_line(a + dir * s0, a + dir * s1, col, 2.5, true)
			s += 14.0
		fg.draw_circle(b, 3.0, col)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			var before := to_ly(mb.position)
			zoom = clampf(zoom * 1.2, 0.25, 14.0)
			center += before - to_ly(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			var before2 := to_ly(mb.position)
			zoom = clampf(zoom / 1.2, 0.25, 14.0)
			center += before2 - to_ly(mb.position)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag = true
				_moved = 0.0
			else:
				_drag = false
				if _moved < 6.0:
					_pick(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _drag:
		var mm := event as InputEventMouseMotion
		_moved += mm.relative.length()
		center += Vector2(-mm.relative.x, mm.relative.y) / zoom
		accept_event()


func _pick(p: Vector2) -> void:
	var best := -1
	var bd := 12.0
	for i in sm.systems.size():
		var d := to_screen(sm.pos(i)).distance_to(p)
		if d < bd:
			bd = d
			best = i
	if best >= 0:
		select(best)


func select(i: int) -> void:
	selected = i
	route = sm.route(c.location, i) if c.location >= 0 else []
	system_selected.emit(i)
