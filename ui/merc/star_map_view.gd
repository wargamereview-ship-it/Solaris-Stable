extends Control
## The Inner Sphere at today's date: a multi-layer starfield, GPU Voronoi/metaball faction territories
## with contested war-front borders, astrogation grid, jump-lane network, spectral-colored stars,
## capitals, hiring halls, collision-free labels, hover tooltip, and animated travel routes.

signal system_selected(i: int)

const SPACE_MIN := Vector2(-1920.0, -2048.0)
const SPACE_MAX := Vector2(1950.0, 1930.0)
const GRID_STEP := 32.0
const GRID_W := 128
const GRID_H := 128
const MAX_SLOTS := 64
const CELL_ROWS := 32          # 2 star slots per row * 32 rows = 64 slots per cell
const DISC_LY := 25.0
const INSERT_LY := 25.5        # conservative margin above DISC_LY so quantization never clips at boundary

var c: MercCampaign
var sm: StarMap
var center := Vector2.ZERO     # light years
var zoom := 1.25               # pixels per light year
var selected := -1
var hovered := -1
var route: Array = []
var show_lanes := true
var show_grid := true

var _cols: PackedColorArray
var _star_cols: PackedColorArray
var _cols_year := -1
var _cell_tex: ImageTexture
var _war_tex: ImageTexture
var _capitals: Dictionary = {} # system index -> faction key
var _terra_idx := -1
var _solaris_idx := -1
var _drag := false
var _moved := 0.0
var _mouse_pos := Vector2(-9999, -9999)
var _t := 0.0
var bg: ColorRect
var terr: Control
var fg: Control
var _labels: Array = []        # [name, ly position, color, count, faction_key]


func setup(camp: MercCampaign) -> void:
	c = camp
	sm = camp.sm
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_terra_idx = sm.index_of("Terra")
	_solaris_idx = sm.index_of("Solaris")
	_build_star_colors()
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

	terr = Control.new()
	terr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	terr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tm := ShaderMaterial.new()
	tm.shader = load("res://ui/merc/territory.gdshader")
	terr.material = tm
	terr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terr.draw.connect(_draw_territory)
	add_child(terr)

	fg = Control.new()
	fg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fg.draw.connect(_draw_fg)
	add_child(fg)


func _build_star_colors() -> void:
	_star_cols = PackedColorArray()
	_star_cols.resize(sm.systems.size())
	for i in sm.systems.size():
		var st := str(sm.systems[i].get("star", "G"))
		var ch := st.substr(0, 1).to_upper() if st.length() > 0 else "G"
		match ch:
			"O", "B":
				_star_cols[i] = Color(0.68, 0.84, 1.0)
			"A":
				_star_cols[i] = Color(0.88, 0.94, 1.0)
			"F":
				_star_cols[i] = Color(1.0, 0.98, 0.88)
			"G":
				_star_cols[i] = Color(1.0, 0.93, 0.72)
			"K":
				_star_cols[i] = Color(1.0, 0.78, 0.52)
			"M":
				_star_cols[i] = Color(1.0, 0.58, 0.44)
			_:
				_star_cols[i] = Color(0.95, 0.95, 0.95)


func _process(delta: float) -> void:
	_t += delta
	var bm := bg.material as ShaderMaterial
	bm.set_shader_parameter("offset", Vector2(center.x, -center.y) * 0.02)
	bm.set_shader_parameter("zoom", zoom)
	bm.set_shader_parameter("time", _t)
	terr.queue_redraw()
	fg.queue_redraw()


