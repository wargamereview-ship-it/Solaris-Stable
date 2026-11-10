class_name Settlement
extends RefCounted
## Settlements laid out the way places grow: villages strung along a road, towns around a square
## and a main street, cities on a street grid whose downtown towers thin out through apartment
## blocks to houses (with an industrial quarter, parks and parking), stand-alone industrial parks
## (warehouses, factory halls, tank farms) and military compounds.
## Every building gets an id (Arena.bld_id), a type (Arena.bld_kind) and a construction factor in
## the Total Warfare class bands: Light up to 15, Medium up to 40, Heavy up to 90, Hardened up to
## 150. What the open ground is used for (streets, plazas, parking, yards, parks, industrial lots)
## goes in Arena.zone for the viewer. Deterministic: everything comes from the SimRng passed in.

enum K { NONE, HOUSE, ROWHOUSE, SHOP, APARTMENT, OFFICE, TOWER, WAREHOUSE, FACTORY, TANK, CIVIC, CHURCH, BARN, SILO, BUNKER, HANGAR }
enum Z { NONE, ROAD, AVENUE, PLAZA, PARKING, YARD, PARK, LOT }

# levels min/max, construction factor min/max
const SPEC := {
	K.NONE: [1, 3, 20, 36],
	K.HOUSE: [1, 1, 8, 15],
	K.ROWHOUSE: [1, 2, 12, 20],
	K.SHOP: [1, 2, 18, 30],
	K.APARTMENT: [2, 4, 30, 45],
	K.OFFICE: [3, 5, 45, 65],
	K.TOWER: [5, 8, 70, 90],
	K.WAREHOUSE: [1, 2, 25, 40],
	K.FACTORY: [2, 3, 55, 80],
	K.TANK: [1, 2, 20, 30],
	K.CIVIC: [2, 3, 95, 120],
	K.CHURCH: [2, 3, 40, 60],
	K.BARN: [1, 1, 8, 12],
	K.SILO: [2, 3, 15, 25],
	K.BUNKER: [1, 1, 110, 150],
	K.HANGAR: [2, 2, 60, 90],
}
const NAMES := {K.NONE: "building", K.HOUSE: "house", K.ROWHOUSE: "row house", K.SHOP: "shop", K.APARTMENT: "apartment block",
	K.OFFICE: "office block", K.TOWER: "tower", K.WAREHOUSE: "warehouse", K.FACTORY: "factory hall", K.TANK: "storage tank",
	K.CIVIC: "civic hall", K.CHURCH: "church", K.BARN: "barn", K.SILO: "silo", K.BUNKER: "bunker", K.HANGAR: "hangar"}


# ------------------------------------------------------------------ primitives

static func new_id(a: Arena) -> int:
	a.next_bld_id += 1
	return a.next_bld_id


## A building of `kind` on the cells of r that are free (not water, road or another building).
static func stamp(a: Arena, rng: SimRng, r: Rect2i, kind: int, levels := -1, cf := -1) -> Array:
	var sp: Array = SPEC[kind]
	var lv := levels if levels > 0 else rng.randi_range(int(sp[0]), int(sp[1]))
	var c := cf if cf > 0 else rng.randi_range(int(sp[2]), int(sp[3]))
	var id := new_id(a)
	var cells: Array = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not a.inside(x, y):
				continue
			var i := a.idx(x, y)
			if a.terrain[i] == Arena.T.WATER or a.terrain[i] == Arena.T.BUILDING or a.zone[i] in [Z.ROAD, Z.AVENUE]:
				continue
			a.terrain[i] = Arena.T.BUILDING
			a.depth[i] = 0
			a.bld_h[i] = lv
			a.bld_cf[i] = c
			a.bld_id[i] = id
			a.bld_kind[i] = kind
			a.zone[i] = Z.NONE
			cells.append(i)
	return cells


