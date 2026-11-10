class_name ArenaGenerator
extends RefCounted
## Builds a fair procedural arena from a theme and a seed. One half is generated and point-mirrored,
## so every start zone sees the same terrain (hazards are mirrored too). Same seed + theme always gives
## the same arena. teams > 2 places free-for-all spawns in mirrored pairs around the edge.


static func generate(theme_id: String, seed_value: int, team_size := 1, arena_id := "", teams := 2) -> Arena:
	for attempt in 12:
		var a := _try(theme_id, seed_value + attempt * 7919, team_size, teams)
		a.arena_id = arena_id
		if _validate(a):
			a.seed_value = seed_value
			return a
	var b := _try("bowl", seed_value, team_size, teams)
	b.arena_id = arena_id
	b.seed_value = seed_value
	return b


static func _try(theme_id: String, seed_value: int, team_size: int, teams: int) -> Arena:
	var db := GameData.db()
	var th: Dictionary = db.arenas["themes"].get(theme_id, db.arenas["themes"]["bowl"])
	var rng := SimRng.new(seed_value)
	var a := Arena.new()
	a.theme = theme_id
	var sz: Array = th["size_cells"]
	var w := rng.randi_range(int(sz[0]), int(sz[1]))
	if team_size > 1:
		w += 6 + team_size * 3
	if teams > 2:
		w += 10
	var h := int(round(w * 0.78))
	a.setup(w, h)
	var n := w * h

	var hn := FastNoiseLite.new()
	hn.seed = rng.randi_range(1, 1 << 30)
	hn.frequency = float(th["height_scale"])
	hn.fractal_octaves = 3
	var tn := FastNoiseLite.new()
	tn.seed = rng.randi_range(1, 1 << 30)
	tn.frequency = 0.09
	tn.fractal_octaves = 2
	var rn := FastNoiseLite.new()
	rn.seed = rng.randi_range(1, 1 << 30)
	rn.frequency = 0.14
	var wn := FastNoiseLite.new()
	wn.seed = rng.randi_range(1, 1 << 30)
	wn.frequency = 0.05

	var levels := int(th["height_levels"])
	var hv := PackedFloat32Array()
	hv.resize(n)
	for y in h:
		for x in w:
			hv[a.idx(x, y)] = hn.get_noise_2d(x, y)
	# heights by quantile so every arena uses the full range of its theme
	var sorted := hv.duplicate()
	sorted.sort()
	for i in n:
		var q := sorted.bsearch(hv[i]) / float(n)
		a.height[i] = clampi(int(q * (levels + 1)), 0, levels)
	_smooth_heights(a)

	var wood_v := _field(a, tn)
	var rough_v := _field(a, rn)
	var water_v := _field(a, wn)
	var heavy_t := _quantile(wood_v, 1.0 - float(th["heavy_woods"]))
	var light_t := _quantile(wood_v, 1.0 - float(th["heavy_woods"]) - float(th["light_woods"]))
	var rough_t := _quantile(rough_v, 1.0 - float(th["rough"]))
	var water_t := _quantile(water_v, float(th["water"]))
	var pave := float(th.get("pavement", 0.0))
	var pave_t := _quantile(rough_v, pave)
	var deep_t := _quantile(water_v, float(th["water"]) * 0.3)
	for i in n:
		var t := Arena.T.CLEAR
		if pave > 0.0 and rough_v[i] < pave_t:
			t = Arena.T.PAVEMENT
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

	# buildings
	var bsz: Array = th["building_size"]
	var bht: Array = th["building_height"]
	if th.get("grid_streets", false):
		# a city district on a street grid: towers in the middle, apartments and shops around them
		Settlement.city(a, rng, Rect2i(1, 1, w - 2, h - 2), false, [6, 8], {"downtown": 0.62, "midtown": 1.3, "industrial": false})
	elif th.get("industrial", false):
		Settlement.industrial(a, rng, Rect2i(2, 2, w - 4, h - 4))
	else:
		for k in int(th["buildings"]):
			var bw := rng.randi_range(int(bsz[0]), int(bsz[1]))
			var bh2 := rng.randi_range(int(bsz[0]), int(bsz[1]))
			var bx := rng.randi_range(2, w - bw - 2)
			var by := rng.randi_range(2, h - bh2 - 2)
			_place_building(a, bx, by, bw, bh2, rng.randi_range(int(bht[0]), int(bht[1])))

	_mirror(a)
	_place_spawns(a, team_size, teams)
	_place_hazards(a, th.get("hazards", []), rng)
	a.build_astar()
	return a


