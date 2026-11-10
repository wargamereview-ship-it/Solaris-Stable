extends SceneTree
## godot --headless --path . -s tests/test_merc_combat.gd
## Merc battles: battlefields for every biome, 'Mechs against vehicles, player commands, map-edge
## exits, reinforcements, objectives and exact replays.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func entry(id: String, name: String, team: int, controller := "ai", extra := {}) -> Dictionary:
	var d := GameData.db().stock_design(id)
	assert(d != null, id)
	var e := {"design": d, "warrior": {"callsign": name, "gunnery": 4, "piloting": 5, "traits": []}, "orders": {}, "controller": controller}
	for k in extra:
		e[k] = extra[k]
	return e


func vid(prefix: String) -> String:
	for v in GameData.db().get_vehicle_library():
		if str(v["id"]).begins_with(prefix):
			return v["id"]
	return ""


func _init() -> void:
	var db := GameData.db()
	# --- battlefields
	for biome in ["bf_plains", "bf_hills", "bf_forest", "bf_jungle", "bf_desert", "bf_badlands", "bf_arctic", "bf_urban", "bf_mountains", "bf_coast"]:
		var t0 := Time.get_ticks_msec()
		var a := BattlefieldGenerator.generate(biome, 1234, {"player_n": 4, "enemy_n": 6, "scenario": "base_defense"})
		var ms := Time.get_ticks_msec() - t0
		var counts := {}
		for i in a.w * a.h:
			counts[a.terrain[i]] = int(counts.get(a.terrain[i], 0)) + 1
		print("%-13s %dx%d cells  %d ms  defend cells %d  woods %d water %d bld %d pave %d" % [biome, a.w, a.h, ms,
			(a.objectives.get("defend_cells", []) as Array).size(), int(counts.get(Arena.T.LIGHT_WOODS, 0)) + int(counts.get(Arena.T.HEAVY_WOODS, 0)),
			int(counts.get(Arena.T.WATER, 0)), int(counts.get(Arena.T.BUILDING, 0)), int(counts.get(Arena.T.PAVEMENT, 0))])
		check(a.spawns[0].size() == 4 and a.spawns[1].size() == 6, biome + " spawns")
		check(not a.find_path(a.spawns[0][0], a.spawns[1][0]).is_empty(), biome + " path")
	# --- 'Mechs against a combined-arms force
	var tanks := [vid("Manticore Heavy Tank"), vid("Scorpion Light Tank"), vid("Pegasus Scout Hover Tank"), vid("Warrior Attack Helicopter"), vid("Vedette Medium Tank"), vid("Demolisher Heavy Tank")]
	print("vehicles: ", tanks)
	for t in tanks:
		check(t != "", "vehicle in library")
	var stats := {"motive": 0, "vcrit": 0, "veh_destroyed": 0, "mech_destroyed": 0, "exit": 0, "rout": 0, "withdraw_order": 0}
	var wins := {0: 0, 1: 0, -1: 0}
	var total_ms := 0
	for seed in 8:
		var a := BattlefieldGenerator.generate(["bf_plains", "bf_hills", "bf_forest", "bf_urban"][seed % 4], 500 + seed, {"player_n": 4, "enemy_n": 6})
		var sides := [[entry("Marauder MAD-3R", "Lead", 0, "player"), entry("Wolverine WVR-6R", "Two", 0, "player"), entry("Hunchback HBK-4G", "Three", 0, "player"), entry("Jenner JR7-D", "Four", 0, "player")],
			[entry(tanks[0], "Tank 1", 1), entry(tanks[1], "Tank 2", 1), entry(tanks[2], "Hover 1", 1), entry(tanks[3], "Chopper", 1), entry(tanks[4], "Tank 3", 1), entry(tanks[5], "Tank 4", 1)]]
		var sim := CombatSim.create(a, sides, 900 + seed, {"merc": true, "time_limit": 900.0}, true)
		var t0 := Time.get_ticks_msec()
		var res := sim.run_to_end(1200.0)
		total_ms += Time.get_ticks_msec() - t0
		wins[int(res["winner"])] = int(wins.get(int(res["winner"]), 0)) + 1
		for e in sim.events:
			var k := str(e["k"])
			if stats.has(k):
				stats[k] = int(stats[k]) + 1
			if k == "destroyed":
				if sim.mechs[int(e["tg"])].is_vehicle:
					stats["veh_destroyed"] = int(stats["veh_destroyed"]) + 1
				else:
					stats["mech_destroyed"] = int(stats["mech_destroyed"]) + 1
		print("battle %d: %s after %.0f s (%s)" % [seed, ["draw", "player", "enemy"][int(res["winner"]) + 1], float(res["duration"]), res["how"]])
	print("combined arms: wins ", wins, " stats ", stats, " avg %d ms/battle" % (total_ms / 8))
	check(int(stats["motive"]) > 0, "motive system damage happens")
	check(int(stats["vcrit"]) > 0, "vehicle critical hits happen")
	check(int(stats["veh_destroyed"]) > 0, "vehicles get destroyed")
	# --- commands: move, attack, hold, withdraw and replay
	var a2 := BattlefieldGenerator.generate("bf_plains", 77, {"player_n": 2, "enemy_n": 2})
	var sides2 := [[entry("Wolverine WVR-6R", "Alpha", 0, "player"), entry("Griffin GRF-1N", "Bravo", 0, "player")],
		[entry(tanks[0], "Enemy 1", 1), entry("Commando COM-2D", "Enemy 2", 1, "ai", {"arrive": 20.0})]]
	var sim2 := CombatSim.create(a2, sides2, 4242, {"merc": true, "time_limit": 600.0}, true)
	var dest := a2.size_m() / 2.0
	while sim2.t < 2.0:
		sim2.step()
	check(sim2.issue_command([0, 1], "move", dest), "move order accepted")
	check(not sim2.issue_command([2], "move", dest), "can't order enemy units")
	check(sim2.mechs[3].out and sim2.mechs[3].out_reason == "reserve", "reinforcement waits off-map")
	while sim2.t < 30.0 and not sim2.finished:
		sim2.step()
	var near: float = (sim2.mechs[0] as CombatMech).pos.distance_to(dest)
	print("after move order: Alpha %.0f m from the point" % near)
	check(near < 220.0, "move order moves the unit")
	check(not sim2.mechs[3].out or sim2.mechs[3].destroyed, "reinforcement arrived")
	check(sim2.issue_command([1], "attack", 2), "attack order")
	check(sim2.issue_command([0], "withdraw"), "withdraw order")
	while not sim2.finished and sim2.t < 600.0:
		sim2.step()
	print("command battle: ", sim2.result["how"], " Alpha exited=", sim2.result["mechs"][0]["exited"], " inputs ", sim2.inputs.size())
	check(str(sim2.result["mechs"][0]["exited"]) == "W" or sim2.result["mechs"][0]["destroyed"], "withdrawn unit leaves by its edge")
	var a3 := BattlefieldGenerator.generate("bf_plains", 77, {"player_n": 2, "enemy_n": 2})
	var sides3 := [[entry("Wolverine WVR-6R", "Alpha", 0, "player"), entry("Griffin GRF-1N", "Bravo", 0, "player")],
		[entry(tanks[0], "Enemy 1", 1), entry("Commando COM-2D", "Enemy 2", 1, "ai", {"arrive": 20.0})]]
	var sim3 := CombatSim.create(a3, sides3, 4242, {"merc": true, "time_limit": 600.0}, false, sim2.inputs)
	sim3.run_to_end(700.0)
	var same := str(sim3.result["mechs"]) == str(sim2.result["mechs"]) and float(sim3.result["duration"]) == float(sim2.result["duration"])
	print("replay identical: ", same)
	check(same, "replay with recorded commands is identical")
	# --- objectives: destroying the target compound ends the battle
	var a4 := BattlefieldGenerator.generate("bf_urban", 99, {"player_n": 1, "enemy_n": 1, "scenario": "base_attack"})
	var sim4 := CombatSim.create(a4, [[entry("Atlas AS7-D", "Wrecker", 0, "player")], [entry(tanks[1], "Guard", 1)]], 5, {"merc": true}, false)
	for ci in a4.objectives["attack_cells"]:
		sim4.damage_building(int(ci), 9999, sim4.mechs[0])
	sim4.step()
	check(sim4.finished and int(sim4.result["winner"]) == 0, "base attack: destroying the compound wins")
	print("FAILURES: ", fails)
	quit()