## Ground use for the cells of r: streets, plazas, parking and lots are pavement, yards grass,
## parks grass with tree clumps.
static func ground(a: Arena, r: Rect2i, z: int, overwrite_buildings := false) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not a.inside(x, y):
				continue
			var i := a.idx(x, y)
			if a.terrain[i] == Arena.T.BUILDING and not overwrite_buildings:
				continue
			if a.terrain[i] == Arena.T.WATER and not (z in [Z.ROAD, Z.AVENUE]):
				continue
			_clear_building(a, i)
			a.zone[i] = z
			a.depth[i] = 0
			match z:
				Z.ROAD, Z.AVENUE, Z.PLAZA, Z.PARKING, Z.LOT:
					a.terrain[i] = Arena.T.PAVEMENT
				Z.PARK:
					var hh := absi(hash(x * 73856093 ^ y * 19349663 ^ a.seed_value))
					a.terrain[i] = Arena.T.LIGHT_WOODS if hh % 100 < 38 else Arena.T.CLEAR
				_:
					a.terrain[i] = Arena.T.CLEAR


static func _clear_building(a: Arena, i: int) -> void:
	if a.terrain[i] == Arena.T.BUILDING:
		a.terrain[i] = Arena.T.CLEAR
	a.bld_h[i] = 0
	a.bld_cf[i] = 0
	a.bld_id[i] = 0
	a.bld_kind[i] = K.NONE


## Removes whatever stands on r and paves it (a compound or a spawn needs the room).
static func clear_rect(a: Arena, r: Rect2i, z := Z.LOT) -> void:
	ground(a, r, z, true)


## Levels the ground under a settlement to its most common height, then eases the edges.
static func flatten(a: Arena, r: Rect2i, ellipse := false) -> void:
	var counts := {}
	var cells: Array = []
	var c := Vector2(r.position) + Vector2(r.size) / 2.0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not a.inside(x, y):
				continue
			if ellipse and _ell(Vector2(x + 0.5, y + 0.5), c, Vector2(r.size) / 2.0) > 1.0:
				continue
			var i := a.idx(x, y)
			cells.append(i)
			counts[a.height[i]] = int(counts.get(a.height[i], 0)) + 1
	if cells.is_empty():
		return
	var best := 0
	var bn := -1
	for k in counts:
		if int(counts[k]) > bn:
			bn = int(counts[k])
			best = int(k)
	for i in cells:
		a.height[i] = best
	ArenaGenerator._smooth_heights(a)


static func _ell(p: Vector2, c: Vector2, rad: Vector2) -> float:
	var d := (p - c) / Vector2(maxf(1.0, rad.x), maxf(1.0, rad.y))
	return d.length()


## Street lines across [from, to): [position, width, is_avenue]. Blocks sit between lines.
static func _lines(rng: SimRng, from: int, to: int, bmin: int, bmax: int, avenue_every: int, centre: float) -> Array:
	var out: Array = []
	var x := from
	var k := 0
	while x < to - 2:
		out.append([x, 2, avenue_every > 0 and k % avenue_every == 0])
		x += 2 + rng.randi_range(bmin, bmax)
		k += 1
	# the line nearest the centre is always an avenue (the main street)
	var best := 0
	for j in out.size():
		if absf(out[j][0] - centre) < absf(out[best][0] - centre):
			best = j
	if not out.is_empty():
		out[best][2] = true
	for l in out:
		if l[2]:
			l[1] = 3
	return out


static func _split(rng: SimRng, r: Rect2i, n: int, min_side := 3) -> Array:
	var out: Array = [r]
	var guard := 0
	while out.size() < n and guard < 12:
		guard += 1
		out.sort_custom(func(p: Rect2i, q: Rect2i) -> bool: return p.get_area() > q.get_area())
		var p: Rect2i = out[0]
		var horiz := p.size.x >= p.size.y
		var span := p.size.x if horiz else p.size.y
		if span < min_side * 2:
			break
		var cut := clampi(int(round(span * rng.randf_range(0.35, 0.65))), min_side, span - min_side)
		out.remove_at(0)
		if horiz:
			out.append(Rect2i(p.position, Vector2i(cut, p.size.y)))
			out.append(Rect2i(p.position + Vector2i(cut, 0), Vector2i(p.size.x - cut, p.size.y)))
		else:
			out.append(Rect2i(p.position, Vector2i(p.size.x, cut)))
			out.append(Rect2i(p.position + Vector2i(0, cut), Vector2i(p.size.x, p.size.y - cut)))
	return out


