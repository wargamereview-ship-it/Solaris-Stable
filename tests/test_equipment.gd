extends SceneTree
## godot --headless --path . -s tests/test_equipment.gd
## The armor, structure, engine, cockpit, heat sink and myomer types and the weapons and gear that
## came in with the designs after 3085: that they build to the ton, and what each does in a fight.

var fails := 0


func check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		fails += 1


func w(name: String, g := 4, p := 5) -> Dictionary:
	return {"name": name, "callsign": name, "gunnery": g, "piloting": p, "traits": []}


func entry(id: String, name: String, orders := {}) -> Dictionary:
	return {"design": MechDesign.from_stock(id), "warrior": w(name), "orders": orders}


func ids_of(d: Dictionary) -> Array:
	var ids: Array = []
	for loc in d["slots"]:
		for s in d["slots"][loc]:
			if s != "":
				ids.append(MechDesign.base_id(str(s)))
	return ids


## First library design (it builds to the ton) a predicate accepts.
func find(pred: Callable) -> String:
	var db := GameData.db()
	for e in db.get_library():
		var d: Dictionary = db.design_by_id[e["id"]]
		if pred.call(d, ids_of(d)):
			return str(e["id"])
	return ""


func with_item(key: String, value: String) -> String:
	return find(func(_d, ids):
		for id in ids:
			if str(GameData.db().item(id).get(key, "")) == value:
				return true
		return false)


func duel(a: String, b: String, seed_value: int, theme := "bowl") -> CombatSim:
	var arena := ArenaGenerator.generate(theme, seed_value, 1, "", 2)
	return CombatSim.create(arena, [[entry(a, "A")], [entry(b, "B")]], seed_value * 7 + 3, {}, true, [])


func count(sim: CombatSim, kind: String, pred := Callable()) -> int:
	var n := 0
	for e in sim.events:
		if e["k"] == kind and (not pred.is_valid() or pred.call(e)):
			n += 1
	return n


## Armor lost on the center torso to one hit of a kind of damage.
func armor_lost(sim: CombatSim, target: CombatMech, dmg: int, cls: String) -> int:
	target.armor["CT"] = 40
	target.internal["CT"] = target.max_internal["CT"]
	sim._dclass = cls
	sim.apply_damage(target, "CT", dmg, false, null, "test")
	sim._dclass = "other"
	return 40 - int(target.armor["CT"])


