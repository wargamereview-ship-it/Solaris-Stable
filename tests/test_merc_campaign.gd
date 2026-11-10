extends SceneTree
## godot --headless --path . -s tests/test_merc_campaign.gd [-- days seed safe|x noinf|x start_year]
## Runs a mercenary company for a stretch of days: contracts, travel, battles (auto-resolved),
## salvage, repairs, procurement, payroll; then a save/load round trip.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


## Values that differ after a save and load (numbers compare by value: JSON turns whole floats into ints).
func _diff(a: Variant, b: Variant, path: String, out: Array) -> void:
	if out.size() > 10:
		return
	if (a is float or a is int) and (b is float or b is int):
		if absf(float(a) - float(b)) > 0.0001:
			out.append("%s: %s vs %s" % [path, str(a), str(b)])
		return
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				out.append("%s.%s missing after load" % [path, k])
			else:
				_diff(a[k], b[k], "%s.%s" % [path, k], out)
		return
	if a is Array and b is Array:
		if a.size() != b.size():
			out.append("%s: %d items vs %d" % [path, a.size(), b.size()])
			return
		for i in a.size():
			_diff(a[i], b[i], "%s[%d]" % [path, i], out)
		return
	if str(a) != str(b):
		out.append("%s: %s vs %s" % [path, str(a).left(60), str(b).left(60)])