func _colors() -> void:
	var y := c.year() * 4 + (c.month() - 1) / 3
	if y == _cols_year and _cell_tex != null:
		return
	_cols_year = y
	var n_sys := sm.systems.size()
	_cols = PackedColorArray()
	_cols.resize(n_sys)
	var yf := c.year_f()
	var cache := {}
	var sums := {}
	var fac_sys := {}
	var fac_id := {}
	var id_to_fac: Array = [""]

	for i in n_sys:
		var o := sm.owner(i, yf)
		var real := sm.is_real_faction(o) and o != "IND"
		if not cache.has(o):
			cache[o] = sm.faction_color(o) if real else Color(0.38, 0.40, 0.44)
		_cols[i] = cache[o]
		if real:
			if not fac_id.has(o) and id_to_fac.size() < 255:
				fac_id[o] = id_to_fac.size()
				id_to_fac.append(o)
			var p := sm.pos(i)
			var e: Array = sums.get(o, [Vector2.ZERO, 0])
			e[0] = (e[0] as Vector2) + p
			e[1] = int(e[1]) + 1
			sums[o] = e
			if not fac_sys.has(o):
				fac_sys[o] = PackedInt32Array()
			(fac_sys[o] as PackedInt32Array).append(i)

	# Active faction capitals
	_capitals.clear()
	for o in sums:
		var cap_name := str(sm.factions.get(o, {}).get("capital", ""))
		if cap_name != "":
			var ci := sm.index_of(cap_name)
			if ci >= 0 and sm.owner(ci, yf) == o:
				_capitals[ci] = o

	# Build 256x256 active war matrix texture
	var war_bytes := PackedByteArray()
	war_bytes.resize(256 * 256 * 4)
	war_bytes.fill(0)
	for ia in range(1, id_to_fac.size()):
		var fa: String = id_to_fac[ia]
		for ib in range(ia + 1, id_to_fac.size()):
			var fb: String = id_to_fac[ib]
			if sm.at_war(fa, fb, yf):
				var o1 := (ib * 256 + ia) * 4
				var o2 := (ia * 256 + ib) * 4
				war_bytes[o1] = 255
				war_bytes[o1 + 3] = 255
				war_bytes[o2] = 255
				war_bytes[o2 + 3] = 255
	_war_tex = ImageTexture.create_from_image(Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, war_bytes))

	# Build 512 x 4096 spatial grid texture (128x128 cells, 64 star slots per cell: 2 slots/row x 32 rows).
	# Max systems within 25.5 ly of any 32x32 ly cell in the entire dataset is 52, so zero stars are ever dropped.
	var cell_counts := PackedByteArray()
	cell_counts.resize(GRID_W * GRID_H)
	cell_counts.fill(0)
	var tex_w := GRID_W * 4
	var tex_h := GRID_H * CELL_ROWS
	var cell_bytes := PackedByteArray()
	cell_bytes.resize(tex_w * tex_h * 4)
	cell_bytes.fill(0)

	var r_sq := INSERT_LY * INSERT_LY
	for i in n_sys:
		var o := sm.owner(i, yf)
		if not fac_id.has(o):
			continue
		var fid: int = fac_id[o]
		var col: Color = _cols[i]
		var r8 := clampi(int(round(col.r * 255.0)), 0, 255)
		var g8 := clampi(int(round(col.g * 255.0)), 0, 255)
		var b8 := clampi(int(round(col.b * 255.0)), 0, 255)
		var p := sm.pos(i)
		var ix := clampi(int(round((p.x - SPACE_MIN.x) / 4096.0 * 65535.0)), 0, 65535)
		var iy := clampi(int(round((p.y - SPACE_MIN.y) / 4096.0 * 65535.0)), 0, 65535)
		var x_hi := (ix >> 8) & 255
		var x_lo := ix & 255
		var y_hi := (iy >> 8) & 255
		var y_lo := iy & 255

		var cx0 := maxi(0, int(floor((p.x - INSERT_LY - SPACE_MIN.x) / GRID_STEP)))
		var cx1 := mini(GRID_W - 1, int(floor((p.x + INSERT_LY - SPACE_MIN.x) / GRID_STEP)))
		var cy0 := maxi(0, int(floor((p.y - INSERT_LY - SPACE_MIN.y) / GRID_STEP)))
		var cy1 := mini(GRID_H - 1, int(floor((p.y + INSERT_LY - SPACE_MIN.y) / GRID_STEP)))

		for cy in range(cy0, cy1 + 1):
			var cmin_y := SPACE_MIN.y + cy * GRID_STEP
			var dy := maxf(0.0, maxf(cmin_y - p.y, p.y - (cmin_y + GRID_STEP)))
			for cx in range(cx0, cx1 + 1):
				var cidx := cy * GRID_W + cx
				var cnt := cell_counts[cidx]
				if cnt >= MAX_SLOTS:
					continue
				var cmin_x := SPACE_MIN.x + cx * GRID_STEP
				var dx := maxf(0.0, maxf(cmin_x - p.x, p.x - (cmin_x + GRID_STEP)))
				var d2 := dx * dx + dy * dy
				if d2 >= r_sq:
					continue
				var row := cy * CELL_ROWS + (cnt >> 1)
				var col_x := cx * 4 + (cnt & 1) * 2
				var idx0 := (row * tex_w + col_x) * 4
				cell_bytes[idx0] = x_hi
				cell_bytes[idx0 + 1] = x_lo
				cell_bytes[idx0 + 2] = y_hi
				cell_bytes[idx0 + 3] = y_lo
				cell_bytes[idx0 + 4] = r8
				cell_bytes[idx0 + 5] = g8
				cell_bytes[idx0 + 6] = b8
				cell_bytes[idx0 + 7] = fid
				cell_counts[cidx] = cnt + 1

	_cell_tex = ImageTexture.create_from_image(
		Image.create_from_data(tex_w, tex_h, false, Image.FORMAT_RGBA8, cell_bytes)
	)

	# Compute interior label anchors for factions
	_labels = []
	for o in sums:
		var n := int(sums[o][1])
		var tags := sm.faction_tags(o)
		var notable := "MAJOR" in tags or "PERIPHERY" in tags or "CLAN" in tags or "PLAYABLE" in tags
		if n < 10 and not (notable and n >= 4):
			continue
		var mean_p: Vector2 = (sums[o][0] as Vector2) / float(n)
		var s_arr: PackedInt32Array = fac_sys[o]
		var step := maxi(1, s_arr.size() / 65)
		var best_p := mean_p
		var best_score := -1e9
		for k in range(0, s_arr.size(), step):
			var si := s_arr[k]
			var sp := sm.pos(si)
			var sc := -sp.distance_to(mean_p) * 0.035
			for nb in sm.systems[si]["nb"]:
				var nbi := int(nb[0])
				if sm.owner(nbi, yf) == o:
					sc += 2.2
				else:
					sc -= 4.5
			for m in range(0, s_arr.size(), step):
				var d := sp.distance_to(sm.pos(s_arr[m]))
				if d < 55.0:
					sc += 1.0 - d / 55.0
			if sc > best_score:
				best_score = sc
				best_p = sp
		# Pull slightly toward local friendly cluster centroid for smooth centering
		var loc_sum := Vector2.ZERO
		var loc_n := 0
		for k in range(0, s_arr.size(), step):
			var p2 := sm.pos(s_arr[k])
			if p2.distance_to(best_p) < 75.0:
				loc_sum += p2
				loc_n += 1
		if loc_n > 0:
			best_p = best_p.lerp(loc_sum / float(loc_n), 0.45)
		_labels.append([sm.faction_name(o).to_upper(), best_p, cache[o], n, o])
	_labels.sort_custom(func(a, b): return int(a[3]) > int(b[3]))


