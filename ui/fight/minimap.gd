extends Control
## The battlefield at a glance for the command view: terrain (one pixel per cell, hill-shaded, in the
## battlefield's own palette), objectives, your units and the enemies you can see (or last saw),
## and the camera's view. Click or drag to move the camera there.

const PX := 2.4

var view            # the command view (sim, sprites, cam, selected, last_seen, arena_view)
var tex: ImageTexture
var _sig := -1
var _t := 0.0
var _drag := false


func setup(v) -> void:
	view = v
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var A: Arena = view.sim.arena
	var w := 294.0
	custom_minimum_size = Vector2(w, clampf(w * float(A.h) / float(A.w), 120.0, 230.0))
	_rebuild()


func _col(key: String, fallback: Array) -> Color:
	var p: Dictionary = view.arena_view.pal
	var a: Array = p.get(key, fallback)
	return Color(float(a[0]), float(a[1]), float(a[2]))


func _rebuild() -> void:
	var A: Arena = view.sim.arena
	_sig = A.collapsed_at.size() * 1000 + A.burned_at.size()
	var img := Image.create(A.w, A.h, false, Image.FORMAT_RGB8)
	var ground := _col("a", [0.47, 0.52, 0.31])
	var dirt := _col("dirt", [0.47, 0.41, 0.31])
	var forest := _col("forest", [0.2, 0.27, 0.15])
	var tree := _col("tree", [0.26, 0.42, 0.2])
	var ws := _col("ws", [0.2, 0.38, 0.45])
	var wd := _col("wd", [0.06, 0.16, 0.27])
	var asphalt := _col("asphalt", [0.27, 0.28, 0.3])
	var maxl := 1
	for y in A.h:
		for x in A.w:
			maxl = maxi(maxl, A.height[A.idx(x, y)])
	for y in A.h:
		for x in A.w:
			var i := A.idx(x, y)
			var t := A.terrain[i]
			var c: Color
			match t:
				Arena.T.PAVEMENT:
					c = asphalt.lightened(0.08)
				Arena.T.ROUGH:
					c = dirt
				Arena.T.LIGHT_WOODS:
					c = tree
				Arena.T.HEAVY_WOODS:
					c = forest.lerp(tree, 0.35)
				Arena.T.WATER:
					c = ws.lerp(wd, clampf(float(A.depth[i]) / 2.0, 0.0, 1.0))
				Arena.T.BUILDING:
					c = Color(0.62, 0.63, 0.66).lerp(Color(0.85, 0.86, 0.88), clampf(float(A.bld_h[i]) / 5.0, 0.0, 1.0))
				Arena.T.RUBBLE:
					c = Color(0.42, 0.39, 0.36)
				_:
					c = ground
			if t != Arena.T.WATER and t != Arena.T.BUILDING:
				var hl := float(A.height[i])
				c = c.lightened(hl / float(maxl) * 0.22) if hl > 0 else c.darkened(-hl * 0.08)
				# light from the north-west
				var nx := A.height[A.idx(maxi(0, x - 1), maxi(0, y - 1))]
				c = c.lightened(0.12) if nx < A.height[i] else (c.darkened(0.14) if nx > A.height[i] else c)
			if A.burning(i):
				c = c.lerp(Color(1.0, 0.45, 0.1), 0.6)
			img.set_pixel(x, y, c)
	if tex == null:
		tex = ImageTexture.create_from_image(img)
	else:
		tex.update(img)


func _map_rect() -> Rect2:
	return Rect2(Vector2(3, 3), size - Vector2(6, 6))


func to_mini(world_px: Vector2) -> Vector2:
	var r := _map_rect()
	var msz: Vector2 = view.sim.arena.size_m() * PX
	return r.position + world_px / msz * r.size


func _process(delta: float) -> void:
	if view == null:
		return
	_t += delta
	var A: Arena = view.sim.arena
	if A.collapsed_at.size() * 1000 + A.burned_at.size() != _sig or (fmod(_t, 2.0) < delta and not A.fire_start.is_empty()):
		_rebuild()
	queue_redraw()


