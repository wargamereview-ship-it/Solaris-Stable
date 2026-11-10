extends SceneTree
## godot --headless --path . -s tests/test_merc_arena.gd
## A mercenary company on Solaris VII: the fight card, who may enter, the duel, the purse, the damage and
## the MechWarrior afterwards, the card closing under contract or off-world, and a save/load round trip.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _init() -> void:
	var orders := {"range": "optimal", "heat": "balanced", "position": "cover", "retreat": 0.55, "focus": "focus"}
	# off-world: nothing on offer, but there is a route
	var g := MercCampaign.new_game("Far Co", Color(0.3, 0.5, 0.7), 3025, "Galatea", "lance", 5)
	check(not g.on_solaris() and not g.arena_open(), "Galatea is not Solaris")
	check(g.arena_offers.is_empty(), "no offers off-world")
	check(g.plan_trip(g.solaris()).get("ok", false), "a route to Solaris exists")
	check(g.start_travel(g.solaris()) == "", "the company can set out for Solaris")
	var arrived := false
	for k in 400:
		for e in g.advance_day():
			if str(e.get("kind", "")) == "arena":
				arrived = true
		if arrived:
			break
	check(arrived and g.on_solaris(), "arriving on Solaris posts the fight card")
	check(not g.arena_offers.is_empty(), "offers after landing")

	var c := MercCampaign.new_game("Arena Co", Color(0.7, 0.3, 0.2), 3025, "Solaris", "combined", 4242)
	check(c.on_solaris() and c.arena_open(), "a company founded on Solaris may fight")
	check(c.arena_offers.size() >= 3, "a fight card is posted (%d)" % c.arena_offers.size())
	var total_won := 0
	var fought := 0
	for o in c.arena_offers.duplicate():
		var od: Dictionary = o["opp"]
		var d := MercCampaign.db_design(str(od["design"]))
		check(d != null and not d.is_vehicle(), "the opponent brings a 'Mech")
		check(c.db.weight_class(d.tons) == str(o["class"]), "opponent in the offer's weight class")
		check(int(o["purse"]) > 0, "a purse")
		var ids := c.arena_entrants(o)
		for uid in ids:
			var eu: MercUnit = c.units[uid]
			check(not eu.is_vehicle() and c.db.weight_class(eu.tons()) == str(o["class"]), "entrants match the class")
		if ids.is_empty():
			continue
		var uid0 := int(ids[0])
		var u: MercUnit = c.units[uid0]
		var p := c.crew_of(u)
		var cash0 := c.cash
		var battles0 := p.battles
		# a vehicle or a 'Mech of the wrong class is refused
		for vid in c.units:
			if c.units[vid].is_vehicle():
				check(c.make_arena_bout(int(o["id"]), int(vid), orders).is_empty(), "vehicles can't enter")
				break
		# determinism: the same bout twice gives the same fight
		var b1 := c.make_arena_bout(int(o["id"]), uid0, orders, false)
		var b2 := c.make_arena_bout(int(o["id"]), uid0, orders, false)
		check(not b1.is_empty(), "the bout is built")
		(b1["sim"] as CombatSim).run_to_end()
		(b2["sim"] as CombatSim).run_to_end()
		check(str(b1["sim"].result["how"]) == str(b2["sim"].result["how"]) and is_equal_approx(float(b1["sim"].result["duration"]), float(b2["sim"].result["duration"])), "deterministic")
		var res: Dictionary = b1["sim"].result
		var sum := c.resolve_arena(b1["bout"], res)
		check(not sum.is_empty(), "the result is booked")
		check(c.resolve_arena(b1["bout"], res).is_empty(), "a bout is booked once")
		check(c.arena_offer(int(o["id"])).is_empty(), "the offer leaves the card")
		var purses := c.arena_purses(o)
		var won: bool = sum["won"]
		check(c.cash - cash0 == int(sum["purse"]), "the purse is paid")
		check(int(sum["purse"]) == (purses[0] if won else (int(o["purse"]) / 2 if sum["draw"] else purses[1])), "winner and loser shares")
		check(p.battles == battles0 + 1 or p.status == "dead", "the MechWarrior's record")
		var rm: Dictionary = res["mechs"][0]
		if float(rm["dmg_taken"]) > 0.0 and c.units.has(uid0):
			check(u.damaged() or u.wreck(), "damage carries over to the hangar")
		print("  %s at %s: %s vs %s -> %s, %s, purse %d; %s" % [o["class"], o["arena_name"], u.label(), d.display_name(),
			"WON" if won else "lost", res["how"], int(sum["purse"]), sum["lines"]])
		total_won += int(won)
		fought += 1
	check(fought >= 2, "at least two bouts fought (%d)" % fought)
	check(int(c.stats.get("arena_fights", 0)) == fought and int(c.stats.get("arena_wins", 0)) == total_won, "the arena record")
	# auto-resolve path and the weekly card
	var guard := 0
	while c.arena_offers.is_empty() and guard < 10:
		c.advance_day()
		guard += 1
	check(not c.arena_offers.is_empty(), "a new card within the week")
	# save / load
	var d2 := MercCampaign.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(d2.arena_offers.size() == c.arena_offers.size(), "offers survive a save")
	if not d2.arena_offers.is_empty():
		var o2: Dictionary = d2.arena_offers[0]
		check(o2["id"] is int and int(o2["id"]) == int(c.arena_offers[0]["id"]), "offer ids stay ints")
		for o3 in d2.arena_offers:
			var ids3 := d2.arena_entrants(o3)
			if not ids3.is_empty():
				var s3 := d2.arena_auto(int(o3["id"]), int(ids3[0]), orders)
				check(not s3.is_empty() and s3.has("purse"), "auto-resolve after loading")
				break
	# under contract the card comes down
	c.contract = {"status": "active", "system": c.location, "end_day": c.day + 60, "score": 0, "morale": 3}
	check(not c.arena_open(), "closed under contract")
	c.refresh_arena()
	check(c.arena_offers.is_empty(), "no offers under contract")
	print("ARENA TEST DONE, fails: %d" % fails)
	quit()
