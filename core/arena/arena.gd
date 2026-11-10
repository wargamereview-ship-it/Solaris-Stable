class_name Arena
extends RefCounted
## A generated arena: a heightmap plus 10 m terrain cells. 'Mechs move freely in meters;
## cells only set movement cost, cover and line of sight. The arena also carries the live battlefield
## state the fight changes: burning woods, smoke, collapsed buildings and the arena's own hazards.
## Every change is stamped with the sim time it happened, so the viewer can show any moment.

const CELL := 10.0        # meters per cell
const LEVEL_M := 6.0      # meters per elevation level (tabletop level)
const MECH_LEVELS := 2.0  # a standing 'Mech is two levels tall

enum T { CLEAR, PAVEMENT, ROUGH, LIGHT_WOODS, HEAVY_WOODS, WATER, BUILDING, RUBBLE }
const T_NAMES := ["clear", "pavement", "rough", "light woods", "heavy woods", "water", "building", "rubble"]

var w := 0
var h := 0
var theme := ""
var arena_id := ""
var seed_value := 0
var height := PackedInt32Array()
var terrain := PackedByteArray()
var depth := PackedByteArray()
var bld_h := PackedByteArray()
var bld_cf := PackedInt32Array()
var bld_id := PackedInt32Array()     # which building a cell belongs to (0: a loose cell), for the viewer
var bld_kind := PackedByteArray()    # Settlement.K: house, tower, warehouse...
var zone := PackedByteArray()        # Settlement.Z: what open ground is used for (street, plaza, parking...)
var next_bld_id := 0
var spawns: Array = []         # Array of Array[Vector2] per team
var spawn_facing: Array = []   # radians per team
var astar: AStarGrid2D
var _astars: Dictionary = {}   # mover -> AStarGrid2D for vehicles ("tracked", "wheeled", "hover", "vtol")

# battlefields (merc mode): deployment edges per team ("W", "E", "N", "S"), objectives, map name
var edges: Array = []
var objectives: Dictionary = {}
var biome := ""

# live state (sim time stamps)
var now := 0.0
var max_los_m := INF
var wind := Vector2i.ZERO                 # smoke drifts one cell downwind
var fire_start: Dictionary = {}           # cell -> t
var fire_end: Dictionary = {}             # cell -> t
var burned_at: Dictionary = {}            # cell -> t (woods burned down a step)
var burned_from: Dictionary = {}          # cell -> original terrain
var collapsed_at: Dictionary = {}         # cell -> t (building became rubble)
var collapsed_h: Dictionary = {}          # cell -> building height before it fell (for the viewer)
var hazards: Array = []                   # {"type", "pos", "cell", "period", "active", "phase", ...}
var vent_cells: Dictionary = {}           # cell -> hazard index (steam vent clouds)
var pylon_cells: Dictionary = {}          # cell -> hazard index


func setup(w_: int, h_: int) -> void:
	w = w_
	h = h_
	var n := w * h
	height.resize(n)
	terrain.resize(n)
	depth.resize(n)
	bld_h.resize(n)
	bld_cf.resize(n)
	bld_id.resize(n)
	bld_kind.resize(n)
	zone.resize(n)
	height.fill(0)
	terrain.fill(T.CLEAR)
	depth.fill(0)
	bld_h.fill(0)
	bld_cf.fill(0)
	bld_id.fill(0)
	bld_kind.fill(0)
	zone.fill(0)


func size_m() -> Vector2:
	return Vector2(w * CELL, h * CELL)


func idx(x: int, y: int) -> int:
	return y * w + x


func inside(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor(p.x / CELL)), 0, w - 1), clampi(int(floor(p.y / CELL)), 0, h - 1))


func cell_index(p: Vector2) -> int:
	var c := cell_of(p)
	return idx(c.x, c.y)


func center_of(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL, (c.y + 0.5) * CELL)


func center_of_index(i: int) -> Vector2:
	return center_of(Vector2i(i % w, i / w))


func terrain_at(p: Vector2) -> int:
	var c := cell_of(p)
	return terrain[idx(c.x, c.y)]


func level_at(p: Vector2) -> int:
	var c := cell_of(p)
	return height[idx(c.x, c.y)]


## Ground height in meters (water surface counts as the bottom: 'Mechs wade).
func ground_m(p: Vector2) -> float:
	var c := cell_of(p)
	var i := idx(c.x, c.y)
	return (height[i] - depth[i]) * LEVEL_M


## Top of whatever occupies the cell (hill, building), in meters.
func obstacle_top_m(x: int, y: int) -> float:
	var i := idx(x, y)
	var top := float(height[i]) * LEVEL_M
	if terrain[i] == T.BUILDING:
		top += bld_h[i] * LEVEL_M
	return top


func passable(x: int, y: int, mover := "mech") -> bool:
	if not inside(x, y):
		return false
	var i := idx(x, y)
	var t: int = terrain[i]
	match mover:
		"mech":
			return t != T.BUILDING and depth[i] < 3
		"vtol":
			return true
		"tracked":
			return t != T.BUILDING and t != T.HEAVY_WOODS and depth[i] == 0
		"wheeled":
			return t in [T.CLEAR, T.PAVEMENT] and depth[i] == 0
		"hover":
			return t in [T.CLEAR, T.PAVEMENT, T.WATER]
	return t != T.BUILDING and depth[i] < 3


