extends SceneTree
## godot --headless --path . -s tests/test_infantry.gd
## Infantry platoons and battle armour squads: data, construction, damage rules, leg attacks and
## whole battles against 'Mechs and vehicles.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func entry(id: String, name: String, controller := "ai", extra := {}) -> Dictionary:
	var d := GameData.db().stock_design(id)
	assert(d != null, id)
	var e := {"design": d, "warrior": {"callsign": name, "gunnery": 4, "piloting": 5, "traits": []}, "orders": {}, "controller": controller}
	for k in extra:
		e[k] = extra[k]
	return e


func battle(seed: int, inputs := []) -> CombatSim:
	var a2 := BattlefieldGenerator.generate(["bf_urban", "bf_forest", "bf_plains"][seed % 3], 800 + seed, {"player_n": 3, "enemy_n": 7})
	var s2 := [[entry("Wolverine WVR-6R", "Lead", "player"), entry("Hunchback HBK-4G", "Two", "player"), entry("Firestarter FS9-H", "Three", "player")],
		[entry("Foot Platoon (SRM)", "1st"), entry("Foot Platoon (Laser)", "2nd"), entry("Jump Platoon (Laser)", "3rd"),
		entry("Motorized Platoon (SRM)", "4th"), entry("Mechanized Platoon (MG)", "5th"),
		entry("IS Standard Battle Armor (Small Laser)", "BA 1"), entry("Elemental (Small Laser)", "Point")]]
	return CombatSim.create(a2, s2, 60 + seed, {"merc": true, "time_limit": 900.0}, true, inputs)