## Lots along the four edges of a block, `depth` deep, each with the side its street is on
## ("N", "S", "W", "E"). Returns [[Rect2i, side], ...] and the leftover courtyard as the last
## entry ([Rect2i, ""]).
static func _perimeter(rng: SimRng, b: Rect2i, depth: int, lot_min: int, lot_max: int) -> Array:
	var lots: Array = []
	var d := mini(depth, b.size.y / 2)
	var dx := mini(depth, b.size.x / 2)
	for row in [[b.position.y, "N"], [b.end.y - d, "S"]]:
		var x := b.position.x
		while x < b.end.x:
			var lw := mini(rng.randi_range(lot_min, lot_max), b.end.x - x)
			if b.end.x - (x + lw) < lot_min:
				lw = b.end.x - x
			lots.append([Rect2i(x, int(row[0]), lw, d), row[1]])
			x += lw
	for col in [[b.position.x, "W"], [b.end.x - dx, "E"]]:
		var y := b.position.y + d
		while y < b.end.y - d:
			var lh := mini(rng.randi_range(lot_min, lot_max), b.end.y - d - y)
			if b.end.y - d - (y + lh) < lot_min:
				lh = b.end.y - d - y
			lots.append([Rect2i(int(col[0]), y, dx, lh), col[1]])
			y += lh
	lots.append([Rect2i(b.position.x + dx, b.position.y + d, maxi(0, b.size.x - 2 * dx), maxi(0, b.size.y - 2 * d)), ""])
	return lots


## A footprint inside a lot: `size` against the street side (with `setback` cells of front yard).
static func _front(lot: Rect2i, side: String, size: Vector2i, setback: int) -> Rect2i:
	var s := Vector2i(mini(size.x, lot.size.x), mini(size.y, lot.size.y))
	var p := lot.position + (lot.size - s) / 2
	match side:
		"N":
			p.y = lot.position.y + mini(setback, lot.size.y - s.y)
		"S":
			p.y = lot.end.y - s.y - mini(setback, lot.size.y - s.y)
		"W":
			p.x = lot.position.x + mini(setback, lot.size.x - s.x)
		"E":
			p.x = lot.end.x - s.x - mini(setback, lot.size.x - s.x)
	return Rect2i(p, s)


# ------------------------------------------------------------------ cities and towns

## A city on a street grid over r. Downtown towers at the centre, apartment blocks and shops
## around them, houses at the edge, an industrial quarter on one side, a civic plaza, parks and
## parking. extend: carry the avenues on to the map edges. Returns the building cells.
## opts: "downtown" / "midtown" (how far out, 0..1 of the radius, those districts reach) and
## "industrial" (false: no industrial quarter).
static func city(a: Arena, rng: SimRng, r: Rect2i, extend := true, block := [9, 12], opts := {}) -> Array:
	var p := {"style": "city", "block": block, "avenue_every": 3, "extend": extend}
	p.merge(opts)
	return _grid(a, rng, r, p)


## A town: a main street (the road through it), a town square with a church or hall, shops and
## row houses along the main street, houses towards the edge. Round-ish: blocks past the edge
## stay countryside. vertical: the main street runs north-south.
static func town(a: Arena, rng: SimRng, c: Vector2i, radius: int, vertical: bool) -> Array:
	var rx := radius if not vertical else int(radius * 0.8)
	var ry := radius if vertical else int(radius * 0.8)
	var r := Rect2i(c.x - rx, c.y - ry, rx * 2, ry * 2)
	return _grid(a, rng, r, {"style": "town", "block": [8, 11], "avenue_every": 0, "ellipse": true, "vertical": vertical})


