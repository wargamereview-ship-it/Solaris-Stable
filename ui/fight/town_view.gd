extends RefCounted
## Drawing for settlements (Settlement in core/arena): every building type's walls and roof in the
## viewer's 2.5D lean, and the street layer under them (lane lines, sidewalks and curbs,
## crosswalks, parking bays, paved plazas with fountains, industrial lots, park paths, hedges and
## street lights at night).

const K := Settlement.K
const Z := Settlement.Z

const WALL := {
	K.HOUSE: [[0.8, 0.74, 0.63], [0.7, 0.5, 0.4], [0.84, 0.82, 0.76], [0.64, 0.68, 0.72], [0.74, 0.66, 0.5]],
	K.ROWHOUSE: [[0.62, 0.38, 0.3], [0.74, 0.66, 0.54], [0.56, 0.46, 0.4], [0.68, 0.56, 0.46]],
	K.SHOP: [[0.76, 0.71, 0.62], [0.62, 0.64, 0.68], [0.72, 0.62, 0.5], [0.8, 0.78, 0.72]],
	K.APARTMENT: [[0.72, 0.68, 0.61], [0.63, 0.61, 0.59], [0.68, 0.6, 0.52], [0.58, 0.6, 0.64]],
	K.OFFICE: [[0.46, 0.52, 0.58], [0.54, 0.56, 0.58], [0.6, 0.58, 0.54]],
	K.TOWER: [[0.28, 0.38, 0.48], [0.34, 0.42, 0.52], [0.4, 0.44, 0.5], [0.3, 0.44, 0.44]],
	K.WAREHOUSE: [[0.52, 0.55, 0.58], [0.44, 0.5, 0.46], [0.56, 0.52, 0.45], [0.42, 0.46, 0.54]],
	K.FACTORY: [[0.56, 0.36, 0.3], [0.5, 0.5, 0.52], [0.48, 0.42, 0.36]],
	K.TANK: [[0.84, 0.84, 0.82], [0.72, 0.74, 0.76], [0.78, 0.7, 0.5]],
	K.CIVIC: [[0.82, 0.78, 0.68], [0.76, 0.74, 0.7]],
	K.CHURCH: [[0.7, 0.66, 0.6], [0.66, 0.6, 0.52]],
	K.BARN: [[0.62, 0.25, 0.19], [0.5, 0.36, 0.26]],
	K.SILO: [[0.77, 0.78, 0.76], [0.6, 0.62, 0.64]],
	K.BUNKER: [[0.42, 0.43, 0.4]],
	K.HANGAR: [[0.42, 0.46, 0.4], [0.5, 0.52, 0.5]],
	K.NONE: [[0.5, 0.5, 0.52]],
}
const ROOF := {
	K.HOUSE: [[0.62, 0.32, 0.24], [0.34, 0.37, 0.41], [0.46, 0.34, 0.26], [0.32, 0.42, 0.35], [0.55, 0.42, 0.3]],
	K.ROWHOUSE: [[0.42, 0.3, 0.26], [0.36, 0.38, 0.42], [0.55, 0.32, 0.25]],
	K.SHOP: [[0.6, 0.6, 0.6], [0.52, 0.53, 0.55], [0.66, 0.64, 0.6]],
	K.APARTMENT: [[0.56, 0.55, 0.53], [0.5, 0.5, 0.5], [0.6, 0.58, 0.55]],
	K.OFFICE: [[0.44, 0.45, 0.47], [0.5, 0.5, 0.52]],
	K.TOWER: [[0.24, 0.3, 0.36], [0.3, 0.33, 0.38]],
	K.WAREHOUSE: [[0.62, 0.64, 0.66], [0.5, 0.55, 0.5], [0.58, 0.55, 0.5], [0.48, 0.52, 0.58]],
	K.FACTORY: [[0.48, 0.48, 0.5], [0.42, 0.4, 0.38]],
	K.TANK: [[0.9, 0.9, 0.88], [0.78, 0.8, 0.82]],
	K.CIVIC: [[0.7, 0.68, 0.62]],
	K.CHURCH: [[0.3, 0.32, 0.36], [0.4, 0.3, 0.26]],
	K.BARN: [[0.48, 0.2, 0.16], [0.4, 0.38, 0.36]],
	K.SILO: [[0.82, 0.83, 0.82]],
	K.BUNKER: [[0.36, 0.37, 0.35]],
	K.HANGAR: [[0.5, 0.54, 0.48], [0.56, 0.58, 0.56]],
	K.NONE: [[0.46, 0.47, 0.5]],
}
const AWNINGS := [[0.72, 0.18, 0.16], [0.16, 0.42, 0.3], [0.18, 0.32, 0.6], [0.82, 0.62, 0.16], [0.5, 0.2, 0.42]]


static func hv(id: int, k: int) -> int:
	return absi(hash(id * 7919 + k * 104729 + 17))


static func pick(table: Dictionary, kind: int, id: int, k := 0) -> Color:
	var opts: Array = table.get(kind, table[K.NONE])
	var c: Array = opts[hv(id, k) % opts.size()]
	return Color(float(c[0]), float(c[1]), float(c[2]))


static func _lit(id: int, k: int, night: float, share := 0.45) -> bool:
	return night > 0.2 and float(hv(id, k) % 1000) / 1000.0 < share


# ------------------------------------------------------------------ buildings

