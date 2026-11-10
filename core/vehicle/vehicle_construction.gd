class_name VehicleConstruction
extends RefCounted
## TechManual combat vehicle construction (as MegaMek's TestTank checks it): weight, armor limit,
## item slots, C-bill cost and an approximate BV2. Construction.analyze() forwards vehicles here,
## so everything that prices or rates a design works for both kinds.

const ENGINE_MULT := {"ice": 2.0, "fusion": 1.0, "xl": 0.5, "light": 0.75, "compact": 1.5, "fuel_cell": 1.2,
	"xxl": 1.0 / 3.0, "fission": 1.75}
const ENGINE_COST := {"ice": 1250, "fusion": 5000, "xl": 20000, "light": 15000, "compact": 10000, "fuel_cell": 3500,
	"xxl": 100000, "fission": 7500}
const ARMOR_PPT := {"standard": 16.0, "ferro": 17.92, "ferro_clan": 19.2}
const ARMOR_COST := {"standard": 10000, "ferro": 20000, "ferro_clan": 20000}
const COST_DIV := {"hover": 50.0, "wheeled": 200.0, "tracked": 100.0, "vtol": 30.0}
const TYPE_MOD := {"tracked": 0.9, "wheeled": 0.8, "hover": 0.7, "vtol": 0.7}
const ENERGY_HEAT := ["laser", "pulse", "ppc"]


static func half_up(x: float) -> float:
	return Construction.half_up(x)


static func suspension(motion: String, tons: int) -> int:
	match motion:
		"hover":
			for row in [[10, 40], [20, 85], [30, 130], [40, 175], [50, 235]]:
				if tons <= int(row[0]):
					return int(row[1])
			return 235
		"vtol":
			for row in [[10, 50], [20, 95], [30, 140]]:
				if tons <= int(row[0]):
					return int(row[1])
			return 140
		"wheeled":
			return 20
	return 0


static func engine_rating_for(motion: String, tons: int, cruise: int) -> int:
	var r := maxi(10, cruise * tons - suspension(motion, tons))
	if r % 5 != 0:
		r += 5 - r % 5
	return r


static func engine_tons(d: VehicleDesign) -> float:
	var db := GameData.db()
	var r := clampi(int(ceil(d.engine_rating / 5.0)) * 5, 10, 400)
	var w := half_up(float(db.std_engine.get(r, 0.0)) * float(ENGINE_MULT.get(d.engine_type, 1.0)))
	if d.fusion():
		w = half_up(w * 1.5)
	if d.motion == "hover":
		w = maxf(w, half_up(d.tons / 5.0))
	return w


static func internal_points(d: VehicleDesign) -> Dictionary:
	var n := int(ceil(d.tons / 10.0))
	var out := {}
	if d.is_battle_armor():
		for loc in d.locs():
			out[loc] = 1
		return out
	if d.is_infantry():
		return {"PL": d.troopers}
	for loc in d.locs():
		out[loc] = n
	return out


static func armor_ppt(d: VehicleDesign) -> float:
	if d.armor_type == "ferro":
		return ARMOR_PPT["ferro_clan"] if d.tech == "Clan" else ARMOR_PPT["ferro"]
	return float(Construction.ARMOR_PPT.get(d.armor_type, 16.0))


static func max_armor(d: VehicleDesign) -> int:
	return int(d.tons * 3.5 + 40)


static func is_energy(it: Dictionary, id: String) -> bool:
	if id == "flamer_vehicle":
		return false
	var wt: String = it.get("wtype", "")
	if str(it.get("ammo", "")) != "" and wt in ["laser", "flamer"]:
		return false        # chemical lasers and ammo-fed flamers burn their own fuel
	if wt in ENERGY_HEAT or wt in ["plasma", "tsemp"]:
		return true
	return wt == "flamer"


## Infantry weapons are not catalogue items: each line of the unit's weapon list becomes one synthetic
## weapon, fired by the whole squad. Its damage is set from the head count when the fight starts.
static func squad_item(d: VehicleDesign, w: Dictionary) -> Dictionary:
	var it := {"id": "squad_" + str(w.get("name", "weapon")).to_snake_case(), "name": str(w.get("name", "Small arms")),
		"kind": "weapon", "wtype": str(w.get("wtype", "rifle")), "dmg": 1, "heat": 0, "min": 0,
		"s": int(w.get("s", 1)), "m": int(w.get("m", 2)), "l": int(w.get("l", 3)), "tons": 0, "slots": 0, "bv": 0,
		"cost": 0, "squad": true, "per": float(w.get("per", 0.27))}
	if w.has("missiles"):
		it["missiles"] = int(w["missiles"])
	if w.has("salvos"):
		it["salvos"] = int(w["salvos"])
	return it


