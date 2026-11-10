class_name MercRepair
extends RefCounted
## MekHQ-style repairs. A unit's damage becomes a list of tasks, each with a time in minutes, a
## target number modifier and the spare part it uses (from the warehouse). Applying a task heals
## that piece of the unit's condition. Parts are keyed strings:
##   armor:<type> (tons)   ammo:<item id> (tons)   item:<item id>   loc:<head|limb|torso>:<tons>
##   act:<actuator>:<tons>   engine:<type>:<rating>:<tons>   gyro:<type>:<size>   cockpit   life_support
##   sensors:<tons>   vsensors:<tons>

const ACTUATORS := ["shoulder", "upper_arm", "lower_arm", "hand", "hip", "upper_leg", "lower_leg", "foot"]


static func rules() -> Dictionary:
	return GameData.db().merc()["rules"]


static func loc_kind(loc: String) -> String:
	if loc == "HD":
		return "head"
	if loc in ["LA", "RA", "LL", "RL"]:
		return "limb"
	return "torso"


## Every repair the unit needs right now. Each task: {key, label, kind, minutes, tn, part, qty, requires}.
static func tasks(u: MercUnit) -> Array:
	if u.condition.is_empty() or u.wreck():
		return []
	if u.design.is_infantry():
		return _infantry_tasks(u)
	if u.is_vehicle():
		return _vehicle_tasks(u)
	var R: Dictionary = rules()["repair"]
	var d := u.design
	var c := u.condition
	var out: Array = []
	var ipts := Construction.internal_points(d.tons)
	var inner: Dictionary = c.get("internal", {})
	var dead := {}
	for loc in MechDesign.LOCS:
		var mx := int(ipts.get(loc, 0))
		var cur := int(inner.get(loc, mx))
		if cur <= 0:
			dead[loc] = true
			out.append({"key": "loc:" + loc, "label": "Replace %s" % MechDesign.LOC_NAMES[loc].to_lower(), "kind": "location",
				"minutes": int(R["location_replace_min"]), "tn": int(R["location_tn"]),
				"part": "loc:%s:%d" % [loc_kind(loc), d.tons], "qty": 1.0, "loc": loc, "requires": ""})
		elif cur < mx:
			out.append({"key": "is:" + loc, "label": "Repair %s structure (%d)" % [MechDesign.LOC_NAMES[loc].to_lower(), mx - cur],
				"kind": "structure", "minutes": maxi(int(R["structure_min_min"]), (mx - cur) * int(R["structure_min_per_point"])),
				"tn": 1, "part": "", "qty": 0.0, "loc": loc, "requires": ""})
	var armor: Dictionary = c.get("armor", {})
	for k in d.armor:
		var mx2 := int(d.armor[k])
		var cur2 := int(armor.get(k, mx2))
		if cur2 < mx2:
			var base_loc: String = k.substr(0, 2) if k.length() == 3 else k
			var pts := mx2 - cur2
			out.append({"key": "armor:" + k, "label": "Armor: %s (%d pts)" % [MechDesign.LOC_NAMES.get(k, k), pts], "kind": "armor",
				"minutes": pts * int(R["armor_min_per_point"]), "tn": -1, "part": "armor:" + d.armor_type,
				"qty": snappedf(pts / Construction.armor_ppt(d.armor_type), 0.01), "loc": base_loc,
				"requires": ("loc:" + base_loc) if dead.has(base_loc) else ""})
	# destroyed components
	var mounts := Construction.mounts_of(d)
	var slot_mount := {}
	for mi in mounts.size():
		for sl in mounts[mi]["slots"]:
			slot_mount["%s:%d" % [sl[0], sl[1]]] = mi
	var hit_mounts := {}
	var fixed_hits := {}
	for hs in c.get("hit_slots", []):
		var loc: String = hs[0]
		var i := int(hs[1])
		var key := "%s:%d" % [loc, i]
		if slot_mount.has(key):
			hit_mounts[int(slot_mount[key])] = loc
			continue
		var tag: String = d.slots[loc][i] if i < (d.slots[loc] as Array).size() else ""
		if tag in ACTUATORS:
			if dead.has(loc):
				continue
			out.append({"key": "act:%s:%d" % [loc, i], "label": "Replace %s %s" % [MechDesign.LOC_NAMES[loc].to_lower(), tag.replace("_", " ")],
				"kind": "actuator", "minutes": int(R["fixed_min"].get(tag, 90)), "tn": int(R["fixed_tn"].get(tag, 0)),
				"part": "act:%s:%d" % [tag, d.tons], "qty": 1.0, "loc": loc, "requires": ""})
		elif tag in ["engine", "gyro", "cockpit", "sensors", "life_support"]:
			fixed_hits[tag] = true
	for tag in fixed_hits:
		var part := ""
		match tag:
			"engine":
				part = "engine:%s:%d:%d" % [d.engine_type, d.engine_rating, d.tons]
			"gyro":
				part = "gyro:%s:%d" % [d.gyro, int(ceil(d.engine_rating / 100.0))]
			"cockpit":
				part = "cockpit"
			"sensors":
				part = "sensors:%d" % d.tons
			"life_support":
				part = "life_support"
		var req := ""
		if tag in ["cockpit", "sensors", "life_support"] and dead.has("HD"):
			req = "loc:HD"
		if tag == "engine" and dead.has("CT"):
			req = "loc:CT"
		out.append({"key": "fix:" + tag, "label": "Replace %s" % tag.replace("_", " "), "kind": tag,
			"minutes": int(R["fixed_min"].get(tag, 180)), "tn": int(R["fixed_tn"].get(tag, 0)), "part": part, "qty": 1.0,
			"loc": "", "requires": req})
	var db := GameData.db()
	for mi in hit_mounts:
		var mt: Dictionary = mounts[mi]
		var it := db.item(mt["id"])
		var kind := _item_kind(it)
		var loc3: String = mt["loc"]
		var part2 := "item:" + str(mt["id"])
		var qty := 1.0
		if it.get("kind", "") == "ammo":
			part2 = "ammo:" + str(mt["id"])
			qty = float(it.get("tons", 1.0))
		out.append({"key": "mount:%d" % mi, "label": "Replace %s (%s)" % [it.get("name", mt["id"]), loc3], "kind": kind,
			"minutes": int(R["item_min"].get(kind, 90)), "tn": int(R["item_tn"].get(kind, 0)), "part": part2, "qty": qty,
			"loc": loc3, "requires": ("loc:" + loc3) if dead.has(loc3) else ""})
	# ammo reloads
	var ammo: Dictionary = c.get("ammo", {})
	for k in ammo:
		var mi2 := int(k)
		if hit_mounts.has(mi2) or mi2 >= mounts.size():
			continue
		var it2 := db.item(mounts[mi2]["id"])
		var full := int(it2.get("shots", 0))
		var have := int(ammo[k])
		if have < full and full > 0:
			out.append({"key": "reload:%d" % mi2, "label": "Reload %s (%d shots)" % [it2.get("name", ""), full - have], "kind": "reload",
				"minutes": int(R["reload_min"]), "tn": -99, "part": "ammo:" + str(mounts[mi2]["id"]),
				"qty": snappedf(float(it2.get("tons", 1.0)) * (full - have) / float(full), 0.01), "loc": mounts[mi2]["loc"], "requires": ""})
	return out