func passable_p(p: Vector2, mover := "mech") -> bool:
	var c := cell_of(p)
	return passable(c.x, c.y, mover) and p.x >= 2.0 and p.y >= 2.0 and p.x <= w * CELL - 2.0 and p.y <= h * CELL - 2.0


## Movement points to enter a cell (tabletop costs), by mover: 'Mechs and each vehicle motion type.
func move_cost(x: int, y: int, mover := "mech") -> float:
	var i := idx(x, y)
	if mover == "vtol":
		return 1.0
	if mover != "mech":
		match terrain[i]:
			T.PAVEMENT:
				return 0.8 if mover == "wheeled" else 1.0
			T.ROUGH, T.RUBBLE, T.LIGHT_WOODS:
				return 2.0
			T.WATER:
				return 1.0
		return 1.0
	match terrain[i]:
		T.ROUGH, T.RUBBLE, T.LIGHT_WOODS:
			return 2.0
		T.HEAVY_WOODS:
			return 3.0
		T.WATER:
			return 2.0 if depth[i] <= 1 else 4.0
		T.BUILDING:
			return 99.0
	return 1.0


func _cell_weight(x: int, y: int, mover := "mech") -> float:
	var cost := move_cost(x, y, mover)
	if mover == "vtol":
		return cost
	var hh := height[idx(x, y)]
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nx: int = x + o.x
		var ny: int = y + o.y
		if inside(nx, ny) and absi(height[idx(nx, ny)] - hh) >= 1:
			cost += 0.5
			break
	if burning(idx(x, y)):
		cost += 4.0
	if pylon_cells.has(idx(x, y)):
		cost += 3.0
	return cost


func build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	astar.update()
	for y in h:
		for x in w:
			if not passable(x, y):
				astar.set_point_solid(Vector2i(x, y), true)
			else:
				astar.set_point_weight_scale(Vector2i(x, y), _cell_weight(x, y))


## Pathfinding grid for a vehicle motion type, built the first time a unit of that kind needs one.
func astar_for(mover: String) -> AStarGrid2D:
	if mover == "mech":
		return astar
	if _astars.has(mover):
		return _astars[mover]
	var g := AStarGrid2D.new()
	g.region = Rect2i(0, 0, w, h)
	g.cell_size = Vector2(CELL, CELL)
	g.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	g.default_compute_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	g.default_estimate_heuristic = AStarGrid2D.HEURISTIC_EUCLIDEAN
	g.update()
	for y in h:
		for x in w:
			if not passable(x, y, mover):
				g.set_point_solid(Vector2i(x, y), true)
			else:
				g.set_point_weight_scale(Vector2i(x, y), _cell_weight(x, y, mover))
	_astars[mover] = g
	return g


## Re-reads one cell after the battlefield changed it (fire, collapse).
func refresh_cell(i: int) -> void:
	if astar == null:
		return
	var c := Vector2i(i % w, i / w)
	astar.set_point_solid(c, not passable(c.x, c.y))
	if passable(c.x, c.y):
		astar.set_point_weight_scale(c, _cell_weight(c.x, c.y))
	for mv in _astars:
		var g: AStarGrid2D = _astars[mv]
		g.set_point_solid(c, not passable(c.x, c.y, mv))
		if passable(c.x, c.y, mv):
			g.set_point_weight_scale(c, _cell_weight(c.x, c.y, mv))


## Path in meters from a to b (cell centers, first point dropped). Empty if unreachable.
func find_path(a: Vector2, b: Vector2, mover := "mech") -> PackedVector2Array:
	var ca := cell_of(a)
	var cb := cell_of(b)
	if not passable(cb.x, cb.y, mover):
		cb = nearest_passable(cb, mover)
	if not passable(ca.x, ca.y, mover):
		ca = nearest_passable(ca, mover)
	var pts := astar_for(mover).get_id_path(ca, cb)
	var out := PackedVector2Array()
	for k in range(1, pts.size()):
		out.append(center_of(pts[k]))
	if out.size() > 0:
		out[out.size() - 1] = b if passable_p(b, mover) else out[out.size() - 1]
	return out


func nearest_passable(c: Vector2i, mover := "mech") -> Vector2i:
	for r in range(1, 12):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var x := c.x + dx
				var y := c.y + dy
				if passable(x, y, mover):
					return Vector2i(x, y)
	return c


## Distance in meters from p to a map edge ("W", "E", "N", "S").
func edge_distance(p: Vector2, edge: String) -> float:
	match edge:
		"W":
			return p.x
		"E":
			return w * CELL - p.x
		"N":
			return p.y
		"S":
			return h * CELL - p.y
	return INF


