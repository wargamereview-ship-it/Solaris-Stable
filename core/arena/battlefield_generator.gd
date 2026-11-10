class_name BattlefieldGenerator
extends RefCounted
## Open battlefields for the merc mode: 1.2-1.5 km of terrain from a planet biome, with roads, rivers,
## towns and woods. Not mirrored. Each team deploys along a map edge; scenarios add objectives
## (buildings to hold or destroy, an edge to break through, recon points).
##
## opts: {"player_edge": "W", "enemy_edge": "E", "player_n": 4, "enemy_n": 4, "scenario": "standup",
##        "ally_n": 0, "size": 1.0}

const EDGES := ["W", "E", "N", "S"]
const OPPOSITE := {"W": "E", "E": "W", "N": "S", "S": "N"}


static func generate(biome: String, seed_value: int, opts := {}) -> Arena:
	for attempt in 10:
		var a := _try(biome, seed_value + attempt * 104729, opts)
		if _validate(a):
			a.seed_value = seed_value
			return a
	var b := _try("bf_plains", seed_value, opts)
	b.seed_value = seed_value
	return b


static func _try(biome: String, seed_value: int, opts: Dictionary) -> Arena:
	var db := GameData.db()
	var th: Dictionary = db.arenas["themes"].get(biome, db.arenas["themes"]["bf_plains"])
	var rng := SimRng.new(seed_value)
	var a := Arena.new()
	a.theme = biome if db.arenas["themes"].has(biome) else "bf_plains"
	a.biome = a.theme
	var sz: Array = th["size_cells"]
	var w := int(rng.randi_range(int(sz[0]), int(sz[1])) * float(opts.get("size", 1.0)))
	var h := int(round(w * rng.randf_range(0.62, 0.72)))
	a.setup(w, h)
	var n := w * h

	var hn := FastNoiseLite.new()
	hn.seed = rng.randi_range(1, 1 << 30)
	hn.frequency = float(th["height_scale"])
	hn.fractal_octaves = 4
	var levels := int(th["height_levels"])
	var hv := PackedFloat32Array()
	hv.resize(n)
	for y in h:
		for x in w:
			hv[a.idx(x, y)] = hn.get_noise_2d(x, y)
	var sorted := hv.duplicate()
	sorted.sort()
	for i in n:
		var q := sorted.bsearch(hv[i]) / float(n)
		# flatter lowlands, a few high crests
		a.height[i] = clampi(int(pow(q, 1.35) * (levels + 1)), 0, levels)
	ArenaGenerator._smooth_heights(a)

	var wood_v := _field(a, rng, 0.045, 3)
	var wood2 := _field(a, rng, 0.13, 2)
	var rough_v := _field(a, rng, 0.09, 2)
	var water_v := _field(a, rng, 0.03, 2)
	for i in n:
		wood_v[i] = wood_v[i] * 0.75 + wood2[i] * 0.25
	var heavy_t := _quantile(wood_v, 1.0 - float(th["heavy_woods"]))
	var light_t := _quantile(wood_v, 1.0 - float(th["heavy_woods"]) - float(th["light_woods"]))
	var rough_t := _quantile(rough_v, 1.0 - float(th["rough"]))
	var water_t := _quantile(water_v, float(th["water"]))
	var deep_t := _quantile(water_v, float(th["water"]) * 0.35)
	for i in n:
		var t := Arena.T.CLEAR
		if float(th["heavy_woods"]) > 0.0 and wood_v[i] >= heavy_t:
			t = Arena.T.HEAVY_WOODS
		elif float(th["light_woods"]) > 0.0 and wood_v[i] >= light_t:
			t = Arena.T.LIGHT_WOODS
		if float(th["rough"]) > 0.0 and rough_v[i] >= rough_t and t == Arena.T.CLEAR:
			t = Arena.T.ROUGH
		if float(th["water"]) > 0.0 and water_v[i] <= water_t and a.height[i] <= 1:
			t = Arena.T.WATER
			a.depth[i] = 2 if water_v[i] <= deep_t else 1
		a.terrain[i] = t

	if rng.chance(float(th.get("rivers", 0.0))):
		_river(a, rng)
	var kinds: Array = th.get("settlements", [])
	var roads: Array = []
	if not ("city" in kinds):
		for k in int(th.get("roads", 0)):
			roads.append(_road(a, rng, k))
	_settle(a, rng, kinds, roads)

	var pe := str(opts.get("player_edge", "W"))
	var ee := str(opts.get("enemy_edge", OPPOSITE.get(pe, "E")))
	a.edges = [pe, ee]
	a.spawns = [_edge_spawns(a, rng, pe, int(opts.get("player_n", 4)) + int(opts.get("ally_n", 0)), 0.06),
		_edge_spawns(a, rng, ee, int(opts.get("enemy_n", 4)), 0.06)]
	a.spawn_facing = [_inward(pe), _inward(ee)]
	if str(opts.get("scenario", "")) == "ambush":
		# the enemy is caught in the open, close to the middle of the map
		a.spawns[1] = _edge_spawns(a, rng, ee, int(opts.get("enemy_n", 4)), 0.42)
	_objectives(a, rng, str(opts.get("scenario", "standup")), pe, ee)
	a.build_astar()
	return a