static func _grid(a: Arena, rng: SimRng, r: Rect2i, p: Dictionary) -> Array:
	r = r.intersection(Rect2i(1, 1, a.w - 2, a.h - 2))
	if r.size.x < 12 or r.size.y < 12:
		return []
	var style := str(p["style"])
	var ell := bool(p.get("ellipse", false))
	var centre := Vector2(r.position) + Vector2(r.size) / 2.0
	var rad := Vector2(r.size) / 2.0
	flatten(a, r, ell)
	# clear the woods and rough in town (parks get their own trees)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if ell and _ell(Vector2(x + 0.5, y + 0.5), centre, rad) > 1.0:
				continue
			var i := a.idx(x, y)
			if a.terrain[i] in [Arena.T.LIGHT_WOODS, Arena.T.HEAVY_WOODS, Arena.T.ROUGH]:
				a.terrain[i] = Arena.T.CLEAR
	var bl: Array = p["block"]
	var every := int(p.get("avenue_every", 3))
	var xs := _lines(rng, r.position.x, r.end.x, int(bl[0]), int(bl[1]), every, centre.x)
	var ys := _lines(rng, r.position.y, r.end.y, int(bl[0]), int(bl[1]), every, centre.y)
	var vertical := bool(p.get("vertical", true))
	# streets; in a town only the main street runs past the edge, side streets stop with the houses
	for l in xs:
		var main := bool(l[2]) and (style == "city" or vertical)
		for y in range(r.position.y, r.end.y):
			if ell and not main and _ell(Vector2(l[0] + 1, y + 0.5), centre, rad) > 1.02:
				continue
			ground(a, Rect2i(int(l[0]), y, int(l[1]), 1), Z.AVENUE if l[2] else Z.ROAD)
		if main and bool(p.get("extend", false)):
			ground(a, Rect2i(int(l[0]), 1, int(l[1]), r.position.y - 1), Z.AVENUE)
			ground(a, Rect2i(int(l[0]), r.end.y, int(l[1]), a.h - 1 - r.end.y), Z.AVENUE)
	for l in ys:
		var main2 := bool(l[2]) and (style == "city" or not vertical)
		for x in range(r.position.x, r.end.x):
			if ell and not main2 and _ell(Vector2(x + 0.5, l[0] + 1), centre, rad) > 1.02:
				continue
			ground(a, Rect2i(x, int(l[0]), 1, int(l[1])), Z.AVENUE if l[2] else Z.ROAD)
		if main2 and bool(p.get("extend", false)):
			ground(a, Rect2i(1, int(l[0]), r.position.x - 1, int(l[1])), Z.AVENUE)
			ground(a, Rect2i(r.end.x, int(l[0]), a.w - 1 - r.end.x, int(l[1])), Z.AVENUE)
	# the blocks between the lines
	var blocks: Array = []
	for ix in xs.size():
		var bx0 := int(xs[ix][0]) + int(xs[ix][1])
		var bx1 := int(xs[ix + 1][0]) if ix + 1 < xs.size() else r.end.x
		for iy in ys.size():
			var by0 := int(ys[iy][0]) + int(ys[iy][1])
			var by1 := int(ys[iy + 1][0]) if iy + 1 < ys.size() else r.end.y
			var b := Rect2i(bx0, by0, bx1 - bx0, by1 - by0)
			if b.size.x < 3 or b.size.y < 3:
				continue
			var bc := Vector2(b.position) + Vector2(b.size) / 2.0
			var d := _ell(bc, centre, rad)
			if ell and d > 0.98:
				continue
			# which sides face an avenue (shops go there)
			var av := {"W": bool(xs[ix][2]), "E": ix + 1 < xs.size() and bool(xs[ix + 1][2]),
				"N": bool(ys[iy][2]), "S": iy + 1 < ys.size() and bool(ys[iy + 1][2])}
			blocks.append({"r": b, "d": d, "av": av})
	if blocks.is_empty():
		return []
	# the block nearest the centre is the square
	var sq := 0
	for k in blocks.size():
		if float(blocks[k]["d"]) < float(blocks[sq]["d"]):
			sq = k
	var ind_angle := rng.randf_range(0.0, TAU)
	var cells: Array = []
	for k in blocks.size():
		var b: Rect2i = blocks[k]["r"]
		var d: float = blocks[k]["d"]
		var av: Dictionary = blocks[k]["av"]
		var bc := Vector2(b.position) + Vector2(b.size) / 2.0
		var ang := absf(angle_difference((bc - centre).angle(), ind_angle))
		var dt := float(p.get("downtown", 0.32))
		var mt := float(p.get("midtown", 0.66))
		if k == sq:
			cells.append_array(_fill_square(a, rng, b, style))
		elif style == "city":
			if bool(p.get("industrial", true)) and d > 0.42 and ang < 0.85:
				cells.append_array(_fill_industrial(a, rng, b))
			elif d < dt:
				cells.append_array(_fill_downtown(a, rng, b) if not rng.chance(0.07) else _fill_open(a, rng, b, Z.PLAZA))
			elif d < mt:
				if rng.chance(0.08):
					_fill_open(a, rng, b, Z.PARK)
				elif rng.chance(0.07):
					_fill_open(a, rng, b, Z.PARKING)
				else:
					cells.append_array(_fill_midtown(a, rng, b, av))
			else:
				if rng.chance(0.07):
					_fill_open(a, rng, b, Z.PARK)
				else:
					cells.append_array(_fill_outskirts(a, rng, b, av))
		else:
			# town: shops on the main street near the centre, houses beyond
			var on_main: bool = (bool(av["W"]) or bool(av["E"])) if vertical else (bool(av["N"]) or bool(av["S"]))
			if d < 0.85 and on_main:
				cells.append_array(_fill_mainstreet(a, rng, b, av))
			elif rng.chance(0.06):
				_fill_open(a, rng, b, Z.PARK)
			else:
				cells.append_array(_fill_outskirts(a, rng, b, av))
	return cells