static func mounts_of(d: VehicleDesign) -> Array:
	var db := GameData.db()
	var out: Array = []
	if d.is_infantry():
		for w in d.squad_weapons:
			var sq := squad_item(d, w)
			out.append({"id": sq["id"], "loc": "BD", "rear": false, "slots": [], "item": sq})
		return out
	for e in d.equipment:
		var it := db.item(str(e[0]))
		out.append({"id": str(e[0]), "loc": str(e[1]), "rear": str(e[1]) == "RR", "slots": [], "item": it})
	return out


static func analyze(d: VehicleDesign, year := -1) -> Dictionary:
	var db := GameData.db()
	if d.is_infantry():
		return _analyze_infantry(d)
	var errors: Array = []
	var warnings: Array = []
	var breakdown: Array = []
	var max_t: int = VehicleDesign.MAX_TONS.get(d.motion, 100)
	if d.tons < 1 or d.tons > max_t:
		errors.append("%s vehicles weigh 1-%d tons" % [d.motion_label(), max_t])
	var want_rating := engine_rating_for(d.motion, d.tons, d.walk)
	if d.engine_rating != want_rating:
		errors.append("Engine rating %d should be %d for Cruise %d" % [d.engine_rating, want_rating, d.walk])
	if d.engine_rating > 400:
		errors.append("Engine rating must be 400 or less")
	var t_struct := half_up(d.tons / 10.0)
	var t_engine := engine_tons(d)
	var t_lift := 0.0
	if d.motion in ["hover", "vtol"]:
		t_lift = half_up(d.tons / 10.0)
	var t_controls := half_up(d.tons / 20.0)
	breakdown.append(["Internal structure", t_struct])
	breakdown.append(["Engine %d %s" % [d.engine_rating, d.engine_type.replace("_", " ")], t_engine])
	if t_lift > 0.0:
		breakdown.append(["Lift equipment" if d.motion == "hover" else "Rotor", t_lift])
	breakdown.append(["Controls", t_controls])
	var mounts := mounts_of(d)
	var turret_w := 0.0
	var eq_tons := 0.0
	var eq_cost := 0.0
	var energy_w := 0.0
	var heat_need := 0
	var df_tons := 0.0
	for mt in mounts:
		var it: Dictionary = mt["item"]
		if it.is_empty():
			errors.append("Unknown item %s" % mt["id"])
			continue
		if it.get("kind", "") == "weapon" and str(it.get("wtype", "")) in Construction.DIRECT_FIRE:
			df_tons += float(it.get("tons", 0) if it.get("tons") != null else 0)
	var case_locs := {}
	var slots_used := 0
	var ammo_kinds := {}
	for mt in mounts:
		var it: Dictionary = mt["item"]
		if it.is_empty():
			continue
		var w := Construction.item_tons(d, mt["id"], df_tons)
		eq_tons += w
		eq_cost += float(it.get("cost", 0) if it.get("cost") != null else 0)
		if mt["loc"] == "TU" and it.get("kind", "") != "ammo":
			turret_w += w
		if it.get("kind", "") == "weapon" and is_energy(it, mt["id"]):
			energy_w += w
			heat_need += int(it.get("heat", 0))
		if it.get("kind", "") == "ammo":
			if not ammo_kinds.has(mt["id"]):
				ammo_kinds[mt["id"]] = true
				slots_used += 1
		else:
			slots_used += 1
		if it.get("misc", "") == "case":
			case_locs[mt["loc"]] = true
		if it.get("misc", "") in ["jump_jet", "masc", "tsm"]:
			errors.append("%s can't be mounted on a vehicle" % it.get("name", mt["id"]))
	var t_turret := half_up(turret_w / 10.0) if d.turret else 0.0
	if d.turret:
		breakdown.append(["Turret", t_turret])
	var free_sinks := 10 if d.fusion() else Construction.free_sinks(d.engine_type) if d.engine_type in ["fuel_cell", "fission"] else 0
	var sinks := maxi(0, heat_need - free_sinks)
	var t_sinks := float(sinks)
	if sinks > 0:
		breakdown.append(["Heat sinks (%d)" % sinks, t_sinks])
	var t_amp := 0.0
	if not d.fusion() and energy_w > 0.0:
		t_amp = half_up(energy_w / 10.0)
		breakdown.append(["Power amplifiers", t_amp])
	var apts := d.armor_total()
	var t_armor := half_up(apts / armor_ppt(d))
	breakdown.append(["Armor %d pts (%s)" % [apts, d.armor_type], t_armor])
	if apts > max_armor(d):
		errors.append("Armor %d exceeds the limit of %d" % [apts, max_armor(d)])
	breakdown.append(["Weapons and equipment", eq_tons])
	if d.dead_weight > 0.0:
		breakdown.append(["Cargo and crew space", d.dead_weight])
	var used := t_struct + t_engine + t_lift + t_controls + t_turret + t_sinks + t_amp + t_armor + eq_tons + d.dead_weight
	if used > d.tons + 0.001:
		errors.append("Overweight: %.1f / %d tons" % [used, d.tons])
	var max_slots := 5 + int(d.tons / 5)
	if slots_used > max_slots:
		warnings.append("Uses %d item slots of %d" % [slots_used, max_slots])
	if year > 0 and not buildable_in(d, year):
		warnings.append("Some equipment isn't on the market in %d" % year)
	# cost (TechManual / MegaMek CombatVehicleCostCalculator)
	var c := 0.0
	c += float(ENGINE_COST.get(d.engine_type, 5000)) * d.engine_rating * d.tons / 75.0
	c += t_armor * float(Construction.ARMOR_COST.get(d.armor_type, 10000))
	c += t_struct * 10000.0
	c += t_controls * 10000.0
	c += 20000.0 * t_amp
	c += 2000.0 * sinks
	c += 5000.0 * t_turret
	c += eq_cost
	if d.motion in ["hover", "vtol"]:
		c += ceilf(d.tons / 5.0) / 2.0 * (40000.0 if d.motion == "vtol" else 20000.0)
	if d.omni:
		c *= 1.25
	c *= 1.0 + d.tons / float(COST_DIV.get(d.motion, 100.0))
	var ipts := internal_points(d)
	var rep := {"valid": errors.is_empty(), "errors": errors, "warnings": warnings, "breakdown": breakdown,
		"tons_used": used, "cost": int(round(c)), "mounts": mounts, "case": case_locs, "internal": ipts,
		"armor_points": apts, "armor_max": max_armor(d), "slots_used": slots_used, "slots_max": max_slots,
		"heat": {"generated": 0, "dissipation": 0, "jump": 0}, "sinks": sinks, "kind": "vehicle"}
	rep["bv"] = battle_value(d, rep)
	return rep


