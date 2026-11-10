extends Node2D
## The battlefield, drawn top-down:
## - ground on the GPU (terrain.gdshader) from per-cell data textures: blended terrain, relief, water,
##   roads, building shadows, and live ash, rubble and fire glow,
## - instanced tree canopies with shadows (conifers in the cold biomes),
## - 2.5D buildings: walls and roofs with rooftop gear, lit windows at night, cracks when damaged,
## - around Solaris arenas, the arena wall and the crowd in the stands; around battlefields, a dark fall-off.
## Live changes follow the playback time (set_time), so scrubbing back shows the field as it was.

const TownView := preload("res://ui/fight/town_view.gd")
const PX := 2.4
const BLD_SHIFT := 7.5   # screen pixels of wall per building level (the 2.5D lean)

const PALETTES := {
	"default": {"a": [0.47, 0.52, 0.31], "b": [0.41, 0.47, 0.27], "dirt": [0.47, 0.41, 0.31], "rock": [0.52, 0.5, 0.46], "forest": [0.2, 0.27, 0.15],
		"ws": [0.2, 0.38, 0.45], "wd": [0.06, 0.16, 0.27], "asphalt": [0.27, 0.28, 0.3], "tree": [0.26, 0.42, 0.2]},
	"bowl": {"a": [0.63, 0.55, 0.41], "b": [0.57, 0.49, 0.36], "dirt": [0.5, 0.42, 0.3], "rock": [0.56, 0.51, 0.45], "forest": [0.26, 0.3, 0.17], "tree": [0.27, 0.4, 0.19], "sand": 0.6},
	"factory": {"a": [0.46, 0.46, 0.45], "b": [0.42, 0.42, 0.42], "dirt": [0.37, 0.35, 0.33], "rock": [0.43, 0.42, 0.41], "forest": [0.22, 0.25, 0.18], "tree": [0.25, 0.33, 0.2], "paved": 1.0, "asphalt": [0.37, 0.37, 0.38]},
	"jungle": {"a": [0.27, 0.42, 0.18], "b": [0.21, 0.35, 0.14], "dirt": [0.36, 0.3, 0.2], "rock": [0.4, 0.4, 0.34], "forest": [0.11, 0.2, 0.09],
		"ws": [0.16, 0.32, 0.3], "wd": [0.05, 0.15, 0.17], "tree": [0.17, 0.38, 0.15]},
	"boreal": {"a": [0.58, 0.63, 0.62], "b": [0.5, 0.56, 0.54], "dirt": [0.42, 0.4, 0.36], "rock": [0.5, 0.52, 0.53], "forest": [0.2, 0.26, 0.24], "tree": [0.14, 0.28, 0.22], "snow": 0.7, "conifer": true},
	"urban": {"a": [0.43, 0.45, 0.41], "b": [0.38, 0.4, 0.37], "dirt": [0.38, 0.36, 0.33], "rock": [0.46, 0.45, 0.43], "forest": [0.2, 0.27, 0.16], "tree": [0.24, 0.38, 0.19], "asphalt": [0.3, 0.31, 0.33]},
	"canyon": {"a": [0.67, 0.47, 0.32], "b": [0.59, 0.4, 0.28], "dirt": [0.52, 0.36, 0.25], "rock": [0.62, 0.43, 0.31], "forest": [0.3, 0.3, 0.18], "tree": [0.3, 0.38, 0.2], "sand": 0.4},
	"bf_plains": {"a": [0.49, 0.54, 0.31], "b": [0.42, 0.48, 0.27]},
	"bf_hills": {"a": [0.45, 0.51, 0.29], "b": [0.38, 0.45, 0.25]},
	"bf_forest": {"a": [0.36, 0.46, 0.25], "b": [0.3, 0.4, 0.21], "tree": [0.2, 0.36, 0.17]},
	"bf_jungle": {"a": [0.27, 0.42, 0.18], "b": [0.21, 0.35, 0.14], "dirt": [0.36, 0.3, 0.2], "forest": [0.11, 0.2, 0.09],
		"ws": [0.16, 0.32, 0.3], "wd": [0.05, 0.15, 0.17], "tree": [0.17, 0.38, 0.15]},
	"bf_desert": {"a": [0.79, 0.67, 0.46], "b": [0.72, 0.6, 0.41], "dirt": [0.66, 0.53, 0.37], "rock": [0.66, 0.55, 0.43], "forest": [0.4, 0.38, 0.24], "tree": [0.36, 0.42, 0.24], "sand": 1.0},
	"bf_badlands": {"a": [0.63, 0.48, 0.34], "b": [0.55, 0.41, 0.29], "dirt": [0.5, 0.37, 0.27], "rock": [0.53, 0.41, 0.33], "forest": [0.3, 0.3, 0.2], "tree": [0.32, 0.38, 0.22], "sand": 0.35},
	"bf_arctic": {"a": [0.7, 0.75, 0.78], "b": [0.62, 0.68, 0.72], "dirt": [0.45, 0.45, 0.45], "rock": [0.5, 0.53, 0.56], "forest": [0.22, 0.28, 0.27], "tree": [0.14, 0.25, 0.22], "snow": 1.0, "conifer": true,
		"ws": [0.3, 0.45, 0.55], "wd": [0.12, 0.22, 0.33]},
	"bf_urban": {"a": [0.45, 0.48, 0.38], "b": [0.4, 0.43, 0.35]},
	"bf_mountains": {"a": [0.46, 0.5, 0.38], "b": [0.42, 0.45, 0.37], "rock": [0.53, 0.53, 0.52], "snow": 0.25, "conifer": true, "tree": [0.17, 0.3, 0.2]},
	"bf_coast": {"a": [0.5, 0.54, 0.34], "b": [0.44, 0.48, 0.3], "ws": [0.18, 0.42, 0.5], "wd": [0.05, 0.19, 0.33]},
}
const ROOFS := [[0.46, 0.47, 0.5], [0.52, 0.36, 0.3], [0.34, 0.38, 0.42], [0.44, 0.42, 0.36], [0.3, 0.4, 0.4], [0.55, 0.53, 0.48]]