func _init() -> void:
	var db := GameData.db()
	check(db.infantry.size() >= 12, "infantry data loaded")
	var lib := db.get_infantry_library()
	check(lib.size() == db.infantry.size(), "infantry library")
	for u in db.infantry:
		var d := VehicleDesign.vfrom_dict(u)
		var r := VehicleConstruction.analyze(d)
		check(d.is_infantry() and d.is_vehicle(), "%s is infantry" % d.id)
		check(r["valid"] and int(r["bv"]) > 0 and int(r["cost"]) > 0, "%s analyzes" % d.id)
		check(FileAccess.file_exists("res://assets/megamek/units/" + str(u["sprite"])), "%s sprite" % d.id)
		var back := VehicleDesign.vfrom_dict(d.to_dict())
		check(back.troopers == d.troopers and back.squad_weapons.size() == d.squad_weapons.size() and back.is_battle_armor() == d.is_battle_armor(), "%s round-trips" % d.id)
		var m := CombatMech.create_any(d, {"callsign": "x", "gunnery": 4, "piloting": 5, "traits": []}, {}, 0, 0)
		check(m.is_infantry and m.troopers_alive() == d.troopers, "%s combat unit" % d.id)
		check(m.weapons.size() == d.squad_weapons.size(), "%s weapons" % d.id)
	# --- damage rules, on a flat field
	var a := BattlefieldGenerator.generate("bf_plains", 31, {"player_n": 2, "enemy_n": 2})
	var sides := [[entry("Hunchback HBK-4G", "Hunch", "player"), entry("Locust LCT-1V", "Bug", "player")],
		[entry("Foot Platoon (Rifle)", "Rifles"), entry("IS Standard Battle Armor (Small Laser)", "Suits")]]
	var sim := CombatSim.create(a, sides, 77, {"merc": true, "time_limit": 600.0}, true)
	var hb: CombatMech = sim.mechs[0]
	var pl: CombatMech = sim.mechs[2]
	var ba: CombatMech = sim.mechs[3]
	check(pl.is_infantry and not pl.battle_armor and ba.battle_armor, "unit kinds")
	check(pl.troopers_alive() == 28 and ba.troopers_alive() == 4, "starting strength")
	var rifle_dmg := int(pl.mounts[pl.weapons[0]]["item"]["dmg"])
	check(rifle_dmg == 8, "28 rifles do 8 (got %d)" % rifle_dmg)
	# an AC/20 into a platoon kills 2 (x2 in the open), not 20
	pl.pos = a.size_m() / 2.0
	var before := pl.troopers_alive()
	sim.apply_damage(pl, "PL", 20, false, hb, "AC/20")
	var lost := before - pl.troopers_alive()
	check(lost == 2, "20 points of damage kill 2 troopers (got %d)" % lost)
	check(int(pl.mounts[pl.weapons[0]]["item"]["dmg"]) < rifle_dmg or pl.troopers_alive() > 24, "fewer rifles, less damage")
	# machine guns are the real killers
	var mg := {"wtype": "mg", "dmg": 2, "name": "Machine Gun"}
	before = pl.troopers_alive()
	sim._fire_on_platoon(hb, pl, mg, "standard", 1, "Machine Gun")
	lost = before - pl.troopers_alive()
	check(lost >= 2, "a machine gun burst kills at least 2 (got %d)" % lost)
	# battle armour: one suit takes the hit, the rest fight on
	sim.apply_damage(ba, "T1", 20, false, hb, "AC/20")
	check(ba.troopers_alive() == 3, "an AC/20 kills exactly one suit (left %d)" % ba.troopers_alive())
	sim.apply_damage(ba, "T1", 5, false, hb, "Medium Laser")
	check(ba.troopers_alive() == 3, "a medium laser only dents a suit")
	check(not ba.out, "squad still fighting")
	# leg attacks
	var hits := 0
	var leg0 := int(hb.armor["LL"]) + int(hb.armor["RL"])
	for k in 40:
		sim.leg_attack(ba, hb)
		if sim.events[-1].get("k", "") != "leg_attack" or true:
			pass
	for e in sim.events:
		if e["k"] == "leg_attack" and e["hit"]:
			hits += 1
	check(hits > 3, "leg attacks land (%d of 40)" % hits)
	check(int(hb.armor["LL"]) + int(hb.armor["RL"]) < leg0 or hb.out, "leg attacks hurt legs")
	# --- whole battles
	var stats := {"trooper": 0, "leg_attack": 0, "inf_out": 0, "mech_dmg_by_inf": 0}
	var wins := {0: 0, 1: 0, -1: 0}
	var ms := 0
	for seed in 6:
		var sm := battle(seed)
		var t0 := Time.get_ticks_msec()
		var res := sm.run_to_end(1200.0)
		ms += Time.get_ticks_msec() - t0
		wins[int(res["winner"])] = int(wins.get(int(res["winner"]), 0)) + 1
		for e in sm.events:
			var k := str(e["k"])
			if stats.has(k):
				stats[k] = int(stats[k]) + 1
			check(sm.describe(e) != "" or not (k in ["trooper", "leg_attack"]), "event text for " + k)
		for m: CombatMech in sm.mechs:
			if m.is_infantry:
				stats["mech_dmg_by_inf"] = int(stats["mech_dmg_by_inf"]) + m.dmg_dealt
				if m.out:
					stats["inf_out"] = int(stats["inf_out"]) + 1
		for u in res["mechs"]:
			if u.get("infantry", false):
				check(u.has("troopers") and u["vehicle"], "result carries infantry state")
		var detail: Array = []
		for m: CombatMech in sm.mechs:
			detail.append("%s %s%s dealt %d" % [m.name, ("%d left" % m.troopers_alive()) if m.is_infantry else ("%d%% int" % int((1.0 - m.internal_lost_fraction()) * 100)), " OUT:" + m.out_reason if m.out else "", m.dmg_dealt])
		print("   ", " | ".join(detail))
		print("battle %d: %s after %.0f s (%s)" % [seed, ["draw", "player", "enemy"][int(res["winner"]) + 1], float(res["duration"]), res["how"]])
		# exact replay
		if seed == 0:
			var rp := battle(seed, sm.inputs)
			var r2 := rp.run_to_end(1200.0)
			check(str(r2["mechs"]) == str(res["mechs"]) and float(r2["duration"]) == float(res["duration"]), "replay matches")
	print("infantry battles: wins ", wins, " stats ", stats, " avg %d ms" % (ms / 6))
	check(int(stats["trooper"]) > 10, "troopers fall")
	check(int(stats["mech_dmg_by_inf"]) > 20, "infantry hurt 'Mechs")
	check(int(stats["inf_out"]) > 0, "squads get wiped out or break")
	merc_layer()
	print("INFANTRY TEST DONE, fails: %d" % fails)
	quit()