static func _item_kind(it: Dictionary) -> String:
	match it.get("kind", ""):
		"weapon":
			return "weapon"
		"ammo":
			return "ammo"
	match it.get("misc", ""):
		"heat_sink", "double_heat_sink":
			return "heat_sink"
		"jump_jet":
			return "jump_jet"
	return "misc"


## Infantry are brought back to strength with replacements: troopers for a platoon, a suit and the
## soldier in it for battle armour ("troops:<unit id>" parts, found like any other part), and suit
## armour patched by the techs.
static func _infantry_tasks(u: MercUnit) -> Array:
	var R: Dictionary = rules()["repair"]["infantry"]
	var d := u.design as VehicleDesign
	var c := u.condition
	var out: Array = []
	var inner: Dictionary = c.get("internal", {})
	var armor: Dictionary = c.get("armor", {})
	var part := "troops:" + d.id
	if not d.is_battle_armor():
		var lost := d.troopers - int(inner.get("PL", d.troopers))
		if lost > 0:
			out.append({"key": "is:PL", "label": "Replacements: %d trooper%s" % [lost, "" if lost == 1 else "s"], "kind": "replacements",
				"minutes": lost * int(R["trooper_min"]), "tn": -99, "part": part, "qty": float(lost), "loc": "PL", "requires": ""})
		return out
	var n := 0
	for loc in d.locs():
		n += 1
		if int(inner.get(loc, 1)) <= 0:
			out.append({"key": "is:" + loc, "label": "Replace suit %d and its trooper" % n, "kind": "replacements",
				"minutes": int(R["suit_min"]), "tn": -99, "part": part, "qty": 1.0, "loc": loc, "requires": ""})
			continue
		var mx := int(d.armor.get(loc, 0))
		var cur := int(armor.get(loc, mx))
		if cur < mx:
			out.append({"key": "armor:" + loc, "label": "Repair suit %d armor (%d pts)" % [n, mx - cur], "kind": "armor",
				"minutes": (mx - cur) * int(R["suit_armor_min"]), "tn": -1, "part": "", "qty": 0.0, "loc": loc, "requires": ""})
	return out