static func _fill_square(a: Arena, rng: SimRng, b: Rect2i, style: String) -> Array:
	ground(a, b, Z.PLAZA)
	var s := Vector2i(maxi(3, b.size.x - 4), maxi(3, b.size.y - 4))
	if style == "town":
		s = Vector2i(clampi(b.size.x / 2, 3, 5), clampi(b.size.y / 2 + 1, 3, 6))
	var fp := Rect2i(b.position + (b.size - s) / 2, s)
	if style == "town":
		# the church or hall stands on the square's north side, the rest is open
		fp.position.y = b.position.y + 1
	return stamp(a, rng, fp, K.CIVIC if style == "city" or rng.chance(0.4) else K.CHURCH)


static func _fill_open(a: Arena, rng: SimRng, b: Rect2i, z: int) -> Array:
	ground(a, b, z)
	return []


static func _fill_downtown(a: Arena, rng: SimRng, b: Rect2i) -> Array:
	var cells: Array = []
	var n := rng.randi_range(1, 2) if b.get_area() < 90 else rng.randi_range(2, 4)
	for pr in _split(rng, b, n, 3):
		var parcel: Rect2i = pr
		var kind := K.TOWER if parcel.get_area() >= 20 and rng.chance(0.55) else K.OFFICE
		if parcel.get_area() < 10 and rng.chance(0.5):
			ground(a, parcel, Z.PLAZA)
			continue
		# towers stand back a little behind a forecourt
		var fp := parcel
		if kind == K.TOWER and parcel.size.x >= 5 and parcel.size.y >= 5:
			ground(a, parcel, Z.PLAZA)
			fp = parcel.grow(-1)
		cells.append_array(stamp(a, rng, fp, kind))
	return cells


