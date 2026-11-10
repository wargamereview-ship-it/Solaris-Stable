extends SceneTree
## godot --path . -s tests/screenshots_terrain.gd -- <out_dir> [theme ...]
## Renders battlefields and arenas mid-fight, zoomed out and zoomed in, to check the terrain renderer.

var out := "user://shots"
var game
var themes := ["bf_plains", "bf_urban", "bf_arctic", "bf_desert", "bf_forest", "bf_coast", "factory", "jungle", "canyon"]


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		themes = args.slice(1)
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func shot(name: String) -> void:
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func entry(id: String, name: String, team: int) -> Dictionary:
	return {"design": GameData.db().stock_design(id), "warrior": {"callsign": name, "gunnery": 3, "piloting": 4, "traits": ["brawler"]}, "orders": {"range": "close"}}


func _run() -> void:
	root.size = Vector2i(1600, 960)
	game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var n := 0
	for th in themes:
		n += 1
		var a: Arena
		if str(th).begins_with("bf_"):
			a = BattlefieldGenerator.generate(th, 300 + n, {"player_n": 3, "enemy_n": 3, "scenario": "base_defense" if n % 2 == 0 else "standup"})
		else:
			a = ArenaGenerator.generate(th, 300 + n, 2, "", 2)
		var sides := [[entry("Marauder MAD-3R", "Ace", 0), entry("Wolverine WVR-6R", "Duke", 0), entry("Griffin GRF-1N", "Hex", 0)],
			[entry("Warhammer WHM-6R", "Rook", 1), entry("Shadow Hawk SHD-2H", "Vale", 1), entry("Jenner JR7-D", "Pike", 1)]]
		var lights := ["day", "day", "dusk", "day", "day", "day", "night", "day", "day"]
		var sim := CombatSim.create(a, sides, 77 + n, {"time_limit": 600.0, "conditions": {"light": lights[(n - 1) % lights.size()], "weather": "clear"}}, true)
		var fvs = load("res://ui/fight/fight_view.gd")
		if fvs == null or not fvs.can_instantiate():
			quit()
			return
		var fv = fvs.new()
		fv.setup(sim, {"format": "duel", "kind": "regular", "class": "medium", "arena_name": th, "purse": 0})
		game.show_screen(fv)
		for k in 4:
			await process_frame
		fv.speed = 4.0
		while fv.sim.t < 26.0 and not fv.sim.finished:
			fv._process(0.25)
			await process_frame
		fv.playing = false
		fv.follow = false
		fv._fit_camera(true)
		fv._process(0.0)
		await shot("t%02d_%s_wide" % [n, th])
		var p := Vector2.ZERO
		var cnt := 0
		for m in fv.sim.mechs:
			if not (m as CombatMech).out:
				p += (m as CombatMech).pos
				cnt += 1
		fv.cam.position = (p / maxf(1, cnt)) * fv.PX
		fv.cam.zoom = Vector2(1.1, 1.1)
		fv._process(0.0)
		await shot("t%02d_%s_close" % [n, th])
	quit()