static func _vehicle_tasks(u: MercUnit) -> Array:
	var R: Dictionary = rules()["repair"]
	var d := u.design as VehicleDesign
	var c := u.condition
	var out: Array = []
	var ipts := VehicleConstruction.internal_points(d)
	var inner: Dictionary = c.get("internal", {})
	for loc in ipts:
		var mx := int(ipts[loc])
		var cur := int(inner.get(loc, mx))
		if cur < mx:
			out.append({"key": "is:" + loc, "label": "Repair %s structure (%d)" % [VehicleDesign.VLOC_NAMES[loc].to_lower(), mx - cur],
				"kind": "structure", "minutes": maxi(int(R["structure_min_min"]), (mx - cur) * int(R["structure_min_per_point"])),
				"tn": 1, "part": "", "qty": 0.0, "loc": loc, "requires": ""})
	var armor: Dictionary = c.get("armor", {})
	for k in d.armor:
		var mx2 := int(d.armor[k])
		var cur2 := int(armor.get(k, mx2))
		if cur2 < mx2:
			out.append({"key": "armor:" + k, "label": "Armor: %s (%d pts)" % [VehicleDesign.VLOC_NAMES.get(k, k), mx2 - cur2], "kind": "armor",
				"minutes": (mx2 - cur2) * int(R["armor_min_per_point"]), "tn": -1, "part": "armor:" + d.armor_type,
				"qty": snappedf((mx2 - cur2) / VehicleConstruction.armor_ppt(d), 0.01), "loc": k, "requires": ""})
	var mounts := VehicleConstruction.mounts_of(d)
	var db := GameData.db()
	var dead_m := {}
	for mi in c.get("dead_mounts", []):
		var m2 := int(mi)
		if m2 < 0 or m2 >= mounts.size():
			continue
		dead_m[m2] = true
		var it := db.item(mounts[m2]["id"])
		var kind := _item_kind(it)
		var part := "item:" + str(mounts[m2]["id"])
		var qty := 1.0
		if it.get("kind", "") == "ammo":
			part = "ammo:" + str(mounts[m2]["id"])
			qty = float(it.get("tons", 1.0))
		out.append({"key": "mount:%d" % m2, "label": "Replace %s (%s)" % [it.get("name", ""), VehicleDesign.VLOC_NAMES.get(mounts[m2]["loc"], mounts[m2]["loc"])],
			"kind": kind, "minutes": int(R["item_min"].get(kind, 90)), "tn": int(R["item_tn"].get(kind, 0)), "part": part, "qty": qty,
			"loc": mounts[m2]["loc"], "requires": ""})
	var vs: Dictionary = c.get("vstate", {})
	var VM: Dictionary = R["vehicle_min"]
	var VT: Dictionary = R["vehicle_tn"]
	var motive := int(vs.get("cruise_lost", 0)) + (2 if vs.get("cruise_halved", false) else 0) + (3 if vs.get("immobile", false) else 0)
	if motive > 0:
		out.append({"key": "motive", "label": "Repair %s" % ("rotor" if d.motion == "vtol" else "motive system"), "kind": "motive",
			"minutes": int(VM["motive"]) * motive, "tn": int(VT["motive"]) + (1 if vs.get("immobile", false) else 0), "part": "", "qty": 0.0, "loc": "", "requires": ""})
	if vs.get("engine_dead", false):
		out.append({"key": "fix:engine", "label": "Repair engine", "kind": "engine", "minutes": int(VM["engine"]), "tn": int(VT["engine"]),
			"part": "engine:%s:%d:%d" % [d.engine_type, d.engine_rating, d.tons], "qty": 1.0, "loc": "", "requires": ""})
	if vs.get("turret_locked", false) and d.turret:
		out.append({"key": "turret", "label": "Repair turret drive", "kind": "turret", "minutes": int(VM["turret"]), "tn": int(VT["turret"]),
			"part": "", "qty": 0.0, "loc": "TU", "requires": ""})
	if int(vs.get("vsensors", 0)) > 0:
		out.append({"key": "vsensors", "label": "Replace sensors", "kind": "sensors", "minutes": int(VM["sensors"]), "tn": int(VT["sensors"]),
			"part": "vsensors:%d" % d.tons, "qty": 1.0, "loc": "", "requires": ""})
	for loc in vs.get("stabilizers", []):
		out.append({"key": "stab:" + str(loc), "label": "Repair %s stabilizer" % VehicleDesign.VLOC_NAMES.get(loc, loc).to_lower(),
			"kind": "stabilizer", "minutes": int(VM["stabilizer"]), "tn": int(VT["stabilizer"]), "part": "", "qty": 0.0, "loc": loc, "requires": ""})
	var ammo: Dictionary = c.get("ammo", {})
	for k in ammo:
		var mi3 := int(k)
		if dead_m.has(mi3) or mi3 >= mounts.size():
			continue
		var it3 := db.item(mounts[mi3]["id"])
		var full := int(it3.get("shots", 0))
		var have := int(ammo[k])
		if have < full and full > 0:
			out.append({"key": "reload:%d" % mi3, "label": "Reload %s (%d shots)" % [it3.get("name", ""), full - have], "kind": "reload",
				"minutes": int(R["reload_min"]), "tn": -99, "part": "ammo:" + str(mounts[mi3]["id"]),
				"qty": snappedf(float(it3.get("tons", 1.0)) * (full - have) / float(full), 0.01), "loc": mounts[mi3]["loc"], "requires": ""})
	return out


