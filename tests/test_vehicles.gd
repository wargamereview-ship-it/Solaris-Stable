extends SceneTree
## godot --headless --path . -s tests/test_vehicles.gd
## Rebuilds every imported stock vehicle under the vehicle construction rules.

func _init() -> void:
	var db := GameData.db()
	var exact := 0
	var under := 0
	var over := 0
	var invalid := 0
	var diffs := {}
	var samples: Array = []
	for v in db.vehicles:
		var vd := VehicleDesign.vfrom_dict(v)
		var r := VehicleConstruction.analyze(vd)
		var d := float(r["tons_used"]) - vd.tons
		if not r["valid"] and d <= 0.001:
			invalid += 1
			if samples.size() < 8:
				samples.append("%s: %s" % [vd.id, r["errors"]])
		if absf(d) < 0.01:
			exact += 1
		elif d < 0:
			under += 1
			var k := "%s/%s" % [vd.motion, vd.engine_type]
			diffs[k] = int(diffs.get(k, 0)) + 1
		else:
			over += 1
			if samples.size() < 16:
				samples.append("OVER %s %.2f: %s" % [vd.id, d, r["breakdown"]])
	print("vehicles %d: exact %d, under %d, over %d, invalid %d" % [db.vehicles.size(), exact, under, over, invalid])
	print("under by motion/engine: ", diffs)
	for s in samples:
		print("  ", s)
	var lib := db.get_vehicle_library()
	var y3025 := 0
	for e in lib:
		if int(e["year"]) <= 3025:
			y3025 += 1
	print("library %d (available by 3025: %d)" % [lib.size(), y3025])
	for id in ["Manticore Heavy Tank", "Scorpion Light Tank", "Pegasus Scout Hover Tank", "Warrior Attack Helicopter H-7", "Demolisher Heavy Tank", "Vedette Medium Tank", "Savannah Master Hovercraft", "J. Edgar Light Hover Tank"]:
		for v in db.vehicles:
			if str(v["id"]).begins_with(id):
				var vd2 := VehicleDesign.vfrom_dict(v)
				var r2 := VehicleConstruction.analyze(vd2)
				print("%s  %d t %s cruise %d  used %.1f  cost %d  bv %d  %s" % [vd2.id, vd2.tons, vd2.motion, vd2.walk, r2["tons_used"], r2["cost"], r2["bv"], r2["errors"]])
				break
	quit()