func to_screen(p: Vector2) -> Vector2:
	return size / 2.0 + Vector2(p.x - center.x, -(p.y - center.y)) * zoom


func to_ly(s: Vector2) -> Vector2:
	var d := (s - size / 2.0) / zoom
	return Vector2(center.x + d.x, center.y - d.y)


func _draw_territory() -> void:
	_colors()
	if _cell_tex == null or size.x <= 1.0 or size.y <= 1.0:
		return
	var tm := terr.material as ShaderMaterial
	tm.set_shader_parameter("cell_tex", _cell_tex)
	tm.set_shader_parameter("war_tex", _war_tex)
	tm.set_shader_parameter("view_size", size)
	tm.set_shader_parameter("center", center)
	tm.set_shader_parameter("zoom", zoom)
	tm.set_shader_parameter("time", _t)
	terr.draw_texture_rect(_cell_tex, Rect2(Vector2.ZERO, size), false)


func _draw_fg() -> void:
	_colors()
	var font := UI.font("medium")
	var bold_font := UI.font("semibold")
	var mono := UI.font("mono")
	var icons := UI.font("icons")
	var yf := c.year_f()
	var rect := Rect2(Vector2(-40, -40), size + Vector2(80, 80))

	if show_grid:
		_draw_grid(mono)

	# Faction titles over their territory when zoomed out
	if zoom < 3.2:
		var lf := UI.spaced("cond", 4)
		var fac_rects: Array[Rect2] = []
		for l in _labels:
			var lp := to_screen(l[1])
			if not rect.has_point(lp):
				continue
			var n_worlds := int(l[3])
			if n_worlds < 12 and zoom < 0.75:
				continue
			var fs := int(clampf(9.0 + sqrt(float(n_worlds)) * 0.78 * zoom, 12.0, 32.0))
			var txt := str(l[0])
			var tsz := lf.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var box := Rect2(lp - Vector2(tsz.x * 0.5 + 8.0, tsz.y * 0.75), tsz + Vector2(16.0, 6.0))
			var hit := false
			for r0 in fac_rects:
				if r0.intersects(box):
					hit = true
					break
			if hit:
				continue
			fac_rects.append(box)
			var lc: Color = l[2]
			var fade := clampf((3.2 - zoom) / 0.9, 0.0, 1.0)
			if n_worlds < 15:
				fade *= clampf((zoom - 0.6) / 0.5, 0.35, 1.0)
			var draw_p := lp - Vector2(tsz.x * 0.5, 0.0)
			for off: Vector2 in [Vector2(-1.5, 1.5), Vector2(1.5, 1.5), Vector2(0, 2.5), Vector2(0, -1.5)]:
				fg.draw_string(lf, draw_p + off, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.0, 0.0, 0.0, 0.62 * fade))
			var tc := lc.lightened(0.36)
			fg.draw_string(lf, draw_p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(tc.r, tc.g, tc.b, 0.68 * fade))

	# Jump range horizon around the company
	if c.location >= 0 and not c.in_transit():
		var jp := to_screen(sm.pos(c.location))
		var jr := 30.0 * zoom
		fg.draw_circle(jp, jr, Color(0.32, 0.68, 1.0, 0.045))
		fg.draw_arc(jp, jr, 0, TAU, 96, Color(0.45, 0.78, 1.0, 0.42), 1.5, true)
		for k in 12:
			var ang := k * TAU / 12.0
			var vdir := Vector2.from_angle(ang)
			fg.draw_line(jp + vdir * (jr - 3.5), jp + vdir * (jr + 3.5), Color(0.55, 0.84, 1.0, 0.5), 1.2, true)
		if jr >= 48.0:
			var jtxt := "30 LY JUMP HORIZON"
			var jfs := 10
			var jw := mono.get_string_size(jtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, jfs).x
			var jpos := jp + Vector2(-jw * 0.5, -jr - 6.0)
			if rect.has_point(jpos):
				fg.draw_string(mono, jpos + Vector2(1, 1), jtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, jfs, Color(0, 0, 0, 0.75))
				fg.draw_string(mono, jpos, jtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, jfs, Color(0.55, 0.84, 1.0, 0.75))

	# Jump-lane constellation network
	if show_lanes:
		_draw_jump_lanes(rect, yf)

	# Planned route & active travel route
	if route.size() > 1:
		_dash_route(route, Color(1.0, 0.82, 0.32, 0.95), mono)
	if c.in_transit():
		_dash_route(c.travel["route"], Color(0.45, 0.88, 1.0, 0.95), mono)

	# Systems: faction halo + ring, spectral star core, industrial ticks, capital & hall badges
	var r := clampf(zoom * 1.05, 1.15, 4.4)
	var candidate_labels: Array = []
	for i in sm.systems.size():
		var sp := to_screen(sm.pos(i))
		if not rect.has_point(sp):
			continue
		var col := _cols[i]
		var scol := _star_cols[i]
		var pop := sm.population(i, yf)
		var big := 1.0 + clampf(log(maxf(1.0, pop / 1.0e8)) * 0.17, 0.0, 0.82)
		var sr := r * big
		var is_cap := _capitals.has(i) or i == _terra_idx
		var hall := sm.hall(i, yf)

		# Soft faction glow
		fg.draw_circle(sp, sr * 2.8, Color(col.r, col.g, col.b, 0.15))

		# Industrial world corner ticks when zoomed in
		if zoom >= 2.3 and sm.industrial(i, yf):
			var tr_rad := sr + 3.2
			for q in 4:
				var a := PI * 0.25 + q * PI * 0.5
				var vd := Vector2.from_angle(a)
				fg.draw_line(sp + vd * (tr_rad - 1.2), sp + vd * (tr_rad + 2.2), Color(0.76, 0.86, 0.96, 0.52), 1.2, true)

		# Capital double-ring & diamond
		if is_cap:
			var cap_col := Color(1.0, 0.88, 0.42) if i == _terra_idx else col.lightened(0.45)
			var cr := maxf(sr + 4.5, 6.5)
			fg.draw_arc(sp, cr, 0, TAU, 28, Color(cap_col.r, cap_col.g, cap_col.b, 0.82), 1.5, true)
			var dpts := PackedVector2Array([
				sp + Vector2(0, -cr - 2.5),
				sp + Vector2(cr + 2.5, 0),
				sp + Vector2(0, cr + 2.5),
				sp + Vector2(-cr - 2.5, 0),
				sp + Vector2(0, -cr - 2.5),
			])
			fg.draw_polyline(dpts, Color(cap_col.r, cap_col.g, cap_col.b, 0.55), 1.1, true)

		# Faction ring + spectral core
		if zoom >= 1.4:
			fg.draw_circle(sp, sr * 1.15, col.lightened(0.18))
			fg.draw_circle(sp, sr * 0.72, scol)
			if big >= 1.35 and zoom >= 2.2:
				fg.draw_circle(sp, sr * 0.34, Color.WHITE)
		else:
			fg.draw_circle(sp, sr, col.lightened(0.32).lerp(scol, 0.45))

		# Hiring hall badge
		if hall != "":
			var major_hall := hall in ["GREAT", "STANDARD"]
			var hr := 8.5 if major_hall else 6.8
			fg.draw_circle(sp, hr + 2.5, Color(1.0, 0.78, 0.25, 0.16))
			fg.draw_circle(sp, hr, Color(0.06, 0.07, 0.10, 0.88))
			fg.draw_arc(sp, hr, 0, TAU, 24, Color(1.0, 0.80, 0.28, 0.9 if major_hall else 0.7), 1.4, true)
			var gs := 12 if major_hall else 10
			var st_txt := UI.ic("star")
			var st_sz := icons.get_string_size(st_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, gs)
			var ascent := icons.get_ascent(gs)
			fg.draw_string(icons, sp + Vector2(-st_sz.x * 0.5, ascent * 0.42), st_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, gs, Color(1.0, 0.84, 0.32))

		# Check if system qualifies for a text label
		var is_special := (i == selected or i == hovered or i == c.location
			or (not c.contract.is_empty() and i == int(c.contract["system"]))
			or is_cap or i == _solaris_idx or hall != "")
		var show := is_special or zoom >= 3.6 or (zoom >= 2.0 and pop > 2500000000) or (zoom >= 2.7 and pop > 600000000)
		if show:
			var prio := 100 + int(clampf(log(maxf(1.0, pop / 1.0e6)) * 14.0, 0.0, 280.0))
			if hall != "":
				prio = 720 if hall in ["GREAT", "STANDARD"] else 620
			if is_cap or i == _solaris_idx:
				prio = 820
			if not c.contract.is_empty() and i == int(c.contract["system"]):
				prio = 920
			if i == c.location:
				prio = 960
			if i == hovered:
				prio = 990
			if i == selected:
				prio = 1000
			candidate_labels.append([prio, i, sp, hall, is_cap])

	# Sort and draw collision-free system labels
	candidate_labels.sort_custom(func(a, b): return int(a[0]) > int(b[0]))
	var occupied: Array[Rect2] = []

	# Reserve space for contract badge and company marker
	if not c.contract.is_empty():
		var cp0 := to_screen(sm.pos(int(c.contract["system"])))
		occupied.append(Rect2(cp0 + Vector2(16, -24), Vector2(82, 18)))

	var drawn_labels := 0
	for item in candidate_labels:
		if drawn_labels >= 220:
			break
		var prio: int = item[0]
		var idx: int = item[1]
		var sp2: Vector2 = item[2]
		var hall2: String = item[3]
		var is_cap2: bool = item[4]
		var nm := sm.name_of(idx)
		var use_bold := prio >= 700
		var f_use := bold_font if use_bold else font
		var fs2 := 13 if (use_bold or zoom >= 3.8) else 12
		var tsz := f_use.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2)
		var off_x := 11.0 if (hall2 != "" or is_cap2) else 9.0
		var lpos := sp2 + Vector2(off_x, 4.0)
		var lrect := Rect2(lpos.x - 3.0, lpos.y - fs2, tsz.x + 6.0, fs2 + 5.0)

		if prio < 900:
			var coll := false
			for orect in occupied:
				if orect.intersects(lrect):
					coll = true
					break
			if coll:
				continue
		occupied.append(lrect)
		drawn_labels += 1

		if prio >= 700:
			var pill := Rect2(lpos.x - 4.0, lpos.y - fs2 + 1.0, tsz.x + 8.0, fs2 + 4.0)
			fg.draw_rect(pill, Color(0.03, 0.04, 0.06, 0.76), true)
			if idx == selected or idx == hovered:
				fg.draw_rect(pill, Color(0.45, 0.72, 1.0, 0.45), false, 1.0)
		else:
			fg.draw_string(f_use, lpos + Vector2(1, 1), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, Color(0, 0, 0, 0.82))

		var lcol := Color(0.90, 0.93, 0.97, 0.92)
		if idx == selected or idx == hovered:
			lcol = Color.WHITE
		elif hall2 != "":
			lcol = Color(1.0, 0.86, 0.44)
		elif is_cap2:
			lcol = _cols[idx].lightened(0.52)
		fg.draw_string(f_use, lpos, nm, HORIZONTAL_ALIGNMENT_LEFT, -1, fs2, lcol)

	# Contract target marker
	if not c.contract.is_empty():
		var cp := to_screen(sm.pos(int(c.contract["system"])))
		var pulse := 0.5 + 0.5 * sin(_t * 3.0)
		fg.draw_arc(cp, 12.0 + pulse * 4.0, 0, TAU, 32, Color(UI.BAD.r, UI.BAD.g, UI.BAD.b, 0.9 - pulse * 0.5), 2.0, true)
		for q in 4:
			var a := q * PI / 2.0
			fg.draw_line(cp + Vector2.from_angle(a) * 8.0, cp + Vector2.from_angle(a) * 18.0, UI.BAD, 2.0)
		var lbl := "CONTRACT"
		var cfont := UI.spaced("cond_semi", 2)
		var csz := cfont.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
		fg.draw_rect(Rect2(cp + Vector2(18, -22), csz + Vector2(8, 4)), Color(0.14, 0.03, 0.03, 0.85), true)
		fg.draw_rect(Rect2(cp + Vector2(18, -22), csz + Vector2(8, 4)), Color(UI.BAD.r, UI.BAD.g, UI.BAD.b, 0.6), false, 1.0)
		fg.draw_string(cfont, cp + Vector2(22, -11), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.BAD)

	# Hovered system reticle
	if hovered >= 0 and hovered != selected:
		_draw_brackets(to_screen(sm.pos(hovered)), 11.0, Color(0.75, 0.90, 1.0, 0.85), 1.5)

	# Selected system reticle
	if selected >= 0:
		var sp3 := to_screen(sm.pos(selected))
		fg.draw_arc(sp3, 11.5, _t * 1.4, _t * 1.4 + PI * 1.35, 24, Color.WHITE, 2.0, true)
		fg.draw_arc(sp3, 11.5, _t * 1.4 + PI, _t * 1.4 + PI * 1.65, 16, Color(0.55, 0.82, 1.0, 0.8), 1.5, true)
		_draw_brackets(sp3, 14.5, Color(1.0, 0.85, 0.35, 0.9), 1.6)

	# Company marker
	var here := sm.pos(c.location) if c.location >= 0 else Vector2.ZERO
	if c.in_transit():
		var tp := c.travel_position()
		here = sm.pos(int(tp["a"])).lerp(sm.pos(int(tp["b"])), float(tp["f"]))
	var hp := to_screen(here)
	var pl := fmod(_t * 0.75, 1.0)
	fg.draw_arc(hp, 8.0 + pl * 22.0, 0, TAU, 32, Color(c.color.r, c.color.g, c.color.b, 0.8 * (1.0 - pl)), 2.0, true)
	fg.draw_circle(hp, 7.0, c.color)
	fg.draw_arc(hp, 7.5, 0, TAU, 24, Color.WHITE, 2.0, true)
	fg.draw_string(icons, hp + Vector2(-6, -13), UI.ic("rocket"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

	# Scale bar & bottom HUD legend bar
	_draw_hud_bars(font, mono, icons)

	# Hover tooltip card
	if hovered >= 0 and hovered != selected:
		_draw_hover_tooltip(hovered, font, bold_font, mono, yf)


func _draw_brackets(p: Vector2, rad: float, col: Color, width: float) -> void:
	var arm := 4.5
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			var corner := p + Vector2(sx * rad, sy * rad)
			fg.draw_line(corner, corner + Vector2(-sx * arm, 0), col, width, true)
			fg.draw_line(corner, corner + Vector2(0, -sy * arm), col, width, true)


func _draw_grid(mono: Font) -> void:
	var tl_ly := to_ly(Vector2.ZERO)
	var br_ly := to_ly(size)
	var min_x := minf(tl_ly.x, br_ly.x)
	var max_x := maxf(tl_ly.x, br_ly.x)
	var min_y := minf(tl_ly.y, br_ly.y)
	var max_y := maxf(tl_ly.y, br_ly.y)

	# Minor 100 LY grid lines when zoomed in
	if zoom >= 0.55:
		var a100 := clampf((zoom - 0.55) / 1.2, 0.0, 1.0) * 0.045
		var gx0 := int(floor(min_x / 100.0)) * 100
		var gx1 := int(ceil(max_x / 100.0)) * 100
		for gx in range(gx0, gx1 + 1, 100):
			if gx % 500 == 0:
				continue
			var sx := to_screen(Vector2(gx, 0)).x
			fg.draw_line(Vector2(sx, 0), Vector2(sx, size.y), Color(0.45, 0.65, 0.88, a100), 1.0)
		var gy0 := int(floor(min_y / 100.0)) * 100
		var gy1 := int(ceil(max_y / 100.0)) * 100
		for gy in range(gy0, gy1 + 1, 100):
			if gy % 500 == 0:
				continue
			var sy := to_screen(Vector2(0, gy)).y
			fg.draw_line(Vector2(0, sy), Vector2(size.x, sy), Color(0.45, 0.65, 0.88, a100), 1.0)

	# Major 500 LY grid lines + edge coordinate labels
	var gx50 := int(floor(min_x / 500.0)) * 500
	var gx51 := int(ceil(max_x / 500.0)) * 500
	for gx in range(gx50, gx51 + 1, 500):
		var sx := to_screen(Vector2(gx, 0)).x
		var col := Color(0.52, 0.72, 0.95, 0.09 if gx == 0 else 0.065)
		fg.draw_line(Vector2(sx, 0), Vector2(sx, size.y), col, 1.0)
		if sx > 40.0 and sx < size.x - 60.0:
			var lbl := ("%+d LY" % gx) if gx != 0 else "0 LY (TERRA)"
			fg.draw_string(mono, Vector2(sx + 4, 54), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.70, 0.86, 0.42))

	var gy50 := int(floor(min_y / 500.0)) * 500
	var gy51 := int(ceil(max_y / 500.0)) * 500
	for gy in range(gy50, gy51 + 1, 500):
		var sy := to_screen(Vector2(0, gy)).y
		var col := Color(0.52, 0.72, 0.95, 0.09 if gy == 0 else 0.065)
		fg.draw_line(Vector2(0, sy), Vector2(size.x, sy), col, 1.0)
		if sy > 65.0 and sy < size.y - 50.0:
			var lbl := ("%+d LY" % gy) if gy != 0 else "0 LY"
			fg.draw_string(mono, Vector2(8, sy - 4), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.70, 0.86, 0.42))

	# Subtle range rings centered on Terra (0, 0)
	var tp := to_screen(Vector2.ZERO)
	for rad_ly: float in [250.0, 500.0]:
		var rpx := rad_ly * zoom
		if rpx > 40.0 and rpx < maxf(size.x, size.y) * 1.8:
			fg.draw_arc(tp, rpx, 0, TAU, 96, Color(0.45, 0.68, 0.92, 0.055), 1.0, true)