## One intact building of a settlement type. b: {"rect", "kind", "id", "h"}; dmg 0..1.
static func draw_building(cv: CanvasItem, b: Dictionary, cell: float, shift: float, night: float, dmg: float) -> void:
	var r: Rect2i = b["rect"]
	var kind: int = b["kind"]
	var id: int = b["id"]
	var lv := float(b["h"])
	var R := Rect2(Vector2(r.position) * cell, Vector2(r.size) * cell)
	var hs := lv * shift
	var wall := pick(WALL, kind, id, 1)
	var roof := pick(ROOF, kind, id, 2)
	if dmg > 0.0:
		wall = wall.lerp(Color(0.14, 0.12, 0.11), clampf(dmg * 0.6, 0.0, 0.5))
		roof = roof.lerp(Color(0.15, 0.13, 0.12), clampf(dmg * 0.7, 0.0, 0.6))
	if night > 0.0:
		wall = wall.darkened(night * 0.5)
		roof = roof.darkened(night * 0.45)
	if kind == K.TANK or kind == K.SILO:
		_cylinder(cv, kind, id, R, hs, wall, roof, night)
		return
	# the south wall
	var W := Rect2(R.position.x, R.end.y - hs, R.size.x, hs)
	cv.draw_polygon(PackedVector2Array([W.position, Vector2(W.end.x, W.position.y), W.end, Vector2(W.position.x, W.end.y)]),
		PackedColorArray([wall, wall, wall.darkened(0.3), wall.darkened(0.3)]))
	_facade(cv, kind, id, W, int(lv), shift, night, wall)
	cv.draw_line(Vector2(W.position.x, W.end.y), W.end, wall.darkened(0.55), 1.5)
	# the roof
	var RR := Rect2(R.position - Vector2(0, hs), R.size)
	_roof(cv, kind, id, RR, roof, night)
	cv.draw_line(RR.position, Vector2(RR.end.x, RR.position.y), roof.lightened(0.25), 1.5)
	cv.draw_line(RR.position, Vector2(RR.position.x, RR.end.y), roof.lightened(0.18), 1.5)
	cv.draw_line(Vector2(RR.end.x, RR.position.y), RR.end, roof.darkened(0.4), 1.5)
	cv.draw_line(Vector2(RR.position.x, RR.end.y), RR.end, roof.darkened(0.45), 1.5)
	if dmg > 0.35:
		var crack := Color(0.06, 0.05, 0.05, 0.85)
		var a := RR.position + Vector2(float(hv(id, 9) % int(maxf(1.0, RR.size.x - 10))) + 4.0, 3)
		cv.draw_polyline(PackedVector2Array([a, a + Vector2(4, 7), a + Vector2(1, 13), a + Vector2(6, 19)]), crack, 1.4)


static func _windows_row(cv: CanvasItem, x0: float, x1: float, y: float, w: float, h: float, gap: float, id: int, k: int, night: float, warm := true) -> void:
	var x := x0
	var m := 0
	while x + w <= x1:
		var on := _lit(id, k * 97 + m, night)
		var c := (Color(1.0, 0.82, 0.48, 0.95) if warm else Color(0.82, 0.9, 1.0, 0.95)) if on else Color(0.13, 0.17, 0.21, 0.85).lerp(Color(0.55, 0.64, 0.72, 0.7), 0.3 * (1.0 - night))
		cv.draw_rect(Rect2(Vector2(x, y), Vector2(w, h)), c)
		x += w + gap
		m += 1


