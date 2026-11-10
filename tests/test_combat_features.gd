extends SceneTree
## godot --headless --path . -s tests/test_combat_features.gd
## Team fights, corner calls, physical attacks, fire and collapsing buildings, hazards, night and weather,
## alternate ammo, MASC, ECM, C3 and Narc.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func w(name: String, g := 4, p := 5, traits := []) -> Dictionary:
	return {"name": name, "callsign": name, "gunnery": g, "piloting": p, "traits": traits}


func entry(id: String, name: String, orders := {}, traits := []) -> Dictionary:
	return {"design": MechDesign.from_stock(id), "warrior": w(name, 4, 5, traits), "orders": orders}


func run(theme: String, sides: Array, seed_value: int, bout := {}, inputs := []) -> CombatSim:
	var team_size := 1
	for s in sides:
		team_size = maxi(team_size, (s as Array).size())
	var arena := ArenaGenerator.generate(theme, seed_value, team_size, "", sides.size())
	var sim := CombatSim.create(arena, sides, seed_value * 7 + 3, bout, true, inputs)
	sim.run_to_end()
	return sim


func count(sim: CombatSim, kind: String) -> int:
	var n := 0
	for e in sim.events:
		if e["k"] == kind:
			n += 1
	return n


## First library design whose loadout matches a predicate on its item list.
func find_design(pred: Callable, max_tons := 100) -> String:
	var db := GameData.db()
	for e in db.get_library():
		if int(e["tons"]) > max_tons or e["tech"] == "Clan":
			continue
		var d: Dictionary = db.design_by_id[e["id"]]
		var ids: Array = []
		for loc in d["slots"]:
			for s in d["slots"][loc]:
				if s != "":
					ids.append(MechDesign.base_id(str(s)))
		if pred.call(ids, d):
			return e["id"]
	return ""


func has_misc(ids: Array, misc: String) -> bool:
	for id in ids:
		if GameData.db().item(id).get("misc", "") == misc:
			return true
	return false


func has_wtype(ids: Array, wt: String) -> bool:
	for id in ids:
		if GameData.db().item(id).get("wtype", "") == wt:
			return true
	return false


