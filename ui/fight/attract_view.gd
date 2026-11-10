extends "res://ui/fight/fight_view.gd"
## The title screen's backdrop: a real battle between random lances on a random battlefield or arena,
## filmed by a slow cinematic camera. When it ends, a new one starts.

signal battle_over

var caption := ""
var _over_t := -1.0
var _cam_t := 0.0


static func random_battle(seed_v: int) -> CombatSim:
	var r := SimRng.new(seed_v)
	var themes := ["bf_plains", "bf_forest", "bf_urban", "bf_desert", "bf_arctic", "bf_hills", "bf_coast", "factory", "jungle", "canyon", "urban"]
	var th: String = themes[r.randi_range(0, themes.size() - 1)]
	var n := r.randi_range(3, 4)
	var a: Arena
	if th.begins_with("bf_"):
		a = BattlefieldGenerator.generate(th, seed_v, {"player_n": n, "enemy_n": n, "size": 0.75})
	else:
		a = ArenaGenerator.generate(th, seed_v, n, "", 2)
	var lib := GameData.db().get_library()
	var vlib := GameData.db().get_vehicle_library()
	var sides := [[], []]
	var names: Array = GameData.db().names["callsigns"]
	for team in 2:
		for k in n:
			var use_vehicle := th.begins_with("bf_") and r.chance(0.3)
			var pool: Array = vlib if use_vehicle else lib
			var e: Dictionary = pool[r.randi_range(0, pool.size() - 1)]
			for tries in 12:
				if int(e.get("year", 3000)) <= 3050 and int(e.get("tons", 50)) >= 25 and bool(e.get("armed", true)):
					break
				e = pool[r.randi_range(0, pool.size() - 1)]
			sides[team].append({"design": GameData.db().stock_design(str(e["id"])),
				"warrior": {"callsign": str(names[r.randi_range(0, names.size() - 1)]), "gunnery": r.randi_range(3, 4), "piloting": r.randi_range(4, 5), "traits": ["brawler"] if r.chance(0.4) else []},
				"orders": {"range": "close" if r.chance(0.5) else "optimal"}})
	var light := "day"
	var lr := r.randf()
	if lr < 0.22:
		light = "night"
	elif lr < 0.4:
		light = "dusk"
	return CombatSim.create(a, sides, seed_v + 1, {"merc": th.begins_with("bf_"), "time_limit": 240.0, "conditions": {"light": light, "weather": "clear", "floodlights": not th.begins_with("bf_")}}, true)


func _ready() -> void:
	super._ready()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	(get_child(0) as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	follow = true
	playing = true
	speed = 1.0
	var hues := [Color(0.85, 0.45, 0.2), Color(0.3, 0.55, 0.9)]
	for k in sim.mechs.size():
		var m: CombatMech = sim.mechs[k]
		(sprites[k] as Sprite2D).material = Game.tint_material(hues[m.team].lerp(Color(0.6, 0.6, 0.6), 0.15))
		(sprites[k] as Sprite2D).set_meta("color", hues[m.team])
	var names: Array = []
	for m in sim.mechs:
		names.append((m as CombatMech).design.display_name())
	caption = "%s  ·  %s vs %s" % [str(GameData.db().arenas["themes"].get(sim.arena.theme, {}).get("label", "")), names[0], names[sim.mechs.size() - 1]]
	_fit_camera(true)


func _build_hud() -> void:
	# no HUD: the viewer still needs these to exist
	time_lbl = Label.new()
	live_lbl = Label.new()
	log_box = RichTextLabel.new()
	slider = HSlider.new()
	done_btn = Button.new()
	for n in [time_lbl, live_lbl, log_box, slider, done_btn]:
		(n as Control).visible = false
		add_child(n)


func _update_panels(_f0: PackedFloat32Array, _f1: PackedFloat32Array, _a: float) -> void:
	pass


func _log(_e: Dictionary) -> void:
	pass


func _gui_input(_event: InputEvent) -> void:
	pass


func _unhandled_input(_event: InputEvent) -> void:
	pass


func _process(delta: float) -> void:
	if not sim.finished:
		var want := sim.t + delta * speed
		var steps := 0
		while sim.t < want and not sim.finished and steps < 200:
			sim.step()
			steps += 1
		_sync_frames()
	elif _over_t < 0.0:
		_over_t = 0.0
	else:
		_over_t += delta
		if _over_t > 5.0:
			battle_over.emit()
			_over_t = -100.0
	pt = sim.t
	_spawn_events()
	_update_scene()
	_cam_t += delta
	_fit_camera(false, delta)
	under.pt = pt
	over.pt = pt
	arena_view.set_time(pt)
	under.queue_redraw()
	over.queue_redraw()
	fx_node.queue_redraw()
	glow.queue_redraw()
	lights.queue_redraw()
	_apply_shake(delta)


## A slow, drifting camera on the middle of the action.
func _fit_camera(instant: bool, delta := 0.0) -> void:
	var c := Vector2.ZERO
	var n := 0
	for k in sprites.size():
		var flags: int = (sprites[k] as Sprite2D).get_meta("flags", 0)
		if flags & 4:
			continue
		c += (sprites[k] as Sprite2D).position
		n += 1
	if n == 0:
		c = sim.arena.size_m() * PX / 2.0
	else:
		c /= n
	var drift := Vector2(sin(_cam_t * 0.07), cos(_cam_t * 0.05)) * 90.0
	var z := 0.82 + sin(_cam_t * 0.04) * 0.06
	var target := c + drift + Vector2(-230.0 / z, 0)
	# keep the frame on the battlefield
	var vs := get_viewport_rect().size
	var half := vs / 2.0 / z
	var msz := sim.arena.size_m() * PX
	target.x = clampf(target.x, half.x - 40.0, msz.x - half.x + 40.0) if msz.x > half.x * 2.0 else msz.x / 2.0
	target.y = clampf(target.y, half.y - 40.0, msz.y - half.y + 40.0) if msz.y > half.y * 2.0 else msz.y / 2.0
	if instant:
		cam.position = target
		cam.zoom = Vector2(z, z)
	else:
		var k2 := clampf(delta * 0.6, 0.0, 1.0)
		cam.position = cam.position.lerp(target, k2)
		cam.zoom = cam.zoom.lerp(Vector2(z, z), k2)


func _finish() -> void:
	applied = true
