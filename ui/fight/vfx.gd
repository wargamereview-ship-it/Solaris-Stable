class_name Vfx
extends RefCounted
## Battle effects shared by the arena viewer and the command view. Effects are plain dictionaries in
## the viewer's fx list ({"type": "pfx", "kind", "t", "pos", ...}) drawn for the playback time, and
## every random choice is seeded from the event, so a replay shows exactly the same effects.
## Two passes: draw_normal (debris, smoke, dust, shock rings) on the normal layer, draw_glow (fire,
## flashes, sparks, beams, muzzle flashes) on an additive layer.

const PX := 2.4
const GRAVITY := 520.0


static func _seed(t: float, salt: int) -> int:
	return int(t * 1000.0) * 31 + salt * 7919


## A full explosion: flash, fireball, shock ring, flying debris, sparks and a smoke plume.
static func explosion(fx: Array, t: float, pos: Vector2, size: float, salt: int, debris_col := Color(0.22, 0.21, 0.2)) -> void:
	var r := SimRng.new(_seed(t, salt))
	var s := size / 60.0
	fx.append({"type": "pfx", "kind": "flash", "t": t, "pos": pos, "r": size * 2.4, "life": 0.22})
	fx.append({"type": "pfx", "kind": "fireball", "t": t, "pos": pos, "r": size, "life": 0.95})
	fx.append({"type": "pfx", "kind": "shock", "t": t, "pos": pos, "r": size * 1.9, "life": 0.55})
	var parts: Array = []
	for k in int(10 + 14 * s):
		parts.append([Vector2.from_angle(r.randf() * TAU) * r.randf_range(50.0, 190.0) * s, r.randf_range(90.0, 260.0) * sqrt(s), r.randf_range(2.0, 5.5) * sqrt(s), r.randf_range(-12.0, 12.0)])
	fx.append({"type": "pfx", "kind": "debris", "t": t, "pos": pos, "parts": parts, "col": debris_col, "life": 2.2})
	var sparks: Array = []
	for k in int(12 + 10 * s):
		sparks.append([Vector2.from_angle(r.randf() * TAU), r.randf_range(160.0, 420.0) * s, r.randf_range(0.25, 0.7)])
	fx.append({"type": "pfx", "kind": "sparks", "t": t, "pos": pos, "parts": sparks, "life": 0.75})
	var puffs: Array = []
	for k in int(6 + 6 * s):
		puffs.append([Vector2(r.randf_range(-0.5, 0.5), r.randf_range(-0.5, 0.5)) * size, Vector2(r.randf_range(-14.0, 14.0), r.randf_range(-34.0, -12.0)), r.randf_range(0.35, 0.6) * size, r.randf_range(0.8, 1.3) * size, r.randf_range(0.0, 0.25), r.randf_range(0.1, 0.22)])
	fx.append({"type": "pfx", "kind": "puffs", "t": t + 0.12, "pos": pos, "parts": puffs, "life": 4.2})


## Dust kicked up by a fall, a charge or a building coming down.
static func dust(fx: Array, t: float, pos: Vector2, size: float, salt: int, col := Color(0.62, 0.56, 0.44)) -> void:
	var r := SimRng.new(_seed(t, salt))
	var puffs: Array = []
	for k in 8:
		var a := r.randf() * TAU
		puffs.append([Vector2.from_angle(a) * size * 0.3, Vector2.from_angle(a) * r.randf_range(20.0, 55.0), size * 0.35, size * r.randf_range(0.7, 1.0), r.randf_range(0.0, 0.1), r.randf_range(0.5, 0.65)])
	fx.append({"type": "pfx", "kind": "puffs", "t": t, "pos": pos, "parts": puffs, "life": 1.8, "col": col})


## Chunks of concrete and a dust cloud for a collapsing building.
static func collapse(fx: Array, t: float, pos: Vector2, salt: int) -> void:
	dust(fx, t, pos, 70.0, salt, Color(0.6, 0.58, 0.54))
	var r := SimRng.new(_seed(t, salt + 5))
	var parts: Array = []
	for k in 18:
		parts.append([Vector2.from_angle(r.randf() * TAU) * r.randf_range(30.0, 120.0), r.randf_range(60.0, 180.0), r.randf_range(2.5, 6.0), r.randf_range(-8.0, 8.0)])
	fx.append({"type": "pfx", "kind": "debris", "t": t, "pos": pos, "parts": parts, "col": Color(0.5, 0.48, 0.45), "life": 2.0})


## Sparks where a shot strikes armor.
static func impact(fx: Array, t: float, pos: Vector2, dir: Vector2, salt: int, energy := false) -> void:
	var r := SimRng.new(_seed(t, salt))
	var sparks: Array = []
	for k in 7:
		var a := dir.angle() + PI + r.randf_range(-1.1, 1.1)
		sparks.append([Vector2.from_angle(a), r.randf_range(120.0, 300.0), r.randf_range(0.12, 0.3)])
	fx.append({"type": "pfx", "kind": "sparks", "t": t, "pos": pos, "parts": sparks, "life": 0.35, "energy": energy})
	fx.append({"type": "pfx", "kind": "flash", "t": t, "pos": pos, "r": 26.0 if energy else 18.0, "life": 0.12})