static func _fill_midtown(a: Arena, rng: SimRng, b: Rect2i, av: Dictionary, town := false) -> Array:
	var cells: Array = []
	var lots := _perimeter(rng, b, rng.randi_range(3, 4) if not town else 3, 3, 5)
	for e in lots:
		var lot: Rect2i = e[0]
		var side: String = e[1]
		if lot.size.x <= 0 or lot.size.y <= 0:
			continue
		if side == "":
			# the courtyard: parking, a pocket park or yards
			var roll := rng.randf()
			ground(a, lot, Z.PARKING if roll < 0.35 else (Z.PARK if roll < 0.55 else Z.YARD))
			continue
		var kind := K.SHOP if bool(av.get(side, false)) or rng.chance(0.3) else K.APARTMENT
		if town:
			kind = K.SHOP if bool(av.get(side, false)) else (K.ROWHOUSE if rng.chance(0.6) else K.APARTMENT)
		cells.append_array(stamp(a, rng, lot, kind, -1 if kind != K.APARTMENT or not town else rng.randi_range(2, 3)))
	return cells


## A block on a town's main street: an unbroken row of shops and row houses facing it, houses on
## the quieter sides, gardens behind.
static func _fill_mainstreet(a: Arena, rng: SimRng, b: Rect2i, av: Dictionary) -> Array:
	var cells: Array = []
	ground(a, b, Z.YARD)
	for e in _perimeter(rng, b, 3, 2, 3):
		var lot: Rect2i = e[0]
		var side: String = e[1]
		if side == "" or lot.size.x < 2 or lot.size.y < 2:
			continue
		if bool(av.get(side, false)):
			cells.append_array(stamp(a, rng, lot, K.SHOP if rng.chance(0.6) else K.ROWHOUSE))
		elif rng.chance(0.75):
			var sz := Vector2i(2, 2) if lot.size.x < 4 and lot.size.y < 4 else (Vector2i(3, 2) if lot.size.x >= lot.size.y else Vector2i(2, 3))
			cells.append_array(stamp(a, rng, _front(lot, side, sz, rng.randi_range(0, 1)), K.HOUSE))
	return cells


static func _fill_outskirts(a: Arena, rng: SimRng, b: Rect2i, av: Dictionary) -> Array:
	var cells: Array = []
	if rng.chance(0.22):
		# a terrace: row houses two cells wide all round the block
		for e in _perimeter(rng, b, 2, 2, 2):
			var lot: Rect2i = e[0]
			if lot.size.x <= 0 or lot.size.y <= 0:
				continue
			if e[1] == "":
				ground(a, lot, Z.YARD)
			else:
				cells.append_array(stamp(a, rng, lot, K.ROWHOUSE))
		return cells
	ground(a, b, Z.YARD)
	if rng.chance(0.05) and b.size.x >= 6 and b.size.y >= 6:
		cells.append_array(stamp(a, rng, Rect2i(b.position + (b.size - Vector2i(3, 5)) / 2, Vector2i(3, 5)), K.CHURCH))
		return cells
	for e in _perimeter(rng, b, 3, 3, 4):
		var lot: Rect2i = e[0]
		var side: String = e[1]
		if side == "" or lot.size.x < 2 or lot.size.y < 2:
			continue
		if rng.chance(0.12):
			continue
		var shop := bool(av.get(side, false)) and rng.chance(0.35)
		var sz := Vector2i(2, 2) if lot.size.x < 4 and lot.size.y < 4 else (Vector2i(3, 2) if lot.size.x >= lot.size.y else Vector2i(2, 3))
		var fp := _front(lot, side, sz, 0 if shop else rng.randi_range(0, 1))
		cells.append_array(stamp(a, rng, fp, K.SHOP if shop else K.HOUSE))
	return cells