## Infantry are bought whole: the report only restates the unit, so pricing, BV and repair code can use it.
static func _analyze_infantry(d: VehicleDesign) -> Dictionary:
	var apts := d.suit_armor * d.troopers if d.is_battle_armor() else 0
	return {"valid": true, "errors": [], "warnings": [], "breakdown": [], "tons_used": float(d.tons),
		"cost": d.fixed_cost, "mounts": mounts_of(d), "case": {}, "internal": internal_points(d),
		"armor_points": apts, "armor_max": apts, "slots_used": 0, "slots_max": 0,
		"heat": {"generated": 0, "dissipation": 0, "jump": 0}, "sinks": 0, "kind": "vehicle", "infantry": true,
		"bv": d.fixed_bv}


## BV2 for combat vehicles, following MegaMek's CombatVehicleBVCalculator closely enough to balance
## forces (approx: no stealth, amphibious or quirk adjustments).
static func battle_value(d: VehicleDesign, rep: Dictionary) -> int:
	var db := GameData.db()
	var is_total := 0
	for k in rep["internal"]:
		is_total += int(rep["internal"][k])
	var def := float(rep["armor_points"]) * 2.5 + is_total * 1.5
	var off := 0.0
	var ammo_bv := {}
	var weapon_bv_by_ammo := {}
	for mt in rep["mounts"]:
		var it: Dictionary = mt["item"]
		var bv := float(it.get("bv", 0)) if it.get("bv") != null else 0.0
		match it.get("kind", ""):
			"weapon":
				if it.get("wtype", "") == "ams":
					def += bv
					continue
				off += bv * (0.5 if mt["loc"] == "RR" else 1.0)
				var key: String = it.get("ammo", "")
				if key != "":
					weapon_bv_by_ammo[key] = float(weapon_bv_by_ammo.get(key, 0.0)) + bv
			"ammo":
				var key2: String = it.get("ammo", "")
				ammo_bv[key2] = float(ammo_bv.get(key2, 0.0)) + bv
			"misc":
				if it.get("misc", "") in ["ecm", "probe"]:
					def += bv
	def *= float(TYPE_MOD.get(d.motion, 0.8))
	var tmm := Construction.tmm_for_hexes(d.flank_mp())
	if d.motion == "vtol":
		tmm += 1
	def *= 1.0 + tmm / 10.0
	for key in ammo_bv:
		off += minf(ammo_bv[key], weapon_bv_by_ammo.get(key, 0.0))
	off += d.tons / 2.0
	var sf := pow((d.flank_mp() - 5.0) / 10.0 + 1.0, 1.2)
	off *= snappedf(sf, 0.01)
	return int(round(maxf(1.0, def) + off))


static func buildable_in(d: VehicleDesign, year: int) -> bool:
	var db := GameData.db()
	if d.is_infantry():
		return d.year <= year
	if not d.fusion() and d.engine_type != "ice":
		if d.engine_type == "xl" and not db.component_available("engine", "xl", year):
			return false
	if d.engine_type == "xl" and not db.component_available("engine", "xl", year):
		return false
	if d.armor_type != "standard" and not db.component_available("armor", d.armor_type, year):
		return false
	if d.engine_type == "xxl" and not db.component_available("engine", "xxl", year):
		return false
	for e in d.equipment:
		if not db.item_available(str(e[0]), year):
			return false
	return true