static func _facade(cv: CanvasItem, kind: int, id: int, W: Rect2, lv: int, shift: float, night: float, wall: Color) -> void:
	var x0 := W.position.x + 2.0
	var x1 := W.end.x - 2.0
	match kind:
		K.HOUSE, K.ROWHOUSE:
			for k in lv:
				_windows_row(cv, x0 + 2.0, x1 - 2.0, W.position.y + k * shift + shift * 0.25, 4.0, shift * 0.42, 6.0, id, k, night)
			# doors along the bottom, one per unit
			var unit := 2.0 * Arena.CELL * 2.4 if kind == K.ROWHOUSE else W.size.x
			var u := W.position.x
			while u < W.end.x - 6.0:
				cv.draw_rect(Rect2(Vector2(u + minf(unit, W.end.x - u) * 0.5 - 2.0, W.end.y - shift * 0.62), Vector2(4.0, shift * 0.62)), wall.darkened(0.6))
				u += unit
		K.SHOP:
			var sb := W.end.y - shift
			cv.draw_rect(Rect2(Vector2(x0, sb + shift * 0.3), Vector2(x1 - x0, shift * 0.6)), Color(1.0, 0.86, 0.55, 0.9) if night > 0.2 else Color(0.32, 0.4, 0.46, 0.9))
			var aw := pick({0: AWNINGS}, 0, id, 4)
			cv.draw_rect(Rect2(Vector2(W.position.x, sb), Vector2(W.size.x, shift * 0.28)), aw.darkened(night * 0.4))
			var sx := W.position.x
			while sx < W.end.x:
				cv.draw_line(Vector2(sx, sb), Vector2(sx, sb + shift * 0.28), aw.lightened(0.35), 1.5)
				sx += 6.0
			for k in lv - 1:
				_windows_row(cv, x0 + 1.0, x1 - 1.0, W.position.y + k * shift + shift * 0.25, 4.0, shift * 0.42, 4.0, id, k, night)
		K.APARTMENT:
			for k in lv:
				var y := W.position.y + k * shift
				_windows_row(cv, x0, x1, y + shift * 0.22, 3.5, shift * 0.45, 3.0, id, k, night)
				cv.draw_line(Vector2(W.position.x, y + shift * 0.82), Vector2(W.end.x, y + shift * 0.82), wall.lightened(0.2), 1.0)
		K.OFFICE:
			for k in lv:
				var y2 := W.position.y + k * shift + shift * 0.2
				var on := _lit(id, k, night, 0.6)
				cv.draw_rect(Rect2(Vector2(x0, y2), Vector2(x1 - x0, shift * 0.52)), Color(0.85, 0.92, 1.0, 0.9) if on else Color(0.22, 0.32, 0.4, 0.9).lerp(Color(0.6, 0.72, 0.82, 0.8), 0.35 * (1.0 - night)))
				var mx := x0
				while mx < x1:
					cv.draw_line(Vector2(mx, y2), Vector2(mx, y2 + shift * 0.52), wall.darkened(0.3), 1.0)
					mx += 6.0
		K.TOWER:
			cv.draw_polygon(PackedVector2Array([W.position, Vector2(W.end.x, W.position.y), W.end, Vector2(W.position.x, W.end.y)]),
				PackedColorArray([wall.lightened(0.25), wall.lightened(0.1), wall.darkened(0.25), wall.darkened(0.1)]))
			var mx2 := W.position.x + 4.0
			while mx2 < W.end.x:
				cv.draw_line(Vector2(mx2, W.position.y), Vector2(mx2, W.end.y), wall.lightened(0.32), 1.0)
				mx2 += 5.0
			for k in lv:
				var y3 := W.position.y + k * shift
				cv.draw_line(Vector2(W.position.x, y3), Vector2(W.end.x, y3), wall.darkened(0.35), 1.0)
				if night > 0.2:
					var lx := W.position.x + 2.0
					var m := 0
					while lx + 3.0 < W.end.x:
						if _lit(id, k * 131 + m, night, 0.35):
							cv.draw_rect(Rect2(Vector2(lx, y3 + 1.5), Vector2(3.0, shift - 3.0)), Color(0.85, 0.92, 1.0, 0.85))
						lx += 5.0
						m += 1
		K.WAREHOUSE:
			var cx := W.position.x
			while cx < W.end.x:
				cv.draw_line(Vector2(cx, W.position.y), Vector2(cx, W.end.y), wall.darkened(0.18), 1.0)
				cx += 3.0
			var dw := 12.0
			var dx := W.position.x + 6.0
			while dx + dw < W.end.x - 4.0:
				var dh := minf(W.size.y - 2.0, shift * 0.85)
				cv.draw_rect(Rect2(Vector2(dx, W.end.y - dh), Vector2(dw, dh)), wall.darkened(0.35))
				for q in 4:
					cv.draw_line(Vector2(dx, W.end.y - dh + q * dh / 4.0), Vector2(dx + dw, W.end.y - dh + q * dh / 4.0), wall.darkened(0.5), 1.0)
				dx += dw + 16.0
		K.FACTORY:
			_windows_row(cv, x0, x1, W.position.y + shift * 0.25, 5.0, shift * 0.4, 2.0, id, 0, night, true)
			var bd := minf(W.size.y - 2.0, shift * 1.2)
			cv.draw_rect(Rect2(Vector2(W.position.x + W.size.x * 0.4, W.end.y - bd), Vector2(minf(16.0, W.size.x * 0.25), bd)), wall.darkened(0.45))
		K.CIVIC:
			var cx2 := W.position.x + 3.0
			while cx2 < W.end.x - 2.0:
				cv.draw_rect(Rect2(Vector2(cx2, W.position.y + 2.0), Vector2(2.5, W.size.y - 4.0)), wall.lightened(0.22))
				cx2 += 6.0
			cv.draw_rect(Rect2(Vector2(W.position.x, W.end.y - 3.0), Vector2(W.size.x, 3.0)), wall.darkened(0.2))
		K.CHURCH:
			var cx3 := W.position.x + 5.0
			while cx3 < W.end.x - 4.0:
				var on2 := _lit(id, int(cx3), night, 0.7)
				cv.draw_rect(Rect2(Vector2(cx3, W.position.y + 2.0), Vector2(3.0, W.size.y - 5.0)), Color(1.0, 0.8, 0.45, 0.9) if on2 else Color(0.3, 0.35, 0.5, 0.85))
				cx3 += 9.0
		K.BARN:
			var px := W.position.x
			while px < W.end.x:
				cv.draw_line(Vector2(px, W.position.y), Vector2(px, W.end.y), wall.darkened(0.25), 1.0)
				px += 3.0
			var bw := minf(14.0, W.size.x * 0.4)
			var br := Rect2(Vector2(W.get_center().x - bw / 2.0, W.position.y + 1.0), Vector2(bw, W.size.y - 1.0))
			cv.draw_rect(br, wall.darkened(0.3))
			cv.draw_line(br.position, br.end, Color(0.9, 0.86, 0.8, 0.7), 1.0)
			cv.draw_line(Vector2(br.end.x, br.position.y), Vector2(br.position.x, br.end.y), Color(0.9, 0.86, 0.8, 0.7), 1.0)
		K.BUNKER:
			cv.draw_rect(Rect2(Vector2(x0 + 3.0, W.position.y + W.size.y * 0.35), Vector2(x1 - x0 - 6.0, 2.0)), Color(0.05, 0.05, 0.05, 0.9))
		K.HANGAR:
			var hd := Rect2(Vector2(W.position.x + W.size.x * 0.1, W.position.y + 1.0), Vector2(W.size.x * 0.8, W.size.y - 1.0))
			cv.draw_rect(hd, wall.darkened(0.3))
			var hx := hd.position.x
			while hx < hd.end.x:
				cv.draw_line(Vector2(hx, hd.position.y), Vector2(hx, hd.end.y), wall.darkened(0.5), 1.0)
				hx += 7.0
		_:
			for k in lv:
				_windows_row(cv, x0, x1, W.position.y + k * shift + shift * 0.3, 5.0, shift * 0.45, 3.0, id, k, night)


