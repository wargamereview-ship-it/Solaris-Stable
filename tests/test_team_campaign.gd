extends SceneTree
## godot --headless --path . -s tests/test_team_campaign.gd
## Tag, lance and free-for-all bouts through the campaign: offers, booking, results, the AI card, saves.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func _init() -> void:
	var c := Campaign.new_game("Team Test", "Black Hills", 777)
	var p := c.player()
	# give the stable enough people and 'Mechs to field a lance
	p.cash = 40000000
	p.bays = 10
	for k in 3:
		var w := c._gen_warrior("Federated Suns", 0.5)
		c._sign(w, p, w.salary, 52)
	for cls in ["medium", "medium", "heavy"]:
		var did := c._pick_design(cls, "balanced", 7000000)
		c._add_mech(did, p)
	c._auto_assign(p)
	c.generate_offers()
	var formats := {}
	for o in c.offers:
		formats[o.get("format", "duel")] = int(formats.get(o.get("format", "duel"), 0)) + 1
	print("offers by format: ", formats, "   AI card formats: ", c.ai_card.map(func(b): return b.get("format", "duel")))
	check(formats.has("tag") or formats.has("lance"), "team offers appear once the stable can field them")
	var booked := {}
	for o in c.offers.duplicate():
		var fmt: String = o.get("format", "duel")
		if fmt == "duel" or booked.has(fmt):
			continue
		var need: int = (o["sides"][0] as Array).size()
		var entries: Array = []
		var tons := 0
		var cap := int(o.get("cap", 0))
		var cands: Array = p.warriors.duplicate()
		cands.sort_custom(func(a, b): return c.mechs[c.warriors[a].mech_uid].design.tons < c.mechs[c.warriors[b].mech_uid].design.tons)
		for wid in cands:
			var w: Warrior = c.warriors[wid]
			if entries.size() >= need or c._booked(wid) or w.mech_uid < 0:
				continue
			var om: OwnedMech = c.mechs[w.mech_uid]
			if o["class"] in Campaign.CLASSES and c.mech_class(om.uid) != o["class"]:
				continue
			if cap > 0 and tons + om.design.tons > cap:
				continue
			var used := false
			for e in entries:
				if e[1] == om.uid:
					used = true
			if used:
				continue
			entries.append([wid, om.uid])
			tons += om.design.tons
		if entries.size() < need:
			print("  (couldn't field a %s team)" % fmt)
			continue
		var ammo := {}
		for e in entries:
			var opts := c.munition_options(c.mechs[e[1]])
			if not opts.is_empty():
				var fam: String = opts.keys()[0]
				ammo[str(e[0])] = {fam: opts[fam][-1]}
		var err := c.book_team(o["id"], entries, {"range": "optimal", "focus": "focus"}, ammo, 20000)
		check(err == "", "booked a %s bout (%d warriors%s) %s" % [fmt, need, (", %d of %d t" % [tons, cap]) if cap > 0 else "", err])
		booked[fmt] = true
	# a melee needs only one warrior
	for o in c.offers.duplicate():
		if o.get("format", "") == "melee":
			for wid in p.warriors:
				var w2: Warrior = c.warriors[wid]
				if not c._booked(wid) and w2.mech_uid >= 0 and not (w2.mech_uid in c._booked_mechs()):
					var err2 := c.book(o["id"], wid, w2.mech_uid, {"range": "close"}, 0)
					check(err2 == "", "booked a free-for-all %s" % err2)
					booked["melee"] = true
					break
	var n_book := c.bookings.size()
	var cash0 := p.cash
	var elo0 := {}
	for wid in p.warriors:
		elo0[wid] = c.warriors[wid].elo
	var t0 := Time.get_ticks_msec()
	c.advance_week()
	print("week with team bouts took %d ms" % (Time.get_ticks_msec() - t0))
	var team_results := 0
	for r in c.results:
		if r.get("format", "duel") != "duel":
			team_results += 1
			if r["player"]:
				print("  %s at %s: %s, winner side %d" % [r["format"], r["arena"], r["how"], r["winner"]])
	check(team_results >= booked.size(), "team results recorded (%d)" % team_results)
	var moved := 0
	for wid in elo0:
		if absf(c.warriors[wid].elo - float(elo0[wid])) > 0.01:
			moved += 1
	check(moved > 0, "ratings moved for %d of your warriors" % moved)
	check(p.cash != cash0, "purses and wagers paid (cash %s -> %s)" % [Campaign.money(cash0), Campaign.money(p.cash)])
	for k in 6:
		c.advance_week()
	var ai_team := 0
	for r in c.results:
		if r.get("format", "duel") != "duel" and not r["player"]:
			ai_team += 1
	check(ai_team > 0, "rival stables fight tag, lance and free-for-all bouts (%d)" % ai_team)
	var path := "user://team_test.json"
	c.save_to(path)
	var c2 := Campaign.load_from(path)
	check(c2 != null and c2.results.size() == c.results.size(), "save and load keep team results")
	c2.advance_week()
	check(true, "loaded game advances to %s" % c2.date_str())
	print("FAILURES: ", fails)
	quit(fails)