func _draw_jump_lanes(rect: Rect2, yf: float) -> void:
	# Ambient jump network when zoomed in
	if zoom >= 1.35:
		var lane_a := clampf((zoom - 1.35) / 1.4, 0.0, 1.0) * 0.16
		var base_col := Color(0.48, 0.68, 0.92, lane_a)
		for i in sm.systems.size():
			var p1 := to_screen(sm.pos(i))
			if not rect.has_point(p1):
				continue
			var o1 := sm.owner(i, yf)
			for nb in sm.systems[i]["nb"]:
				var j := int(nb[0])
				if j <= i:
					continue
				var p2 := to_screen(sm.pos(j))
				var o2 := sm.owner(j, yf)
				var lcol := base_col
				if o1 == o2 and sm.is_real_faction(o1) and o1 != "IND":
					var fc := _cols[i].lightened(0.25)
					lcol = Color(fc.r, fc.g, fc.b, lane_a * 1.15)
				fg.draw_line(p1, p2, lcol, 1.0, true)

	# Highlighted 1-jump spokes for player location, selected system, and hovered system
	var highlights := []
	if c.location >= 0 and not c.in_transit():
		highlights.append([c.location, Color(0.42, 0.82, 1.0, 0.34), 1.4])
	if selected >= 0 and selected != c.location:
		highlights.append([selected, Color(1.0, 0.82, 0.35, 0.45), 1.5])
	if hovered >= 0 and hovered != selected and hovered != c.location:
		highlights.append([hovered, Color(0.78, 0.92, 1.0, 0.45), 1.4])

	for h in highlights:
		var idx: int = h[0]
		var col: Color = h[1]
		var w: float = h[2]
		var p1 := to_screen(sm.pos(idx))
		for nb in sm.systems[idx]["nb"]:
			var j := int(nb[0])
			var p2 := to_screen(sm.pos(j))
			fg.draw_line(p1, p2, col, w, true)
			fg.draw_circle(p2, 2.6, col)


