extends SceneTree
## godot --headless --path . -s tests/test_setup.gd
## The setup screen's choices in the rules: what a custom start gives you in both modes, and that
## every campaign setting changes what it says it changes.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func merc(over := {}, play := {}, seed_v := 77) -> MercCampaign:
	return MercCampaign.new_custom("Setup Co", Color(0.4, 0.5, 0.6), MercCampaign.start_setup("combined", over), seed_v, play)


func kinds(c: MercCampaign) -> Dictionary:
	var out := {"mech": 0, "vehicle": 0, "infantry": 0}
	for id in c.units:
		var u: MercUnit = c.units[id]
		if u.design.is_infantry():
			out["infantry"] += 1
		elif u.is_vehicle():
			out["vehicle"] += 1
		else:
			out["mech"] += 1
	return out


func _init() -> void:
	# ---------------------------------------------------------------- mercenary: what you start with
	var a := MercCampaign.new_game("Setup Co", Color(0.4, 0.5, 0.6), 3025, "Galatea", "combined", 77)
	var b := merc({"year": 3025, "hall": "Galatea"}, {"difficulty": "Regular"})
	var ids_a: Array = []
	var ids_b: Array = []
	for id in a.units:
		ids_a.append((a.units[id] as MercUnit).design.id)
	for id in b.units:
		ids_b.append((b.units[id] as MercUnit).design.id)
	check(ids_a == ids_b and a.cash == b.cash and a.people.size() == b.people.size(), "a package and the same setup give the same company")
	var c := merc({"year": 3050, "month": 7, "hall": "Outreach", "mechs": 6, "vehicles": 2, "infantry": 2, "mech_bv": 6 * 1100,
		"vehicle_bv": 2 * 600, "infantry_bv": 260, "techs": 5, "astechs": 30, "doctors": 2, "medics": 8, "admins": 3, "cash": 7500000})
	var k := kinds(c)
	check(int(k["mech"]) == 6 and int(k["vehicle"]) == 2 and int(k["infantry"]) >= 1 and int(k["infantry"]) <= 2, "a custom force: %s" % str(k))
	check(c.cash == 7500000 and c.active("tech").size() == 5 and c.active("doctor").size() == 2 and c.active("admin").size() == 3 and c.astechs == 30, "custom staff and cash")
	check(c.date_str() == "1 July 3050" and c.sm.name_of(c.location) == "Outreach", "custom date and place: %s on %s" % [c.date_str(), c.sm.name_of(c.location)])
	var crewed := true
	for id in c.units:
		if c.crew_of(c.units[id]) == null:
			crewed = false
	check(crewed and c.lances.size() >= 3, "every unit has a crew and a lance (%d lances)" % c.lances.size())
	var light := merc({"mech_tons_max": 35, "mechs": 6, "mech_bv": 6 * 700, "vehicles": 0, "vehicle_bv": 0})
	var heaviest := 0
	for id in light.units:
		heaviest = maxi(heaviest, (light.units[id] as MercUnit).design.tons)
	check(heaviest <= 35 and kinds(light)["vehicle"] == 0, "a light company has nothing over 35 tons (heaviest %d)" % heaviest)
	var skill := {}
	for shift in [-0.25, 0.35]:
		var tot := 0.0
		var n := 0
		for sd in [1, 2, 3, 4]:
			var cc := merc({"crew": shift}, {}, sd)
			for p in cc.active("mechwarrior"):
				tot += (p as MercPerson).gunnery + (p as MercPerson).piloting
				n += 1
		skill[shift] = tot / maxf(1.0, n)
	check(float(skill[0.35]) < float(skill[-0.25]) - 1.0, "elite crews shoot and pilot better than green ones (%.1f against %.1f)" % [skill[0.35], skill[-0.25]])
	var worn := merc({"worn": true})
	var hurt := 0
	for id in worn.units:
		if (worn.units[id] as MercUnit).damaged():
			hurt += 1
	check(hurt >= worn.units.size() - 1 and not worn.repair_queue().is_empty(), "second-hand gear starts damaged (%d of %d)" % [hurt, worn.units.size()])
	var late := merc({"year": 3146, "hall": "Galatea"})
	check(late.units.size() == 8 and late.year() == 3146 and not late.market_units.is_empty(), "a company founded in 3146")
	check(MercCampaign.new_custom("Solo", Color.GRAY, MercCampaign.start_setup("lance", {"mechs": 0, "mech_bv": 0, "vehicles": 1, "vehicle_bv": 500}), 5, {}).units.size() == 1, "a one-tank company")

	# ---------------------------------------------------------------- mercenary: how it plays
	var base := merc()
	check(is_equal_approx(base.enemy_strength(), 0.8), "enemy strength defaults to Regular")
	var hard := merc({}, {"enemy_strength": 1.25})
	check(is_equal_approx(hard.enemy_strength(), 1.25) and str(hard.settings["difficulty"]) == "Elite", "the slider sets enemy strength, and the nearest difficulty name")
	var rich := merc({}, {"pay": 2.0})
	var pay_a := 0
	var pay_b := 0
	for o in base.contract_offers:
		pay_a += int(o["base_pay"])
	for o in rich.contract_offers:
		pay_b += int(o["base_pay"])
	check(base.contract_offers.size() == rich.contract_offers.size() and absf(float(pay_b) / maxf(1.0, pay_a) - 2.0) < 0.02, "contract pay x2 (%d against %d)" % [pay_b, pay_a])
	var dear := merc({}, {"prices": 1.5, "supply": 2})
	check(is_equal_approx(dear.price_mult(), 1.5) and int(dear.part_info("armor:standard")["price"]) == int(round(int(base.part_info("armor:standard")["price"]) * 1.5)), "prices x1.5")
	check(int(dear.procurement_tn("armor:standard")["tn"]) == int(base.procurement_tn("armor:standard")["tn"]) + 2, "parts harder to find by 2")
	var unit_a := 0
	var unit_b := 0
	for o in base.market_units:
		unit_a += int(o["price"])
	for o in dear.market_units:
		unit_b += int(o["price"])
	check(absf(float(unit_b) / maxf(1.0, unit_a) - 1.5) < 0.02, "market units cost x1.5 too")
	var quick := merc({}, {"repair_speed": 2.0, "upkeep": 0.5})
	check(quick.tech_minutes() == base.tech_minutes() * 2, "techs work twice as fast")
	check(absi(int(quick.monthly_costs()["Maintenance"]) * 2 - int(base.monthly_costs()["Maintenance"])) <= 2 and int(quick.monthly_costs()["Salaries"]) == int(base.monthly_costs()["Salaries"]), "upkeep halved, salaries untouched")
	var tough := merc({}, {"enemy_skill": 1})
	var rank := ["green", "regular", "veteran", "elite"]
	var up := 0
	for i in mini(base.contract_offers.size(), tough.contract_offers.size()):
		if rank.find(str(tough.contract_offers[i]["enemy_skill"])) > rank.find(str(base.contract_offers[i]["enemy_skill"])):
			up += 1
	check(up > 0, "tougher enemies: %d of %d offers a step up" % [up, base.contract_offers.size()])
	# off-board support and infantry
	for on in [true, false]:
		var sc0 := merc({}, {"enemy_support": on})
		sc0.contract = {"terms": {"command": "House"}, "enemy": "DC"}
		var with_support := 0
		for sd in 60:
			var bs := sc0.battle_support({"type": "major_battle", "seed": sd})
			if int(bs["enemy"]["artillery"]) + int(bs["enemy"]["air_strike"]) > 0:
				with_support += 1
		check((with_support > 0) == on, "enemy support %s: %d of 60 battles have it" % ["on" if on else "off", with_support])
	# the timeline
	var quiet := merc({"year": 3028, "month": 8}, {"news": false, "trade_effects": false})
	var loud := merc({"year": 3028, "month": 8})
	for d in 30:
		quiet.advance_day()
		loud.advance_day()
	check(quiet.news.is_empty() and not loud.news.is_empty(), "news off: nothing in the news (%d against %d)" % [quiet.news.size(), loud.news.size()])
	check(is_equal_approx(quiet.timeline_mult("pay"), 1.0) and is_equal_approx(quiet.price_mult(), 1.0) and loud.timeline_mult("pay") > 1.2, "trade effects off: the war leaves pay and prices alone")
	# IndustrialMechs
	var plain := merc({"year": 3050}, {"industrial": false})
	var ind := 0
	for r in 25:
		plain.refresh_markets()
		for o in plain.market_units:
			if ForceGen.industrial(str(o["design"])):
				ind += 1
	check(ind == 0, "IndustrialMechs off: none in 25 markets")
	# deaths
	var safe := merc({}, {"lethality": 0.0})
	var grim := merc({}, {"lethality": 1.0})
	var res := {"kills": 0, "pilot_hits": 6, "reason": "MechWarrior killed", "crew_killed": false, "destroyed": true, "ejected": false}
	var sk: Dictionary = safe.rules["skills"]
	for deadly in [false, true]:
		var cc2: MercCampaign = grim if deadly else safe
		var u2: MercUnit = null
		for id in cc2.units:
			if not (cc2.units[id] as MercUnit).is_vehicle():
				u2 = cc2.units[id]
				break
		var p2: MercPerson = cc2.crew_of(u2)
		cc2._crew_after(p2, u2, res, false, true, false, sk)
		check((p2.status == "dead") == deadly, "a killing hit with deaths %s: %s" % ["on" if deadly else "off", p2.status])
	# saves
	var path := "user://_setup_test.json"
	check(dear.save_to(path), "merc save")
	var back := MercCampaign.load_from(path)
	check(back != null and is_equal_approx(back.price_mult(), 1.5) and int(back.opt("supply")) == 2, "settings survive a save")
	var old := base.to_dict()
	old["settings"] = {"auto_withdraw": true, "difficulty": "Veteran"}
	var oldc := MercCampaign.from_dict(JSON.parse_string(JSON.stringify(old)))
	check(is_equal_approx(oldc.enemy_strength(), 0.95) and is_equal_approx(oldc.opt("pay"), 1.0) and oldc.flag("news"), "an older save plays by the defaults and its difficulty name")

	# ---------------------------------------------------------------- stable
	var s0 := Campaign.new_game("Setup Stable", "Silesia", 21)
	var p0 := s0.player()
	check(s0.year == 3015 and p0.cash == 4000000 and p0.warriors.size() == 3 and p0.mechs.size() == 3 and s0.stables.size() == 20, "the default stable start is unchanged")
	var s1 := Campaign.new_game("Setup Stable", "Kobe", 21, Color(-1, 0, 0), {"year": 3050, "cash": 9000000, "warriors": 5,
		"mechs": ["light", "heavy", "assault"], "bays": 2, "techs": 6, "fame": 20.0, "rivals": 8, "rival_skill": 0.25},
		{"purses": 2.0, "prices": 1.5, "upkeep": 0.5, "sponsors": 2.0, "injuries": 0.5, "timeline": false, "merc_work": false})
	var p1 := s1.player()
	check(s1.year == 3050 and p1.cash == 9000000 and p1.warriors.size() == 5 and s1.stables.size() == 9 and p1.techs == 6 and is_equal_approx(p1.fame, 20.0), "a custom stable: year, cash, people, league")
	var classes: Array = []
	for uid in p1.mechs:
		classes.append(s1.db.weight_class((s1.mechs[uid] as OwnedMech).design.tons))
	classes.sort()
	check(classes == ["assault", "heavy", "light"] and p1.bays >= 3, "its 'Mechs by weight class: %s in %d bays" % [str(classes), p1.bays])
	check(is_equal_approx(s1.effect_mult("purse_mult"), 2.0) and is_equal_approx(s1.price_mult(), 1.5), "purses x2 and prices x1.5")
	var jobs := 0
	for wk in 12:
		s1.advance_week()
		jobs += s1.merc_jobs.size()
	var events := 0
	for n in s1.news:
		if str(n["kind"]) == "event":
			events += 1
	check(jobs == 0, "mercenary work off: no offers in 12 weeks")
	check(events == 0, "timeline off: the Clan invasion goes unreported in 3050 (%d events)" % events)
	var s2 := Campaign.new_game("Setup Stable", "Kobe", 21, Color(-1, 0, 0), {"year": 3050})
	for wk in 12:
		s2.advance_week()
	var events2 := 0
	for n in s2.news:
		if str(n["kind"]) == "event":
			events2 += 1
	check(events2 >= 1 and s2.flag_active("clan_salvage"), "timeline on: it is reported (%d events)" % events2)
	# upkeep and sponsors on the player's ledger only
	var led: Dictionary = p1.ledger[-1].get("lines", {}) if not p1.ledger.is_empty() else {}
	check(int(led.get("Bay upkeep", 0)) == -int(p1.bays * int(s1.rules["bay_upkeep_week"]) * 0.5), "upkeep halved on the weekly ledger: %s" % str(led.get("Bay upkeep", 0)))
	var spath := "user://_setup_stable_test.json"
	check(s1.save_to(spath), "stable save")
	var sb := Campaign.load_from(spath)
	check(sb != null and is_equal_approx(sb.effect_mult("purse_mult") / maxf(0.01, s1.effect_mult("purse_mult")), 1.0) and not sb.flag("merc_work"), "stable settings survive a save")
	var s3 := Campaign.new_game("Late Stable", "Cathay", 9, Color(-1, 0, 0), {"year": 3146, "rivals": 12})
	for wk in 3:
		s3.advance_week()
	check(s3.year == 3146 and s3.week == 4 and s3.stables.size() == 13, "a stable founded in 3146 runs")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(spath))
	print("SETUP TEST DONE, fails: %d" % fails)
	quit()