static func _field(a: Arena, noise: FastNoiseLite) -> PackedFloat32Array:
	var v := PackedFloat32Array()
	v.resize(a.w * a.h)
	for y in a.h:
		for x in a.w:
			v[a.idx(x, y)] = noise.get_noise_2d(x, y)
	return v


static func _quantile(v: PackedFloat32Array, q: float) -> float:
	if q <= 0.0:
		return -INF
	if q >= 1.0:
		return INF
	var s := v.duplicate()
	s.sort()
	return s[clampi(int(q * s.size()), 0, s.size() - 1)]


static func _smooth_heights(a: Arena) -> void:
	for _pass in 6:
		var changed := false
		for y in a.h:
			for x in a.w:
				var i := a.idx(x, y)
				for o in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, -1)]:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if not a.inside(nx, ny):
						continue
					var j := a.idx(nx, ny)
					if a.height[i] - a.height[j] > 1:
						a.height[i] -= 1
						changed = true
					elif a.height[j] - a.height[i] > 1:
						a.height[j] -= 1
						changed = true
		if not changed:
			break


static func _place_building(a: Arena, bx: int, by: int, bw: int, bh: int, levels: int) -> void:
	var id := Settlement.new_id(a)
	for y in range(by, mini(a.h, by + bh)):
		for x in range(bx, mini(a.w, bx + bw)):
			var i := a.idx(x, y)
			a.terrain[i] = Arena.T.BUILDING
			a.depth[i] = 0
			a.bld_h[i] = levels
			a.bld_cf[i] = 8 * levels + 10
			a.bld_id[i] = id
			a.bld_kind[i] = Settlement.K.NONE


const MIRROR_ID := 100000


## Point symmetry: cell i takes the value of its mirror for the second half of the grid.
static func _mirror(a: Arena) -> void:
	var n := a.w * a.h
	for i in n:
		var j := n - 1 - i
		if i > j:
			a.height[i] = a.height[j]
			a.terrain[i] = a.terrain[j]
			a.depth[i] = a.depth[j]
			a.bld_h[i] = a.bld_h[j]
			a.bld_cf[i] = a.bld_cf[j]
			# the mirrored half's buildings are buildings of their own
			a.bld_id[i] = a.bld_id[j] + MIRROR_ID if a.bld_id[j] > 0 else 0
			a.bld_kind[i] = a.bld_kind[j]
			a.zone[i] = a.zone[j]
	a.next_bld_id += MIRROR_ID


static func _place_spawns(a: Arena, team_size: int, teams: int) -> void:
	a.spawns = []
	a.spawn_facing = []
	if teams <= 2:
		a.spawns = [[], []]
		a.spawn_facing = [0.0, PI]
		var cy := a.h / 2
		for k in team_size:
			var off := (k - (team_size - 1) / 2.0) * 5.0
			var c0 := Vector2i(int(a.w * 0.1), clampi(int(cy + off), 2, a.h - 3))
			_clear_zone(a, c0)
			var c1 := Vector2i(a.w - 1 - c0.x, a.h - 1 - c0.y)
			_clear_zone(a, c1)
			a.spawns[0].append(a.center_of(c0))
			a.spawns[1].append(a.center_of(c1))
		return
	# free-for-all: pairs of mirrored spawns spread down the two long edges
	var pairs := int(ceil(teams / 2.0))
	var firsts: Array = []
	for k in pairs:
		var fy := (k + 1.0) / (pairs + 1.0)
		var c := Vector2i(int(a.w * (0.1 if k % 2 == 0 else 0.22)), clampi(int(a.h * fy), 2, a.h - 3))
		firsts.append(c)
	var all: Array = []
	for c in firsts:
		all.append(c)
	for c in firsts:
		all.append(Vector2i(a.w - 1 - c.x, a.h - 1 - c.y))
	var center := a.size_m() / 2.0
	for t in teams:
		var cc: Vector2i = all[t]
		_clear_zone(a, cc)
		var p := a.center_of(cc)
		a.spawns.append([p])
		a.spawn_facing.append((center - p).angle())