var arena: Arena
var theme: Dictionary
var pal: Dictionary
var night := 0.0
var ground: Sprite2D
var mat: ShaderMaterial
var img_c: Image
var tex_c: ImageTexture
var trees_mm: MultiMesh
var shade_mm: MultiMesh
var tree_cell: PackedInt32Array
var tree_col: PackedColorArray
var bld_node: Node2D
var streets_node: Node2D
var buildings: Array = []        # {"cells", "h", "roof", "seed", "pylon", "id", "kind", "rect", "full"}, south-most last
var bld_of: Dictionary = {}      # cell -> building index
var cf0: Dictionary = {}         # cell -> starting construction factor
var scorch: Array = []           # [t, cell] scorch marks from explosions
var _orig_terrain: PackedByteArray
var _orig_h: PackedByteArray
var _live_cells: Dictionary = {}
var _live_key := ""
var _bld_key := ""
var _pt := 0.0


func setup(a: Arena) -> void:
	arena = a
	theme = GameData.db().arenas["themes"].get(a.theme, {})
	pal = PALETTES["default"].duplicate()
	var over: Dictionary = PALETTES.get(a.theme, {})
	for k in over:
		pal[k] = over[k]
	_capture_start()
	_build_ground()
	_build_trees()
	_build_buildings()
	queue_redraw()


func set_night(n: float) -> void:
	night = n
	if mat != null:
		mat.set_shader_parameter("night", n)
	if trees_mm != null:
		_tint_trees(true)
	if bld_node != null:
		bld_node.queue_redraw()
	if streets_node != null:
		streets_node.queue_redraw()


## The field as it was before the fight changed it (the sim edits terrain in place).
func _capture_start() -> void:
	_orig_terrain = arena.terrain.duplicate()
	_orig_h = arena.bld_h.duplicate()
	for i in arena.burned_from:
		_orig_terrain[i] = int(arena.burned_from[i])
	for i in arena.collapsed_at:
		_orig_terrain[i] = Arena.T.BUILDING
		_orig_h[i] = int(arena.collapsed_h.get(i, 2))
	for i in arena.w * arena.h:
		if _orig_terrain[i] == Arena.T.BUILDING:
			cf0[i] = maxi(1, int(arena.bld_cf[i]))


static func _col(v: Variant) -> Color:
	var a: Array = v
	return Color(float(a[0]), float(a[1]), float(a[2]))


