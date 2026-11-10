extends SceneTree
## godot --headless --path . -s tests/test_combat.gd
## Arena generation, determinism, a logged duel, and a balance batch.

func duel(a_id: String, b_id: String, seed_value: int, theme := "bowl", record := false, orders_a := {}, orders_b := {}) -> CombatSim:
	var arena := ArenaGenerator.generate(theme, seed_value)
	var wa := {"name": "Alpha", "callsign": a_id.split(" ")[0], "gunnery": 4, "piloting": 5, "traits": []}
	var wb := {"name": "Bravo", "callsign": b_id.split(" ")[0] + "*", "gunnery": 4, "piloting": 5, "traits": []}
	var sides := [[{"design": MechDesign.from_stock(a_id), "warrior": wa, "orders": orders_a}],
		[{"design": MechDesign.from_stock(b_id), "warrior": wb, "orders": orders_b}]]
	var sim := CombatSim.create(arena, sides, seed_value * 31 + 7, {}, record)
	sim.run_to_end()
	return sim


func _init() -> void:
	var fails := 0
	# --- arenas
	for theme in ["bowl", "factory", "jungle", "boreal", "urban", "canyon"]:
		var t0 := Time.get_ticks_usec()
		var a := ArenaGenerator.generate(theme, 1234)
		var counts := {}
		for i in a.w * a.h:
			counts[Arena.T_NAMES[a.terrain[i]]] = int(counts.get(Arena.T_NAMES[a.terrain[i]], 0)) + 1
		# mirror check
		var sym := true
		for i in a.w * a.h:
			if a.terrain[i] != a.terrain[a.w * a.h - 1 - i] or a.height[i] != a.height[a.w * a.h - 1 - i]:
				sym = false
		print("%-8s %dx%d cells  %.1f ms  symmetric=%s  %s" % [theme, a.w, a.h, (Time.get_ticks_usec() - t0) / 1000.0, sym, counts])
		if not sym:
			fails += 1
	# --- determinism
	var s1 := duel("Hunchback HBK-4G", "Wolverine WVR-6R", 99, "jungle", true)
	var s2 := duel("Hunchback HBK-4G", "Wolverine WVR-6R", 99, "jungle", true)
	var same: bool = s1.result["winner"] == s2.result["winner"] and s1.t == s2.t and s1.events.size() == s2.events.size() and s1.mechs[0].dmg_dealt == s2.mechs[0].dmg_dealt
	print("determinism: ", same, "  (", s1.events.size(), " events, ", s1.t, " s)")
	if not same:
		fails += 1
	# --- one logged fight
	var t0 := Time.get_ticks_msec()
	var sim := duel("Atlas AS7-D", "Marauder MAD-3R", 5, "boreal", true)
	print("Atlas vs Marauder: %s in %.1f s sim time, %d ms real, %d frames" % [sim.result["how"], sim.t, Time.get_ticks_msec() - t0, sim.frames.size()])
	var shown := 0
	for e in sim.events:
		var line := sim.describe(e)
		if line != "" and e["k"] != "dmg" and shown < 40:
			print("  %6.1f  %s" % [e["t"], line])
			shown += 1
	for m in sim.result["mechs"]:
		print("  %s: dealt %d, took %d, shots %d hits %d, %s" % [m["name"], m["dmg_dealt"], m["dmg_taken"], m["shots"], m["hits"], m["reason"]])
	# --- balance batch: heavy should usually beat a light
	var pairs := [["Marauder MAD-3R", "Locust LCT-1V"], ["Atlas AS7-D", "Commando COM-2D"], ["Hunchback HBK-4G", "Wolverine WVR-6R"], ["Warhammer WHM-6R", "Archer ARC-2R"], ["Jenner JR7-D", "Panther PNT-9R"]]
	for pr in pairs:
		var wins := [0, 0, 0]
		var hows := {}
		var t1 := Time.get_ticks_msec()
		var dur := 0.0
		var n := 30
		for k in n:
			var themes := ["bowl", "factory", "jungle", "boreal", "urban", "canyon"]
			var s := duel(pr[0], pr[1], 1000 + k, themes[k % themes.size()], false)
			var wnr: int = s.result["winner"]
			wins[wnr if wnr >= 0 else 2] += 1
			hows[s.result["how"]] = int(hows.get(s.result["how"], 0)) + 1
			dur += s.t
		print("%-18s vs %-18s  %2d-%2d (draws %d)  avg %.0f s  %d ms/fight  %s" % [pr[0], pr[1], wins[0], wins[1], wins[2], dur / n, (Time.get_ticks_msec() - t1) / n, hows])
	print("FAILURES: ", fails)
	quit(fails)
