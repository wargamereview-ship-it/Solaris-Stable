extends SceneTree
## godot --headless --path . -s tests/test_support.gd
## Off-board support: artillery fire missions and air strikes, who gets them, what they hit,
## the enemy's own fire control, and exact replays.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func entry(id: String, name: String, controller := "ai") -> Dictionary:
	var d := GameData.db().stock_design(id)
	assert(d != null, id)
	return {"design": d, "warrior": {"callsign": name, "gunnery": 4, "piloting": 5, "traits": []}, "orders": {}, "controller": controller}


func field(seed: int, support: Array, inputs := [], theme := "bf_plains") -> CombatSim:
	var a := BattlefieldGenerator.generate(theme, 500 + seed, {"player_n": 3, "enemy_n": 5})
	var s := [[entry("Hunchback HBK-4G", "Hunch", "player"), entry("Wolverine WVR-6R", "Wolv", "player"), entry("Locust LCT-1V", "Bug", "player")],
		[entry("Griffin GRF-1N", "Griff"), entry("Shadow Hawk SHD-2H", "Hawk"), entry("Foot Platoon (Rifle)", "Rifles"),
		entry("IS Standard Battle Armor (Small Laser)", "Suits"), entry("Vedette Medium Tank", "Tank")]]
	return CombatSim.create(a, s, 90 + seed, {"merc": true, "time_limit": 900.0, "support": support}, true, inputs)


func count(sim: CombatSim, kind: String, team := -1) -> int:
	var n := 0
	for e in sim.events:
		if str(e["k"]) == kind and (team < 0 or int(e.get("team", -1)) == team):
			n += 1
	return n


func armor_left(m: CombatMech) -> int:
	var n := 0
	for loc in m.armor:
		n += int(m.armor[loc])
	for loc in m.internal:
		n += int(m.internal[loc])
	return n