func _build_ground() -> void:
	var w := arena.w
	var h := arena.h
	var ia := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var ib := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img_c = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img_c.fill(Color(0, 0, 0, 0))
	var maxl := 1
	for i in w * h:
		maxl = maxi(maxl, int(arena.height[i]))
	var max_level := float(maxl + 1)
	for y in h:
		for x in w:
			var i := arena.idx(x, y)
			var t: int = _orig_terrain[i]
			ia.set_pixel(x, y, Color(1.0 if t == Arena.T.LIGHT_WOODS else 0.0, 1.0 if t == Arena.T.HEAVY_WOODS else 0.0,
				1.0 if t == Arena.T.ROUGH else 0.0, 1.0 if t == Arena.T.RUBBLE else 0.0))
			var wv := 0.0
			if t == Arena.T.WATER:
				wv = 0.55 if arena.depth[i] <= 1 else 1.0
			var bh := 0.0
			if t == Arena.T.BUILDING:
				bh = clampf(float(_orig_h[i]) / 5.0, 0.1, 1.0)
			ib.set_pixel(x, y, Color(wv, 1.0 if t == Arena.T.PAVEMENT else 0.0, float(arena.height[i]) / max_level, bh))
	var noise := NoiseTexture2D.new()
	noise.width = 512
	noise.height = 512
	noise.seamless = true
	noise.generate_mipmaps = true
	var fn := FastNoiseLite.new()
	fn.seed = arena.seed_value + 3
	fn.frequency = 0.012
	fn.fractal_octaves = 5
	noise.noise = fn
	var grain := NoiseTexture2D.new()
	grain.width = 256
	grain.height = 256
	grain.seamless = true
	grain.generate_mipmaps = true
	var gn := FastNoiseLite.new()
	gn.seed = arena.seed_value + 7
	gn.frequency = 0.06
	gn.fractal_octaves = 3
	gn.noise_type = FastNoiseLite.TYPE_CELLULAR if pal.has("paved") else FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	grain.noise = gn
	tex_c = ImageTexture.create_from_image(img_c)
	mat = ShaderMaterial.new()
	mat.shader = load("res://ui/fight/terrain.gdshader")
	mat.set_shader_parameter("data_a", ImageTexture.create_from_image(ia))
	mat.set_shader_parameter("data_b", ImageTexture.create_from_image(ib))
	mat.set_shader_parameter("data_c", tex_c)
	mat.set_shader_parameter("noise", noise)
	mat.set_shader_parameter("grain", grain)
	mat.set_shader_parameter("cells", Vector2(w, h))
	mat.set_shader_parameter("max_level", max_level)
	mat.set_shader_parameter("ground_a", _col(pal["a"]))
	mat.set_shader_parameter("ground_b", _col(pal["b"]))
	mat.set_shader_parameter("dirt", _col(pal["dirt"]))
	mat.set_shader_parameter("rock", _col(pal["rock"]))
	mat.set_shader_parameter("forest_floor", _col(pal["forest"]))
	mat.set_shader_parameter("water_shallow", _col(pal["ws"]))
	mat.set_shader_parameter("water_deep", _col(pal["wd"]))
	mat.set_shader_parameter("asphalt", _col(pal["asphalt"]))
	mat.set_shader_parameter("snow", float(pal.get("snow", 0.0)))
	mat.set_shader_parameter("sand", float(pal.get("sand", 0.0)))
	mat.set_shader_parameter("paved_floor", float(pal.get("paved", 0.0)))
	mat.set_shader_parameter("night", night)
	ground = Sprite2D.new()
	var one := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	one.fill(Color.WHITE)
	ground.texture = ImageTexture.create_from_image(one)
	ground.centered = false
	ground.scale = Vector2(w, h) * Arena.CELL * PX
	ground.material = mat
	add_child(ground)


# ------------------------------------------------------------------ trees