## Heals the part of the unit's condition a finished task covers.
static func apply(u: MercUnit, task: Dictionary) -> void:
	var c := u.condition
	var key: String = task["key"]
	var d := u.design
	if u.is_vehicle():
		var vd := d as VehicleDesign
		var vs: Dictionary = c.get("vstate", {})
		if key.begins_with("is:"):
			(c["internal"] as Dictionary)[key.substr(3)] = int(VehicleConstruction.internal_points(vd)[key.substr(3)])
			if vd.is_battle_armor():   # a new suit comes whole
				(c["armor"] as Dictionary)[key.substr(3)] = int(vd.armor[key.substr(3)])
		elif key.begins_with("armor:"):
			(c["armor"] as Dictionary)[key.substr(6)] = int(vd.armor[key.substr(6)])
		elif key.begins_with("mount:"):
			var mi := int(key.substr(6))
			(c["dead_mounts"] as Array).erase(mi)
			(c.get("ammo", {}) as Dictionary).erase(str(mi))
		elif key == "motive":
			vs["cruise_lost"] = 0
			vs["cruise_halved"] = false
			vs["immobile"] = false
		elif key == "fix:engine":
			vs["engine_dead"] = false
		elif key == "turret":
			vs["turret_locked"] = false
		elif key == "vsensors":
			vs["vsensors"] = 0
		elif key.begins_with("stab:"):
			(vs.get("stabilizers", []) as Array).erase(key.substr(5))
		elif key.begins_with("reload:"):
			(c["ammo"] as Dictionary).erase(key.substr(7))
		normalize(u)
		return
	var ipts := Construction.internal_points(d.tons)
	if key.begins_with("loc:"):
		var loc := key.substr(4)
		(c["internal"] as Dictionary)[loc] = int(ipts[loc])
		# the new location comes with its actuators; equipment in it is replaced separately
		var keep: Array = []
		for hs in c.get("hit_slots", []):
			if str(hs[0]) == loc and str(d.slots[loc][int(hs[1])]) in ACTUATORS:
				continue
			keep.append(hs)
		c["hit_slots"] = keep
	elif key.begins_with("is:"):
		(c["internal"] as Dictionary)[key.substr(3)] = int(ipts[key.substr(3)])
	elif key.begins_with("armor:"):
		(c["armor"] as Dictionary)[key.substr(6)] = int(d.armor[key.substr(6)])
	elif key.begins_with("act:"):
		var parts := key.split(":")
		var keep2: Array = []
		for hs in c.get("hit_slots", []):
			if str(hs[0]) == parts[1] and int(hs[1]) == int(parts[2]):
				continue
			keep2.append(hs)
		c["hit_slots"] = keep2
	elif key.begins_with("fix:"):
		var tag := key.substr(4)
		var keep3: Array = []
		for hs in c.get("hit_slots", []):
			if str(d.slots[str(hs[0])][int(hs[1])]) == tag:
				continue
			keep3.append(hs)
		c["hit_slots"] = keep3
	elif key.begins_with("mount:"):
		var mi2 := int(key.substr(6))
		var mounts := Construction.mounts_of(d)
		var slots: Array = mounts[mi2]["slots"]
		var keep4: Array = []
		for hs in c.get("hit_slots", []):
			var hit_here := false
			for sl in slots:
				if str(sl[0]) == str(hs[0]) and int(sl[1]) == int(hs[1]):
					hit_here = true
			if not hit_here:
				keep4.append(hs)
		c["hit_slots"] = keep4
		(c.get("ammo", {}) as Dictionary).erase(str(mi2))
	elif key.begins_with("reload:"):
		(c["ammo"] as Dictionary).erase(key.substr(7))
	normalize(u)


