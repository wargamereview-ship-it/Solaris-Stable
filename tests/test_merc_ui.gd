extends SceneTree
## godot --headless --path . -s tests/test_merc_ui.gd
## Builds the merc UI and goes through it: menu form, every hub tab, star map selection, a contract,
## a battle in the command view with orders, the results, salvage, and a day advance.

func _init() -> void:
	_run.call_deferred()


func _frames(n := 2) -> void:
	for k in n:
		await process_frame


func _run() -> void:
	var game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await _frames()
	var menu = game.root_ui.get_child(0)
	menu._show_merc_form()
	await _frames()
	# the setup screen: change a few things and found a company from it
	var setup = game.root_ui.get_child(0)
	print("setup screen: halls ", setup._halls.size(), ", rows ", setup.w.size())
	(setup.w["year"] as SpinBox).value = 3050
	(setup.w["mechs"] as SpinBox).value = 5
	(setup.w["enemy_strength"] as HSlider).value = 110
	(setup.w["news"] as CheckBox).button_pressed = false
	(setup.w["preset_lance"] as Button).pressed.emit()
	await _frames()
	(setup.w["infantry"] as SpinBox).value = 1
	await _frames()
	var su: Dictionary = setup.merc_setup()
	var pl: Dictionary = setup.merc_play()
	if int(su["year"]) != 3050 or int(su["mechs"]) != 4 or int(su["infantry"]) != 1 or absf(float(pl["enemy_strength"]) - 1.1) > 0.001 or pl["news"]:
		print("SETUP SCREEN FAIL: ", su, " ", pl)
	(setup.w["start"] as Button).pressed.emit()
	await _frames(6)
	if game.merc == null or game.merc.year() != 3050 or absf(game.merc.enemy_strength() - 1.1) > 0.001:
		print("SETUP SCREEN FAIL: the company did not start as set up")
	else:
		print("setup screen: founded ", game.merc.name, " in ", game.merc.date_str(), " with ", game.merc.units.size(), " units")
	game.new_merc_game("UI Test Company", Color(0.3, 0.5, 0.8), 3025, "Galatea", "combined", 4242)
	await _frames(3)
	var hub = game.root_ui.get_child(0)
	var c: MercCampaign = game.merc
	for t in hub.TABS:
		hub.show_tab(t[0])
		await _frames()
		print("tab ok: ", t[0])
	# star map: select a system and look at it
	hub.show_tab("map")
	await _frames()
	var tab = hub.content.get_child(0)
	tab.view.select(c.sm.index_of("Outreach"))
	await _frames()
	print("map selection ok: ", c.sm.name_of(tab.sel))
	# contracts: negotiate and accept the first offer, then fly there
	hub.show_tab("contracts")
	await _frames()
	var o: Dictionary = c.contract_offers[0]
	print("negotiate: ", c.negotiate(int(o["offer"]), "salvage"))
	print("accept: '", c.accept_contract(int(o["offer"])), "'")
	if c.location != int(c.contract["system"]):
		print("travel: '", c.start_travel(int(c.contract["system"])), "'")
	hub.show_tab("command")
	await _frames()
	var ev := c.advance_to_event(200)
	print("advanced to ", c.date_str(), ": ", ev.size(), " events, contract ", c.contract.get("status", ""))
	var guard := 0
	while c.pending_scenarios().is_empty() and guard < 30:
		c.advance_to_event(30)
		guard += 1
	print("battles waiting: ", c.pending_scenarios().size(), " on ", c.date_str())
	hub.show_tab("ops")
	await _frames(3)
	var s: Dictionary = c.pending_scenarios()[0]
	var uids := c.default_deployment(s)
	game.watch_merc_battle(int(s["id"]), uids)
	await _frames(3)
	var cv = game.root_ui.get_child(0)
	print("command view up: ", cv.sim.mechs.size(), " units, objective: ", cv.meta["type"])
	cv._select_all()
	cv.playing = true
	for k in 6:
		cv._process(0.5)
		await process_frame
	var tgt := -1
	for m in cv.sim.mechs:
		if (m as CombatMech).team == 1 and not (m as CombatMech).out:
			tgt = (m as CombatMech).index
			break
	cv._order("move", cv.sim.arena.size_m() / 2.0)
	cv._order("range", "close")
	if tgt >= 0:
		cv._order("attack", tgt)
	cv._order("hold")
	print("orders recorded: ", cv.sim.inputs.size())
	for k in 6:
		cv._process(0.5)
		await process_frame
	cv._hand_over()
	cv._process(0.1)
	await _frames(2)
	print("battle over: ", cv.sim.result["how"], " applied=", cv.applied, " outcome ", cv.summary_m.get("outcome", ""))
	cv._done()
	await _frames(3)
	hub = game.root_ui.get_child(0)
	print("back to hub tab: ", hub.current, " salvage waiting ", c.salvage.size())
	if not c.salvage.is_empty():
		print(c.claim_salvage(c.auto_salvage_picks()))
	for t in hub.TABS:
		hub.show_tab(t[0])
		await _frames()
	hub._advance_day()
	await _frames(3)
	print("next day ", c.date_str())
	print("MERC UI TEST DONE")
	quit()
