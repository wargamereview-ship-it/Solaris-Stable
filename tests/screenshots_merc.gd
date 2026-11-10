extends SceneTree
## godot --path . -s tests/screenshots_merc.gd -- <out_dir>
## Screenshots of the merc mode: hub tabs, the star map, a briefing and a live battle with orders.

var out := "user://shots"
var game


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func shot(name: String) -> void:
	for k in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func tab(hub, id: String, name: String) -> void:
	hub.show_tab(id)
	await shot(name)


func _run() -> void:
	root.size = Vector2i(1600, 960)
	game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var menu = game.root_ui.get_child(0)
	menu._show_merc_form()
	await shot("30_menu_merc")
	game.new_merc_game("Kell's Raiders", Color(0.45, 0.42, 0.3), 3025, "Galatea", "combined", 909)
	for k in 3:
		await process_frame
	var c: MercCampaign = game.merc
	var hub = game.root_ui.get_child(0)
	await tab(hub, "command", "31_command")
	await tab(hub, "contracts", "32_contracts")
	await tab(hub, "map", "33_star_map")
	# take a contract and get to the fighting
	var best: Dictionary = c.contract_offers[0]
	for o in c.contract_offers:
		if int(o["jumps"]) < int(best["jumps"]):
			best = o
	c.accept_contract(int(best["offer"]))
	if c.location != int(c.contract["system"]):
		c.start_travel(int(c.contract["system"]))
	var guard := 0
	while (c.pending_scenarios().is_empty() or not c.contract_active()) and guard < 40:
		c.advance_to_event(30)
		guard += 1
	await tab(hub, "toe", "34_toe")
	# a base defense with the whole company, so both sides bring 'Mechs and vehicles
	for ps in c.pending_scenarios():
		c.scenarios.erase(ps)
	var sc := c._new_scenario(c.lances[0], "defend", "base_defense")
	sc["biome"] = "bf_hills"
	c.scenarios.append(sc)
	load("res://ui/merc/ops_tab.gd").sel = int(sc["id"])
	var all: Array = []
	for u in c.combat_units():
		all.append((u as MercUnit).id)
	load("res://ui/merc/ops_tab.gd").deploy[int(sc["id"])] = {}
	for uid in all:
		load("res://ui/merc/ops_tab.gd").deploy[int(sc["id"])][uid] = true
	await tab(hub, "ops", "35_briefing")
	game.watch_merc_battle(int(sc["id"]), all)
	for k in 4:
		await process_frame
	var cv = game.root_ui.get_child(0)
	await shot("36_battle_start")
	cv._select_all()
	cv.playing = true
	cv.speed = 4.0
	while cv.sim.t < 20.0 and not cv.sim.finished:
		cv._process(0.25)
		await process_frame
	var mid: Vector2 = MercCampaign._cells_center(cv.sim.arena, cv.sim.arena.objectives.get("defend_cells", []))
	cv._order("move", mid + Vector2(60, 0))
	while cv.sim.t < 55.0 and not cv.sim.finished:
		cv._process(0.25)
		await process_frame
	cv.playing = false
	var p := Vector2.ZERO
	var n := 0
	for m in cv.sim.mechs:
		var cm: CombatMech = m
		if not cm.out and (cm.team == 0 or cm.spotted):
			p += cm.pos
			n += 1
	if n > 0:
		cv.cam.position = p / n * cv.PX
	cv.cam.zoom = Vector2(0.6, 0.6)
	cv.selected.clear()
	for i in cv.player_idx.slice(0, 4):
		cv.selected[i] = true
	cv._process(0.0)
	cv._info_t = 0.0
	cv._process(0.0)
	await shot("37_battle_fight")
	cv._hand_over()
	cv._process(0.1)
	await shot("38_battle_result")
	cv._done()
	for k in 3:
		await process_frame
	hub = game.root_ui.get_child(0)
	await tab(hub, "ops", "39_after_battle")
	await tab(hub, "hangar", "40_hangar")
	await tab(hub, "logistics", "41_logistics")
	await tab(hub, "market", "42_market")
	await tab(hub, "people", "43_people")
	await tab(hub, "money", "44_money")
	quit()
