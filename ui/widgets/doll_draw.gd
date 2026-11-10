extends RefCounted
## Shared code for the armor dolls ('Mech and vehicle): the art layers painted by doll.gdshader,
## the colors, hit flashes and the numbers drawn over the art.

const SHADER := preload("res://ui/widgets/doll.gdshader")
static var _db: Dictionary = {}


## Label anchors and sizes of every doll texture (assets/dolls/dolls.json).
static func db() -> Dictionary:
	if _db.is_empty():
		var f := FileAccess.open("res://assets/dolls/dolls.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary:
				_db = d
	return _db


## A TextureRect showing one doll texture through the shader. name: e.g. "veh_tracked", "mech_front".
static func art_layer(name: String) -> TextureRect:
	var t := TextureRect.new()
	t.texture = load("res://assets/dolls/%s_shade.png" % name)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("id_tex", load("res://assets/dolls/%s_id.png" % name))
	# line art (the 'Mech) has its own lines lit instead of its shading traced
	var e: Dictionary = db().get(name, db().get(name.get_slice("_", 0), {}))
	m.set_shader_parameter("line_art", bool(e.get("line_art", false)))
	t.material = m
	return t


## Where a texture of tex_size fits inside box, keeping its aspect, centered.
static func fit(tex_size: Vector2, box: Rect2) -> Rect2:
	var k := minf(box.size.x / tex_size.x, box.size.y / tex_size.y)
	var sz := tex_size * k
	return Rect2(box.position + (box.size - sz) / 2.0, sz)


## Sends every location's colors and state to a doll layer. locs: id -> [armor key, structure key,
## dim]; a location the unit doesn't have (no turret, no rotor) shows as plain hull.
static func paint(t: TextureRect, locs: Dictionary, armor: Dictionary, max_armor: Dictionary, internal: Dictionary,
		max_internal: Dictionary, flash: Dictionary, hi: String) -> void:
	var ac := PackedColorArray()
	var sc := PackedColorArray()
	var st := PackedFloat32Array()
	var fl := PackedFloat32Array()
	var dm := PackedFloat32Array()
	for k in 12:
		ac.append(Color(0.5, 0.5, 0.5))
		sc.append(Color(0.5, 0.5, 0.5))
		st.append(3.0)
		fl.append(0.0)
		dm.append(0.0)
	var hi_id := -1
	for id in locs:
		var e: Array = locs[id]
		var ak: String = e[0]
		var sk: String = e[1]
		var ma := float(max_armor.get(ak, 0))
		var mi := float(max_internal.get(sk, 0))
		if ma <= 0.0 and mi <= 0.0:
			continue
		var a := float(armor.get(ak, 0))
		var i := float(internal.get(sk, 0))
		ac[id] = hud_col(a / ma) if ma > 0.0 else hud_col(i / mi)
		sc[id] = struct_hud_col(i / mi if mi > 0.0 else 1.0)
		st[id] = 2.0 if (mi > 0.0 and i <= 0.0) else (1.0 if (ma > 0.0 and a <= 0.0) else 0.0)
		fl[id] = maxf(flash_k(flash, ak), flash_k(flash, sk))
		dm[id] = float(e[2]) if e.size() > 2 else 0.0
		if ak == hi and hi != "":
			hi_id = id
	var m := t.material as ShaderMaterial
	m.set_shader_parameter("armor_col", ac)
	m.set_shader_parameter("struct_col", sc)
	m.set_shader_parameter("state", st)
	m.set_shader_parameter("flash", fl)
	m.set_shader_parameter("dim", dm)
	m.set_shader_parameter("hi", hi_id)
	m.set_shader_parameter("hi_col", Color(1.0, 1.0, 1.0))
	if t.size.y > 0.0 and t.texture != null:
		m.set_shader_parameter("tpp", float(t.texture.get_height()) / t.size.y)


## Armor numbers over the art at each location's anchor (✕ when the location is gone).
static func numbers(cv: CanvasItem, t: TextureRect, anchors: Dictionary, locs: Dictionary, armor: Dictionary,
		max_armor: Dictionary, internal: Dictionary, max_internal: Dictionary, fs: int, prefix := "") -> void:
	if t.texture == null:
		return
	var k := t.size / Vector2(t.texture.get_size())
	for id in locs:
		var an: Dictionary = anchors.get(str(id), {})
		if an.is_empty():
			continue
		var e: Array = locs[id]
		var ak: String = e[0]
		var sk: String = e[1]
		if float(max_armor.get(ak, 0)) <= 0.0 and float(max_internal.get(sk, 0)) <= 0.0:
			continue
		var p: Vector2 = t.position + Vector2(float(an["anchor"][0]), float(an["anchor"][1])) * k
		if float(max_internal.get(sk, 0)) > 0.0 and float(internal.get(sk, 0)) <= 0.0:
			readout(cv, p, "XX", fs, Color(1.0, 0.3, 0.22))
		elif float(max_armor.get(ak, 0)) > 0.0:
			var ma := float(max_armor.get(ak, 0))
			readout(cv, p, prefix + str(int(armor.get(ak, 0))), fs, hud_col(float(armor.get(ak, 0)) / ma).lightened(0.35))


const HUD_GREEN := Color(0.33, 1.0, 0.56)
const HUD_AMBER := Color(1.0, 0.82, 0.28)
const HUD_RED := Color(1.0, 0.3, 0.2)
const HUD_CYAN := Color(0.42, 0.82, 1.0)
const SCREEN_BG := Color(0.012, 0.035, 0.03, 0.94)


## Status color of a location on the targeting screen: phosphor green when whole, amber at half,
## red when nearly gone.
static func hud_col(f: float) -> Color:
	f = clampf(f, 0.0, 1.0)
	if f >= 0.6:
		return HUD_AMBER.lerp(HUD_GREEN, (f - 0.6) / 0.4)
	return HUD_RED.lerp(HUD_AMBER, f / 0.6)


## The structure trace: cool cyan while untouched, then amber to red as it is eaten into.
static func struct_hud_col(f: float) -> Color:
	if f >= 0.999:
		return HUD_CYAN
	f = clampf(f, 0.0, 1.0)
	return HUD_RED.lerp(HUD_AMBER, f)


## A number on the targeting screen: monospace, glowing, on a dark backing.
static func readout(cv: CanvasItem, center: Vector2, txt: String, fs: int, col: Color) -> void:
	var f := UI.font("mono")
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var r := Rect2(center - Vector2(w / 2.0 + 3.0, fs * 0.55), Vector2(w + 6.0, fs * 1.1))
	cv.draw_rect(r, Color(0.0, 0.04, 0.03, 0.7))
	cv.draw_rect(r, Color(col.r, col.g, col.b, 0.35), false, 1.0)
	var p := center + Vector2(-w / 2.0, fs * 0.36)
	cv.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(col.r, col.g, col.b, 0.35))
	cv.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## The targeting screen behind a doll: dark glass, a faint grid, scanlines, corner brackets and a