static func _field(a: Arena, rng: SimRng, freq: float, octaves: int) -> PackedFloat32Array:
	var noise := FastNoiseLite.new()
	noise.seed = rng.randi_range(1, 1 << 30)
	noise.frequency = freq
	noise.fractal_octaves = octaves
	var v := PackedFloat32Array()
	v.resize(a.w * a.h)
	for y in a.h:
		for x in a.w:
			v[a.idx(x, y)] = noise.get_noise_2d(x, y)
	return v


static func _quantile(v: PackedFloat32Array, q: float) -> float:
	return ArenaGenerator._quantile(v, q)


static func _inward(edge: String) -> float:
	match edge:
		"W":
			return 0.0
		"E":
			return PI
		"N":
			return PI / 2.0
	return -PI / 2.0


## A river winding across the map (depth 1 with deep pools), with a few fords.
static func _river(a: Arena, rng: SimRng) -> void:
	var vertical := rng.chance(0.5)
	var length := a.h if vertical else a.w
	var across := a.w if vertical else a.h
	var c := rng.randf_range(across * 0.35, across * 0.65)
	var wid := rng.randi_range(1, 3)
	var drift := 0.0
	for k in length:
		drift = clampf(drift + rng.randf_range(-0.35, 0.35), -0.9, 0.9)
		c = clampf(c + drift, 4.0, across - 5.0)
		var ford := k % 23 < 3
		for d in range(-wid, wid + 1):
			var x := int(c) + d if vertical else k
			var y := k if vertical else int(c) + d
			if not a.inside(x, y):
				continue
			var i := a.idx(x, y)
			if a.terrain[i] == Arena.T.BUILDING:
				continue
			a.terrain[i] = Arena.T.WATER
			a.depth[i] = 1 if (ford or absi(d) == wid or rng.chance(0.7)) else 2
			a.height[i] = mini(int(a.height[i]), 1)


## A road from one edge to the other: a pavement strip that also bridges water.
static func _road(a: Arena, rng: SimRng, k: int) -> Array:
	var vertical := (k % 2 == 1) if rng.chance(0.7) else rng.chance(0.5)
	var length := a.h if vertical else a.w
	var across := a.w if vertical else a.h
	var c := rng.randf_range(across * 0.2, across * 0.8)
	var pts: Array = []
	var drift := 0.0
	for s in length:
		drift = clampf(drift + rng.randf_range(-0.2, 0.2), -0.6, 0.6)
		c = clampf(c + drift, 3.0, across - 4.0)
		for d in 2:
			var x := int(c) + d if vertical else s
			var y := s if vertical else int(c) + d
			if not a.inside(x, y):
				continue
			var i := a.idx(x, y)
			a.terrain[i] = Arena.T.PAVEMENT
			a.depth[i] = 0
			a.zone[i] = Settlement.Z.ROAD
		pts.append(Vector2i(int(c), s) if vertical else Vector2i(s, int(c)))
	return [pts, vertical]