static func _clear_zone(a: Arena, c: Vector2i) -> void:
	var lvl := a.height[a.idx(c.x, c.y)]
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x := c.x + dx
			var y := c.y + dy
			if a.inside(x, y):
				var i := a.idx(x, y)
				if a.terrain[i] in [Arena.T.BUILDING, Arena.T.WATER, Arena.T.HEAVY_WOODS]:
					Settlement._clear_building(a, i)
					a.terrain[i] = Arena.T.CLEAR
					a.depth[i] = 0
				a.height[i] = lvl


## Arena hazards from the theme (flame jets, steam vents, shock pylons), placed in mirrored pairs
## on open ground away from the spawns.
static func _place_hazards(a: Arena, defs: Array, rng: SimRng) -> void:
	for d in defs:
		var count := int(d.get("count", 0))
		var pairs := maxi(1, count / 2)
		var placed := 0
		var tries := 0
		while placed < pairs and tries < 200:
			tries += 1
			var x := rng.randi_range(4, a.w / 2 - 2)
			var y := rng.randi_range(3, a.h - 4)
			var i := a.idx(x, y)
			if not (a.terrain[i] in [Arena.T.CLEAR, Arena.T.PAVEMENT, Arena.T.ROUGH]) or a.depth[i] > 0:
				continue
			var far := true
			for sp in a.spawns:
				for p in sp:
					if a.center_of(Vector2i(x, y)).distance_to(p) < 70.0:
						far = false
			for hz in a.hazards:
				if (hz["pos"] as Vector2).distance_to(a.center_of(Vector2i(x, y))) < 60.0:
					far = false
			if not far:
				continue
			var phase := rng.randf_range(0.0, float(d.get("period", 20.0)))
			for c in [Vector2i(x, y), Vector2i(a.w - 1 - x, a.h - 1 - y)]:
				var ci := a.idx(c.x, c.y)
				var hz := {"type": d["type"], "pos": a.center_of(c), "cell": ci, "period": float(d.get("period", 20.0)),
					"active": float(d.get("active", 4.0)), "phase": phase, "reach_m": float(d.get("reach_m", 45.0)),
					"damage": int(d.get("damage", 5))}
				var hi := a.hazards.size()
				a.hazards.append(hz)
				match d["type"]:
					"steam_vents":
						for dy in range(-1, 2):
							for dx in range(-1, 2):
								if a.inside(c.x + dx, c.y + dy):
									a.vent_cells[a.idx(c.x + dx, c.y + dy)] = hi
					"shock_pylons":
						a.terrain[ci] = Arena.T.BUILDING
						a.bld_h[ci] = 3
						a.bld_cf[ci] = 99999
						a.bld_id[ci] = Settlement.new_id(a)
						a.bld_kind[ci] = Settlement.K.NONE
						a.zone[ci] = Settlement.Z.NONE
						a.pylon_cells[ci] = hi
			placed += 1


static func _validate(a: Arena) -> bool:
	for t in range(1, a.spawns.size()):
		var p := a.find_path(a.spawns[0][0], a.spawns[t][0])
		if p.is_empty():
			return false
	for k in a.spawns[0].size():
		if a.spawns.size() > 1 and k < a.spawns[1].size():
			if a.find_path(a.spawns[0][k], a.spawns[1][k]).is_empty():
				return false
	return true