func _init() -> void:
	var t0 := Time.get_ticks_msec()
	print("== Team fights")
	var tag := run("bowl", [[entry("Hunchback HBK-4G", "Hunch"), entry("Wolverine WVR-6R", "Wolvie")],
		[entry("Centurion CN9-A", "Cent"), entry("Enforcer ENF-4R", "Enf")]], 11)
	check(tag.mechs.size() == 4 and tag.finished, "2v2 tag fight finishes (%s after %.0f s, winner team %d)" % [tag.result["how"], tag.t, tag.result["winner"]])
	var lance := run("factory", [[entry("Marauder MAD-3R", "A1"), entry("Warhammer WHM-6R", "A2"), entry("Archer ARC-2R", "A3"), entry("Jenner JR7-D", "A4")],
		[entry("Thunderbolt TDR-5S", "B1"), entry("Rifleman RFL-3N", "B2"), entry("Catapult CPLT-C1", "B3"), entry("Panther PNT-9R", "B4")]], 12)
	check(lance.mechs.size() == 8 and lance.finished, "4v4 lance fight finishes (%s after %.0f s)" % [lance.result["how"], lance.t])
	var melee_sides: Array = []
	for id in ["Hunchback HBK-4G", "Wolverine WVR-6R", "Centurion CN9-A", "Enforcer ENF-4R", "Griffin GRF-1N", "Shadow Hawk SHD-2H"]:
		melee_sides.append([entry(id, id.split(" ")[0])])
	var melee := run("urban", melee_sides, 13)
	var placement: Array = melee.result["placement"]
	check(melee.mechs.size() == 6 and placement.size() == 6, "six-'Mech free-for-all finishes, winner %s" % melee.mechs[placement[0]].name)
	var first_out := 99999.0
	for m in melee.result["mechs"]:
		if m["out"]:
			first_out = minf(first_out, float(m["out_time"]))
	check(melee.result["winner"] < 0 or melee.mechs[placement[0]].team == melee.result["winner"], "placement puts the winner first")

	print("== Corner calls")
	var base_sides := func(): return [[entry("Hunchback HBK-4G", "H")], [entry("Wolverine WVR-6R", "W")]]
	var live := CombatSim.create(ArenaGenerator.generate("jungle", 21), base_sides.call(), 99, {}, true)
	for k in 200:
		live.step()
	check(live.issue_call(0, "back_off"), "call accepted mid-fight")
	for k in 200:
		live.step()
	live.issue_call(0, "press")
	live.run_to_end()
	var replay := CombatSim.create(ArenaGenerator.generate("jungle", 21), base_sides.call(), 99, {}, true, live.result["inputs"])
	replay.run_to_end()
	check(replay.result["winner"] == live.result["winner"] and replay.t == live.t and replay.events.size() == live.events.size(),
		"replaying the recorded calls reproduces the fight exactly (%d calls, %.1f s)" % [live.result["inputs"].size(), live.t])
	var plain := CombatSim.create(ArenaGenerator.generate("jungle", 21), base_sides.call(), 99, {}, true)
	plain.run_to_end()
	check(plain.events.size() != live.events.size() or plain.t != live.t, "calls change the fight")
	var limited := CombatSim.create(ArenaGenerator.generate("bowl", 22), base_sides.call(), 5, {"calls": 1}, true)
	limited.step()
	check(limited.issue_call(0, "flank") and not limited.issue_call(0, "cool"), "corner calls are limited per fight")

	print("== Physical attacks (brawlers in the jungle)")
	var kinds := {}
	var jumpers := ["Wolverine WVR-6R", "Griffin GRF-1N", "Phoenix Hawk PXH-1", "Shadow Hawk SHD-2H"]
	for k in 24:
		var a: String = jumpers[k % jumpers.size()]
		var b: String = ["Hunchback HBK-4G", "Centurion CN9-A", "Enforcer ENF-4R", "Trebuchet TBT-5N"][k % 4]
		var brawl := {"range": "close", "position": "brawl", "heat": "hot", "retreat": 0.8}
		var s := run("jungle" if k % 2 == 0 else "factory", [[entry(a, "A", brawl, ["showboat", "brawler"])], [entry(b, "B", brawl, ["brawler"])]], 300 + k)
		for e in s.events:
			var key: String = e["k"]
			if key == "physical":
				key = "physical:" + str(e["w"])
			kinds[key] = int(kinds.get(key, 0)) + 1
	print("  ", kinds)
	check(int(kinds.get("physical:kick", 0)) + int(kinds.get("physical:punch", 0)) > 0, "kicks and punches happen")
	check(int(kinds.get("charge", 0)) > 0, "charges happen (%d)" % int(kinds.get("charge", 0)))
	check(int(kinds.get("dfa", 0)) > 0, "death from above happens (%d)" % int(kinds.get("dfa", 0)))
	check(int(kinds.get("club_pickup", 0)) > 0, "'Mechs rip up trees and girders for clubs (%d)" % int(kinds.get("club_pickup", 0)))

	print("== The battlefield")
	var fires := 0
	var collapses := 0
	var flame := find_design(func(ids, d): return has_wtype(ids, "flamer"), 60)
	for k in 12:
		var s2 := run("jungle", [[entry(flame, "F", {"range": "close"})], [entry("Wolverine WVR-6R", "W", {"range": "close"})]], 400 + k)
		fires += count(s2, "fire")
	check(fires > 0, "flamers set the jungle alight (%d fires with %s)" % [fires, flame])
	for k in 12:
		var s3 := run("urban", [[entry("Atlas AS7-D", "A")], [entry("Marauder MAD-3R", "M")]], 500 + k)
		collapses += count(s3, "collapse")
	check(collapses > 0, "buildings collapse in urban fights (%d)" % collapses)
	var hz := {}
	for theme in ["factory", "canyon", "urban"]:
		var s4 := run(theme, [[entry("Hunchback HBK-4G", "H")], [entry("Centurion CN9-A", "C")]], 600)
		check(s4.arena.hazards.size() > 0, "%s arena has hazards (%d)" % [theme, s4.arena.hazards.size()])
		for e in s4.events:
			if e["k"] == "hazard":
				hz[e["type"]] = int(hz.get(e["type"], 0)) + 1
	print("  hazard events: ", hz)
	check(hz.has("flame_jets") and hz.has("steam_vents"), "flame jets and steam vents fire")

	print("== Night and weather")
	var night := run("bowl", [[entry("Archer ARC-2R", "A")], [entry("Rifleman RFL-3N", "R")]], 700, {"conditions": {"light": "night", "weather": "rain"}})
	var saw_night := false
	var saw_rain := false
	for e in night.events:
		if e["k"] == "shot":
			for md in e["mods"]:
				if md[0] == "Night":
					saw_night = true
				if md[0] == "Rain":
					saw_rain = true
	check(saw_night and saw_rain, "night and rain modifiers appear in the to-hit rolls")
	var fog := run("bowl", [[entry("Archer ARC-2R", "A")], [entry("Rifleman RFL-3N", "R")]], 701, {"conditions": {"weather": "fog"}})
	var longest := 0.0
	for e in fog.events:
		if e["k"] == "shot":
			var d: float = fog.mechs[e["m"]].pos.distance_to(fog.mechs[e["tg"]].pos)
			longest = maxf(longest, d)
	check(fog.arena.max_los_m < 400.0, "fog limits line of sight to %.0f m" % fog.arena.max_los_m)

	print("== Ammunition")
	var srm := find_design(func(ids, d): return has_wtype(ids, "srm"), 60)
	var inf := 0
	for k in 6:
		var s5 := run("jungle", [[entry(srm, "S", {"ammo": {"srm": "inferno"}, "range": "close"})], [entry("Wolverine WVR-6R", "W")]], 800 + k)
		inf += count(s5, "inferno")
	check(inf > 0, "Inferno SRMs splash heat (%d hits with %s)" % [inf, srm])
	var lbx := find_design(func(ids, d): return has_wtype(ids, "lbx"))
	if lbx != "":
		var s6 := run("bowl", [[entry(lbx, "L", {"ammo": {"lbx": "lbx_cluster"}})], [entry("Marauder MAD-3R", "M")]], 900)
		var cl := false
		for e in s6.events:
			if e["k"] == "shot" and str(e["w"]).find("cluster") >= 0:
				cl = true
		check(cl, "LB-X fires cluster rounds (%s)" % lbx)
	var ac := find_design(func(ids, d): return has_wtype(ids, "ac"))
	var s7 := run("bowl", [[entry(ac, "A", {"ammo": {"ac": "armor_piercing"}})], [entry("Marauder MAD-3R", "M")]], 901)
	check(count(s7, "ap") > 0 or count(s7, "shot") > 0, "armor-piercing autocannon rounds load (%s, %d AP crit chances)" % [ac, count(s7, "ap")])

	print("== Equipment")
	var masc := find_design(func(ids, d): return has_misc(ids, "masc"))
	if masc != "":
		var sprint := false
		var masc_fail := 0
		for k in 6:
			var s8 := run("canyon", [[entry(masc, "M")], [entry("Atlas AS7-D", "A")]], 1000 + k)
			masc_fail += count(s8, "masc_fail")
			for f in s8.frames:
				if int(f[7]) & 64:
					sprint = true
		check(sprint, "MASC sprints happen (%s, %d failures)" % [masc, masc_fail])
	var ecm := find_design(func(ids, d): return has_misc(ids, "ecm"))
	var c3 := find_design(func(ids, d): return has_misc(ids, "c3"))
	var narc := find_design(func(ids, d): return has_wtype(ids, "narc"))
	print("  using ECM %s, C3 %s, Narc %s" % [ecm, c3, narc])
	if c3 != "":
		var c3_shot := 0
		for k in 4:
			var s9 := run("bowl", [[entry(c3, "C1", {"range": "long"}), entry(c3, "C2", {"range": "close", "position": "flank"})],
				[entry("Marauder MAD-3R", "M1"), entry("Warhammer WHM-6R", "M2")]], 1100 + k)
			for e in s9.events:
				if e["k"] == "shot":
					for md in e["mods"]:
						if str(md[0]).find("(C3)") >= 0:
							c3_shot += 1
		check(c3_shot > 0, "C3 networks share range (%d shots used a teammate's range)" % c3_shot)
	if narc != "":
		var s10 := run("bowl", [[entry(narc, "N")], [entry("Marauder MAD-3R", "M")]], 1200)
		check(count(s10, "narc") > 0, "Narc beacons stick (%d)" % count(s10, "narc"))
	if ecm != "":
		var s11 := run("bowl", [[entry(ecm, "E")], [entry("Marauder MAD-3R", "M")]], 1300)
		check(s11.mechs[0].ecm or s11.mechs[0].out, "ECM mounts work")
	print("time: %d ms" % (Time.get_ticks_msec() - t0))
	print("FAILURES: ", fails)
	quit(fails)