func _init() -> void:
	var days := 400
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0].is_valid_int():
		days = int(args[0])
	var t0 := Time.get_ticks_msec()
	var safe := args.size() > 2 and args[2] == "safe"
	var seed := 31337
	if args.size() > 1 and args[1].is_valid_int():
		seed = int(args[1])
	var start_year := 3025
	if args.size() > 4 and args[4].is_valid_int():
		start_year = int(args[4])
	var c := MercCampaign.new_game("Test Raiders", Color(0.7, 0.3, 0.2), start_year, "Galatea", "combined", seed)
	if args.size() > 3 and args[3] == "noinf":
		c.rules["operations"]["infantry"]["enemy_chance"] = {}
		c.rules["operations"]["infantry"]["garrison_chance"] = 0.0
	print("new game %d ms: %d units, %d people, cash %s, at %s" % [Time.get_ticks_msec() - t0, c.units.size(), c.people.size(), Campaign.money(c.cash), c.sm.name_of(c.location)])
	for id in c.units:
		var u: MercUnit = c.units[id]
		var p := c.crew_of(u)
		print("  %-36s %-8s BV %4d  crew %s" % [u.label(), u.kind_label(), u.bv(), p.full_name() + " " + p.skill_str() if p != null else "-"])
	check(c.units.size() == 8, "combined package has 8 units")
	print("rating ", c.rating())
	print("offers at Galatea: ", c.contract_offers.size())
	for o in c.contract_offers:
		var v := c.contract_value(o)
		print("  %-20s %-18s vs %-22s on %-16s %2d mo  %s total  %d jumps" % [o["employer_name"], o["mission_label"], o["enemy_name"], o["system_name"], int(o["months"]), Campaign.money(int(v["total"])), int(o["jumps"])])
	check(c.contract_offers.size() > 0, "contracts on offer at a great hiring hall")
	var battles := 0
	var victories := 0
	var contracts := 0
	var min_cash := c.cash
	var t1 := Time.get_ticks_msec()
	var sim_ms := 0
	for k in days:
		# take the best-paying nearby contract when idle
		if c.contract.is_empty() and not c.in_transit() and not c.contract_offers.is_empty():
			var best: Dictionary = {}
			var best_v := -1.0
			for o in c.contract_offers:
				var v2 := c.contract_value(o)
				var score := float(v2["total"]) / (1.0 + int(o["jumps"]) * 0.15)
				if safe and not (str(o["mission"]) in ["garrison", "pirate_hunting", "security", "cadre", "riot"]):
					score *= 0.05
				if score > best_v:
					best_v = score
					best = o
			c.negotiate(int(best["offer"]), "pay")
			c.negotiate(int(best["offer"]), "salvage")
			var err := c.accept_contract(int(best["offer"]))
			check(err == "", "accept contract: " + err)
			contracts += 1
			if c.location != int(c.contract["system"]):
				var e2 := c.start_travel(int(c.contract["system"]))
				check(e2 == "", "travel: " + e2)
		# replace losses from the market and crew them
		if not c.in_transit() and c.combat_units().size() < 6 and c.cash > 4000000:
			for o2 in c.market_units.duplicate():
				if int(o2["price"]) < c.cash - 2500000 and c.combat_units().size() < 8:
					if c.buy_unit(int(o2["offer"])) == "":
						var nu: MercUnit = c.units[c.units.keys().max()]
						var want := "vehicle_crew" if nu.is_vehicle() else "mechwarrior"
						var crew: MercPerson = c.crew_of(nu)   # infantry sign on with their own officer
						if crew != null:
							if not c.lances.is_empty():
								c.set_lance(nu.id, int(c.lances[0]["id"]))
							continue
						for p0 in c.roster():
							if (p0 as MercPerson).role == want and (p0 as MercPerson).unit_id < 0 and (p0 as MercPerson).alive():
								crew = p0
						if crew == null:
							for hp in c.market_people.duplicate():
								if hp.has("person") and str(hp["person"]["role"]) == want:
									c.hire(int(hp["offer"]))
									crew = c.people[c.next_id]
									break
						if crew != null:
							c.assign(crew.id, nu.id)
						if not c.lances.is_empty():
							c.set_lance(nu.id, int(c.lances[0]["id"]))
		var ev := c.advance_day()
		for e in ev:
			if e["kind"] in ["contract", "arrive", "game_over"]:
				print("%s  %s" % [c.date_str(), e["text"]])
		for s in c.pending_scenarios():
			var dep := c.default_deployment(s)
			if dep.is_empty():
				continue
			var ts := Time.get_ticks_msec()
			var sum := c.auto_resolve(int(s["id"]), dep)
			sim_ms += Time.get_ticks_msec() - ts
			battles += 1
			if sum.get("outcome", "") == "victory":
				victories += 1
			if battles <= 8:
				print("%s  %s with %d units (BV %d vs %d, skill x%s): %s (%s)  %s" % [c.date_str(), s["label"], dep.size(), int(sum.get("player_bv", 0)), int(sum.get("enemy_bv", 0)), str(sum.get("skill", [])), str(sum.get("outcome", "?")).to_upper(), sum.get("how", ""), "; ".join(sum.get("units", []))])
		min_cash = mini(min_cash, c.cash)
		if c.game_over:
			break
	var ms := Time.get_ticks_msec() - t1
	print("%d days in %d ms (%d ms in battles), %d contracts, %d battles, %d victories" % [days, ms, sim_ms, contracts, battles, victories])
	print("now %s at %s, cash %s (low %s), rating %s" % [c.date_str(), c.sm.name_of(c.location), Campaign.money(c.cash), Campaign.money(min_cash), c.rating()["letter"]])
	print("stats ", c.stats)
	var damaged := 0
	var wrecks := 0
	for id in c.units:
		var u2: MercUnit = c.units[id]
		if u2.wreck():
			wrecks += 1
		elif u2.damaged():
			damaged += 1
	print("units %d (damaged %d, wrecks %d), warehouse kinds %d, shopping %d, orders %d" % [c.units.size(), damaged, wrecks, c.warehouse.size(), c.shopping.size(), c.orders.size()])
	var dead := 0
	var injured := 0
	for p2 in c.roster(true):
		var pp: MercPerson = p2
		if pp.status == "dead":
			dead += 1
		elif pp.status == "injured":
			injured += 1
	print("people %d (dead %d, injured %d), history %s" % [c.people.size(), dead, injured, c.history.map(func(h): return "%s:%s" % [h["mission"], h["result"]])])
	check(battles > 0, "battles happened")
	check(contracts > 0, "contracts taken")
	# repair queue sanity
	var q := c.repair_queue()
	print("repair tasks open: %d" % q.size())
	for i in mini(6, q.size()):
		var t: Dictionary = q[i]["task"]
		print("  %s: %s (%d min, part %s x%s)" % [(q[i]["unit"] as MercUnit).label(), t["label"], int(t["minutes"]), t["part"], str(t["qty"])])
	# save / load
	var path := "user://merc_test.json"
	check(c.save_to(path), "save")
	var c2 := MercCampaign.load_from(path)
	check(c2 != null, "load")
	if c2 != null:
		var a := JSON.stringify(c.to_dict())
		var diffs: Array = []
		_diff(c.to_dict(), c2.to_dict(), "", diffs)
		print("save/load round trip identical: ", diffs.is_empty(), " (%d bytes)" % a.length())
		for d in diffs:
			print("  differs: ", d)
		check(diffs.is_empty(), "save/load round trip")
		var ev1 := c.advance_to_event(20)
		var ev2 := c2.advance_to_event(20)
		check(str(ev1) == str(ev2) and c.cash == c2.cash, "loaded game continues identically")
	print("FAILURES: ", fails)
	quit()
