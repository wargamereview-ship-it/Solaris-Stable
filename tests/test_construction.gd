extends SceneTree
## godot --headless --path . -s tests/test_construction.gd
## Rebuilds every stock design with the construction rules and checks the weight, crits and armor.

func _init() -> void:
	var t0 := Time.get_ticks_msec()
	var db := GameData.db()
	print("loaded %d items, %d designs in %d ms" % [db.items.size(), db.designs.size(), Time.get_ticks_msec() - t0])
	var exact := 0
	var bad := 0
	var reasons := {}
	var examples := {}
	var under := 0
	for raw in db.designs:
		var d := MechDesign.from_dict(raw)
		var r := Construction.analyze(d)
		if not r.get("valid", false):
			bad += 1
			var key: String = str(r["errors"][0]).left(60)
			reasons[key] = int(reasons.get(key, 0)) + 1
			if not examples.has(key):
				examples[key] = d.id
			continue
		var used: float = r["tons_used"]
		if absf(used - d.tons) < 0.001:
			exact += 1
		else:
			under += 1
			var key2 := "underweight %.1f" % (d.tons - used)
			reasons[key2] = int(reasons.get(key2, 0)) + 1
			if not examples.has(key2):
				examples[key2] = d.id
	print("exact %d, under %d, invalid %d of %d" % [exact, under, bad, db.designs.size()])
	var keys := reasons.keys()
	keys.sort_custom(func(a, b): return reasons[a] > reasons[b])
	for k in keys.slice(0, 25):
		print("  %5d  %s   e.g. %s" % [reasons[k], k, examples[k]])
	# spot checks
	for id in ["Locust LCT-1V", "Atlas AS7-D", "Wolverine WVR-6R", "Marauder MAD-3R", "Hunchback HBK-4G"]:
		var d2 := MechDesign.from_stock(id)
		if d2 == null:
			print("missing ", id)
			continue
		var r2 := Construction.analyze(d2, 3015)
		print("%-20s %5.1f/%d t  bv %d (MUL %d)  cost %d  heat %d/%d  valid=%s %s" % [id, r2["tons_used"], d2.tons, r2["bv"], d2.bv_ref, r2["cost"], r2["heat"]["alpha"], r2["heat"]["dissipation"], r2["valid"], r2["errors"] + r2["warnings"]])
	quit()