func _dash_route(r: Array, col: Color, mono: Font) -> void:
	var off := fmod(_t * 20.0, 14.0)
	var glow_col := Color(col.r, col.g, col.b, 0.18)
	var track_col := Color(col.r, col.g, col.b, 0.38)
	for k in range(1, r.size()):
		var a := to_screen(sm.pos(int(r[k - 1])))
		var b := to_screen(sm.pos(int(r[k])))
		fg.draw_line(a, b, glow_col, 7.0, true)
		fg.draw_line(a, b, track_col, 1.5, true)
		var d := a.distance_to(b)
		var dir := (b - a) / maxf(d, 0.001)
		var s := -off
		while s < d:
			var s0 := maxf(0.0, s)
			var s1 := minf(d, s + 8.0)
			if s1 > s0:
				fg.draw_line(a + dir * s0, a + dir * s1, col, 2.6, true)
			s += 14.0
		fg.draw_circle(b, 3.8, Color(0.05, 0.07, 0.10, 0.9))
		fg.draw_arc(b, 3.8, 0, TAU, 16, col, 1.6, true)
		if zoom >= 1.4 and d >= 26.0:
			var s_lbl := str(k)
			var tw := mono.get_string_size(s_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
			var bp := b + Vector2(-tw * 0.5, -7.0)
			fg.draw_rect(Rect2(bp.x - 3, bp.y - 9, tw + 6, 12), Color(0.04, 0.05, 0.08, 0.85), true)
			fg.draw_string(mono, bp, s_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, col)


func _draw_hud_bars(font: Font, mono: Font, icons: Font) -> void:
	# Scale bar on bottom-left above legend
	var ref_ly := 100.0
	if zoom >= 3.2:
		ref_ly = 30.0
	elif zoom >= 1.5:
		ref_ly = 50.0
	elif zoom < 0.65:
		ref_ly = 250.0
	var bar_px := ref_ly * zoom
	var sb_pos := Vector2(16, size.y - 48)
	fg.draw_rect(Rect2(sb_pos.x - 6, sb_pos.y - 16, bar_px + 12, 24), Color(0.03, 0.04, 0.06, 0.72), true)
	fg.draw_line(sb_pos, sb_pos + Vector2(bar_px, 0), Color(0.72, 0.84, 0.96, 0.85), 2.0)
	fg.draw_line(sb_pos + Vector2(0, -4), sb_pos + Vector2(0, 4), Color(0.72, 0.84, 0.96, 0.85), 1.5)
	fg.draw_line(sb_pos + Vector2(bar_px, -4), sb_pos + Vector2(bar_px, 4), Color(0.72, 0.84, 0.96, 0.85), 1.5)
	var slbl := "%d LY%s" % [int(ref_ly), " (1 JUMP)" if int(ref_ly) == 30 else ""]
	fg.draw_string(mono, sb_pos + Vector2(4, -4), slbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.75, 0.85, 0.96, 0.9))

	# Bottom legend pill bar
	var lbar := Rect2(10, size.y - 32, size.x - 20, 24)
	fg.draw_rect(lbar, Color(0.035, 0.045, 0.062, 0.86), true)
	fg.draw_rect(lbar, UI.LINE, false, 1.0)
	var x := 20.0
	var y := size.y - 15.0
	var items := [
		[UI.ic("rocket"), Color.WHITE, "Company"],
		[UI.ic("star"), Color(1.0, 0.82, 0.32), "Hiring Hall"],
		["◆", Color(1.0, 0.88, 0.45), "Capital"],
		[UI.ic("dot"), Color(0.45, 0.80, 1.0), "30 LY Jump Range"],
		["━", Color(1.0, 0.48, 0.28), "War Front"],
		[UI.ic("arrows_alt") if UI.ICONS.has("arrows_alt") else UI.ic("arrow_right"), UI.DIM, "Drag pan · Wheel zoom · Click inspect"],
	]
	for it in items:
		fg.draw_string(icons, Vector2(x, y), str(it[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, it[1])
		x += 16.0
		var lbl := str(it[2])
		fg.draw_string(font, Vector2(x, y), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 0.80, 0.86))
		x += font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x + 22.0


func _draw_hover_tooltip(i: int, font: Font, bold_font: Font, mono: Font, yf: float) -> void:
	var nm := sm.name_of(i)
	var o := sm.owner(i, yf)
	var fname := sm.faction_name(o)
	var fcol := _cols[i].lightened(0.32)
	var hall := sm.hall(i, yf)
	var is_cap := _capitals.has(i) or i == _terra_idx
	var badge := ""
	if is_cap:
		badge = "  [CAPITAL]"
	elif hall != "":
		badge = "  [%s HALL]" % hall
	elif sm.industrial(i, yf):
		badge = "  [INDUSTRIAL]"

	var line1 := nm + badge
	var line2 := fname
	var line3 := ""
	if i == c.location and not c.in_transit():
		line3 = "Current location"
	elif c.location >= 0:
		var r := sm.route(c.location, i)
		if r.size() > 1:
			line3 = "%d jump%s · ~%d days" % [r.size() - 1, "" if r.size() == 2 else "s", sm.trip_days(r)]
		else:
			line3 = "Unreachable"

	var w1 := bold_font.get_string_size(line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var w2 := font.get_string_size(line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var w3 := mono.get_string_size(line3, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x if line3 != "" else 0.0
	var bw := maxf(maxf(w1, w2), w3) + 20.0
	var bh := 58.0 if line3 != "" else 42.0

	var sp := to_screen(sm.pos(i))
	var pos := sp + Vector2(16, -bh * 0.5)
	if pos.x + bw > size.x - 12:
		pos.x = sp.x - bw - 16
	pos.y = clampf(pos.y, 54.0, size.y - bh - 38.0)

	var box := Rect2(pos, Vector2(bw, bh))
	fg.draw_rect(box, Color(0.04, 0.055, 0.075, 0.94), true)
	fg.draw_rect(box, fcol, false, 1.2)
	fg.draw_rect(Rect2(pos, Vector2(3.0, bh)), fcol, true)
	fg.draw_string(bold_font, pos + Vector2(10, 17), line1, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
	fg.draw_string(font, pos + Vector2(10, 33), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, fcol)
	if line3 != "":
		fg.draw_string(mono, pos + Vector2(10, 49), line3, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UI.ACCENT)


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
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse_pos = mm.position
		if _drag:
			_moved += mm.relative.length()
			center += Vector2(-mm.relative.x, mm.relative.y) / zoom
			accept_event()
		else:
			var h := _nearest(mm.position, 13.0)
			if h != hovered:
				hovered = h
				mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if hovered >= 0 else Control.CURSOR_ARROW


func _nearest(p: Vector2, max_d := 12.0) -> int:
	var best := -1
	var bd := max_d
	for i in sm.systems.size():
		var d := to_screen(sm.pos(i)).distance_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func _pick(p: Vector2) -> void:
	var best := _nearest(p, 13.0)
	if best >= 0:
		select(best)


func select(i: int) -> void:
	selected = i
	route = sm.route(c.location, i) if (c.location >= 0 and i >= 0) else []
	system_selected.emit(i)


func focus_system(i: int, min_zoom := 1.6) -> void:
	if i < 0 or i >= sm.systems.size():
		return
	center = sm.pos(i)
	if zoom < min_zoom:
		zoom = min_zoom
	select(i)