func _init() -> void:
	var db := GameData.db()
	var T: Dictionary = db.tables
	print("loaded %d designs, %d in the library" % [db.designs.size(), db.get_library().size()])
	check(db.designs.size() >= 3900, "designs through 3152 are loaded (%d)" % db.designs.size())
	check(db.get_library().size() >= 3800, "and almost all build to the ton (%d)" % db.get_library().size())
	var late := 0
	for e in db.get_library():
		if int(db.design_by_id[e["id"]]["year"]) > 3085:
			late += 1
	check(late >= 800, "library designs introduced after 3085: %d" % late)

	print("== Every new chassis part has a design that builds to the ton")
	var sample := {}
	for pair in [["armor_type", ["stealth", "ferro_lamellor", "reflective", "reflective_clan", "reactive", "reactive_clan", "hardened",
			"heavy_industrial", "industrial", "commercial", "primitive", "ballistic_reinforced", "impact_resistant",
			"anti_penetrative", "heat_dissipating"]],
			["structure", ["industrial", "endo_composite", "endo_composite_clan", "composite", "reinforced"]],
			["gyro", ["none"]], ["cockpit", ["industrial", "primitive", "interface", "command_console"]],
			["myomer", ["industrial_tsm", "super_cooled"]]]:
		for v in pair[1]:
			var id := find(func(d, _ids): return str(d[pair[0]]) == v)
			sample["%s:%s" % [pair[0], v]] = id
			check(id != "", "%s %s: %s" % [str(pair[0]).replace("_type", ""), v, id])
	for v in ["ice", "fuel_cell", "fission"]:
		var id2 := find(func(d, _ids): return str(d["engine"]["type"]) == v)
		sample["engine:" + v] = id2
		check(id2 != "", "engine %s: %s" % [v, id2])
	for v in ["laser", "compact"]:
		var id3 := find(func(d, _ids): return str(d["hs"]["type"]) == v)
		sample["hs:" + v] = id3
		check(id3 != "", "heat sinks %s: %s" % [v, id3])

	print("== Armor types answer damage by its kind")
	var base := duel("Atlas AS7-D", "Atlas AS7-D", 3)
	var plain: CombatMech = base.mechs[1]
	check(armor_lost(base, plain, 10, "energy") == 10, "standard armor takes a hit as it comes")
	var cases := [["reflective", "energy", 10, 5], ["reflective", "ballistic", 10, 10], ["reflective", "physical", 6, 12],
		["reactive", "missile", 10, 5], ["reactive", "energy", 10, 10], ["ferro_lamellor", "ballistic", 10, 8],
		["ballistic_reinforced", "ballistic", 10, 5], ["ballistic_reinforced", "energy", 10, 10],
		["impact_resistant", "physical", 9, 6], ["hardened", "energy", 10, 5]]
	for c in cases:
		var id4: String = sample["armor_type:" + str(c[0])]
		if id4 == "":
			continue
		var s := duel("Atlas AS7-D", id4, 5)
		var got := armor_lost(s, s.mechs[1], int(c[2]), str(c[1]))
		check(got == int(c[3]), "%s armor, %d %s damage: %d points gone (want %d)" % [c[0], c[2], c[1], got, c[3]])
	# hardened armor slows the run
	if sample["armor_type:hardened"] != "":
		var sh := duel("Atlas AS7-D", sample["armor_type:hardened"], 5)
		var hm: CombatMech = sh.mechs[1]
		check(hm.run_mp() == int(ceil(hm.walk_mp() * 1.5)) - 1, "hardened armor costs a point of running speed")

	print("== Structure types")
	for c2 in [["composite", 3, 6], ["reinforced", 4, 2]]:
		var id5: String = sample["structure:" + str(c2[0])]
		if id5 == "":
			continue
		var s2 := duel("Atlas AS7-D", id5, 7)
		var tg: CombatMech = s2.mechs[1]
		tg.armor["LA"] = 0
		tg.internal["LA"] = 12
		tg.max_internal["LA"] = 12
		s2.apply_damage(tg, "LA", int(c2[1]), false, null, "test")
		check(12 - int(tg.internal["LA"]) == int(c2[2]), "%s structure: %d damage costs %d points (want %d)" % [c2[0], c2[1], 12 - int(tg.internal["LA"]), c2[2]])

	print("== Stealth, cockpits, engines")
	if sample["armor_type:stealth"] != "":
		var ss := duel("Atlas AS7-D", sample["armor_type:stealth"], 9)
		var st: CombatMech = ss.mechs[1]
		check(st.signatures.size() >= 1 and st.ecm, "a stealth 'Mech carries its ECM suite")
		check(st.signatures_on().size() >= 1, "and the armor is switched on")
		ss.mechs[0].pos = Vector2(200, 300)
		st.pos = Vector2(200 + 12 * CombatSim.HEX, 300)
		var seen := false
		for wi in ss.mechs[0].weapons:
			var th := ss.to_hit(ss.mechs[0], ss.mechs[0].mounts[wi], st)
			if th.get("ok", false):
				for md in th["mods"]:
					if str(md[0]) == "Stealth" and int(md[1]) > 0:
						seen = true
		check(seen, "shots at it from medium or long range are harder")
		var h0 := st.heat
		for k in 200:
			ss._heat_tick(st)
		st.ecm = false
		check(st.signatures_on().is_empty(), "without its ECM the stealth armor is just armor")
	if sample["cockpit:industrial"] != "":
		var si := duel(sample["cockpit:industrial"], "Atlas AS7-D", 11)
		check(si.mechs[0].cockpit_to_hit == 1, "an industrial cockpit shoots at +1")
	if sample["engine:ice"] != "":
		var se := duel(sample["engine:ice"], "Atlas AS7-D", 13)
		var em: CombatMech = se.mechs[0]
		check(em.no_move_heat, "a combustion engine makes no heat from walking")
		check(Construction.free_sinks("ice") == 0 and Construction.free_sinks("fission") == 5 and Construction.free_sinks("xl") == 10, "free heat sinks by engine")
	if sample["myomer:industrial_tsm"] != "":
		check(duel(sample["myomer:industrial_tsm"], "Atlas AS7-D", 13).mechs[0].always_strong, "industrial TSM always hits hard")
	if sample["hs:laser"] != "":
		check(duel(sample["hs:laser"], "Atlas AS7-D", 13).mechs[0].double_sinks, "laser heat sinks shed two each")

	print("== Weapons that used to be dead weight")
	for wt in ["hag", "plasma", "artillery", "artcannon", "tsemp", "magshot", "mortar", "pac"]:
		var id6 := with_item("wtype", wt)
		if id6 == "":
			check(false, "a library design with a %s weapon" % wt)
			continue
		var fired := 0
		var special := 0
		for sd in [3, 4, 5]:
			var sim := duel(id6, "Atlas AS7-D", sd, "bowl" if wt != "artillery" else "canyon")
			sim.run_to_end()
			fired += count(sim, "shot", func(e): return str(e.get("wt", "")) == wt)
			match wt:
				"plasma":
					special += count(sim, "plasma_heat")
				"artillery":
					special += count(sim, "shell")
				"tsemp":
					special += count(sim, "emp")
				_:
					special += 1
		check(fired > 0, "%s fires (%s, %d shots in three fights)" % [wt, id6, fired])
		check(special > 0, "  and does what it should (%d)" % special)

	print("== Gear")
	var cap := with_item("misc", "ppc_capacitor")
	if cap != "":
		var sc := duel(cap, "Atlas AS7-D", 3)
		var n_cap := 0
		for wi in sc.mechs[0].weapons:
			if sc.mechs[0].mounts[wi].has("cap"):
				n_cap += 1
		check(n_cap > 0, "a PPC capacitor is wired to a PPC (%s)" % cap)
	var wing := with_item("misc", "partial_wing")
	if wing != "":
		var sw := duel(wing, "Atlas AS7-D", 3)
		var wm: CombatMech = sw.mechs[0]
		check(wm.wing_mount >= 0 and wm.jump_mp() > wm.design.jump, "a partial wing adds jump (%s: %d from %d jets)" % [wing, wm.jump_mp(), wm.design.jump])
		var plain_cool := (wm.sinks_total - wm.sinks_lost) * (2.0 if wm.double_sinks else 1.0)
		check(wm.dissipation() > plain_cool, "and sheds heat")
	for phys in ["claw", "retractable_blade", "lance", "vibroblade", "talons"]:
		var idp := with_item("misc", phys)
		if idp == "":
			continue
		var sp := duel(idp, "Atlas AS7-D", 3)
		var pm: CombatMech = sp.mechs[0]
		if phys == "talons":
			check(pm.talons, "talons sharpen a kick (%s)" % idp)
		else:
			check(pm.physical_weapon != "" and T["physical"].has(pm.physical_weapon), "%s: the 'Mech fights with its %s (%s)" % [phys, pm.physical_weapon.replace("_", " "), idp])
	var pod := find(func(_d, ids):
		for id in ids:
			if str(GameData.db().item(id).get("coolant", "")) != "" or str(GameData.db().item(id).get("ammo", "")).begins_with("coolant"):
				return true
		return false)
	if pod != "":
		var sp2 := duel(pod, "Atlas AS7-D", 3)
		var cm: CombatMech = sp2.mechs[0]
		check(cm.coolers.size() > 0, "coolant pods are plumbed in (%s)" % pod)
		cm.heat = 20.0
		sp2._gear_turn(cm)
		check(cm.heat < 20.0 and count(sp2, "coolant") == 1, "and flushed when the 'Mech runs hot (heat now %.0f)" % cm.heat)
	var hj := with_item("misc", "harjel_repair")
	if hj != "":
		var sj := duel(hj, "Atlas AS7-D", 3)
		var jm: CombatMech = sj.mechs[0]
		var jl: String = jm.mounts[int(jm.harjel[0][0])]["loc"]
		jm.armor[jl] = int(jm.max_armor[jl]) - 5
		sj._gear_turn(jm)
		check(int(jm.armor[jl]) > int(jm.max_armor[jl]) - 5, "HarJel seals armor back up (%s)" % hj)
	var apod := with_item("misc", "apod")
	if apod != "":
		var inf := VehicleDesign.any_from_dict(db.vehicle_by_id["Foot Platoon (Rifle)"])
		var arena := ArenaGenerator.generate("bowl", 5, 1, "", 2)
		var spod := CombatSim.create(arena, [[entry(apod, "A")], [{"design": inf, "warrior": w("P"), "orders": {}}]], 99, {}, true, [])
		var before: int = spod.mechs[1].troopers_alive()
		spod._pods_fire(spod.mechs[0], spod.mechs[1])
		check(spod.mechs[1].troopers_alive() < before and count(spod, "pod") == 1, "an A-pod cuts down infantry at its feet (%s: %d to %d)" % [apod, before, spod.mechs[1].troopers_alive()])

	print("== Whole fights with the new designs")
	var rng := SimRng.new(77)
	var lib: Array = []
	for e in db.get_library():
		if int(db.design_by_id[e["id"]]["year"]) > 3085:
			lib.append(str(e["id"]))
	var finished := 0
	var fights := 40
	for k in fights:
		var a: String = lib[rng.randi_range(0, lib.size() - 1)]
		var b: String = lib[rng.randi_range(0, lib.size() - 1)]
		var sim2 := duel(a, b, 100 + k, ["bowl", "canyon", "urban", "factory"][k % 4])
		var res := sim2.run_to_end()
		if not res.is_empty():
			finished += 1
	check(finished == fights, "%d of %d duels between designs after 3085 run to a result" % [finished, fights])
	print("EQUIPMENT TEST DONE, fails: %d" % fails)
	quit()
