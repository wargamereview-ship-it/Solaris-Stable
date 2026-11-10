extends SceneTree
## godot --path . -s tests/screenshots_features.gd -- <out_dir>
## Screenshots of team bouts, corner calls, night and weather, hazards and fire.

var out := "user://shots"
var game


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func view(sim: CombatSim, bout: Dictionary, upto: float, name: String, whole := false) -> void:
	var fv = load("res://ui/fight/fight_view.gd").new()
	fv.setup(sim, bout)
	game.show_screen(fv)
	await process_frame
	await process_frame
	fv.follow = not whole
	if whole:
		fv._fit_camera(true)
	fv.speed = 8.0
	while fv.sim.t < upto and not fv.sim.finished:
		fv._process(0.25)
		await process_frame
	fv.speed = 1.0
	for k in 30:
		await process_frame
	await shot(name)


func _run() -> void:
	root.size = Vector2i(1600, 960)
	game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	game.new_game("Iron Gauntlet Stables", "Silesia", Color(0.2, 0.4, 0.8), 4040)
	for k in 3:
		await process_frame
	var c: Campaign = game.campaign
	var hub = game.root_ui.get_child(0)
	hub.show_tab("card")
	for k in 3:
		await process_frame
	var tab = hub.content.get_child(0)
	var team: Dictionary = {}
	for o in c.offers:
		if o.get("format", "duel") in ["tag", "melee"]:
			team = o
			break
	if not team.is_empty():
		tab.sel_offer = int(team["id"])
		tab._show_offer()
		await shot("20_team_booking")
		var need: int = (team["sides"][0] as Array).size()
		var entries: Array = []
		for wid in c.player().warriors:
			var w: Warrior = c.warriors[wid]
			if entries.size() < need and w.mech_uid >= 0 and (not (team["class"] in Campaign.CLASSES) or c.mech_class(w.mech_uid) == team["class"]):
				entries.append([wid, w.mech_uid])
		print("book: ", c.book_team(team["id"], entries, {"range": "optimal", "position": "flank"}, {}, 0))
		var b: Dictionary = c.bookings[-1]
		b["conditions"] = {"light": "night", "weather": "rain", "floodlights": false}
		b["theme"] = "urban"
		var sim := c.make_sim(b, true)
		await view(sim, b, 22.0, "21_tag_night_rain")
	# a dusk lance battle in the Factory, among the flame jets
	var sides := [[], []]
	var ids := [["Marauder MAD-3R", "Warhammer WHM-6R", "Archer ARC-2R", "Jenner JR7-D"], ["Thunderbolt TDR-5S", "Rifleman RFL-3N", "Catapult CPLT-C1", "Panther PNT-9R"]]
	for t in 2:
		for id in ids[t]:
			sides[t].append({"design": MechDesign.from_stock(id), "warrior": {"callsign": id.split(" ")[0], "gunnery": 4, "piloting": 5, "traits": ["brawler"]}, "orders": {"range": "close"}})
	var arena := ArenaGenerator.generate("factory", 77, 4, "the_factory", 2)
	var lsim := CombatSim.create(arena, sides, 77, {"conditions": {"light": "dusk", "weather": "clear"}, "time_limit": 480.0}, true)
	await view(lsim, {"format": "lance", "arena_name": "The Factory", "purse": 0}, 40.0, "22_lance_factory_dusk", true)
	# fire in the jungle
	var flame := "UrbanMech UM-R61"
	for e in GameData.db().get_library():
		if str(e["chassis"]) == "Firestarter" and int(e["tons"]) == 35:
			flame = e["id"]
			break
	var fsides := [[{"design": MechDesign.from_stock(flame), "warrior": {"callsign": "Torch", "gunnery": 3, "piloting": 4, "traits": ["hot_blooded"]}, "orders": {"range": "close", "heat": "hot"}}],
		[{"design": MechDesign.from_stock("Wolverine WVR-6R"), "warrior": {"callsign": "Wolf", "gunnery": 4, "piloting": 5, "traits": []}, "orders": {"range": "close"}}]]
	var fsim := CombatSim.create(ArenaGenerator.generate("jungle", 405, 1, "the_jungle", 2), fsides, 405, {"conditions": {"light": "day", "weather": "wind"}}, true)
	await view(fsim, {"format": "duel", "kind": "regular", "class": "light", "arena_name": "The Jungle", "purse": 0}, 45.0, "23_jungle_fire")
	quit()