static func muzzle(fx: Array, t: float, pos: Vector2, dir: Vector2, wt: String) -> void:
	var col := Color(1.0, 0.82, 0.45)
	var size := 16.0
	match wt:
		"laser":
			col = Color(1.0, 0.3, 0.25)
			size = 10.0
		"pulse":
			col = Color(1.0, 0.8, 0.3)
			size = 10.0
		"ppc":
			col = Color(0.5, 0.75, 1.0)
			size = 20.0
		"gauss", "lgauss", "hgauss":
			col = Color(0.7, 0.85, 1.0)
			size = 14.0
		"lrm", "srm", "mrm", "atm", "mml", "streak_srm", "streak_lrm":
			col = Color(1.0, 0.7, 0.35)
			size = 18.0
	fx.append({"type": "pfx", "kind": "muzzle", "t": t, "pos": pos + dir * 14.0, "dir": dir, "col": col, "r": size, "life": 0.1})


## A wreck that burns for a while and smolders after.
static func wreck_fire(fx: Array, t: float, pos: Vector2) -> void:
	fx.append({"type": "pfx", "kind": "wreckfire", "t": t, "pos": pos, "life": 40.0})


## Draws one effect on the normal layer. Returns false once it's over.
static func draw_normal(cv: CanvasItem, f: Dictionary, age: float) -> bool:
	var life := float(f.get("life", 1.0))
	if age > life:
		return false
	var k := age / life
	var pos: Vector2 = f["pos"]
	match str(f["kind"]):
		"debris":
			var col: Color = f["col"]
			for p in f["parts"]:
				var vxy: Vector2 = p[0]
				var vz: float = p[1]
				var tl := 2.0 * vz / GRAVITY
				var a := minf(age, tl)
				var z := maxf(0.0, vz * a - 0.5 * GRAVITY * a * a)
				var q := pos + vxy * a * (1.0 if age < tl else 1.0) - Vector2(0, z)
				var s: float = p[2]
				var alpha := clampf((life - age) / (life * 0.35), 0.0, 1.0)
				var rot: float = float(p[3]) * a
				var pts := PackedVector2Array([q + Vector2(-s, -s * 0.6).rotated(rot), q + Vector2(s, -s * 0.3).rotated(rot), q + Vector2(s * 0.4, s * 0.8).rotated(rot)])
				if z > 1.0:
					cv.draw_circle(q + Vector2(z * 0.25, z * 0.6), s * 0.6, Color(0, 0, 0, 0.18 * alpha))
				cv.draw_colored_polygon(pts, Color(col.r, col.g, col.b, alpha))
		"puffs":
			var base: Color = f.get("col", Color(0.18, 0.18, 0.18))
			for p in f["parts"]:
				var d: float = float(p[4])
				var a2 := age - d
				if a2 < 0.0:
					continue
				var kk := clampf(a2 / (life - d), 0.0, 1.0)
				var ease := 1.0 - pow(1.0 - kk, 3.0)
				var q2: Vector2 = pos + (p[0] as Vector2) + (p[1] as Vector2) * a2
				var rr: float = lerpf(float(p[2]), float(p[3]), ease)
				var g: float = float(p[5])
				var c := Color(base.r + g * 0.3, base.g + g * 0.3, base.b + g * 0.3, 0.42 * (1.0 - kk))
				if f.has("col"):
					c = Color(base.r, base.g, base.b, 0.38 * (1.0 - kk))
				cv.draw_circle(q2, rr, c)
		"shock":
			var rr2: float = float(f["r"]) * (1.0 - pow(1.0 - k, 2.0))
			cv.draw_arc(pos, rr2, 0, TAU, 40, Color(0.95, 0.9, 0.8, 0.45 * (1.0 - k)), 6.0 * (1.0 - k) + 1.0, true)
		"wreckfire":
			# a smoke column that thins out over the wreck's life
			var n := 7
			var strength := clampf(1.0 - age / life, 0.0, 1.0)
			for i in n:
				var ph := fmod(age * 0.45 + float(i) / n, 1.0)
				var sway := sin(age * 0.7 + i * 1.9) * 10.0
				var q3 := pos + Vector2(sway + ph * 26.0, -ph * 150.0)
				cv.draw_circle(q3, 12.0 + ph * 34.0, Color(0.1, 0.1, 0.1, 0.3 * (1.0 - ph) * (0.35 + 0.65 * strength)))
		_:
			pass
	return true