static func _pitched(cv: CanvasItem, RR: Rect2, roof: Color, ridge_h: bool) -> void:
	if ridge_h:
		var mid := RR.position.y + RR.size.y / 2.0
		cv.draw_rect(Rect2(RR.position, Vector2(RR.size.x, mid - RR.position.y)), roof.lightened(0.12))
		cv.draw_rect(Rect2(Vector2(RR.position.x, mid), Vector2(RR.size.x, RR.end.y - mid)), roof.darkened(0.16))
		cv.draw_line(Vector2(RR.position.x, mid), Vector2(RR.end.x, mid), roof.lightened(0.32), 1.5)
		var t := RR.position.x + 3.0
		while t < RR.end.x:
			cv.draw_line(Vector2(t, RR.position.y + 1.0), Vector2(t, mid - 1.0), roof.darkened(0.06), 1.0)
			cv.draw_line(Vector2(t, mid + 1.0), Vector2(t, RR.end.y - 1.0), roof.darkened(0.25), 1.0)
			t += 4.0
	else:
		var midx := RR.position.x + RR.size.x / 2.0
		cv.draw_rect(Rect2(RR.position, Vector2(midx - RR.position.x, RR.size.y)), roof.lightened(0.12))
		cv.draw_rect(Rect2(Vector2(midx, RR.position.y), Vector2(RR.end.x - midx, RR.size.y)), roof.darkened(0.16))
		cv.draw_line(Vector2(midx, RR.position.y), Vector2(midx, RR.end.y), roof.lightened(0.32), 1.5)
		var t2 := RR.position.y + 3.0
		while t2 < RR.end.y:
			cv.draw_line(Vector2(RR.position.x + 1.0, t2), Vector2(midx - 1.0, t2), roof.darkened(0.06), 1.0)
			cv.draw_line(Vector2(midx + 1.0, t2), Vector2(RR.end.x - 1.0, t2), roof.darkened(0.25), 1.0)
			t2 += 4.0


static func _box(cv: CanvasItem, r: Rect2, c: Color) -> void:
	cv.draw_rect(Rect2(r.position + Vector2(2, 2.5), r.size), Color(0, 0, 0, 0.3))
	cv.draw_rect(r, c)
	cv.draw_rect(r, c.darkened(0.35), false, 1.0)