## Drops a condition that no longer has any damage in it.
static func normalize(u: MercUnit) -> void:
	if tasks(u).is_empty():
		u.condition = {}
		if u.status == "damaged":
			u.status = "ready"


## Name, price, availability rating and whether it's counted in tons.
static func part_info(key: String, year: int) -> Dictionary:
	var P: Dictionary = rules()["parts"]
	var db := GameData.db()
	var f := key.split(":")
	var av: Dictionary = P["availability"]
	var col := GameData.era_column(year)
	match f[0]:
		"armor":
			var t := f[1] if f.size() > 1 else "standard"
			return {"name": "%s armor" % t.replace("_", " ").capitalize(), "price": int(P["armor_per_ton"].get(t, 10000)),
				"avail": av["armor_ferro"] if t != "standard" else av["armor"], "tons": true}
		"ammo", "item":
			var it := db.item(f[1])
			var letters: Array = it.get("avail", ["C", "C", "C", "C"]) if it.get("avail") != null else ["C", "C", "C", "C"]
			var letter := str(letters[mini(col, letters.size() - 1)]) if letters.size() > 0 else "C"
			if not GameData.dates_allow(it, year) and it.get("tech", "") != "CLAN":
				letter = "X"
			if it.get("tech", "") == "CLAN" and year < 3050:
				letter = "X"
			var price := 0
			if it.get("cost") != null and int(it["cost"]) > 0:
				price = int(it["cost"])
			elif it.get("misc", "") == "heat_sink":
				price = 2000
			elif it.get("misc", "") == "double_heat_sink":
				price = 6000
			elif it.get("misc", "") == "jump_jet":
				price = 12000
			elif f[0] == "item":
				price = 20000  # the data has no price for it
			return {"name": str(it.get("name", f[1])) + (" (ton)" if f[0] == "ammo" else ""), "price": price,
				"avail": letter, "tons": f[0] == "ammo"}
		"loc":
			var tons := int(f[2])
			return {"name": "%s structure (%d t 'Mech)" % [f[1].capitalize(), tons], "price": int(P["location_per_ton"].get(f[1], 1500)) * tons,
				"avail": av["location"], "tons": false}
		"act":
			var tons2 := int(f[2])
			return {"name": "%s actuator (%d t)" % [f[1].replace("_", " ").capitalize(), tons2], "price": maxi(2000, int(P["actuator_per_ton"].get(f[1], 100)) * tons2 * 10),
				"avail": av["actuator"], "tons": false}
		"engine":
			var etype := f[1]
			var rating := int(f[2])
			var tons3 := int(f[3])
			var cost := 0.0
			if VehicleConstruction.ENGINE_COST.has(etype):
				cost = float(VehicleConstruction.ENGINE_COST[etype]) * rating * tons3 / 75.0
			else:
				cost = float(Construction.ENGINE_COST.get(etype, 5000)) * rating * tons3 / 75.0
			return {"name": "%d %s engine" % [rating, etype.replace("_", " ")], "price": int(cost),
				"avail": av["engine_xl"] if etype.begins_with("xl") else av["engine"], "tons": false}
		"gyro":
			return {"name": "%s gyro (size %s)" % [f[1].capitalize(), f[2]], "price": int(Construction.GYRO_COST.get(f[1], 300000)) * int(f[2]),
				"avail": av["gyro"], "tons": false}
		"cockpit":
			return {"name": "Cockpit" if f.size() < 2 else "%s cockpit" % f[1].capitalize(), "price": int(P["cockpit"]),
				"avail": av["cockpit"], "tons": false}
		"life_support":
			return {"name": "Life support", "price": int(P["life_support"]), "avail": av["life_support"], "tons": false}
		"troops":
			var vd := db.stock_design(f[1]) as VehicleDesign
			if vd == null:
				return {"name": "Replacement troopers", "price": 5000, "avail": "B", "tons": false}
			var ba := vd.is_battle_armor()
			return {"name": "%s for the %s" % ["Suit and trooper" if ba else "Replacement trooper", vd.display_name()],
				"price": int(vd.fixed_cost / maxf(1.0, vd.troopers)), "tons": false,
				"avail": "X" if (vd.tech == "Clan" and year < 3050) else str(rules()["repair"]["infantry"]["avail"]["battle_armor" if ba else "infantry"])}
		"sensors", "vsensors":
			return {"name": "Sensors (%s t)" % f[1], "price": int(P["sensors_per_ton"]) * int(f[1]), "avail": av["sensors"], "tons": false}
	return {"name": key, "price": 10000, "avail": "C", "tons": false}