## Draws one effect on the additive glow layer.
static func draw_glow(cv: CanvasItem, f: Dictionary, age: float) -> void:
	if age < 0.0:
		return
	var life := float(f.get("life", 1.0))
	if age > life:
		return
	var k := age / life
	var pos: Vector2 = f["pos"]
	match str(f["kind"]):
		"flash":
			var r: float = float(f["r"]) * (0.6 + 0.4 * k)
			cv.draw_circle(pos, r, Color(1.0, 0.85, 0.55, 0.32 * (1.0 - k)))
			cv.draw_circle(pos, r * 0.4, Color(1.0, 0.95, 0.8, 0.55 * (1.0 - k)))
		"fireball":
			var r2: float = float(f["r"]) * (0.45 + 0.75 * sqrt(k))
			cv.draw_circle(pos, r2, Color(0.9, 0.35, 0.05, 0.55 * (1.0 - k)))
			cv.draw_circle(pos, r2 * 0.68, Color(1.0, 0.6, 0.15, 0.6 * (1.0 - k)))
			cv.draw_circle(pos, r2 * 0.36 * (1.0 - k * 0.6), Color(1.0, 0.92, 0.7, 0.8 * (1.0 - k)))
		"sparks":
			var energy := bool(f.get("energy", false))
			for p in f["parts"]:
				var lt: float = float(p[2])
				if age > lt:
					continue
				var kk := age / lt
				var dir: Vector2 = p[0]
				var sp: float = float(p[1])
				var head := pos + dir * sp * age + Vector2(0, 90.0 * age * age)
				var tail := head - dir * (10.0 + sp * 0.03)
				var c := Color(1.0, 0.85 - kk * 0.4, 0.4 - kk * 0.3, 1.0 - kk) if not energy else Color(1.0, 0.6, 0.5, 1.0 - kk)
				cv.draw_line(tail, head, c, 2.0)
		"muzzle":
			var dir2: Vector2 = f["dir"]
			var col: Color = f["col"]
			var s: float = float(f["r"]) * (1.0 - k * 0.5)
			var side := dir2.orthogonal() * s * 0.35
			cv.draw_colored_polygon(PackedVector2Array([pos - side, pos + dir2 * s * 1.6, pos + side]), Color(col.r, col.g, col.b, 0.85 * (1.0 - k)))
			cv.draw_circle(pos, s * 0.55, Color(col.r, col.g, col.b, 0.5 * (1.0 - k)))
		"wreckfire":
			var strength := clampf(1.0 - age / (life * 0.6), 0.0, 1.0)
			if strength <= 0.0:
				return
			for i in 6:
				var fl := sin(age * (8.0 + i) + i * 2.1) * 0.5 + 0.5
				var off := Vector2(sin(i * 2.4) * 12.0, cos(i * 1.7) * 9.0 - fl * 6.0)
				cv.draw_circle(pos + off, (8.0 + fl * 7.0) * strength, Color(1.0, 0.45 + fl * 0.25, 0.08, 0.5 * strength))
			cv.draw_circle(pos, 40.0 * strength, Color(0.6, 0.22, 0.03, 0.22 * strength))


## Smoke streaming from a badly damaged unit and a heat shimmer around one running hot.
static func unit_effects(normal: CanvasItem, glow: CanvasItem, pos: Vector2, dmg: float, heat: float, t: float, idx: int) -> void:
	if dmg > 0.3:
		var n := 3 + int(dmg * 5.0)
		for i in n:
			var ph := fmod(t * 0.8 + float(i) / n + idx * 0.37, 1.0)
			var q := pos + Vector2(sin(t * 1.3 + i * 2.0 + idx) * 6.0 + ph * 20.0, -ph * 70.0 - 6.0)
			normal.draw_circle(q, 6.0 + ph * 16.0, Color(0.12, 0.12, 0.12, 0.33 * (1.0 - ph) * clampf(dmg * 1.6, 0.0, 1.0)))
	if heat >= 11.0:
		var pulse := 0.6 + 0.4 * sin(t * 6.0 + idx)
		var a := clampf((heat - 10.0) / 14.0, 0.0, 1.0)
		glow.draw_circle(pos, 30.0, Color(0.6, 0.12, 0.02, 0.2 * a * pulse))
		glow.draw_arc(pos, 26.0 + pulse * 3.0, 0, TAU, 32, Color(1.0, 0.35, 0.1, 0.3 * a * pulse), 2.0, true)


## A small two-part bar under a unit: armor on top, structure below.
static func health_bar(cv: CanvasItem, pos: Vector2, armor: float, structure: float, col: Color, w := 40.0) -> void:
	var p := pos + Vector2(-w / 2.0, 0)
	cv.draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, 7)), Color(0, 0, 0, 0.65))
	cv.draw_rect(Rect2(p, Vector2(w * clampf(armor, 0.0, 1.0), 3)), UI.frac_color(armor))
	cv.draw_rect(Rect2(p + Vector2(0, 3), Vector2(w * clampf(structure, 0.0, 1.0), 2)), Color(0.9, 0.9, 0.92, 0.85) if structure > 0.6 else UI.BAD)
	cv.draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, 7)), Color(col.r, col.g, col.b, 0.5), false, 1.0)