static func _roof(cv: CanvasItem, kind: int, id: int, RR: Rect2, roof: Color, night: float) -> void:
	var ridge_h := RR.size.x >= RR.size.y
	match kind:
		K.HOUSE:
			_pitched(cv, RR, roof, ridge_h)
			var cp := RR.position + Vector2(RR.size.x * (0.25 + 0.5 * float(hv(id, 5) % 2)), RR.size.y * 0.3)
			_box(cv, Rect2(cp, Vector2(3.5, 3.5)), roof.darkened(0.3))
		K.ROWHOUSE:
			_pitched(cv, RR, roof, ridge_h)
			var unit := 2.0 * Arena.CELL * 2.4
			if ridge_h:
				var ux := RR.position.x + unit
				var k := 0
				while ux < RR.end.x - 2.0:
					cv.draw_line(Vector2(ux, RR.position.y), Vector2(ux, RR.end.y), roof.darkened(0.45), 1.5)
					if hv(id, 20 + k) % 3 == 0:
						cv.draw_rect(Rect2(Vector2(ux - unit, RR.position.y), Vector2(unit, RR.size.y)), Color(1, 1, 1, 0.05))
					ux += unit
					k += 1
			else:
				var uy := RR.position.y + unit
				while uy < RR.end.y - 2.0:
					cv.draw_line(Vector2(RR.position.x, uy), Vector2(RR.end.x, uy), roof.darkened(0.45), 1.5)
					uy += unit
		K.BARN:
			_pitched(cv, RR, roof, ridge_h)
			if ridge_h:
				var m := RR.get_center()
				cv.draw_rect(Rect2(m - Vector2(RR.size.x * 0.3, 1.5), Vector2(RR.size.x * 0.6, 3.0)), roof.darkened(0.35))
		K.CHURCH:
			_pitched(cv, RR, roof, ridge_h)
			# the steeple at one end
			var s := minf(RR.size.x, RR.size.y) * 0.55
			var sp := Vector2(RR.position.x + 2.0, RR.get_center().y - s / 2.0) if ridge_h else Vector2(RR.get_center().x - s / 2.0, RR.position.y + 2.0)
			var st := Rect2(sp - Vector2(0, 8), Vector2(s, s))
			cv.draw_rect(Rect2(st.position + Vector2(3, 4), st.size), Color(0, 0, 0, 0.35))
			cv.draw_rect(st, roof.lightened(0.2))
			cv.draw_line(st.position, st.end, roof.darkened(0.3), 1.0)
			cv.draw_line(Vector2(st.end.x, st.position.y), Vector2(st.position.x, st.end.y), roof.darkened(0.3), 1.0)
			var cc := st.get_center()
			cv.draw_line(cc - Vector2(0, 3), cc + Vector2(0, 3), Color(0.9, 0.85, 0.6), 1.2)
			cv.draw_line(cc - Vector2(2, 1), cc + Vector2(2, -1), Color(0.9, 0.85, 0.6), 1.2)
		K.SHOP:
			cv.draw_rect(RR, roof)
			cv.draw_rect(RR.grow(-2.0), roof.darkened(0.12), false, 1.0)
			_box(cv, Rect2(RR.position + Vector2(RR.size.x * 0.6, RR.size.y * 0.3), Vector2(6, 5)), roof.lightened(0.18))
		K.APARTMENT:
			cv.draw_rect(RR, roof)
			cv.draw_rect(RR.grow(-2.0), roof.darkened(0.15), false, 1.5)
			_box(cv, Rect2(RR.position + Vector2(RR.size.x * 0.2, RR.size.y * 0.25), Vector2(9, 7)), roof.lightened(0.15))
			var wt := RR.position + Vector2(RR.size.x * 0.72, RR.size.y * 0.55)
			cv.draw_circle(wt + Vector2(1.5, 2), 4.0, Color(0, 0, 0, 0.3))
			cv.draw_circle(wt, 4.0, roof.darkened(0.25))
			cv.draw_arc(wt, 4.0, 0, TAU, 12, roof.lightened(0.2), 1.0)
			for v in 2:
				cv.draw_rect(Rect2(RR.position + Vector2(RR.size.x * (0.45 + v * 0.12), RR.size.y * 0.7), Vector2(3, 3)), roof.darkened(0.35))
		K.OFFICE:
			cv.draw_rect(RR, roof)
			cv.draw_rect(RR.grow(-2.0), roof.darkened(0.2), false, 1.5)
			var n := clampi(int(RR.size.x / 14.0), 1, 4)
			for q in n:
				_box(cv, Rect2(RR.position + Vector2(5.0 + q * (RR.size.x - 10.0) / n, RR.size.y * 0.35), Vector2(7, 6)), roof.lightened(0.2))
		K.TOWER:
			cv.draw_rect(RR, roof)
			var inner := RR.grow(-minf(RR.size.x, RR.size.y) * 0.18)
			cv.draw_rect(Rect2(inner.position + Vector2(2, 3), inner.size), Color(0, 0, 0, 0.3))
			cv.draw_rect(inner, roof.lightened(0.28))
			cv.draw_rect(inner, roof.lightened(0.45), false, 1.0)
			if hv(id, 6) % 3 == 0 and inner.size.x > 22.0 and inner.size.y > 22.0:
				var hc := inner.get_center()
				var hr := minf(inner.size.x, inner.size.y) * 0.36
				cv.draw_circle(hc, hr, roof.darkened(0.1))
				cv.draw_arc(hc, hr, 0, TAU, 24, Color(0.92, 0.9, 0.84, 0.9), 1.5)
				cv.draw_line(hc + Vector2(-hr * 0.35, -hr * 0.45), hc + Vector2(-hr * 0.35, hr * 0.45), Color(0.92, 0.9, 0.84), 1.5)
				cv.draw_line(hc + Vector2(hr * 0.35, -hr * 0.45), hc + Vector2(hr * 0.35, hr * 0.45), Color(0.92, 0.9, 0.84), 1.5)
				cv.draw_line(hc + Vector2(-hr * 0.35, 0), hc + Vector2(hr * 0.35, 0), Color(0.92, 0.9, 0.84), 1.5)
			else:
				_box(cv, Rect2(inner.get_center() - Vector2(5, 4), Vector2(10, 8)), roof.lightened(0.4))
			var mast := inner.position + Vector2(4, 4)
			cv.draw_line(mast, mast + Vector2(0, -6), roof.lightened(0.5), 1.0)
			cv.draw_circle(mast + Vector2(0, -6), 1.6, Color(1.0, 0.2, 0.15, 0.6 + 0.4 * night))
		K.WAREHOUSE:
			cv.draw_rect(RR, roof)
			if ridge_h:
				var t := RR.position.x + 1.5
				while t < RR.end.x:
					cv.draw_line(Vector2(t, RR.position.y), Vector2(t, RR.end.y), roof.darkened(0.12), 1.0)
					t += 3.0
				cv.draw_rect(Rect2(Vector2(RR.position.x + 4.0, RR.get_center().y - 2.0), Vector2(RR.size.x - 8.0, 4.0)), Color(0.75, 0.85, 0.9, 0.55).darkened(night * 0.6))
			else:
				var t2 := RR.position.y + 1.5
				while t2 < RR.end.y:
					cv.draw_line(Vector2(RR.position.x, t2), Vector2(RR.end.x, t2), roof.darkened(0.12), 1.0)
					t2 += 3.0
				cv.draw_rect(Rect2(Vector2(RR.get_center().x - 2.0, RR.position.y + 4.0), Vector2(4.0, RR.size.y - 8.0)), Color(0.75, 0.85, 0.9, 0.55).darkened(night * 0.6))
		K.FACTORY:
			cv.draw_rect(RR, roof)
			# a sawtooth roof: glazed north lights between the solid slopes
			var step := 8.0
			if ridge_h:
				var t3 := RR.position.x
				while t3 < RR.end.x - 2.0:
					cv.draw_rect(Rect2(Vector2(t3, RR.position.y), Vector2(3.0, RR.size.y)), Color(0.7, 0.8, 0.86, 0.75).darkened(night * 0.5) if night < 0.2 else Color(1.0, 0.75, 0.4, 0.7))
					cv.draw_line(Vector2(t3 + step - 0.5, RR.position.y), Vector2(t3 + step - 0.5, RR.end.y), roof.darkened(0.35), 1.0)
					t3 += step
			else:
				var t4 := RR.position.y
				while t4 < RR.end.y - 2.0:
					cv.draw_rect(Rect2(Vector2(RR.position.x, t4), Vector2(RR.size.x, 3.0)), Color(0.7, 0.8, 0.86, 0.75).darkened(night * 0.5) if night < 0.2 else Color(1.0, 0.75, 0.4, 0.7))
					cv.draw_line(Vector2(RR.position.x, t4 + step - 0.5), Vector2(RR.end.x, t4 + step - 0.5), roof.darkened(0.35), 1.0)
					t4 += step
			for q in 1 + hv(id, 7) % 2:
				var sc := RR.end - Vector2(7.0 + q * 11.0, 7.0)
				cv.draw_circle(sc + Vector2(2, 3), 4.5, Color(0, 0, 0, 0.35))
				cv.draw_circle(sc, 4.5, Color(0.42, 0.3, 0.26).darkened(night * 0.4))
				cv.draw_circle(sc, 2.4, Color(0.06, 0.05, 0.05))
		K.CIVIC:
			cv.draw_rect(RR, roof)
			cv.draw_rect(RR.grow(-3.0), roof.lightened(0.12), false, 2.0)
			var dc := RR.get_center()
			var dr := minf(RR.size.x, RR.size.y) * 0.3
			cv.draw_circle(dc + Vector2(3, 4), dr, Color(0, 0, 0, 0.35))
			for q in 5:
				var f := 1.0 - q / 5.0
				cv.draw_circle(dc - Vector2(dr, dr) * 0.12 * (1.0 - f), dr * f, Color(0.42, 0.56, 0.52).lerp(Color(0.72, 0.84, 0.78), 1.0 - f).darkened(night * 0.45))
			cv.draw_arc(dc, dr, 0, TAU, 24, roof.darkened(0.3), 1.0)
			cv.draw_circle(dc, 2.0, Color(0.9, 0.82, 0.5))
		K.BUNKER:
			cv.draw_rect(RR, roof)
			cv.draw_rect(RR.grow(-2.0), roof.lightened(0.12), false, 2.0)
			cv.draw_circle(RR.get_center(), 3.5, roof.darkened(0.35))
			cv.draw_arc(RR.get_center(), 3.5, 0, TAU, 12, roof.lightened(0.2), 1.0)
		K.HANGAR:
			# a barrel vault along the long side: bright crown, darker flanks, ribs
			var bands := 6
			for q in bands:
				var f2 := float(q) / bands
				var shade := roof.lightened(0.22 - absf(f2 - 0.35) * 0.55)
				if ridge_h:
					cv.draw_rect(Rect2(Vector2(RR.position.x, RR.position.y + f2 * RR.size.y), Vector2(RR.size.x, RR.size.y / bands + 0.5)), shade)
				else:
					cv.draw_rect(Rect2(Vector2(RR.position.x + f2 * RR.size.x, RR.position.y), Vector2(RR.size.x / bands + 0.5, RR.size.y)), shade)
			if ridge_h:
				var t5 := RR.position.x + 6.0
				while t5 < RR.end.x:
					cv.draw_line(Vector2(t5, RR.position.y), Vector2(t5, RR.end.y), roof.darkened(0.3), 1.0)
					t5 += 8.0
			else:
				var t6 := RR.position.y + 6.0
				while t6 < RR.end.y:
					cv.draw_line(Vector2(RR.position.x, t6), Vector2(RR.end.x, t6), roof.darkened(0.3), 1.0)
					t6 += 8.0
		_:
			cv.draw_rect(RR, roof)


