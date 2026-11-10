class_name OwnedMech
extends RefCounted
## A 'Mech owned by a stable: its (possibly customized) design and its battle damage.

var uid := 0
var design: MechDesign
var nickname := ""
var stable_id := -1
var condition: Dictionary = {}   # {} = pristine; else {"armor", "internal", "hit_slots", "ammo"}
var status := "ready"            # ready, repair, refit, wrecked
var work_hours := 0.0            # bay hours left on the current job
var pending_design: Dictionary = {}
var fights := 0
var kills := 0
var fame := 0.0
var paid := 0


func label() -> String:
	if nickname != "":
		return "%s (%s)" % [nickname, design.display_name()]
	return design.display_name()


func is_damaged() -> bool:
	return not condition.is_empty()


func ready() -> bool:
	return status == "ready"


func base_cost() -> int:
	var r := Construction.analyze(design)
	return int(r.get("cost", 0))


## Value accounting for damage (used for selling and the market).
func value() -> int:
	var c := base_cost()
	if status == "wrecked":
		return int(c * 0.12)
	return int(c * (1.0 - 0.6 * damage_fraction()))


func damage_fraction() -> float:
	if condition.is_empty():
		return 0.0
	var ipts := Construction.internal_points(design.tons)
	var lost := 0.0
	var tot := 0.0
	var ci: Dictionary = condition.get("internal", {})
	for loc in MechDesign.LOCS:
		var mx := float(ipts.get(loc, 0))
		tot += mx
		lost += mx - float(ci.get(loc, mx))
	var ca: Dictionary = condition.get("armor", {})
	var at := 0.0
	var al := 0.0
	for k in design.armor:
		at += float(design.armor[k])
		al += float(design.armor[k]) - float(ca.get(k, design.armor[k]))
	return clampf(0.6 * lost / maxf(1.0, tot) + 0.4 * al / maxf(1.0, at), 0.0, 1.0)