func _init() -> void:
	var T: Dictionary = GameData.db().tables["support"]
	check(T.has("artillery") and T.has("air_strike"), "support tables")
	# --- blast damage on each kind of unit
	var sim := field(1, [{"artillery": 2, "air_strike": 1}, {}])
	var hb: CombatMech = sim.mechs[0]
	var pl: CombatMech = sim.mechs[5]
	var ba: CombatMech = sim.mechs[6]
	var tk: CombatMech = sim.mechs[7]
	check(sim.support_left(0, "artillery") == 2 and sim.support_left(0, "air_strike") == 1, "missions on hand")
	check(sim.support_left(1, "artillery") == 0 and not sim.issue_support(1, "artillery", Vector2(100, 100)), "a side without support can call none")
	var before := armor_left(hb)
	sim._area_damage(hb, 20, hb.pos + Vector2(50, 0), "artillery")
	check(before - armor_left(hb) == 20, "20 points on a 'Mech (took %d)" % (before - armor_left(hb)))
	before = armor_left(tk)
	sim._area_damage(tk, 20, tk.pos + Vector2(0, 50), "artillery")
	check(before - armor_left(tk) >= 10, "a tank takes the blast (took %d)" % (before - armor_left(tk)))
	var men := pl.troopers_alive()
	sim._area_damage(pl, 20, pl.pos, "artillery")
	check(men - pl.troopers_alive() >= 4, "a shell cuts down a platoon (%d fell)" % (men - pl.troopers_alive()))
	var suits := armor_left(ba)
	sim._area_damage(ba, 10, ba.pos, "artillery")
	check(suits - armor_left(ba) >= 10 * ba.troopers_alive(), "every suit in the blast is hit (%d)" % (suits - armor_left(ba)))

	# --- a fire mission: called, delayed, lands as three shells, hits whoever is there (your own too)
	sim = field(2, [{"artillery": 1, "air_strike": 1}, {}])
	hb = sim.mechs[0]
	sim.issue_command([0, 1, 2], "hold", null)
	before = armor_left(hb)
	check(sim.issue_support(0, "artillery", hb.pos), "fire mission called")
	check(sim.support_left(0, "artillery") == 0 and not sim.issue_support(0, "artillery", hb.pos), "one mission, one call")
	check(sim.strikes.size() == int(T["artillery"]["shells"]) and count(sim, "support_call", 0) == 1, "shells on the way")
	var t_call := sim.t
	while not sim.finished and sim.t < t_call + float(T["artillery"]["delay_s"]) - 0.5:
		sim.step()
	check(count(sim, "shell") == 0, "nothing lands before the delay")
	while not sim.finished and sim.t < t_call + 30.0:
		sim.step()
	check(count(sim, "shell") == int(T["artillery"]["shells"]) and sim.strikes.is_empty(), "three shells land")
	check(before - armor_left(hb) >= int(T["artillery"]["splash"]) * int(T["artillery"]["shells"]), "your own 'Mech under your own shells is hit (took %d)" % (before - armor_left(hb)))
	for e in sim.events:
		if str(e["k"]) in ["support_call", "shell", "strafe", "strafe_hit"]:
			check(sim.describe(e) != "", "event text for " + str(e["k"]))
	# --- an air strike along a strip
	var wv: CombatMech = sim.mechs[1]
	before = armor_left(wv)
	check(sim.issue_support(0, "air_strike", wv.pos, 0.6), "air strike called")
	t_call = sim.t
	while not sim.finished and sim.t < t_call + float(T["air_strike"]["delay_s"]) + 1.0:
		sim.step()
	check(count(sim, "strafe", 0) == 1, "the fighter makes its run")
	var rolled := false
	for e in sim.events:
		if str(e["k"]) == "strafe_hit" and int(e["tg"]) == 1:
			rolled = true
			check(bool(e["hit"]) == (before - armor_left(wv) >= int(T["air_strike"]["damage"])), "a strafing hit does its damage (took %d)" % (before - armor_left(wv)))
			check(sim.describe(e) != "", "strafe text")
	check(rolled, "the unit under the strip is attacked")

	# --- shells knock buildings down
	sim = field(3, [{"artillery": 2}, {}], [], "bf_urban")
	var A := sim.arena
	var bi := -1
	for i in A.terrain.size():
		if A.terrain[i] == Arena.T.BUILDING and int(A.bld_cf[i]) < 99999:
			bi = i
			break
	check(bi >= 0, "a town has buildings")
	if bi >= 0:
		var cf := int(A.bld_cf[bi])
		sim.issue_support(0, "artillery", A.center_of_index(bi))
		while not sim.finished and sim.strikes.size() > 0:
			sim.step()
		check(A.terrain[bi] != Arena.T.BUILDING or int(A.bld_cf[bi]) < cf, "the building is damaged (%d -> %d)" % [cf, int(A.bld_cf[bi])])

	# --- the enemy's fire control, and yours when the AI fights for you
	var enemy_calls := 0
	var own_calls := 0
	var own_hits := 0
	var sup_dmg := [0, 0]      # damage support did to each team's 'Mechs and vehicles
	for seed in 6:
		var s2 := field(10 + seed, [{"artillery": 2, "air_strike": 1, "auto": true, "first": 20.0, "gap": 30.0},
			{"artillery": 2, "air_strike": 1, "auto": true, "first": 20.0, "gap": 30.0}])
		for m: CombatMech in s2.mechs:
			m.controller = "ai"
		s2.run_to_end(1000.0)
		enemy_calls += count(s2, "support_call", 1)
		own_calls += count(s2, "support_call", 0)
		check(count(s2, "support_call", 1) <= 3 and count(s2, "support_call", 0) <= 3, "no more calls than missions")
		for e in s2.events:
			if str(e["k"]) == "strafe_hit" and bool(e["hit"]):
				own_hits += 1
			if str(e["k"]) == "dmg" and str(e.get("w", "")) in ["artillery", "air strike"] and int(e["tg"]) >= 0:
				var hit_team := (s2.mechs[int(e["tg"])] as CombatMech).team
				sup_dmg[hit_team] = int(sup_dmg[hit_team]) + int(e["dmg"])
	print("auto support over 6 battles: enemy called %d, player's AI called %d, strafing hits %d, damage to team 0 / team 1: %s" % [enemy_calls, own_calls, own_hits, sup_dmg])
	check(enemy_calls >= 3, "the enemy calls its support")
	check(own_calls >= 3, "your side's AI calls yours")
	check(int(sup_dmg[0]) + int(sup_dmg[1]) > 0, "called support does damage")

	# --- exact replay, calls included
	var live := field(20, [{"artillery": 2, "air_strike": 1}, {"artillery": 1, "air_strike": 1, "auto": true, "first": 15.0, "gap": 30.0}])
	while not live.finished and live.t < 12.0:
		live.step()
	live.issue_support(0, "artillery", (live.mechs[3] as CombatMech).pos)
	while not live.finished and live.t < 30.0:
		live.step()
	live.issue_support(0, "air_strike", (live.mechs[4] as CombatMech).pos, 1.1)
	live.issue_command([0, 1], "attack", 3)
	var r1 := live.run_to_end(1000.0)
	var saved: Array = JSON.parse_string(JSON.stringify(live.inputs))      # as a saved game would hold them
	var rp := field(20, [{"artillery": 2, "air_strike": 1}, {"artillery": 1, "air_strike": 1, "auto": true, "first": 15.0, "gap": 30.0}], saved)
	var r2 := rp.run_to_end(1000.0)
	check(str(r2["mechs"]) == str(r1["mechs"]) and float(r2["duration"]) == float(r1["duration"]), "replay matches")
	check(count(rp, "shell") == count(live, "shell") and count(rp, "strafe") == count(live, "strafe") and count(live, "shell") >= 3, "the same shells fall in the replay")
	merc_layer()
	print("SUPPORT TEST DONE, fails: %d" % fails)
	quit()