## The theme's settlements: "city" fills the map with a street grid whose avenues run out to the
## edges; "town" and "village" sit on a road; "industrial" is a works on its own access road.
static func _settle(a: Arena, rng: SimRng, kinds: Array, roads: Array) -> void:
	var used: Array = []
	for kind in kinds:
		match str(kind):
			"city":
				Settlement.city(a, rng, Rect2i(10, 8, a.w - 20, a.h - 16), true)
			"town", "village":
				if roads.is_empty():
					roads.append(_road(a, rng, roads.size()))
				var rd: Array = roads[rng.randi_range(0, roads.size() - 1)]
				var pts: Array = rd[0]
				var vertical: bool = rd[1]
				var at := -1
				for tries in 12:
					var k := rng.randi_range(int(pts.size() * 0.22), int(pts.size() * 0.78))
					var ok := true
					for u in used:
						if (pts[k] as Vector2i).distance_to(u) < 34.0:
							ok = false
					if ok:
						at = k
						break
				if at < 0:
					continue
				used.append(pts[at])
				if str(kind) == "village":
					Settlement.village(a, rng, pts, at, rng.randi_range(12, 16), vertical)
				else:
					_town_on_road(a, rng, pts, at, rng.randi_range(18, 24), vertical)
			"industrial":
				var c := Vector2i(rng.randi_range(int(a.w * 0.3), int(a.w * 0.7)), rng.randi_range(int(a.h * 0.25), int(a.h * 0.75)))
				var r := Rect2i(c - Vector2i(15, 11), Vector2i(rng.randi_range(26, 34), rng.randi_range(20, 26)))
				var cells := Settlement.industrial(a, rng, r)
				if not cells.is_empty() and not roads.is_empty():
					var rd2: Array = roads[0]
					_connect(a, c, _nearest((rd2[0] as Array), c))
				used.append(c)


## A town astride a road: the wandering road through it becomes a straight main street, with
## short links where the road enters and leaves.
static func _town_on_road(a: Arena, rng: SimRng, pts: Array, at: int, radius: int, vertical: bool) -> void:
	var c: Vector2i = pts[at]
	var rx := radius if not vertical else int(radius * 0.8)
	var ry := radius if vertical else int(radius * 0.8)
	var r := Rect2i(c.x - rx, c.y - ry, rx * 2, ry * 2)
	# lift the old road out of the town
	for p in pts:
		var q: Vector2i = p
		if r.has_point(q):
			for d in 2:
				var x := q.x + d if vertical else q.x
				var y := q.y if vertical else q.y + d
				if a.inside(x, y):
					var i := a.idx(x, y)
					a.terrain[i] = Arena.T.CLEAR
					a.zone[i] = Settlement.Z.NONE
	Settlement.town(a, rng, c, radius, vertical)
	# find the main street the town laid and tie the road's ends to it
	var main := -1
	if vertical:
		for x in range(r.position.x, r.end.x):
			if a.inside(x, c.y) and a.zone[a.idx(x, c.y)] == Settlement.Z.AVENUE:
				main = x
				break
	else:
		for y in range(r.position.y, r.end.y):
			if a.inside(c.x, y) and a.zone[a.idx(c.x, y)] == Settlement.Z.AVENUE:
				main = y
				break
	if main < 0:
		return
	for edge_v in [r.position.y if vertical else r.position.x, (r.end.y - 1) if vertical else (r.end.x - 1)]:
		var hit: Vector2i = Vector2i(-1, -1)
		for p in pts:
			var q: Vector2i = p
			if (vertical and q.y == edge_v) or (not vertical and q.x == edge_v):
				hit = q
				break
		if hit.x < 0:
			continue
		if vertical:
			Settlement.ground(a, Rect2i(mini(hit.x, main), edge_v, absi(hit.x - main) + 2, 2), Settlement.Z.ROAD)
		else:
			Settlement.ground(a, Rect2i(edge_v, mini(hit.y, main), 2, absi(hit.y - main) + 2), Settlement.Z.ROAD)


static func _nearest(pts: Array, c: Vector2i) -> Vector2i:
	var best: Vector2i = pts[0]
	for p in pts:
		if (p as Vector2i).distance_squared_to(c) < best.distance_squared_to(c):
			best = p
	return best