## The point on an edge nearest to p, pulled in a few meters so it is on the map.
func edge_point(p: Vector2, edge: String, inset := 8.0) -> Vector2:
	match edge:
		"W":
			return Vector2(inset, clampf(p.y, inset, h * CELL - inset))
		"E":
			return Vector2(w * CELL - inset, clampf(p.y, inset, h * CELL - inset))
		"N":
			return Vector2(clampf(p.x, inset, w * CELL - inset), inset)
		"S":
			return Vector2(clampf(p.x, inset, w * CELL - inset), h * CELL - inset)
	return p


# ------------------------------------------------------------------ live battlefield queries

func burning(i: int, t := -1.0) -> bool:
	var tt := now if t < 0.0 else t
	return fire_start.has(i) and float(fire_start[i]) <= tt and tt < float(fire_end[i])


func hazard_active(hz: Dictionary, t: float, linger := 0.0) -> bool:
	var ph := fposmod(t + float(hz["phase"]), float(hz["period"]))
	return ph < float(hz["active"]) + linger


## Smoke over a cell: 0 none, 1 light (burning woods), 2 heavy (steam vents).
func smoke_level(i: int, t := -1.0) -> int:
	var tt := now if t < 0.0 else t
	if vent_cells.has(i):
		var hz: Dictionary = hazards[vent_cells[i]]
		if hazard_active(hz, tt, 5.0):
			return 2
	if _smoke_from_fire(i, tt):
		return 1
	if wind != Vector2i.ZERO:
		var x := (i % w) - wind.x
		var y := (i / w) - wind.y
		if inside(x, y) and _smoke_from_fire(idx(x, y), tt):
			return 1
	return 0


func _smoke_from_fire(i: int, t: float) -> bool:
	if not fire_start.has(i):
		return false
	return float(fire_start[i]) <= t and t < float(fire_end[i]) + 15.0


## Line of sight between two 'Mechs. Returns {"clear", "woods" (intervening modifier), "smoke",
## "target_woods", "target_smoke", "partial" (target partially covered), "cover_cell" (cell giving partial cover)}.
## ea, eb: eye heights in meters above sea level for the shooter and target (default: a standing 'Mech).
## A target flying above the trees (eb_air) never counts as in woods or behind partial cover.
func los(a: Vector2, b: Vector2, ea := -INF, eb := -INF, eb_air := false) -> Dictionary:
	var dist := a.distance_to(b)
	if dist > max_los_m:
		return {"clear": false, "woods": 0, "smoke": 0, "target_woods": 0, "target_smoke": 0, "partial": false, "cover_cell": -1, "fog": true}
	var ga := ground_m(a)
	var gb := ground_m(b)
	var za := ga + 1.6 * LEVEL_M if ea == -INF else ea
	var zb := gb + 1.6 * LEVEL_M if eb == -INF else eb
	var steps := maxi(1, int(dist / (CELL * 0.7)))
	var light := 0.0
	var heavy := 0.0
	var lsmoke := 0.0
	var hsmoke := 0.0
	var partial := false
	var cover_cell := -1
	var ca := cell_of(a)
	var cb := cell_of(b)
	var last := Vector2i(-1, -1)
	for s in range(1, steps):
		var f := float(s) / steps
		var p := a.lerp(b, f)
		var c := cell_of(p)
		if c == last or c == ca or c == cb:
			continue
		last = c
		var i := idx(c.x, c.y)
		var line_z := lerpf(za, zb, f)
		var top := obstacle_top_m(c.x, c.y)
		if top >= line_z:
			return {"clear": false, "woods": 0, "smoke": 0, "target_woods": 0, "target_smoke": 0, "partial": false, "cover_cell": i}
		var to_target := dist * (1.0 - f)
		# something tall enough to hide the legs right in front of the target
		if to_target < 25.0 and top >= gb + 0.8 * LEVEL_M:
			partial = true
			cover_cell = i
		var t: int = terrain[i]
		if t == T.LIGHT_WOODS or t == T.HEAVY_WOODS:
			var woods_top := height[i] * LEVEL_M + MECH_LEVELS * LEVEL_M
			if line_z < woods_top:
				if t == T.LIGHT_WOODS:
					light += 1.0
				else:
					heavy += 1.0
		var sm := smoke_level(i)
		if sm == 1:
			lsmoke += 1.0
		elif sm == 2:
			hsmoke += 1.0
	var woods := int(round(light / 3.0)) + int(round(heavy * 2.0 / 3.0))
	var smoke := int(round(lsmoke / 3.0)) + int(round(hsmoke * 2.0 / 3.0))
	var ib := idx(cb.x, cb.y)
	var tb: int = terrain[ib]
	var target_woods := 1 if tb == T.LIGHT_WOODS else (2 if tb == T.HEAVY_WOODS else 0)
	var target_smoke := smoke_level(ib)
	if depth[ib] == 1 and eb == -INF:
		partial = true
	if eb_air:
		target_woods = 0
		partial = false
	var blocked := woods + smoke >= 3
	return {"clear": not blocked, "woods": woods, "smoke": smoke, "target_woods": target_woods, "target_smoke": target_smoke,
		"partial": partial, "cover_cell": cover_cell}