## Who gets support in a mercenary campaign, and that the battles carry it.
func merc_layer() -> void:
	var c := MercCampaign.new_game("Fire Co", Color(0.3, 0.5, 0.7), 3028, "Galatea", "lance", 41)
	check(c.accept_contract(int(c.contract_offers[0]["offer"])) == "", "contract accepted")
	var S: Dictionary = c.rules["operations"]["support"]
	var seen_enemy := 0
	var cmds: Array = S["player"].keys()
	for ci in cmds.size():
		c.contract["terms"]["command"] = cmds[ci]
		for type in ["standup", "base_attack", "major_battle", "recon", "chase"]:
			var sc := c._new_scenario(c.lances[0], "fight", type)
			var sup := c.battle_support(sc)
			var want: Dictionary = S["player"][cmds[ci]]
			var exp_art := 0
			if type in S["player_scenarios"]:
				exp_art = int(want["artillery"]) + (int(S["major_battle_bonus"]["artillery"]) if type == "major_battle" else 0)
			check(int(sup["player"]["artillery"]) == exp_art, "%s command, %s: %d fire missions (got %d)" % [cmds[ci], type, exp_art, int(sup["player"]["artillery"])])
			check(str(c.battle_support(sc)) == str(sup), "support is the same every time it is asked")
			if not (type in S["enemy_chance"]):
				check(int(sup["enemy"]["artillery"]) + int(sup["enemy"]["air_strike"]) == 0, "no enemy support in a " + type)
			seen_enemy += int(sup["enemy"]["artillery"]) + int(sup["enemy"]["air_strike"])
	c.contract["terms"]["command"] = "Integrated"
	var called := 0
	var carried := 0
	var dep: Array = []
	for k in 6:
		var sc2 := c._new_scenario(c.lances[0], "fight", ["base_attack", "major_battle", "standup"][k % 3])
		c.scenarios.append(sc2)
		if dep.is_empty():
			dep = c.default_deployment(sc2)
		if dep.is_empty():
			break
		var b := c.make_battle(int(sc2["id"]), dep, false)
		var sim: CombatSim = b["sim"]
		var meta: Dictionary = b["battle"]
		check(sim.support_left(0, "artillery") == int(meta["support"]["player"]["artillery"]) and sim.support_left(0, "artillery") >= 2, "the battle carries your fire missions")
		check(sim.support_left(1, "artillery") == int(meta["support"]["enemy"]["artillery"]), "and the enemy's")
		carried += sim.support_left(1, "artillery") + sim.support_left(1, "air_strike")
		if k == 5:
			var sum := c.auto_resolve(int(sc2["id"]), dep)
			check(not sum.is_empty(), "auto-resolved")
		called += 1
	print("merc battles: %d fought, enemy missions carried %d, enemy missions seen in the table %d" % [called, carried, seen_enemy])
	check(called >= 3, "battles fought")
	check(seen_enemy > 0, "the enemy sometimes has support")
	# pirates never have any
	c.contract["enemy"] = "PIR"
	for k in 20:
		var sc3 := c._new_scenario(c.lances[0], "fight", "major_battle")
		var s3: Dictionary = c.battle_support(sc3)["enemy"]
		check(int(s3["artillery"]) + int(s3["air_strike"]) == 0, "pirates have no artillery park")