static func _canopy_texture(conifer: bool, seed_v: int) -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var fn := FastNoiseLite.new()
	fn.seed = seed_v
	fn.frequency = 0.11
	var light := Vector3(-0.55, -0.65, 0.55).normalized()
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var d := p.length()
			var ang := atan2(p.y, p.x)
			var edge := 0.8 + 0.1 * sin(ang * 7.0 + 1.3) + 0.06 * fn.get_noise_2d(cos(ang) * 30.0, sin(ang) * 30.0)
			if conifer:
				edge = 0.55 + 0.33 * pow(absf(sin(ang * 4.0)), 0.6) + 0.05 * fn.get_noise_2d(x, y)
			var a := clampf((edge - d) / 0.09, 0.0, 1.0)
			if a <= 0.0:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var z := sqrt(maxf(0.0, 1.0 - minf(1.0, d / maxf(edge, 0.01)) * minf(1.0, d / maxf(edge, 0.01))))
			var nrm := Vector3(p.x, p.y, z * 1.2).normalized()
			var lum := 0.42 + 0.62 * clampf(nrm.dot(light), 0.0, 1.0)
			var clump := fn.get_noise_2d(x * 2.0, y * 2.0) * 0.22 + fn.get_noise_2d(x * 5.0, y * 5.0) * 0.12
			if conifer:
				clump = fn.get_noise_2d(x * 3.0, y * 3.0) * 0.18 - (1.0 - d) * 0.05
			lum = clampf(lum + clump, 0.15, 1.15)
			img.set_pixel(x, y, Color(lum, lum, lum, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _quad(size: float) -> ArrayMesh:
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	var hs := size / 2.0
	arr[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-hs, -hs), Vector2(hs, -hs), Vector2(hs, hs), Vector2(-hs, hs)])
	arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	arr[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_trees() -> void:
	var rng := SimRng.new(arena.seed_value + 17)
	var conifer := bool(pal.get("conifer", false))
	var base := _col(pal["tree"])
	if float(pal.get("snow", 0.0)) > 0.5:
		base = base.lerp(Color(0.75, 0.8, 0.82), 0.18)
	var xs: Array = []
	tree_cell = PackedInt32Array()
	tree_col = PackedColorArray()
	for y in arena.h:
		for x in arena.w:
			var i := arena.idx(x, y)
			var t: int = _orig_terrain[i]
			if t != Arena.T.LIGHT_WOODS and t != Arena.T.HEAVY_WOODS:
				continue
			var heavy := t == Arena.T.HEAVY_WOODS
			var n := 2 if not heavy else 4
			for k in n:
				var p := Vector2((x + rng.randf_range(0.0, 1.0)) * Arena.CELL, (y + rng.randf_range(0.0, 1.0)) * Arena.CELL) * PX
				var r := rng.randf_range(4.5, 8.0) * PX * (0.85 if not heavy else 1.05)
				var col := base.lightened(rng.randf_range(-0.06, 0.12)) if rng.chance(0.5) else base.darkened(rng.randf_range(0.0, 0.15))
				if heavy:
					col = col.darkened(0.08)
				xs.append([p, r, rng.randf_range(0.0, TAU)])
				tree_cell.append(i)
				tree_col.append(col)
	var mesh := _quad(1.0)
	trees_mm = MultiMesh.new()
	trees_mm.transform_format = MultiMesh.TRANSFORM_2D
	trees_mm.use_colors = true
	trees_mm.mesh = mesh
	trees_mm.instance_count = xs.size()
	shade_mm = MultiMesh.new()
	shade_mm.transform_format = MultiMesh.TRANSFORM_2D
	shade_mm.use_colors = true
	shade_mm.mesh = mesh
	shade_mm.instance_count = xs.size()
	for k in xs.size():
		var e: Array = xs[k]
		var d: float = float(e[1]) * 2.0
		var rot: float = 0.0 if conifer else float(e[2])
		trees_mm.set_instance_transform_2d(k, Transform2D(rot, Vector2(d, d), 0.0, e[0]))
		shade_mm.set_instance_transform_2d(k, Transform2D(rot, Vector2(d, d) * 1.05, 0.0, (e[0] as Vector2) + Vector2(d * 0.22, d * 0.3)))
	var tex := _canopy_texture(conifer, arena.seed_value)
	var sh_node := MultiMeshInstance2D.new()
	sh_node.multimesh = shade_mm
	sh_node.texture = tex
	add_child(sh_node)
	var tr_node := MultiMeshInstance2D.new()
	tr_node.multimesh = trees_mm
	tr_node.texture = tex
	add_child(tr_node)
	_tint_trees(true)


## Tree colors for the current time: burned trees vanish, burning ones glow, night dims them.
func _tint_trees(all := false, changed := {}) -> void:
	if trees_mm == null:
		return
	var dim := 1.0 - night * 0.55
	for k in tree_cell.size():
		var ci := tree_cell[k]
		if not all and not changed.has(ci):
			continue
		var c := tree_col[k]
		var v := int(_live_cells.get(ci, 0))
		if v & 1:
			trees_mm.set_instance_color(k, Color(0, 0, 0, 0))
			shade_mm.set_instance_color(k, Color(0, 0, 0, 0))
			continue
		if v & 2:
			c = c.lerp(Color(0.35, 0.12, 0.04), 0.6)
		c = Color(c.r * dim, c.g * dim, c.b * (dim + night * 0.2), 1.0)
		trees_mm.set_instance_color(k, c)
		shade_mm.set_instance_color(k, Color(0, 0, 0, 0.34 * (1.0 - night * 0.5)))


# ------------------------------------------------------------------ buildings

func _build_buildings() -> void:
	# settlement buildings come with an id; loose cells (old-style arenas) are grouped by flood fill
	var by_id := {}
	var seen := {}
	var groups: Array = []
	for i in arena.w * arena.h:
		if _orig_terrain[i] != Arena.T.BUILDING:
			continue
		var id := int(arena.bld_id[i])
		if id > 0:
			if not by_id.has(id):
				by_id[id] = groups.size()
				groups.append([id, []])
			(groups[by_id[id]][1] as Array).append(i)
	for i in arena.w * arena.h:
		if _orig_terrain[i] != Arena.T.BUILDING or seen.has(i) or int(arena.bld_id[i]) > 0:
			continue
		var cells: Array = []
		var q: Array = [i]
		seen[i] = true
		var lv := int(_orig_h[i])
		while not q.is_empty():
			var c: int = q.pop_front()
			cells.append(c)
			var x := c % arena.w
			var y := c / arena.w
			for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + o.x
				var ny: int = y + o.y
				if not arena.inside(nx, ny):
					continue
				var j := arena.idx(nx, ny)
				if not seen.has(j) and _orig_terrain[j] == Arena.T.BUILDING and int(arena.bld_id[j]) == 0 and int(_orig_h[j]) == lv and cells.size() < 64:
					seen[j] = true
					q.append(j)
		groups.append([0, cells])
	for g in groups:
		var cells2: Array = g[1]
		var first: int = cells2[0]
		var r := Rect2i(first % arena.w, first / arena.w, 1, 1)
		for c in cells2:
			r = r.expand(Vector2i(int(c) % arena.w, int(c) / arena.w))
		r.size += Vector2i(1, 1)
		var hh := absi(hash(first * 7919 + arena.seed_value))
		var roof := _col(ROOFS[hh % ROOFS.size()])
		if arena.theme in ["factory", "urban"] or arena.theme == "bf_urban":
			roof = roof.lerp(Color(0.42, 0.43, 0.46), 0.4)
		buildings.append({"cells": cells2, "h": int(_orig_h[first]), "roof": roof, "seed": hh, "pylon": arena.pylon_cells.has(first),
			"id": int(g[0]) if int(g[0]) > 0 else hh, "kind": int(arena.bld_kind[first]), "rect": r, "full": cells2.size() == r.get_area()})
	# painter's order: northern buildings first, so the southern ones' walls and roofs overlap them
	buildings.sort_custom(func(p: Dictionary, q2: Dictionary) -> bool:
		var pr: Rect2i = p["rect"]
		var qr: Rect2i = q2["rect"]
		return pr.end.y < qr.end.y or (pr.end.y == qr.end.y and pr.position.x < qr.position.x))
	for bi in buildings.size():
		for c2 in buildings[bi]["cells"]:
			bld_of[c2] = bi
	streets_node = Node2D.new()
	streets_node.draw.connect(func(): TownView.draw_streets(streets_node, arena, _orig_terrain, Arena.CELL * PX, night))
	add_child(streets_node)
	move_child(streets_node, ground.get_index() + 1)
	bld_node = Node2D.new()
	bld_node.draw.connect(_draw_buildings)
	add_child(bld_node)


func _standing(i: int) -> bool:
	return not (arena.collapsed_at.has(i) and float(arena.collapsed_at[i]) <= _pt)


func _draw_buildings() -> void:
	var cv := bld_node
	var cell := Arena.CELL * PX
	var lit := night > 0.2
	for bi in buildings.size():
		var b: Dictionary = buildings[bi]
		var cells: Array = b["cells"]
		if b["pylon"]:
			for c in cells:
				if _standing(c):
					_draw_pylon(cv, c, cell)
			continue
		var standing := 0
		var dmg := 0.0
		for c in cells:
			if _standing(c):
				standing += 1
			dmg += clampf(1.0 - float(arena.bld_cf[c]) / float(cf0.get(c, 1)), 0.0, 1.0)
		if standing == 0:
			continue
		if int(b["kind"]) != Settlement.K.NONE and bool(b["full"]) and standing == cells.size():
			TownView.draw_building(cv, b, cell, BLD_SHIFT, night, dmg / cells.size())
		else:
			_draw_cells(cv, bi, cell, lit)


## A building drawn cell by cell: loose old-style blocks, and settlement buildings once part of
## them has come down.
func _draw_cells(cv: Node2D, bi: int, cell: float, lit: bool) -> void:
	var b: Dictionary = buildings[bi]
	var cells: Array = (b["cells"] as Array).duplicate()
	cells.sort()
	for i: int in cells:
		var y := i / arena.w
		if not _standing(i):
			continue
		if true:
			var lv := float(b["h"])
			var hs := lv * BLD_SHIFT
			var x := i % arena.w
			var pos := Vector2(x, y) * cell
			var roof: Color = b["roof"]
			var dmg := 1.0 - float(arena.bld_cf[i]) / float(cf0.get(i, 1))
			if dmg > 0.0:
				roof = roof.lerp(Color(0.15, 0.13, 0.12), clampf(dmg * 0.7, 0.0, 0.6))
			if night > 0.0:
				roof = roof.darkened(night * 0.45)
			# south wall where the building ends (or steps down)
			var below := i + arena.w
			var wall_here := y + 1 >= arena.h or not bld_of.has(below) or not _standing(below) or float(buildings[bld_of[below]]["h"]) < lv
			if wall_here:
				var wtop := pos.y + cell - hs
				var wc := roof.darkened(0.42)
				cv.draw_polygon(PackedVector2Array([Vector2(pos.x, wtop), Vector2(pos.x + cell, wtop), Vector2(pos.x + cell, pos.y + cell), Vector2(pos.x, pos.y + cell)]),
					PackedColorArray([wc, wc, wc.darkened(0.35), wc.darkened(0.35)]))
				# windows, one row per level
				for k in int(lv):
					var wy := wtop + (k + 0.3) * BLD_SHIFT
					for m in 3:
						var wx := pos.x + 3.0 + m * (cell - 6.0) / 3.0
						var on := lit and (absi(hash(i * 31 + k * 7 + m)) % 5 < 2)
						var gc := Color(1.0, 0.82, 0.45, 0.95) if on else Color(0.12, 0.16, 0.2, 0.8).lerp(Color(0.5, 0.6, 0.7, 0.6), 0.25 * (1.0 - night))
						cv.draw_rect(Rect2(Vector2(wx, wy), Vector2((cell - 6.0) / 3.0 - 2.5, BLD_SHIFT * 0.45)), gc)
			# roof
			var rp := pos - Vector2(0, hs)
			var rc := roof.lightened(((absi(hash(i)) % 7) - 3) * 0.006)
			cv.draw_rect(Rect2(rp, Vector2(cell, cell)), rc)
			# edges against the outside: lit top and left, dark bottom and right
			var hi := roof.lightened(0.28)
			var lo := roof.darkened(0.35)
			var nb := func(dx: int, dy: int) -> bool:
				var nx: int = x + dx
				var ny: int = y + dy
				if not arena.inside(nx, ny):
					return false
				var j := arena.idx(nx, ny)
				return bld_of.has(j) and bld_of[j] == bld_of[i] and _standing(j)
			if not nb.call(0, -1):
				cv.draw_line(rp, rp + Vector2(cell, 0), hi, 2.0)
			if not nb.call(-1, 0):
				cv.draw_line(rp, rp + Vector2(0, cell), hi, 2.0)
			if not nb.call(1, 0):
				cv.draw_line(rp + Vector2(cell, 0), rp + Vector2(cell, cell), lo, 2.0)
			if not nb.call(0, 1):
				cv.draw_line(rp + Vector2(0, cell), rp + Vector2(cell, cell), lo, 2.0)
			# rooftop gear on some cells
			var hh := absi(hash(i * 131 + int(b["seed"])))
			if hh % 4 == 0:
				var s := 5.0 + float(hh % 5)
				var gp := rp + Vector2(4.0 + float((hh >> 3) % 9), 4.0 + float((hh >> 7) % 9))
				cv.draw_rect(Rect2(gp + Vector2(2, 3), Vector2(s, s * 0.8)), Color(0, 0, 0, 0.3))
				cv.draw_rect(Rect2(gp, Vector2(s, s * 0.8)), roof.lightened(0.14))
				cv.draw_rect(Rect2(gp, Vector2(s, s * 0.8)), roof.darkened(0.3), false, 1.0)
			elif hh % 7 == 1:
				cv.draw_circle(rp + Vector2(cell * 0.5, cell * 0.5), 3.5, roof.darkened(0.3))
				cv.draw_arc(rp + Vector2(cell * 0.5, cell * 0.5), 3.5, 0, TAU, 12, roof.lightened(0.2), 1.0)
			if dmg > 0.35:
				var crack := Color(0.06, 0.05, 0.05, 0.8)
				var a := rp + Vector2(float(hh % 20), 2)
				cv.draw_polyline(PackedVector2Array([a, a + Vector2(4, 7), a + Vector2(1, 13), a + Vector2(6, 19)]), crack, 1.4)


func _draw_pylon(cv: Node2D, i: int, cell: float) -> void:
	var c := arena.center_of_index(i) * PX
	cv.draw_circle(c + Vector2(6, 8), cell * 0.5, Color(0, 0, 0, 0.35))
	cv.draw_circle(c, cell * 0.48, Color(0.32, 0.35, 0.42))
	cv.draw_circle(c - Vector2(0, 10), cell * 0.32, Color(0.48, 0.52, 0.62))
	cv.draw_circle(c - Vector2(0, 16), 5.0, Color(0.6, 0.85, 1.0))
	cv.draw_arc(c - Vector2(0, 16), 8.0, 0, TAU, 20, Color(0.6, 0.85, 1.0, 0.6), 2.0)


# ------------------------------------------------------------------ live state

## Scorch mark left by an explosion (shown from time t on).
func add_scorch(t: float, p: Vector2) -> void:
	scorch.append([t, arena.cell_index(p)])
	_live_key = ""


## Follows the playback time: ash, fire, collapsed buildings and scorch marks.
func set_time(pt: float) -> void:
	_pt = pt
	var nb := 0
	for i in arena.burned_at:
		if float(arena.burned_at[i]) <= pt:
			nb += 1
	var nf := 0
	for i in arena.fire_start:
		if arena.burning(i, pt):
			nf += 1
	var nc := 0
	for i in arena.collapsed_at:
		if float(arena.collapsed_at[i]) <= pt:
			nc += 1
	var ns := 0
	for s in scorch:
		if float(s[0]) <= pt:
			ns += 1
	var key := "%d|%d|%d|%d|%d" % [nb, nf, nc, ns, int(pt * 2.0) if nf > 0 else 0]
	if key == _live_key:
		return
	_live_key = key
	var cells := {}
	for i in arena.burned_at:
		if float(arena.burned_at[i]) <= pt:
			cells[i] = int(cells.get(i, 0)) | 1
	for i in arena.fire_start:
		if arena.burning(i, pt):
			cells[i] = int(cells.get(i, 0)) | 2
	for i in arena.collapsed_at:
		if float(arena.collapsed_at[i]) <= pt:
			cells[i] = int(cells.get(i, 0)) | 4
	for s in scorch:
		if float(s[0]) <= pt:
			cells[int(s[1])] = int(cells.get(int(s[1]), 0)) | 8
	var changed := {}
	for i in _live_cells:
		if int(cells.get(i, 0)) != int(_live_cells[i]):
			changed[i] = true
	for i in cells:
		if int(_live_cells.get(i, 0)) != int(cells[i]):
			changed[i] = true
	_live_cells = cells
	for i in changed:
		var v := int(cells.get(i, 0))
		img_c.set_pixel(int(i) % arena.w, int(i) / arena.w, Color(1.0 if v & 1 else 0.0, 1.0 if v & 2 else 0.0, 1.0 if v & 4 else 0.0, 1.0 if v & 8 else 0.0))
	if not changed.is_empty():
		tex_c.update(img_c)
		_tint_trees(false, changed)
	var bkey := "%d|%d" % [nc, _damage_key()]
	if bkey != _bld_key:
		_bld_key = bkey
		bld_node.queue_redraw()


func _damage_key() -> int:
	var k := 0
	for i in cf0:
		k += int(arena.bld_cf[i] < int(cf0[i]) * 0.65)
	return k


# ------------------------------------------------------------------ the frame around the field

func _draw() -> void:
	var size := Vector2(arena.w, arena.h) * Arena.CELL * PX
	if bool(theme.get("battlefield", false)):
		# battlefields fade into the dark past the map edge
		var f := 260.0
		var dark := Color(0.02, 0.025, 0.035, 1.0)
		var clear := Color(0.02, 0.025, 0.035, 0.0)
		var quads := [
			[Vector2(-f, -f), Vector2(size.x + f, -f), Vector2(size.x, 0), Vector2(0, 0)],
			[Vector2(0, size.y), Vector2(size.x, size.y), Vector2(size.x + f, size.y + f), Vector2(-f, size.y + f)],
			[Vector2(-f, -f), Vector2(0, 0), Vector2(0, size.y), Vector2(-f, size.y + f)],
			[Vector2(size.x, 0), Vector2(size.x + f, -f), Vector2(size.x + f, size.y + f), Vector2(size.x, size.y)],
		]
		var cols := [[dark, dark, clear, clear], [clear, clear, dark, dark], [dark, clear, clear, dark], [clear, dark, dark, clear]]
		draw_rect(Rect2(Vector2(-f * 6, -f * 6), size + Vector2(f * 12, f * 12)), Color(0.02, 0.025, 0.035), true)
		for k in 4:
			draw_polygon(PackedVector2Array(quads[k]), PackedColorArray(cols[k]))
		return
	# Solaris arenas: the wall, the stands and the crowd
	var rng := SimRng.new(arena.seed_value + 5)
	var stand := 150.0
	draw_rect(Rect2(Vector2(-stand - 40, -stand - 40), size + Vector2(stand + 40, stand + 40) * 2.0), Color(0.05, 0.055, 0.065))
	for tier in 6:
		var o := 26.0 + tier * 20.0
		var r := Rect2(Vector2(-o, -o), size + Vector2(o, o) * 2.0)
		draw_rect(r, Color(0.09, 0.095, 0.11).lightened(tier * 0.015), false, 18.0)
		# the crowd: dots of every color
		var per := int((r.size.x + r.size.y) * 2.0 / 12.0)
		for k in per:
			var f2 := rng.randf()
			var side := rng.randi_range(0, 3)
			var p := Vector2.ZERO
			match side:
				0:
					p = Vector2(r.position.x + f2 * r.size.x, r.position.y)
				1:
					p = Vector2(r.position.x + f2 * r.size.x, r.end.y)
				2:
					p = Vector2(r.position.x, r.position.y + f2 * r.size.y)
				3:
					p = Vector2(r.end.x, r.position.y + f2 * r.size.y)
			p += Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
			var cc := Color.from_hsv(rng.randf(), rng.randf_range(0.1, 0.45), rng.randf_range(0.28, 0.6))
			draw_circle(p, 2.0, Color(cc.r, cc.g, cc.b, 0.75).darkened(night * 0.5))
	# the wall: concrete with hazard striping on the arena side
	draw_rect(Rect2(Vector2(-16, -16), size + Vector2(32, 32)), Color(0.42, 0.42, 0.44), false, 16.0)
	var stripe := 18.0
	var per_side := [size.x, size.y, size.x, size.y]
	for s in 4:
		var n := int(per_side[s] / stripe)
		for k in n:
			if k % 2 == 1:
				continue
			var a := k * stripe
			var rr := Rect2()
			match s:
				0:
					rr = Rect2(Vector2(a, -6), Vector2(stripe, 6))
				1:
					rr = Rect2(Vector2(size.x, a), Vector2(6, stripe))
				2:
					rr = Rect2(Vector2(a, size.y), Vector2(stripe, 6))
				3:
					rr = Rect2(Vector2(-6, a), Vector2(6, stripe))
			draw_rect(rr, Color(0.85, 0.68, 0.12))
	draw_rect(Rect2(Vector2(-6, -6), size + Vector2(12, 12)), Color(0.1, 0.1, 0.1), false, 2.0)
	# floodlight towers at the corners
	for cnr in [Vector2(-30, -30), Vector2(size.x + 30, -30), Vector2(-30, size.y + 30), size + Vector2(30, 30)]:
		draw_circle(cnr + Vector2(5, 6), 15.0, Color(0, 0, 0, 0.4))
		draw_circle(cnr, 14.0, Color(0.3, 0.31, 0.34))
		draw_circle(cnr, 8.0, Color(1.0, 0.96, 0.8, 0.9 if night > 0.0 else 0.5))