static func _cylinder(cv: CanvasItem, kind: int, id: int, R: Rect2, hs: float, wall: Color, roof: Color, night: float) -> void:
	var c := R.get_center()
	var rad := minf(R.size.x, R.size.y) * 0.46
	var top := c - Vector2(0, hs)
	# ground shadow, then the body as a lit-to-shaded band, then the round top
	cv.draw_circle(c + Vector2(4, 5), rad, Color(0, 0, 0, 0.3))
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var n := 14
	for k in n + 1:
		var a2 := PI - PI * k / n
		pts.append(Vector2(c.x + cos(a2) * rad, top.y))
		cols.append(wall.lightened(0.18).lerp(wall.darkened(0.35), float(k) / n))
	for k in n + 1:
		var a3 := PI * k / n
		pts.append(Vector2(c.x + cos(a3) * rad, c.y + sin(a3) * rad * 0.55))
		cols.append(wall.darkened(0.35).lerp(wall.lightened(0.18), float(k) / n))
	cv.draw_polygon(pts, cols)
	for q in 3:
		var yy := top.y + (c.y - top.y) * (q + 1) / 4.0
		cv.draw_line(Vector2(c.x - rad, yy), Vector2(c.x + rad, yy), wall.darkened(0.2), 1.0)
	cv.draw_circle(top, rad, roof)
	cv.draw_arc(top, rad, 0, TAU, 24, roof.darkened(0.3), 1.2)
	if kind == K.SILO:
		cv.draw_circle(top - Vector2(rad, rad) * 0.25, rad * 0.45, roof.lightened(0.2))
	else:
		cv.draw_arc(top, rad * 0.62, 0, TAU, 20, roof.darkened(0.12), 1.0)
		cv.draw_circle(top, 2.2, roof.darkened(0.4))
		# a ladder down the side
		cv.draw_line(Vector2(c.x + rad * 0.7, top.y + 2.0), Vector2(c.x + rad * 0.7, c.y), wall.darkened(0.45), 1.0)


# ------------------------------------------------------------------ the street layer