## Itemized repair estimate: {"cost", "hours", "lines": [[label, cost, hours]], "missing": [item names that can't be bought]}
func repair_estimate(year: int, rules: Dictionary) -> Dictionary:
	var lines: Array = []
	var cost := 0.0
	var hours := 0.0
	var missing: Array = []
	if condition.is_empty():
		return {"cost": 0, "hours": 0.0, "lines": lines, "missing": missing}
	var db := GameData.db()
	var rh: Dictionary = rules["repair_hours"]
	if status == "wrecked":
		var c := float(base_cost()) * 0.4
		return {"cost": int(c), "hours": 200.0, "lines": [["Rebuild from wreck", int(c), 200.0]], "missing": missing}
	var ca: Dictionary = condition.get("armor", {})
	var apts := 0
	for k in design.armor:
		apts += maxi(0, int(design.armor[k]) - int(ca.get(k, design.armor[k])))
	if apts > 0:
		var per := float(Construction.ARMOR_COST.get(design.armor_type, 10000)) / Construction.armor_ppt(design.armor_type)
		lines.append(["Armor (%d points)" % apts, int(apts * per), apts * float(rh["armor_point"])])
	var ipts := Construction.internal_points(design.tons)
	var ci: Dictionary = condition.get("internal", {})
	var ispts := 0
	for loc in MechDesign.LOCS:
		ispts += maxi(0, int(ipts.get(loc, 0)) - int(ci.get(loc, ipts.get(loc, 0))))
	if ispts > 0:
		var per_is := 1500.0 * design.tons / 50.0 * (2.0 if int(Construction.STRUCT_FILLERS.get(design.structure, 0)) > 0 else 1.0)
		lines.append(["Internal structure (%d points)" % ispts, int(ispts * per_is), ispts * float(rh["internal_point"])])
	# destroyed components, grouped by mount
	var rep := Construction.analyze(design)
	var mount_of := {}
	var mounts: Array = rep.get("mounts", [])
	for mi in mounts.size():
		for sl in mounts[mi]["slots"]:
			mount_of["%s:%d" % [sl[0], sl[1]]] = mi
	var done_mounts := {}
	var fixed_counts := {}
	for hs in condition.get("hit_slots", []):
		var key := "%s:%d" % [hs[0], int(hs[1])]
		var s: String = design.slots[hs[0]][int(hs[1])]
		if mount_of.has(key):
			var mi2: int = mount_of[key]
			if done_mounts.has(mi2):
				continue
			done_mounts[mi2] = true
			var it := db.item(mounts[mi2]["id"])
			var c2 := float(it.get("cost", 0)) if it.get("cost") != null else 2000.0
			var h2 := float(rh["weapon"]) if it.get("kind", "") == "weapon" else float(rh["component"])
			if it.get("kind", "") == "ammo":
				c2 = 0.0
				h2 = 0.5
			if not db.item_available(mounts[mi2]["id"], year) and it.get("kind", "") != "ammo":
				missing.append(it.get("name", mounts[mi2]["id"]))
				continue
			lines.append(["Replace %s" % it.get("name", "?"), int(c2 * 1.2), h2])
		else:
			fixed_counts[s] = int(fixed_counts.get(s, 0)) + 1
	for s in fixed_counts:
		var n: int = fixed_counts[s]
		var c3 := 0.0
		var h3 := float(rh["actuator"])
		match s:
			"engine":
				c3 = float(Construction.ENGINE_COST.get(design.engine_type, 5000)) * design.engine_rating * design.tons / 75.0 * 0.15
				h3 = float(rh["engine"])
			"gyro":
				c3 = float(Construction.GYRO_COST.get(design.gyro, 300000)) * Construction.gyro_tons(design.engine_rating, design.gyro) * 0.5
				h3 = float(rh["gyro"])
			"cockpit":
				c3 = 200000.0 * 0.5
				h3 = 24.0
			"sensors":
				c3 = 2000.0 * design.tons
			"life_support":
				c3 = 50000.0
			"endo", "ferro", "tsm":
				c3 = 0.0
				h3 = 0.0
			_:
				c3 = 150.0 * design.tons
		if c3 > 0.0 or h3 > 0.0:
			lines.append(["Repair %s x%d" % [s.replace("_", " "), n], int(c3 * n), h3 * n])
	# ammo reload
	var ammo: Dictionary = condition.get("ammo", {})
	var reload := 0.0
	for key2 in ammo:
		var mi3 := int(key2)
		if mi3 < mounts.size():
			var it3 := db.item(mounts[mi3]["id"])
			var full := float(it3.get("shots", 0))
			if full > 0.0:
				reload += float(it3.get("cost", 0)) * (1.0 - float(ammo[key2]) / full)
	if reload > 0.0:
		lines.append(["Reload ammunition", int(reload), 1.0])
	for l in lines:
		cost += float(l[1])
		hours += float(l[2])
	return {"cost": int(cost), "hours": hours, "lines": lines, "missing": missing}


## Applies a completed repair. Components that couldn't be sourced stay destroyed.
func complete_repair(missing_names: Array) -> void:
	if missing_names.is_empty():
		condition = {}
		return
	var db := GameData.db()
	var keep: Array = []
	var rep := Construction.analyze(design)
	for mt in rep.get("mounts", []):
		var nm: String = db.item(mt["id"]).get("name", "")
		if nm in missing_names:
			for sl in mt["slots"]:
				keep.append(sl)
	condition = {"armor": {}, "internal": {}, "hit_slots": keep, "ammo": {}} if not keep.is_empty() else {}


func to_dict() -> Dictionary:
	return {"uid": uid, "design": design.to_dict(), "nickname": nickname, "stable_id": stable_id,
		"condition": condition, "status": status, "work_hours": work_hours, "pending_design": pending_design,
		"fights": fights, "kills": kills, "fame": fame, "paid": paid}


static func from_dict(d: Dictionary) -> OwnedMech:
	var m := OwnedMech.new()
	m.uid = int(d["uid"])
	m.design = MechDesign.from_dict(d["design"])
	m.nickname = str(d.get("nickname", ""))
	m.stable_id = int(d.get("stable_id", -1))
	m.condition = d.get("condition", {})
	m.status = str(d.get("status", "ready"))
	m.work_hours = float(d.get("work_hours", 0.0))
	m.pending_design = d.get("pending_design", {})
	m.fights = int(d.get("fights", 0))
	m.kills = int(d.get("kills", 0))
	m.fame = float(d.get("fame", 0.0))
	m.paid = int(d.get("paid", 0))
	return m


## Condition dictionary in the form CombatMech.apply_condition expects.
func sim_condition() -> Dictionary:
	if condition.is_empty():
		return {}
	return {"armor": condition.get("armor", {}), "internal": condition.get("internal", {}),
		"hit_slots": condition.get("hit_slots", [])}