func _draw() -> void:
	var r := _map_rect()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.025, 0.03, 0.9))
	draw_texture_rect(tex, r, false, Color(0.85, 0.85, 0.85) if not bool(view.sim.conditions.get("light", "day") == "night") else Color(0.55, 0.6, 0.75))
	var A: Arena = view.sim.arena
	var px: float = PX
	# exit edges
	for e in view.sim.exit_edges(0):
		var col := Color(0.4, 0.9, 0.5, 0.5) if str(e) == view.sim.home_edge(0) else Color(1.0, 0.8, 0.3, 0.6)
		match str(e):
			"W":
				draw_line(r.position, Vector2(r.position.x, r.end.y), col, 3.0)
			"E":
				draw_line(Vector2(r.end.x, r.position.y), r.end, col, 3.0)
			"N":
				draw_line(r.position, Vector2(r.end.x, r.position.y), col, 3.0)
			"S":
				draw_line(Vector2(r.position.x, r.end.y), r.end, col, 3.0)
	# objectives
	var ob: Dictionary = A.objectives
	for key in ["defend_cells", "attack_cells"]:
		var cc := Color(0.4, 0.7, 1.0) if key == "defend_cells" else Color(1.0, 0.4, 0.3)
		for ci in ob.get(key, []):
			var p := to_mini(A.center_of_index(int(ci)) * px)
			draw_rect(Rect2(p - Vector2(2, 2), Vector2(4, 4)), cc)
	var pts: Array = ob.get("recon_points", [])
	for k in pts.size():
		var done: bool = k < view.sim.recon_done.size() and bool(view.sim.recon_done[k])
		var rc := Color(0.4, 0.95, 0.5) if done else Color(1.0, 0.85, 0.3)
		var rp := to_mini((pts[k] as Vector2) * px)
		var rr := float(ob.get("recon_radius_m", 130.0)) / A.size_m().x * r.size.x
		draw_arc(rp, rr, 0, TAU, 24, rc, 1.5, true)
	# units
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	for k in view.sim.mechs.size():
		var m: CombatMech = view.sim.mechs[k]
		var sp: Sprite2D = view.sprites[k]
		var flags: int = sp.get_meta("flags", 0)
		if not sp.visible:
			if m.team != 0 and view.last_seen.has(k) and not m.out:
				var lp := to_mini(view.last_seen[k])
				draw_arc(lp, 3.5, 0, TAU, 12, Color(1.0, 0.4, 0.35, 0.55), 1.2, true)
			continue
		var p2 := to_mini(sp.position)
		var col2: Color = sp.get_meta("color", Color.WHITE)
		if flags & 4:
			draw_line(p2 - Vector2(3, 3), p2 + Vector2(3, 3), Color(0.5, 0.5, 0.5, 0.7), 1.5)
			draw_line(p2 + Vector2(-3, 3), p2 + Vector2(3, -3), Color(0.5, 0.5, 0.5, 0.7), 1.5)
			continue
		if view.selected.has(k):
			draw_arc(p2, 6.0 + pulse, 0, TAU, 16, Color(0.55, 1.0, 0.65, 0.9), 1.5, true)
		var dir := Vector2.from_angle(sp.rotation - PI / 2.0)
		var tri := PackedVector2Array([p2 + dir * 5.0, p2 + dir.rotated(2.5) * 3.8, p2 + dir.rotated(-2.5) * 3.8])
		draw_colored_polygon(tri, col2.lightened(0.2))
		draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), Color(0, 0, 0, 0.6), 1.0, true)
	# the camera's view
	var vs: Vector2 = view.get_viewport_rect().size
	var z: float = view.cam.zoom.x
	var half := vs / 2.0 / z
	var c0 := to_mini(view.cam.position - half)
	var c1 := to_mini(view.cam.position + half)
	var vr := Rect2(c0, c1 - c0).intersection(r)
	draw_rect(vr, Color(1, 1, 1, 0.06))
	draw_rect(vr, Color(1, 1, 1, 0.7), false, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), UI.LINE_HI, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_drag = (event as InputEventMouseButton).pressed
		if _drag:
			_jump((event as InputEventMouseButton).position)
		accept_event()
	elif event is InputEventMouseMotion and _drag:
		_jump((event as InputEventMouseMotion).position)
		accept_event()


func _jump(p: Vector2) -> void:
	var r := _map_rect()
	var f := ((p - r.position) / r.size).clamp(Vector2.ZERO, Vector2.ONE)
	view.cam.position = f * view.sim.arena.size_m() * PX
	view._clamp_camera()