static func _fill_industrial(a: Arena, rng: SimRng, b: Rect2i) -> Array:
	var cells: Array = []
	ground(a, b, Z.LOT)
	var n := rng.randi_range(1, 2) if b.get_area() < 100 else rng.randi_range(2, 3)
	for pr in _split(rng, b, n, 4):
		var parcel: Rect2i = pr
		var roll := rng.randf()
		if roll < 0.22 and parcel.size.x >= 5 and parcel.size.y >= 5:
			# a tank farm: round tanks in rows with walkways between
			var t := rng.randi_range(2, 3)
			var y := parcel.position.y + 1
			while y + t <= parcel.end.y:
				var x := parcel.position.x + 1
				while x + t <= parcel.end.x:
					cells.append_array(stamp(a, rng, Rect2i(x, y, t, t), K.TANK))
					x += t + 1
				y += t + 1
		elif roll < 0.5 and parcel.size.x >= 5 and parcel.size.y >= 5:
			cells.append_array(stamp(a, rng, parcel.grow(-1), K.FACTORY))
			# a stack of silos in the yard corner
			if rng.chance(0.4):
				cells.append_array(stamp(a, rng, Rect2i(parcel.end - Vector2i(2, 2), Vector2i(2, 2)), K.SILO))
		else:
			var fp := parcel.grow(-1) if parcel.size.x >= 5 and parcel.size.y >= 4 else parcel
			cells.append_array(stamp(a, rng, fp, K.WAREHOUSE))
	return cells


# ------------------------------------------------------------------ villages, industry, compounds

## A village along a road: houses on both sides following the road, a church near the middle,
## and a farm or two (barn and silos) down a lane. road: the road's centre points (from the
## battlefield generator); vertical: which way it runs.
static func village(a: Arena, rng: SimRng, road: Array, at: int, radius: int, vertical: bool) -> Array:
	var cells: Array = []
	var lo := maxi(0, at - radius)
	var hi := mini(road.size() - 1, at + radius)
	var k := lo
	var church_done := false
	while k <= hi:
		var p: Vector2i = road[k]
		for side in [-1, 1]:
			if not rng.chance(0.72):
				continue
			var off := 2 + rng.randi_range(1, 2)
			var sz := Vector2i(2, 2) if rng.chance(0.7) else (Vector2i(3, 2) if vertical else Vector2i(2, 3))
			var pos := Vector2i(p.x + side * off, p.y) if vertical else Vector2i(p.x, p.y + side * off)
			if side < 0:
				pos += Vector2i(-sz.x + 1, 0) if vertical else Vector2i(0, -sz.y + 1)
			var fp := Rect2i(pos, sz)
			if not church_done and absi(k - at) < 4 and rng.chance(0.6):
				fp = Rect2i(pos, Vector2i(3, 5) if not vertical else Vector2i(5, 3))
				if side < 0:
					fp.position = Vector2i(p.x - off - 2, p.y) if vertical else Vector2i(p.x, p.y - off - 2)
				ground(a, fp.grow(1), Z.PLAZA)
				cells.append_array(stamp(a, rng, fp, K.CHURCH))
				church_done = true
				continue
			ground(a, fp.grow(1), Z.YARD)
			cells.append_array(stamp(a, rng, fp, K.SHOP if absi(k - at) < 3 and rng.chance(0.3) else K.HOUSE))
		k += rng.randi_range(4, 6)
	# farms down a lane off the road
	for f in rng.randi_range(1, 2):
		var kk := clampi(at + (radius + rng.randi_range(2, 6)) * (1 if f == 0 else -1), 0, road.size() - 1)
		var p2: Vector2i = road[kk]
		var side2 := -1 if rng.chance(0.5) else 1
		var lane := rng.randi_range(6, 9)
		var yard := Rect2i()
		if vertical:
			var x0 := p2.x + (2 if side2 > 0 else -lane)
			ground(a, Rect2i(x0, p2.y, lane, 1), Z.ROAD)
			yard = Rect2i(p2.x + (lane + 2 if side2 > 0 else -lane - 9), p2.y - 4, 9, 9)
		else:
			var y0 := p2.y + (2 if side2 > 0 else -lane)
			ground(a, Rect2i(p2.x, y0, 1, lane), Z.ROAD)
			yard = Rect2i(p2.x - 4, p2.y + (lane + 2 if side2 > 0 else -lane - 9), 9, 9)
		yard = yard.intersection(Rect2i(2, 2, a.w - 4, a.h - 4))
		if yard.size.x < 6 or yard.size.y < 6:
			continue
		ground(a, yard, Z.YARD)
		cells.append_array(stamp(a, rng, Rect2i(yard.position + Vector2i(1, 1), Vector2i(4, 3)), K.BARN))
		cells.append_array(stamp(a, rng, Rect2i(yard.position + Vector2i(6, 1), Vector2i(2, 2)), K.SILO))
		if rng.chance(0.6):
			cells.append_array(stamp(a, rng, Rect2i(yard.position + Vector2i(6, 4), Vector2i(2, 2)), K.SILO))
		cells.append_array(stamp(a, rng, Rect2i(yard.position + Vector2i(1, 6), Vector2i(2, 2)), K.HOUSE))
	return cells