## Parts a wreck yields when stripped: its intact equipment, and a share of its armor.
static func strip(u: MercUnit) -> Dictionary:
	var out := {}
	var R: Dictionary = rules()["repair"]
	var d := u.design
	var c := u.condition
	var db := GameData.db()
	var dead := {}
	if u.is_vehicle():
		for mi in c.get("dead_mounts", []):
			dead[int(mi)] = true
		var vm := VehicleConstruction.mounts_of(d as VehicleDesign)
		for mi2 in vm.size():
			if dead.has(mi2):
				continue
			var it: Dictionary = vm[mi2]["item"]
			var key := ("ammo:" if it.get("kind", "") == "ammo" else "item:") + str(vm[mi2]["id"])
			out[key] = float(out.get(key, 0.0)) + (float(it.get("tons", 1.0)) if it.get("kind", "") == "ammo" else 1.0)
	else:
		var mounts := Construction.mounts_of(d)
		var hit := {}
		for hs in c.get("hit_slots", []):
			hit["%s:%d" % [hs[0], hs[1]]] = true
		var inner: Dictionary = c.get("internal", {})
		for mi3 in mounts.size():
			var mt: Dictionary = mounts[mi3]
			var broken := int(inner.get(mt["loc"], 1)) <= 0
			for sl in mt["slots"]:
				if hit.has("%s:%d" % [sl[0], sl[1]]):
					broken = true
			if broken:
				continue
			var it2 := db.item(mt["id"])
			var key2 := ("ammo:" if it2.get("kind", "") == "ammo" else "item:") + str(mt["id"])
			out[key2] = float(out.get(key2, 0.0)) + (float(it2.get("tons", 1.0)) if it2.get("kind", "") == "ammo" else 1.0)
	var arm := 0
	var ca: Dictionary = c.get("armor", {})
	for k in d.armor:
		arm += int(ca.get(k, d.armor[k]))
	var ppt := VehicleConstruction.armor_ppt(d as VehicleDesign) if u.is_vehicle() else Construction.armor_ppt(d.armor_type)
	var at := snappedf(arm / ppt * float(R["wreck_strip_fraction"]), 0.5)
	if at > 0.0:
		out["armor:" + d.armor_type] = at
	return out