## caption.
static func screen(cv: CanvasItem, r: Rect2, s: float, caption := "") -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = SCREEN_BG
	sb.set_corner_radius_all(int(4 * s) + 1)
	sb.border_color = Color(HUD_GREEN.r, HUD_GREEN.g, HUD_GREEN.b, 0.16)
	sb.set_border_width_all(1)
	cv.draw_style_box(sb, r)
	var g := maxf(8.0, 12.0 * s)
	var x := r.position.x + g
	while x < r.end.x:
		cv.draw_line(Vector2(x, r.position.y + 2), Vector2(x, r.end.y - 2), Color(HUD_GREEN.r, HUD_GREEN.g, HUD_GREEN.b, 0.045), 1.0)
		x += g
	var y := r.position.y + g
	while y < r.end.y:
		cv.draw_line(Vector2(r.position.x + 2, y), Vector2(r.end.x - 2, y), Color(HUD_GREEN.r, HUD_GREEN.g, HUD_GREEN.b, 0.045), 1.0)
		y += g
	var y2 := r.position.y + 1.0
	while y2 < r.end.y:
		cv.draw_line(Vector2(r.position.x + 1, y2), Vector2(r.end.x - 1, y2), Color(0, 0, 0, 0.12), 1.0)
		y2 += 3.0
	var L := maxf(6.0, 11.0 * s)
	var bc := Color(HUD_GREEN.r, HUD_GREEN.g, HUD_GREEN.b, 0.55)
	var i := 3.0
	for c in [[r.position + Vector2(i, i), Vector2(1, 0), Vector2(0, 1)], [Vector2(r.end.x - i, r.position.y + i), Vector2(-1, 0), Vector2(0, 1)],
			[Vector2(r.position.x + i, r.end.y - i), Vector2(1, 0), Vector2(0, -1)], [r.end - Vector2(i, i), Vector2(-1, 0), Vector2(0, -1)]]:
		cv.draw_line(c[0], c[0] + (c[1] as Vector2) * L, bc, 1.5)
		cv.draw_line(c[0], c[0] + (c[2] as Vector2) * L, bc, 1.5)
	if caption != "":
		var f := UI.font("mono")
		var fs := maxi(8, int(round(9 * s)))
		cv.draw_string(f, r.position + Vector2(i + 4, i + fs + 2), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(HUD_GREEN.r, HUD_GREEN.g, HUD_GREEN.b, 0.6))

const EXPOSED := Color(0.36, 0.13, 0.11)
const DEAD := Color(0.09, 0.095, 0.105)


## Armor color on a smooth ramp: teal-green when full, amber at half, red when nearly gone.
static func armor_col(f: float) -> Color:
	f = clampf(f, 0.0, 1.0)
	var g := Color(0.27, 0.71, 0.5)
	var y := Color(0.93, 0.7, 0.24)
	var r := Color(0.87, 0.29, 0.21)
	if f >= 0.6:
		return y.lerp(g, (f - 0.6) / 0.4)
	return r.lerp(y, f / 0.6)