## An access road (two cells wide, L-shaped) from a to b.
static func _connect(a: Arena, p: Vector2i, q: Vector2i) -> void:
	Settlement.ground(a, Rect2i(mini(p.x, q.x), p.y, absi(q.x - p.x) + 2, 2), Settlement.Z.ROAD)
	Settlement.ground(a, Rect2i(q.x, mini(p.y, q.y), 2, absi(q.y - p.y) + 2), Settlement.Z.ROAD)


## Deployment spots along an edge, `depth` of the way in (0.06 = the edge band).
static func _edge_spawns(a: Arena, rng: SimRng, edge: String, count: int, depth: float) -> Array:
	var out: Array = []
	var along := a.h if edge in ["W", "E"] else a.w
	for k in maxi(1, count):
		var f := (k + 1.0) / (count + 1.0)
		var u := int(along * (0.3 + 0.4 * f)) + rng.randi_range(-2, 2)
		var v := 0
		match edge:
			"W":
				v = int(a.w * depth) + rng.randi_range(0, 2)
			"E":
				v = a.w - 1 - int(a.w * depth) - rng.randi_range(0, 2)
			"N":
				v = int(a.h * depth) + rng.randi_range(0, 2)
			"S":
				v = a.h - 1 - int(a.h * depth) - rng.randi_range(0, 2)
		var c := Vector2i(v, u) if edge in ["W", "E"] else Vector2i(u, v)
		c = Vector2i(clampi(c.x, 1, a.w - 2), clampi(c.y, 1, a.h - 2))
		_clear_spot(a, c)
		out.append(a.center_of(c))
	return out


static func _clear_spot(a: Arena, c: Vector2i) -> void:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := c.x + dx
			var y := c.y + dy
			if a.inside(x, y):
				var i := a.idx(x, y)
				if a.terrain[i] in [Arena.T.BUILDING, Arena.T.WATER, Arena.T.HEAVY_WOODS]:
					Settlement._clear_building(a, i)
					a.terrain[i] = Arena.T.CLEAR
					a.depth[i] = 0


## Scenario objectives: buildings to hold or destroy, an exit edge, recon points.
static func _objectives(a: Arena, rng: SimRng, scenario: String, pe: String, ee: String) -> void:
	var ob := {"type": scenario}
	match scenario:
		"hold_the_line", "base_defense":
			ob["defend_cells"] = _base(a, rng, pe, 0.3)
		"base_attack":
			ob["attack_cells"] = _base(a, rng, ee, 0.25)
		"breakthrough":
			ob["exit_edge"] = ee
		"chase":
			ob["enemy_exit_edge"] = pe
		"recon", "probe":
			var pts: Array = []
			for k in 3:
				var f := rng.randf_range(0.45, 0.8)
				var g := rng.randf_range(0.2, 0.8)
				var p := Vector2.ZERO
				match ee:
					"E":
						p = Vector2(f, g)
					"W":
						p = Vector2(1.0 - f, g)
					"S":
						p = Vector2(g, f)
					"N":
						p = Vector2(g, 1.0 - f)
				var c := Vector2i(int(p.x * a.w), int(p.y * a.h))
				pts.append(a.center_of(c))
			ob["recon_points"] = pts
			ob["recon_radius_m"] = 130.0
	a.objectives = ob


## A military compound at `depth` of the way in from an edge. Returns its building cells.
static func _base(a: Arena, rng: SimRng, edge: String, depth: float) -> Array:
	var along := a.h if edge in ["W", "E"] else a.w
	var u := int(along * rng.randf_range(0.35, 0.65))
	var v := 0
	match edge:
		"W":
			v = int(a.w * depth)
		"E":
			v = a.w - 1 - int(a.w * depth)
		"N":
			v = int(a.h * depth)
		"S":
			v = a.h - 1 - int(a.h * depth)
	var c := Vector2i(v, u) if edge in ["W", "E"] else Vector2i(u, v)
	return Settlement.compound(a, rng, c)


static func _validate(a: Arena) -> bool:
	if a.spawns.size() < 2 or a.spawns[0].is_empty() or a.spawns[1].is_empty():
		return false
	var p := a.find_path(a.spawns[0][0], a.spawns[1][0])
	if p.is_empty():
		return false
	var ob := a.objectives
	for key in ["defend_cells", "attack_cells"]:
		if ob.has(key) and (ob[key] as Array).size() < 4:
			return false
	return true