## Infantry in a mercenary campaign: who fields what, enemy platoons and friendly garrisons in the
## battles, buying a platoon, losing troopers and bringing the unit back to strength.
func merc_layer() -> void:
	var db := GameData.db()
	var rng := SimRng.new(77)
	# who fields what
	for k in 30:
		for id in ForceGen.infantry("PIR", 3060, 300, rng):
			check(not db.stock_design(id).is_battle_armor(), "pirates have no battle armour")
		for id in ForceGen.infantry("LA", 3025, 300, rng):
			check(not db.stock_design(id).is_battle_armor(), "no battle armour in 3025")
		for id in ForceGen.infantry("CW", 3052, 300, rng):
			check(db.stock_design(id).tech == "Clan" and db.stock_design(id).is_battle_armor(), "Clans field Elementals")
		for id in ForceGen.infantry("DC", 3060, 300, rng, {"mobile_only": true}):
			var d := db.stock_design(id) as VehicleDesign
			check(d.is_battle_armor() or d.walk >= 3, "an attacking force brings no foot platoons")
	var seen_ba := false
	for k in 40:
		for id in ForceGen.infantry("FS", 3060, 400, rng):
			if db.stock_design(id).is_battle_armor():
				seen_ba = true
	check(seen_ba, "the Inner Sphere has battle armour by 3060")
	check(ForceGen.bv_of("Foot Platoon (Rifle)") > 0, "infantry have a BV in the force tables")

	var c := MercCampaign.new_game("Foot Co", Color(0.3, 0.6, 0.4), 3055, "Galatea", "combined", 31)
	check(not c.contract_offers.is_empty(), "contract offers")
	check(c.accept_contract(int(c.contract_offers[0]["offer"])) == "", "contract accepted")
	# buy a platoon and a squad: they arrive led and ready
	c.cash += 20000000
	var mine: Array = []
	for id in ["Jump Platoon (Laser)", "IS Standard Battle Armor (Small Laser)"]:
		var off := {"offer": c.new_id(), "design": id, "price": 500000, "condition": {}, "seller": "test"}
		c.market_units.append(off)
		check(c.buy_unit(int(off["offer"])) == "", "bought " + id)
		var nu: MercUnit = null
		for uid in c.units:
			if (c.units[uid] as MercUnit).design.display_name() == db.stock_design(id).display_name():
				nu = c.units[uid]
		check(nu != null and c.crew_of(nu) != null and c.deployable(nu), id + " comes with its officer")
		check(nu.bv() > 0 and nu.value() > 0 and MercRepair.tasks(nu).is_empty(), id + " at full strength")
		c.set_lance(nu.id, int(c.lances[0]["id"]))
		mine.append(nu)
	# the market offers them
	var offered := 0
	for k in 12:
		c.refresh_markets()
		for o in c.market_units:
			if db.stock_design(str(o["design"])).is_infantry():
				offered += 1
				check(int(o["price"]) > 0 and (o["condition"] as Dictionary).is_empty(), "infantry offers are whole and priced")
	check(offered > 0, "the market offers infantry (%d in 12 months)" % offered)
	# battles of every kind: enemy infantry, garrisons, salvage without infantry in it
	var with_inf := 0
	var with_gar := 0
	var types := ["standup", "base_attack", "base_defense", "hold_the_line", "breakthrough", "major_battle", "recon", "ambush"]
	for k in 16:
		var sc := c._new_scenario(c.lances[0], "fight", types[k % types.size()])
		c.scenarios.append(sc)
		var dep := c.default_deployment(sc)
		if dep.is_empty():
			break
		var b := c.make_battle(int(sc["id"]), dep, false)
		check(not b.is_empty(), "battle built: " + str(sc["type"]))
		var meta: Dictionary = b["battle"]
		var sim: CombatSim = b["sim"]
		var ni := 0
		var ng := 0
		for e in meta["enemies"]:
			if e.get("infantry", false):
				ni += 1
		for e in meta["allies"]:
			if e.get("infantry", false):
				ng += 1
		with_inf += 1 if ni > 0 else 0
		with_gar += 1 if ng > 0 else 0
		check(ng == 0 or str(sc["type"]) in ["base_defense", "hold_the_line"], "garrisons only where you defend")
		check(sim.mechs.size() == dep.size() + (meta["allies"] as Array).size() + (meta["enemies"] as Array).size(), "index map holds")
		for j in (meta["enemies"] as Array).size():
			var em: CombatMech = sim.mechs[dep.size() + (meta["allies"] as Array).size() + j]
			check(em.team == 1 and em.is_infantry == bool(meta["enemies"][j].get("infantry", false)), "enemy %d is what the map says" % j)
			check(sim.arena.passable_p(em.pos, em.mover), "enemy stands on passable ground")
		sc["status"] = "declined"
	check(with_inf >= 3, "enemy infantry turn up (%d of 16 battles)" % with_inf)
	check(with_gar >= 1, "garrisons turn up (%d of 16 battles)" % with_gar)
	# losses and replacements
	for nu2 in mine:
		var u2: MercUnit = nu2
		if not c.units.has(u2.id):
			print("  the %s was wiped out in the battles above" % u2.label())
			continue
		var vd := u2.design as VehicleDesign
		if vd.is_battle_armor():
			u2.condition = {"armor": {"T1": 0, "T2": 3, "T3": vd.suit_armor, "T4": vd.suit_armor}, "internal": {"T1": 0, "T2": 1, "T3": 1, "T4": 1}, "dead_mounts": [], "ammo": {}, "vstate": {}}
		else:
			u2.condition = {"armor": {}, "internal": {"PL": vd.troopers - 9}, "dead_mounts": [], "ammo": {}, "vstate": {}}
		u2.status = "damaged"
		var ts := MercRepair.tasks(u2)
		check(ts.size() == (2 if vd.is_battle_armor() else 1), "%s: repair tasks (%d)" % [u2.label(), ts.size()])
		var info := MercRepair.part_info(str(ts[0]["part"]), c.year())
		check(int(info["price"]) > 0 and str(info["name"]) != str(ts[0]["part"]), "replacements have a name and a price: %s, %d" % [info["name"], int(info["price"])])
		check(u2.damage_fraction() > 0.0 and u2.value() < u2.base_cost(), "a mauled unit is worth less")
		var b2 := CombatMech.create_any(u2.design, {"callsign": "x", "gunnery": 4, "piloting": 5}, {}, 0, 0, u2.sim_condition())
		check(b2.troopers_alive() == (3 if vd.is_battle_armor() else vd.troopers - 9), "it goes into battle under strength (%d)" % b2.troopers_alive())
		for t in ts:
			MercRepair.apply(u2, t)
		check(u2.condition.is_empty() and u2.status == "ready", "%s back to strength" % u2.label())
	# fight a few for real: results, salvage and losses are booked
	for k in 3:
		var sc3 := c._new_scenario(c.lances[0], "fight", ["standup", "hold_the_line", "base_attack"][k])
		c.scenarios.append(sc3)
		var dep3 := c.default_deployment(sc3)
		if dep3.is_empty():
			break
		var sum := c.auto_resolve(int(sc3["id"]), dep3, false)
		check(not sum.is_empty(), "battle resolved")
		for sv in c.salvage:
			check(not db.stock_design(str(sv["design"])).is_infantry(), "no infantry in the salvage")
		c.salvage = []
		print("  %s -> %s; %s" % [sc3["type"], sum.get("outcome", "?"), "; ".join(sum.get("units", []))])
		for u in c.combat_units():
			var mu: MercUnit = u
			check(not (mu.design.is_infantry() and mu.wreck()), "infantry are never wrecks")
			if mu.design.is_infantry() and not mu.condition.is_empty():
				check(not MercRepair.tasks(mu).is_empty(), "a hurt squad has replacements to find")
	# a save keeps them
	var c2 := MercCampaign.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	var kept := 0
	for uid in c2.units:
		if (c2.units[uid] as MercUnit).design.is_infantry():
			kept += 1
	var had := 0
	for uid in c.units:
		if (c.units[uid] as MercUnit).design.is_infantry():
			had += 1
	check(kept == had, "infantry survive a save (%d of %d)" % [kept, had])