static func centroid(pts: PackedVector2Array) -> Vector2:
	var c := Vector2.ZERO
	for p in pts:
		c += p
	return c / maxf(1.0, pts.size())


static func shrink(pts: PackedVector2Array, k: float, kx := -1.0) -> PackedVector2Array:
	var c := centroid(pts)
	var out := PackedVector2Array()
	var sx := k if kx < 0.0 else kx
	for p in pts:
		var d := p - c
		out.append(c + Vector2(d.x * sx, d.y * k))
	return out


static func xform(pts: Array, o: Vector2, s: float, mirror_w := -1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		var v: Vector2 = p
		if mirror_w > 0.0:
			v.x = mirror_w - v.x
		out.append(o + v * s)
	if mirror_w > 0.0:
		out.reverse()
	return out


## Fills a polygon with a top-to-bottom shade (lit from above).
static func shaded(cv: CanvasItem, pts: PackedVector2Array, col: Color, light := 0.16, dark := 0.24) -> void:
	var y0 := INF
	var y1 := -INF
	for p in pts:
		y0 = minf(y0, p.y)
		y1 = maxf(y1, p.y)
	var cols := PackedColorArray()
	for p in pts:
		var f := (p.y - y0) / maxf(1.0, y1 - y0)
		cols.append(col.lightened(light).lerp(col.darkened(dark), f))
	cv.draw_polygon(pts, cols)


static func outline(cv: CanvasItem, pts: PackedVector2Array, col: Color, w := 1.5) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	cv.draw_polyline(loop, col, w, true)


static func hatch(cv: CanvasItem, pts: PackedVector2Array, col: Color, gap := 6.0) -> void:
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var line := PackedVector2Array([Vector2(x, r.end.y), Vector2(x + r.size.y, r.position.y)])
		for seg in Geometry2D.intersect_polyline_with_polygon(line, pts):
			cv.draw_polyline(seg, col, 1.2, true)
		x += gap


## One location: an armor plate with its structure frame inside.
## a/ma armor left/max, i/mi structure left/max, flash 0..1 for a fresh hit.
static func plate(cv: CanvasItem, pts: PackedVector2Array, a: float, ma: float, i: float, mi: float, flash := 0.0, inner_k := 0.5, highlight := false) -> void:
	var dead := mi > 0.0 and i <= 0.0
	var stripped := not dead and ma > 0.0 and a <= 0.0
	# drop shadow
	var sh := PackedVector2Array()
	for p in pts:
		sh.append(p + Vector2(1.5, 2.5))
	cv.draw_colored_polygon(sh, Color(0, 0, 0, 0.35))
	var fill: Color
	if dead:
		fill = DEAD
	elif stripped:
		fill = EXPOSED
	elif ma > 0.0:
		fill = armor_col(a / ma)
	else:
		fill = armor_col(i / maxf(1.0, mi))
	if flash > 0.0:
		fill = fill.lerp(Color(1.0, 0.96, 0.88), flash * 0.85)
	shaded(cv, pts, fill)
	if dead:
		hatch(cv, pts, Color(0.75, 0.2, 0.15, 0.55), 5.0)
	elif stripped:
		hatch(cv, pts, Color(0, 0, 0, 0.3), 5.0)
	# the structure frame
	if inner_k > 0.0 and mi > 0.0 and not dead:
		var inn := shrink(pts, inner_k)
		var ic := armor_col(i / mi).darkened(0.5)
		if i < mi:
			ic = ic.lerp(Color(0.55, 0.12, 0.08), 0.35)
		shaded(cv, inn, ic, 0.05, 0.25)
		outline(cv, inn, Color(0, 0, 0, 0.55), 1.0)
	# bevel: a light inner rim and a dark outer edge
	outline(cv, shrink(pts, 0.93), Color(1, 1, 1, 0.13 if not dead else 0.04), 1.0)
	outline(cv, pts, Color(0.02, 0.025, 0.03, 0.85) if not dead else Color(0.5, 0.14, 0.1, 0.9), 1.4)
	if highlight:
		outline(cv, pts, Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.35), 5.0)
		outline(cv, pts, UI.ACCENT, 2.0)


static func number(cv: CanvasItem, center: Vector2, txt: String, fs: int, col := Color.WHITE) -> void:
	var f := UI.font("cond_semi")
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := center + Vector2(-w / 2.0, fs * 0.36)
	cv.draw_string(f, p + Vector2(1, 1), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.85))
	cv.draw_string(f, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


## Remembers when each location last lost points, for the hit flash.
static func note_hits(flash: Dictionary, old: Dictionary, new: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	for k in new:
		if old.has(k) and int(new[k]) < int(old[k]):
			flash[k] = now


static func flash_k(flash: Dictionary, loc: String) -> float:
	if not flash.has(loc):
		return 0.0
	var age := (Time.get_ticks_msec() - int(flash[loc])) / 1000.0
	return clampf(1.0 - age / 0.6, 0.0, 1.0)