## A stand-alone industrial park (a mine head, refinery or depot) on a grid of service roads.
static func industrial(a: Arena, rng: SimRng, r: Rect2i) -> Array:
	r = r.intersection(Rect2i(2, 2, a.w - 4, a.h - 4))
	if r.size.x < 10 or r.size.y < 10:
		return []
	flatten(a, r)
	ground(a, r, Z.LOT)
	var xs := _lines(rng, r.position.x, r.end.x, 9, 13, 0, r.position.x + r.size.x / 2.0)
	var ys := _lines(rng, r.position.y, r.end.y, 8, 12, 0, r.position.y + r.size.y / 2.0)
	for l in xs:
		ground(a, Rect2i(int(l[0]), r.position.y, 2, r.size.y), Z.ROAD)
	for l in ys:
		ground(a, Rect2i(r.position.x, int(l[0]), r.size.x, 2), Z.ROAD)
	var cells: Array = []
	for ix in xs.size():
		var bx0 := int(xs[ix][0]) + 2
		var bx1 := int(xs[ix + 1][0]) if ix + 1 < xs.size() else r.end.x
		for iy in ys.size():
			var by0 := int(ys[iy][0]) + 2
			var by1 := int(ys[iy + 1][0]) if iy + 1 < ys.size() else r.end.y
			var b := Rect2i(bx0, by0, bx1 - bx0, by1 - by0)
			if b.size.x >= 4 and b.size.y >= 4:
				cells.append_array(_fill_industrial(a, rng, b))
	return cells


## A military compound: a hardened command post, hangars and bunkers on a paved apron.
## Returns the building cells (the objective).
static func compound(a: Arena, rng: SimRng, c: Vector2i) -> Array:
	var r := Rect2i(c - Vector2i(7, 6), Vector2i(15, 12)).intersection(Rect2i(3, 3, a.w - 6, a.h - 6))
	if r.size.x < 8 or r.size.y < 8:
		return []
	clear_rect(a, r, Z.LOT)
	var cells: Array = []
	var mid := r.position + r.size / 2
	cells.append_array(stamp(a, rng, Rect2i(mid - Vector2i(2, 1), Vector2i(4, 3)), K.CIVIC, 3, rng.randi_range(110, 140)))
	cells.append_array(stamp(a, rng, Rect2i(r.position + Vector2i(1, 1), Vector2i(5, 3)), K.HANGAR))
	cells.append_array(stamp(a, rng, Rect2i(Vector2i(r.end.x - 6, r.position.y + 1), Vector2i(5, 3)), K.HANGAR))
	for k in rng.randi_range(2, 3):
		var bp := Vector2i(r.position.x + 1 + k * 5, r.end.y - 3)
		cells.append_array(stamp(a, rng, Rect2i(bp, Vector2i(3, 2)), K.BUNKER))
	return cells