static func draw_streets(cv: CanvasItem, a: Arena, terrain: PackedByteArray, cell: float, night: float) -> void:
	var w := a.w
	var h := a.h
	var n := w * h
	var road := PackedByteArray()
	road.resize(n)
	for i in n:
		road[i] = 1 if (a.zone[i] == Z.ROAD or a.zone[i] == Z.AVENUE) and terrain[i] == Arena.T.PAVEMENT else 0
	# which road cells are in town: near buildings or built-up ground (country roads get no curbs)
	var town := PackedByteArray()
	town.resize(n)
	for i in n:
		var zz := int(a.zone[i])
		if terrain[i] == Arena.T.BUILDING or zz in [Z.YARD, Z.PLAZA, Z.PARKING, Z.LOT, Z.PARK, Z.AVENUE]:
			town[i] = 1
	for _pass in 3:
		var grown := town.duplicate()
		for y in h:
			for x in w:
				var i := a.idx(x, y)
				if town[i] == 1:
					continue
				for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if a.inside(nx, ny) and town[a.idx(nx, ny)] == 1:
						grown[i] = 1
						break
		town = grown
	# run lengths across each road cell: how wide the street is here in x and in y
	var hrun := PackedInt32Array()
	var vrun := PackedInt32Array()
	hrun.resize(n)
	vrun.resize(n)
	for y in h:
		var x := 0
		while x < w:
			if road[a.idx(x, y)] == 0:
				x += 1
				continue
			var s := x
			while x < w and road[a.idx(x, y)] == 1:
				x += 1
			for k in range(s, x):
				hrun[a.idx(k, y)] = (x - s) | (s << 16)
	for x in w:
		var y := 0
		while y < h:
			if road[a.idx(x, y)] == 0:
				y += 1
				continue
			var s2 := y
			while y < h and road[a.idx(x, y)] == 1:
				y += 1
			for k in range(s2, y):
				vrun[a.idx(x, k)] = (y - s2) | (s2 << 16)
	var walk := Color(0.6, 0.6, 0.58, 0.85).darkened(night * 0.5)
	var curb := Color(0.78, 0.78, 0.74, 0.9).darkened(night * 0.5)
	var paint := Color(0.92, 0.92, 0.88, 0.6).darkened(night * 0.3)
	var yellow := Color(0.95, 0.78, 0.25, 0.7).darkened(night * 0.3)
	var sw := cell * 0.2
	var lamps: Array = []
	for y in h:
		for x in w:
			var i := a.idx(x, y)
			var z := int(a.zone[i])
			var p := Vector2(x, y) * cell
			if road[i] == 1:
				var hl := hrun[i] & 0xffff
				var vl := vrun[i] & 0xffff
				var hs0 := hrun[i] >> 16
				var vs0 := vrun[i] >> 16
				var avenue := z == Z.AVENUE
				var in_town := town[i] == 1
				# sidewalks and curbs where the street meets the blocks
				for o in ([Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)] if in_town else []):
					var nx: int = x + o.x
					var ny: int = y + o.y
					if not a.inside(nx, ny):
						continue
					var j := a.idx(nx, ny)
					if road[j] == 1 or terrain[j] == Arena.T.WATER:
						continue
					var sr := Rect2()
					var cl := PackedVector2Array()
					match o:
						Vector2i(0, -1):
							sr = Rect2(p, Vector2(cell, sw))
							cl = PackedVector2Array([p + Vector2(0, sw), p + Vector2(cell, sw)])
						Vector2i(0, 1):
							sr = Rect2(p + Vector2(0, cell - sw), Vector2(cell, sw))
							cl = PackedVector2Array([p + Vector2(0, cell - sw), p + Vector2(cell, cell - sw)])
						Vector2i(-1, 0):
							sr = Rect2(p, Vector2(sw, cell))
							cl = PackedVector2Array([p + Vector2(sw, 0), p + Vector2(sw, cell)])
						Vector2i(1, 0):
							sr = Rect2(p + Vector2(cell - sw, 0), Vector2(sw, cell))
							cl = PackedVector2Array([p + Vector2(cell - sw, 0), p + Vector2(cell - sw, cell)])
					cv.draw_rect(sr, walk)
					cv.draw_line(cl[0], cl[1], curb, 1.2)
					if (x + y) % 4 == 0:
						lamps.append(sr.get_center())
				# lane lines down the middle of streets two or three cells wide
				if hl <= 3 and vl > 3:
					var cx := (hs0 + hl / 2.0) * cell
					if x == hs0 + hl / 2 - (1 if hl % 2 == 0 else 0):
						if avenue:
							cv.draw_line(Vector2(cx - 1.5, p.y), Vector2(cx - 1.5, p.y + cell), yellow, 1.2)
							cv.draw_line(Vector2(cx + 1.5, p.y), Vector2(cx + 1.5, p.y + cell), yellow, 1.2)
						else:
							cv.draw_line(Vector2(cx, p.y + cell * 0.15), Vector2(cx, p.y + cell * 0.6), paint, 1.5)
					# a crosswalk where this street opens onto a crossing
					for dy in ([-1, 1] if in_town else []):
						var ny2: int = y + dy
						if a.inside(x, ny2) and road[a.idx(x, ny2)] == 1 and (hrun[a.idx(x, ny2)] & 0xffff) > 3:
							var zy := p.y if dy < 0 else p.y + cell - 5.0
							var q := p.x + 2.0
							while q < p.x + cell - 2.0:
								cv.draw_rect(Rect2(Vector2(q, zy + 0.5), Vector2(2.5, 4.0)), paint)
								q += 5.0
				elif vl <= 3 and hl > 3:
					var cy := (vs0 + vl / 2.0) * cell
					if y == vs0 + vl / 2 - (1 if vl % 2 == 0 else 0):
						if avenue:
							cv.draw_line(Vector2(p.x, cy - 1.5), Vector2(p.x + cell, cy - 1.5), yellow, 1.2)
							cv.draw_line(Vector2(p.x, cy + 1.5), Vector2(p.x + cell, cy + 1.5), yellow, 1.2)
						else:
							cv.draw_line(Vector2(p.x + cell * 0.15, cy), Vector2(p.x + cell * 0.6, cy), paint, 1.5)
					for dx in ([-1, 1] if in_town else []):
						var nx2: int = x + dx
						if a.inside(nx2, y) and road[a.idx(nx2, y)] == 1 and (vrun[a.idx(nx2, y)] & 0xffff) > 3:
							var zx := p.x if dx < 0 else p.x + cell - 5.0
							var q2 := p.y + 2.0
							while q2 < p.y + cell - 2.0:
								cv.draw_rect(Rect2(Vector2(zx + 0.5, q2), Vector2(4.0, 2.5)), paint)
								q2 += 5.0
				continue
			match z:
				Z.PLAZA:
					cv.draw_rect(Rect2(p, Vector2(cell, cell)), Color(0.66, 0.63, 0.57, 0.85).darkened(night * 0.5))
					cv.draw_line(p + Vector2(cell * 0.5, 0), p + Vector2(cell * 0.5, cell), Color(0.5, 0.48, 0.44, 0.5), 1.0)
					cv.draw_line(p + Vector2(0, cell * 0.5), p + Vector2(cell, cell * 0.5), Color(0.5, 0.48, 0.44, 0.5), 1.0)
				Z.LOT:
					cv.draw_rect(Rect2(p, Vector2(cell, cell)), Color(0.52, 0.51, 0.48, 0.55).darkened(night * 0.5))
					cv.draw_rect(Rect2(p, Vector2(cell, cell)), Color(0.3, 0.29, 0.27, 0.35), false, 1.0)
					if absi(hash(i * 31)) % 9 == 0:
						cv.draw_circle(p + Vector2(cell * 0.6, cell * 0.4), cell * 0.18, Color(0.15, 0.14, 0.13, 0.3))
				Z.PARKING:
					cv.draw_rect(Rect2(p, Vector2(cell, cell)), Color(0.24, 0.24, 0.26, 0.6).darkened(night * 0.4))
					var px := p.x + 2.0
					while px < p.x + cell:
						cv.draw_line(Vector2(px, p.y + 1.0), Vector2(px, p.y + cell * 0.42), paint, 1.0)
						cv.draw_line(Vector2(px, p.y + cell * 0.58), Vector2(px, p.y + cell - 1.0), paint, 1.0)
						px += cell / 3.0
					# the odd parked car
					if absi(hash(i * 17)) % 3 == 0:
						var cc: Color = [Color(0.7, 0.15, 0.12), Color(0.85, 0.85, 0.82), Color(0.18, 0.22, 0.3), Color(0.3, 0.32, 0.3)][absi(hash(i)) % 4]
						cv.draw_rect(Rect2(p + Vector2(cell * 0.38, 2.0), Vector2(cell / 3.0 - 3.0, cell * 0.36)), (cc as Color).darkened(night * 0.5))
				Z.YARD:
					# hedges along the street side of gardens
					for o2 in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
						var nx3: int = x + o2.x
						var ny3: int = y + o2.y
						if a.inside(nx3, ny3) and road[a.idx(nx3, ny3)] == 1:
							var e0 := p + Vector2(maxf(0.0, o2.x) * cell, maxf(0.0, o2.y) * cell)
							var e1 := e0 + (Vector2(0, cell) if o2.x != 0 else Vector2(cell, 0))
							var inset := Vector2(-o2.x, -o2.y) * 1.5
							cv.draw_line(e0 + inset, e1 + inset, Color(0.16, 0.3, 0.14, 0.9).darkened(night * 0.5), 3.0)
				Z.PARK:
					if terrain[i] == Arena.T.CLEAR and (x + y) % 2 == 0 and absi(hash(i * 13)) % 3 == 0:
						cv.draw_line(p + Vector2(0, cell * 0.5), p + Vector2(cell, cell * 0.5), Color(0.72, 0.66, 0.52, 0.55).darkened(night * 0.5), 3.0)
	# fountains in the middle of each plaza
	var seen := {}
	for i2 in n:
		if a.zone[i2] != Z.PLAZA or seen.has(i2):
			continue
		var q3: Array = [i2]
		seen[i2] = true
		var sum := Vector2.ZERO
		var cnt := 0
		while not q3.is_empty():
			var c: int = q3.pop_back()
			sum += Vector2(c % w, c / w)
			cnt += 1
			for o3 in [1, -1, w, -w]:
				var j2: int = c + o3
				if j2 >= 0 and j2 < n and not seen.has(j2) and a.zone[j2] == Z.PLAZA and absi((j2 % w) - (c % w)) <= 1:
					seen[j2] = true
					q3.append(j2)
		if cnt >= 12:
			var fc := (sum / cnt + Vector2(0.5, 0.5)) * cell
			var fci := a.idx(int(fc.x / cell), int(fc.y / cell))
			if terrain[fci] != Arena.T.BUILDING:
				cv.draw_circle(fc, cell * 0.55, Color(0.55, 0.53, 0.5).darkened(night * 0.5))
				cv.draw_circle(fc, cell * 0.45, Color(0.25, 0.45, 0.55).darkened(night * 0.5))
				cv.draw_circle(fc, cell * 0.12, Color(0.75, 0.85, 0.9, 0.8).darkened(night * 0.4))
	# street lights: posts by day, pools of light at night
	for lp in lamps:
		var lv2: Vector2 = lp
		if night > 0.15:
			cv.draw_circle(lv2, cell * 0.55, Color(1.0, 0.85, 0.55, 0.07 * night))
			cv.draw_circle(lv2, cell * 0.25, Color(1.0, 0.85, 0.55, 0.12 * night))
		cv.draw_circle(lv2, 1.4, Color(1.0, 0.92, 0.7, 0.9) if night > 0.15 else Color(0.3, 0.3, 0.3, 0.8))
