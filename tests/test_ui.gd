extends SceneTree
## godot --headless --path . -s tests/test_ui.gd
## Builds the real UI and clicks through every screen: menu, every hub tab, the designer, a watched fight.

func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	print("menu ok")
	# the setup screen: change a few things and open a stable from it
	game.root_ui.get_child(0)._show_form()
	for k in 3:
		await process_frame
	var setup = game.root_ui.get_child(0)
	(setup.w["year"] as SpinBox).value = 3040
	(setup.w["m_heavy"] as SpinBox).value = 1
	(setup.w["rivals"] as SpinBox).value = 10
	(setup.w["purses"] as HSlider).value = 150
	(setup.w["sector"] as OptionButton).select(2)
	(setup.w["sector"] as OptionButton).item_selected.emit(2)
	for k in 2:
		await process_frame
	(setup.w["start"] as Button).pressed.emit()
	for k in 6:
		await process_frame
	var sc: Campaign = game.campaign
	if sc == null or sc.year != 3040 or sc.stables.size() != 11 or sc.player().mechs.size() != 4 or absf(sc.effect_mult("purse_mult") - 1.5) > 0.001:
		print("SETUP SCREEN FAIL: the stable did not start as set up")
	else:
		print("setup screen: opened ", sc.player().name, " in ", sc.year, " with ", sc.player().mechs.size(), " 'Mechs against ", sc.stables.size() - 1, " rivals")
	game.new_game("UI Test Stable", "Kobe", Color(0.8, 0.2, 0.2), 777)
	await process_frame
	var hub = game.root_ui.get_child(0)
	for t in hub.TABS:
		hub.show_tab(t[0])
		await process_frame
		print("tab ok: ", t[0])
	for page in 3:
		var mt = load("res://ui/tabs/market_tab.gd")
		mt.page = page
		hub.show_tab("market")
		await process_frame
	print("market pages ok")
	for k in ["open", "light", "stables"]:
		load("res://ui/tabs/rankings_tab.gd").cls = k
		hub.show_tab("rankings")
		await process_frame
	print("rankings ok")
	# designer: refit and a new build
	var c: Campaign = game.campaign
	var uid: int = c.player().mechs[0]
	var d = load("res://ui/designer/designer.gd").new()
	d.setup(c, uid, null)
	game.show_screen(d)
	await process_frame
	d.sel_item = "medium_laser"
	d._place("RA")
	d._fit_armor()
	await process_frame
	print("designer refit ok: ", d.d.display_name(), " valid=", Construction.analyze(d.d)["valid"], " ", Construction.analyze(d.d)["errors"])
	var d2 = load("res://ui/designer/designer.gd").new()
	d2.setup(c, -1, MechDesign.blank(50, 4))
	game.show_screen(d2)
	await process_frame
	d2._sync_sinks()
	d2.sel_item = "ac_10"
	d2._place("RT")
	d2.sel_item = "ac_10_ammo"
	d2._place("RT")
	d2.sel_item = "medium_laser"
	d2._place("LA")
	d2._place("RA")
	d2._fit_armor()
	await process_frame
	var r2 := Construction.analyze(d2.d, c.year)
	print("designer new build: %.1f/%d t valid=%s %s" % [r2["tons_used"], d2.d.tons, r2["valid"], r2["errors"]])
	print("build quote: ", c.build_quote(d2.d)["errors"])
	# book a bout and watch it
	game.show_hub("card")
	await process_frame
	var p := c.player()
	var booked := false
	for wid in p.warriors:
		var w: Warrior = c.warriors[wid]
		for o in c.offers.duplicate():
			if c.book(o["id"], wid, w.mech_uid, {"range": "optimal"}, 50000) == "":
				booked = true
				break
		if booked:
			break
	print("booked: ", booked)
	game.show_hub("card")
	await process_frame
	var bid: int = c.bookings[0]["id"]
	game.watch_bout(bid)
	await process_frame
	var fv = game.root_ui.get_child(0)
	for k in 20:
		fv._process(0.5)
		await process_frame
	print("live viewer: sim at %.1f s, finished=%s" % [fv.sim.t, fv.sim.finished])
	if not fv.sim.finished:
		fv._call(0, "press", -1)
		print("corner call sent: ", fv.sim.inputs)
	fv._skip_to_end()
	fv._process(0.1)
	await process_frame
	print("fight viewer ok: ", fv.sim.result["how"], " applied=", fv.applied, " summary purse ", fv.summary.get("purse_a", 0))
	fv._done()
	await process_frame
	hub = game.root_ui.get_child(0)
	hub._do_advance()
	for k in 4:
		await process_frame
	print("advanced to ", c.date_str())
	# a team bout through the card tab: tag or lance if offered, watched live
	var team_offer := {}
	for o in c.offers:
		if o.get("format", "duel") in ["tag", "melee"]:
			team_offer = o
			break
	if not team_offer.is_empty():
		var need: int = (team_offer["sides"][0] as Array).size()
		var entries: Array = []
		for wid in c.player().warriors:
			var w2: Warrior = c.warriors[wid]
			if entries.size() < need and w2.available() and w2.mech_uid >= 0 and c.mechs[w2.mech_uid].ready() and (not (team_offer["class"] in Campaign.CLASSES) or c.mech_class(w2.mech_uid) == team_offer["class"]):
				entries.append([wid, w2.mech_uid])
		if entries.size() == need:
			print("team booking: ", c.book_team(team_offer["id"], entries, {"range": "optimal"}, {}, 0))
			hub = game.root_ui.get_child(0)
			hub.show_tab("card")
			await process_frame
			await process_frame
			game.watch_bout(c.bookings[-1]["id"])
			await process_frame
			await process_frame
			var tv = game.root_ui.get_child(0)
			for k in 10:
				tv._process(0.5)
				await process_frame
			tv._skip_to_end()
			tv._process(0.1)
			await process_frame
			print("team viewer ok: %s, %d 'Mechs, applied=%s" % [tv.sim.result["how"], tv.sim.mechs.size(), tv.applied])
			tv._done()
			await process_frame
			await process_frame
	hub = game.root_ui.get_child(0)
	for t in hub.TABS:
		hub.show_tab(t[0])
		await process_frame
	print("UI TEST DONE")
	quit()
