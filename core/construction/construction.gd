class_name Construction
extends RefCounted
## TechManual-style construction rules: weight, crit slots, armor limits, heat, C-bill cost, BV.
## analyze() never modifies the design; it returns a report dictionary the bay UI and the sim read.

## Armor: points per ton, crit slots it takes, C-bills per ton. What each does in a fight is in
## data/combat_tables.json ("armor_types"); CombatSim reads it.
const ARMOR_PPT := {"standard": 16.0, "ferro": 17.92, "ferro_clan": 19.2, "light_ferro": 16.96, "heavy_ferro": 19.84,
	"stealth": 16.0, "ferro_lamellor": 14.0, "reflective": 16.0, "reflective_clan": 16.0, "reactive": 16.0,
	"reactive_clan": 16.0, "hardened": 8.0, "heavy_industrial": 16.0, "industrial": 10.72, "commercial": 24.0,
	"primitive": 10.72, "ballistic_reinforced": 12.0, "impact_resistant": 14.0, "anti_penetrative": 12.0,
	"heat_dissipating": 10.0, "ferro_proto": 17.92}
const ARMOR_FILLERS := {"standard": 0, "ferro": 14, "ferro_clan": 7, "light_ferro": 7, "heavy_ferro": 21,
	"stealth": 12, "ferro_lamellor": 12, "reflective": 10, "reflective_clan": 5, "reactive": 14, "reactive_clan": 7,
	"hardened": 0, "heavy_industrial": 0, "industrial": 0, "commercial": 0, "primitive": 0,
	"ballistic_reinforced": 10, "impact_resistant": 10, "anti_penetrative": 6, "heat_dissipating": 6, "ferro_proto": 16}
const ARMOR_COST := {"standard": 10000, "ferro": 20000, "ferro_clan": 20000, "light_ferro": 15000, "heavy_ferro": 25000,
	"stealth": 50000, "ferro_lamellor": 35000, "reflective": 30000, "reflective_clan": 30000, "reactive": 30000,
	"reactive_clan": 30000, "hardened": 15000, "heavy_industrial": 10000, "industrial": 5000, "commercial": 3000,
	"primitive": 5000, "ballistic_reinforced": 25000, "impact_resistant": 20000, "anti_penetrative": 15000,
	"heat_dissipating": 25000, "ferro_proto": 60000}
## Internal structure: share of the 'Mech's tonnage, crit slots, C-bills per ton of 'Mech.
const STRUCT_FRACTION := {"standard": 0.10, "endo": 0.05, "endo_clan": 0.05, "endo_proto": 0.05, "industrial": 0.20,
	"endo_composite": 0.075, "endo_composite_clan": 0.075, "composite": 0.05, "reinforced": 0.20}
const STRUCT_FILLERS := {"standard": 0, "endo": 14, "endo_clan": 7, "endo_proto": 16, "industrial": 0,
	"endo_composite": 7, "endo_composite_clan": 4, "composite": 0, "reinforced": 0}
const STRUCT_COST := {"standard": 400, "endo": 1600, "endo_clan": 1600, "endo_proto": 4800, "industrial": 300,
	"endo_composite": 3200, "endo_composite_clan": 3200, "composite": 1600, "reinforced": 6400}
const ENGINE_MULT := {"standard": 1.0, "xl": 0.5, "xl_clan": 0.5, "light": 0.75, "compact": 1.5,
	"xxl": 1.0 / 3.0, "xxl_clan": 1.0 / 3.0, "ice": 2.0, "fuel_cell": 1.2, "fission": 1.75}
const ENGINE_COST := {"standard": 5000, "xl": 20000, "xl_clan": 20000, "light": 15000, "compact": 10000,
	"xxl": 100000, "xxl_clan": 100000, "ice": 1250, "fuel_cell": 3500, "fission": 7500}
## Heat sinks that come with the engine at no weight. A fusion plant brings ten.
const ENGINE_FREE_SINKS := {"ice": 0, "fuel_cell": 1, "fission": 5}
## Engines that can't feed an energy weapon without power amplifiers (a tenth of the weapons' weight).
const AMPLIFIED := ["ice", "fuel_cell"]
const GYRO_MULT := {"standard": 1.0, "xl": 0.5, "compact": 1.5, "heavy_duty": 2.0, "none": 0.0}
const GYRO_COST := {"standard": 300000, "xl": 750000, "compact": 400000, "heavy_duty": 500000, "none": 0}
const GYRO_SLOTS := {"standard": 4, "xl": 6, "compact": 2, "heavy_duty": 4, "none": 0}
const COCKPIT_TONS := {"standard": 3.0, "small": 2.0, "torso": 4.0, "industrial": 3.0, "primitive": 5.0,
	"primitive_industrial": 5.0, "interface": 4.0, "command_console": 6.0}
const COCKPIT_COST := {"standard": 200000, "small": 175000, "torso": 750000, "industrial": 100000,
	"primitive": 100000, "primitive_industrial": 50000, "interface": 1500000, "command_console": 700000}
## Cockpits that fill two head slots.
const COCKPIT_SLOTS := {"interface": 2, "command_console": 2}
## Heat sinks: tons each (beyond the free ones), heat shed, and the item that goes in a crit slot.
const HS_TONS := {"single": 1.0, "double": 1.0, "double_clan": 1.0, "laser": 1.0, "compact": 1.5}
const HS_SHED := {"single": 1.0, "double": 2.0, "double_clan": 2.0, "laser": 2.0, "compact": 1.0}
const HS_MISC := {"heat_sink": "single", "double_heat_sink": "double", "laser_heat_sink": "laser",
	"compact_heat_sink": "compact"}
## Myomers that take six crit slots.
const MYOMER_SLOTS := {"tsm": 6, "industrial_tsm": 12, "super_cooled": 6}
const MYOMER_COST := {"standard": 2000, "tsm": 16000, "industrial_tsm": 12000, "super_cooled": 10000}
const DIRECT_FIRE := ["laser", "pulse", "ppc", "ac", "uac", "lbx", "rac", "lac", "hvac", "gauss", "lgauss",
	"hgauss", "ihgauss", "sbgauss", "apgauss", "mg", "lmg", "hmg", "flamer", "magshot", "pac", "plasma", "hag"]
const CLUSTER_WEAPONS := ["lrm", "srm", "mrm", "atm", "mml", "elrm", "xlrm", "rl", "tbolt", "lrt", "srt", "mortar"]
const ENERGY_WEAPONS := ["laser", "pulse", "ppc", "tsemp", "taser"]


static func half_up(x: float) -> float:
	return ceil(x * 2.0 - 0.0001) / 2.0


static func engine_tons(rating: int, type: String) -> float:
	var d := GameData.db()
	var r := clampi(int(round(rating / 5.0)) * 5, 10, 500)
	var base: float = d.std_engine.get(r, 0.0)
	return half_up(base * float(ENGINE_MULT.get(type, 1.0)))


static func gyro_tons(rating: int, type: String) -> float:
	var base := ceilf(rating / 100.0)
	return half_up(base * float(GYRO_MULT.get(type, 1.0)))


static func gyro_slots(type: String) -> int:
	return int(GYRO_SLOTS.get(type, 4))


static func structure_tons(tons: int, type: String) -> float:
	return half_up(tons * float(STRUCT_FRACTION.get(type, 0.10)))


## Heat sinks the engine carries at no weight.
static func free_sinks(engine_type: String) -> int:
	return int(ENGINE_FREE_SINKS.get(engine_type, 10))


static func hs_type_of(it: Dictionary) -> String:
	var t := str(HS_MISC.get(str(it.get("misc", "")), ""))
	if t == "double" and it.get("tech") == "CLAN":
		return "double_clan"
	return t


## How many sinks one slot item holds (compact sinks come one or two to the slot).
static func hs_per_item(it: Dictionary) -> int:
	return 2 if str(it.get("misc", "")) == "compact_heat_sink" and str(it.get("name", "")).begins_with("2") else 1


static func armor_ppt(type: String) -> float:
	return float(ARMOR_PPT.get(type, 16.0))


static func armor_tons(points: int, type: String) -> float:
	return half_up(points / armor_ppt(type))


static func jump_jet_tons(tons: int) -> float:
	if tons <= 55:
		return 0.5
	if tons <= 85:
		return 1.0
	return 2.0


static func max_armor(tons: int, loc: String) -> int:
	if loc == "HD":
		return 9
	return int(GameData.db().is_points[tons][loc]) * 2


static func internal_points(tons: int) -> Dictionary:
	return GameData.db().is_points.get(tons, {})


## Crit count of an item as mounted on this design (some items scale with tonnage).
static func item_crits(d: MechDesign, id: String, direct_fire_tons := 0.0) -> int:
	var it := GameData.db().item(id)
	if it.is_empty():
		return 1
	var misc: String = it.get("misc", "")
	var clan: bool = it.get("tech", "") == "CLAN"
	match misc:
		"jump_jet":
			return 1
		"masc":
			return maxi(1, int(round(d.tons / (25.0 if clan else 20.0))))
		"hatchet":
			return maxi(1, int(ceil(d.tons / 15.0)))
		"sword":
			return maxi(1, int(ceil(d.tons / 15.0)))
		"mace":
			return maxi(1, int(ceil(d.tons / 10.0)))
		"tc":
			return maxi(1, int(ceil(direct_fire_tons / (5.0 if clan else 4.0))))
		"supercharger":
			return 1
		"claw":
			return maxi(1, int(ceil(d.tons / 15.0)))
		"lance":
			return maxi(1, int(ceil(d.tons / 20.0)))
		"retractable_blade":
			return 1 + int(ceil(d.tons / 20.0))
		"aes":
			return 1 if d.tons < 40 else (2 if d.tons < 60 else (3 if d.tons < 80 else 4))   # by weight class
		"talons":
			return 2
	if it.get("crits") == null:
		return 1
	return int(it["crits"])


static func item_tons(d: MechDesign, id: String, direct_fire_tons := 0.0) -> float:
	var it := GameData.db().item(id)
	if it.is_empty():
		return 0.0
	var misc: String = it.get("misc", "")
	var clan: bool = it.get("tech", "") == "CLAN"
	match misc:
		"jump_jet":
			return jump_jet_tons(d.tons)
		"masc":
			return float(maxi(1, int(round(d.tons / (25.0 if clan else 20.0)))))
		"hatchet":
			return ceilf(d.tons / 15.0)
		"sword":
			return half_up(d.tons / 20.0)
		"mace":
			return ceilf(d.tons / 10.0)
		"tc":
			return ceilf(direct_fire_tons / (5.0 if clan else 4.0))
		"supercharger":
			return half_up(engine_tons(d.engine_rating, d.engine_type) / 10.0)
		"improved_jump_jet":
			return jump_jet_tons(d.tons) * 2.0
		"umu":
			return jump_jet_tons(d.tons)
		"partial_wing":
			return half_up(d.tons * (0.05 if clan else 0.07))
		"claw":
			return ceilf(d.tons / 15.0)
		"lance":
			return ceilf(d.tons / 20.0)
		"retractable_blade":
			return half_up(d.tons / 20.0) + 0.5
		"aes":
			return half_up(d.tons / 35.0)
		"talons":
			return half_up(d.tons / 15.0) / 2.0     # one set, fitted to both legs
		"booby_trap":
			return minf(10.0, half_up(d.tons * 0.1))
	if it.get("tons") == null:
		match str(it.get("name", "")):
			"Environmental Sealing (Mech)":
				return half_up(d.tons * 0.1)
			"Tracks":
				return half_up(d.tons * 0.1) / 2.0  # one set, a track unit in each leg
		return 0.0
	return float(it["tons"])


## Groups slot runs into mounts: one entry per installed item.
static func mounts_of(d: MechDesign, report_errors: Array = []) -> Array:
	if d.is_vehicle():
		return VehicleConstruction.mounts_of(d as VehicleDesign)
	var db := GameData.db()
	var df_tons := 0.0
	# direct-fire tonnage for targeting computers (first pass over unique runs is approximate but fine)
	var mounts: Array = []
	var partial: Array = []
	for loc in MechDesign.LOCS:
		var row: Array = d.slots[loc]
		var i := 0
		while i < row.size():
			var s: String = row[i]
			if s == "" or MechDesign.is_fixed(s):
				i += 1
				continue
			var run := 0
			while i + run < row.size() and row[i + run] == s:
				run += 1
			var id := MechDesign.base_id(s)
			var c := item_crits(d, id, df_tons)
			var it := db.item(id)
			if it.get("misc", "") == "tc":
				c = 0  # resolved after direct-fire tonnage is known
			var start := i
			if c <= 0:
				mounts.append({"id": id, "loc": loc, "rear": MechDesign.is_rear(s), "slots": _range_slots(loc, start, run), "tc": true})
			else:
				var left := run
				while left >= c:
					mounts.append({"id": id, "loc": loc, "rear": MechDesign.is_rear(s), "slots": _range_slots(loc, start, c)})
					start += c
					left -= c
				if left > 0:
					partial.append({"id": id, "loc": loc, "rear": MechDesign.is_rear(s), "slots": _range_slots(loc, start, left), "need": c})
			i += run
	# join split items across locations
	var used := {}
	for a in partial.size():
		if used.has(a):
			continue
		var pa: Dictionary = partial[a]
		var have: int = pa["slots"].size()
		var joined: Array = (pa["slots"] as Array).duplicate()
		# an item split over two locations sits in neighbours (arm and side torso, side and center torso)
		for b in range(a + 1, partial.size()):
			if used.has(b):
				continue
			var pn: Dictionary = partial[b]
			if pn["id"] == pa["id"] and have + pn["slots"].size() == int(pa["need"]) and _adjacent(str(pa["loc"]), str(pn["loc"])):
				joined.append_array(pn["slots"])
				have += pn["slots"].size()
				used[b] = true
				break
		for b in range(a + 1, partial.size()):
			if used.has(b) or have == int(pa["need"]):
				continue
			var pb: Dictionary = partial[b]
			if pb["id"] == pa["id"] and have + pb["slots"].size() <= int(pa["need"]):
				joined.append_array(pb["slots"])
				have += pb["slots"].size()
				used[b] = true
				if have == int(pa["need"]):
					break
		used[a] = true
		if have == int(pa["need"]):
			mounts.append({"id": pa["id"], "loc": pa["loc"], "rear": pa["rear"], "slots": joined, "split": true})
		else:
			report_errors.append("%s in %s is missing crit slots (%d of %d)" % [db.item(pa["id"]).get("name", pa["id"]), pa["loc"], have, pa["need"]])
			mounts.append({"id": pa["id"], "loc": pa["loc"], "rear": pa["rear"], "slots": joined, "split": true, "broken": true})
	# targeting computer size now that direct-fire tonnage is known
	for m in mounts:
		var it := db.item(m["id"])
		if it.get("kind", "") == "weapon" and it.get("wtype", "") in DIRECT_FIRE:
			df_tons += float(it.get("tons", 0.0))
	var final: Array = []
	for m in mounts:
		if m.get("tc", false):
			var c := item_crits(d, m["id"], df_tons)
			var sl: Array = m["slots"]
			var k := 0
			while k + c <= sl.size():
				final.append({"id": m["id"], "loc": m["loc"], "rear": false, "slots": sl.slice(k, k + c)})
				k += c
			if k < sl.size() or c == 0:
				report_errors.append("Targeting computer needs %d slots" % c)
		else:
			final.append(m)
	return final


static func _adjacent(a: String, b: String) -> bool:
	for pair in [["LA", "LT"], ["RA", "RT"], ["LT", "CT"], ["RT", "CT"], ["LL", "LT"], ["RL", "RT"], ["HD", "CT"]]:
		if (a == pair[0] and b == pair[1]) or (a == pair[1] and b == pair[0]):
			return true
	return false


static func _range_slots(loc: String, start: int, n: int) -> Array:
	var out: Array = []
	for k in n:
		out.append([loc, start + k])
	return out


static func direct_fire_tons(d: MechDesign, mounts: Array) -> float:
	var t := 0.0
	for m in mounts:
		var it := GameData.db().item(m["id"])
		if it.get("kind", "") == "weapon" and it.get("wtype", "") in DIRECT_FIRE:
			t += float(it.get("tons", 0.0))
	return t


## Full construction report. year < 0 skips the tech availability checks.
static func analyze(d: MechDesign, year := -1) -> Dictionary:
	if d.is_vehicle():
		return VehicleConstruction.analyze(d as VehicleDesign, year)
	var db := GameData.db()
	var errors: Array = []
	var warnings: Array = []
	var breakdown: Array = []
	var C: Dictionary = db.construction

	# --- chassis basics
	if d.tons < 20 or d.tons > 100 or d.tons % 5 != 0:
		errors.append("Tonnage must be 20-100 in 5-ton steps")
	if not db.is_points.has(d.tons):
		return {"valid": false, "errors": errors + ["No structure table for %d tons" % d.tons], "warnings": warnings}
	var want_rating := d.tons * d.walk
	if d.cockpit.begins_with("primitive"):
		# a primitive 'Mech needs a fifth more engine for the same speed
		want_rating = int(ceil(want_rating * 1.2 / 5.0 - 0.0001)) * 5
	if d.engine_rating != want_rating:
		errors.append("Engine rating %d must equal tonnage x Walk (%d)" % [d.engine_rating, want_rating])
	if d.engine_rating < 10 or d.engine_rating > 400:
		errors.append("Engine rating must be 10-400")
	var improved_jets := false
	for loc0 in MechDesign.LOCS:
		for s0 in d.slots[loc0]:
			if s0 != "" and not MechDesign.is_fixed(s0) and db.item(MechDesign.base_id(s0)).get("misc", "") == "improved_jump_jet":
				improved_jets = true
	if d.jump > (d.run_mp() if improved_jets else d.walk):
		errors.append("Jump MP can't exceed %s MP" % ("Run" if improved_jets else "Walk"))

	var t_struct := structure_tons(d.tons, d.structure)
	var t_engine := engine_tons(d.engine_rating, d.engine_type)
	var t_gyro := gyro_tons(d.engine_rating, d.gyro)
	var t_cockpit: float = COCKPIT_TONS.get(d.cockpit, 3.0)
	breakdown.append(["Internal structure (%s)" % d.structure.replace("_", " "), t_struct])
	breakdown.append(["Engine %d %s" % [d.engine_rating, d.engine_type.replace("_", " ")], t_engine])
	breakdown.append(["Gyro (%s)" % d.gyro.replace("_", " "), t_gyro])
	breakdown.append(["Cockpit (%s)" % d.cockpit, t_cockpit])

	# --- armor
	var ipts := internal_points(d.tons)
	var armor_pts := d.armor_total()
	var armor_max := 0
	for loc in MechDesign.LOCS:
		var mx := max_armor(d.tons, loc)
		armor_max += mx
		var a: int = d.armor.get(loc, 0)
		if MechDesign.REAR.has(loc):
			a += int(d.armor.get(MechDesign.REAR[loc], 0))
		if a > mx:
			errors.append("%s armor %d exceeds max %d" % [MechDesign.LOC_NAMES[loc], a, mx])
	var t_armor := armor_tons(armor_pts, d.armor_type)
	breakdown.append(["Armor %d pts (%s)" % [armor_pts, d.armor_type.replace("_", " ")], t_armor])

	# --- slots, mounts
	var mounts := mounts_of(d, errors)
	var df_tons := direct_fire_tons(d, mounts)
	var counts := {}
	for loc in MechDesign.LOCS:
		for s in d.slots[loc]:
			if s != "":
				var key: String = s if MechDesign.is_fixed(s) else "_item"
				counts[loc + ":" + key] = int(counts.get(loc + ":" + key, 0)) + 1
				counts[key] = int(counts.get(key, 0)) + 1
	var eng_ct := 3 if d.engine_type == "compact" else 6
	if int(counts.get("CT:engine", 0)) != eng_ct:
		errors.append("Center torso needs %d engine slots" % eng_ct)
	var side := d.side_engine_slots()
	for loc in ["LT", "RT"]:
		if int(counts.get(loc + ":engine", 0)) != side:
			errors.append("%s needs %d engine slots" % [MechDesign.LOC_NAMES[loc], side])
	var gy_n := gyro_slots(d.gyro)
	if int(counts.get("CT:gyro", 0)) != gy_n:
		errors.append("Gyro needs %d center torso slots" % gy_n)
	var cockpit_n := int(COCKPIT_SLOTS.get(d.cockpit, 1))
	if int(counts.get("cockpit", 0)) != cockpit_n:
		errors.append("The %s cockpit takes %d slot%s" % [d.cockpit.replace("_", " "), cockpit_n, "" if cockpit_n == 1 else "s"])
	for loc in ["LL", "RL"]:
		for part in ["hip", "upper_leg", "lower_leg", "foot"]:
			if int(counts.get(loc + ":" + part, 0)) != 1:
				errors.append("%s is missing its %s actuator" % [MechDesign.LOC_NAMES[loc], part.replace("_", " ")])
	for loc in ["LA", "RA"]:
		for part in ["shoulder", "upper_arm"]:
			if int(counts.get(loc + ":" + part, 0)) != 1:
				errors.append("%s is missing its %s" % [MechDesign.LOC_NAMES[loc], part.replace("_", " ")])
		if int(counts.get(loc + ":hand", 0)) > 0 and int(counts.get(loc + ":lower_arm", 0)) == 0:
			errors.append("%s has a hand without a lower arm actuator" % MechDesign.LOC_NAMES[loc])
	var endo_need: int = STRUCT_FILLERS.get(d.structure, 0)
	if int(counts.get("endo", 0)) != endo_need:
		errors.append("%s structure needs %d slots (has %d)" % [d.structure.replace("_", " ").capitalize(), endo_need, int(counts.get("endo", 0))])
	var ferro_need: int = ARMOR_FILLERS.get(d.armor_type, 0)
	if int(counts.get("ferro", 0)) != ferro_need:
		errors.append("%s armor needs %d slots (has %d)" % [d.armor_type.replace("_", " ").capitalize(), ferro_need, int(counts.get("ferro", 0))])
	if int(counts.get("tsm", 0)) != int(MYOMER_SLOTS.get(d.myomer, 0)):
		errors.append("%s myomer needs %d slots" % [d.myomer.replace("_", " ").capitalize(), int(MYOMER_SLOTS.get(d.myomer, 0))])

	# --- equipment
	var t_equip := 0.0
	var hs_in_slots := 0
	var hs_slot_tons := 0.0
	var energy_tons := 0.0
	var jj := 0
	var weapons: Array = []
	var ammo: Array = []
	var has_case := {}
	var misc_flags := {}
	var equip_cost := 0.0
	for m in mounts:
		var it := db.item(m["id"])
		if it.is_empty():
			errors.append("Unknown item %s" % m["id"])
			continue
		var w := item_tons(d, m["id"], df_tons)
		if it.get("tons") == null and it.get("misc", "") in ["other", ""] and w <= 0.0:
			errors.append("%s has no defined weight" % it.get("name", m["id"]))
		t_equip += w
		equip_cost += float(it.get("cost", 0)) if it.get("cost") != null else 0.0
		var misc: String = it.get("misc", "")
		match it.get("kind", ""):
			"weapon":
				weapons.append(m)
				if str(it.get("wtype", "")) in ENERGY_WEAPONS:
					energy_tons += w
			"ammo":
				ammo.append(m)
			"misc":
				if HS_MISC.has(misc):
					hs_in_slots += hs_per_item(it)
					hs_slot_tons += w
					if hs_type_of(it) != d.hs_type:
						errors.append("%s doesn't match the %s heat sink type" % [it.get("name"), d.hs_type])
				elif misc in ["jump_jet", "improved_jump_jet"]:
					jj += 1
				elif misc in ["case", "case2"]:
					has_case[m["loc"]] = true
				misc_flags[misc] = int(misc_flags.get(misc, 0)) + 1
		if year >= 0 and not db.item_available(m["id"], year):
			warnings.append("%s is not available in %d" % [it.get("name", m["id"]), year])
	if d.tech == "Clan" or d.tech == "Mixed":
		# Clan CASE is free and implicit in every Clan location.
		if d.tech == "Clan":
			for loc in MechDesign.LOCS:
				has_case[loc] = true
	if jj != d.jump:
		errors.append("Jump MP %d needs %d jump jets (has %d)" % [d.jump, d.jump, jj])
	var t_jj := 0.0
	# jump jet tons are already part of t_equip via item_tons
	# --- heat sinks
	var integral := mini(d.hs_count, int(floor(d.engine_rating / 25.0)))
	if d.hs_type == "compact":
		integral = mini(d.hs_count, int(floor(d.engine_rating / 25.0)) * 2)
	var need_slots := d.hs_count - integral
	var free_hs := free_sinks(d.engine_type)
	if d.hs_count < free_hs:
		errors.append("At least %d heat sinks are required" % free_hs)
	if hs_in_slots < need_slots:
		errors.append("%d heat sinks need crit slots but only %d are placed" % [need_slots, hs_in_slots])
	elif hs_in_slots > need_slots:
		warnings.append("%d extra heat sinks are placed in slots" % (hs_in_slots - need_slots))
	# heat sink weight: all sinks beyond the 10 free ones (slot-placed sinks were counted as items)
	var t_hs := float(maxi(0, d.hs_count - free_hs)) * float(HS_TONS.get(d.hs_type, 1.0))
	t_equip -= hs_slot_tons  # slot-placed sinks are covered by t_hs
	breakdown.append(["Heat sinks %d %s" % [d.hs_count, d.hs_type.replace("_", " ")], t_hs])
	if d.engine_type in AMPLIFIED and energy_tons > 0.0:
		var t_amp := half_up(energy_tons * 0.1)
		t_equip += t_amp
		breakdown.append(["Power amplifiers", t_amp])
	breakdown.append(["Weapons and equipment", t_equip])

	# --- slot capacity
	for loc in MechDesign.LOCS:
		if (d.slots[loc] as Array).size() != MechDesign.SLOT_COUNT[loc]:
			errors.append("%s has the wrong slot count" % loc)

	# --- tech availability
	if year >= 0:
		for pair in [["engine", d.engine_type], ["structure", d.structure], ["armor", d.armor_type],
				["gyro", d.gyro], ["cockpit", d.cockpit], ["hs", d.hs_type], ["myomer", d.myomer]]:
			if not db.component_available(pair[0], pair[1], year):
				warnings.append("%s %s is not available in %d" % [pair[1].replace("_", " ").capitalize(), pair[0], year])

	var used := t_struct + t_engine + t_gyro + t_cockpit + t_armor + t_hs + t_equip
	if used > d.tons + 0.001:
		errors.append("Overweight: %.1f of %d tons" % [used, d.tons])

	# --- heat profile
	var dissipation := int(d.hs_count * float(HS_SHED.get(d.hs_type, 1.0)))
	var alpha := 0
	for m in weapons:
		var it := db.item(m["id"])
		var h := int(it.get("heat", 0))
		if it.get("wtype", "") == "uac":
			h *= 2
		elif it.get("wtype", "") == "rac":
			h *= 4
		alpha += h
	var run_heat := 2
	var jump_heat := maxi(3, d.jump) if d.jump > 0 else 0

	var report := {
		"valid": errors.is_empty(), "errors": errors, "warnings": warnings,
		"tons_used": used, "tons_free": d.tons - used, "breakdown": breakdown,
		"mounts": mounts, "weapons": weapons, "ammo": ammo, "case": has_case, "misc": misc_flags,
		"armor_points": armor_pts, "armor_max": armor_max, "internal": ipts,
		"heat": {"alpha": alpha, "dissipation": dissipation, "run": run_heat, "jump": jump_heat,
			"integral": integral},
		"walk": d.walk, "run": d.run_mp(), "jump": d.jump,
	}
	report["cost"] = cost(d, report, equip_cost)
	report["bv"] = battle_value(d, report)
	return report


## C-bill cost (MegaMek MekCostCalculator structure, simplified).
static func cost(d: MechDesign, rep: Dictionary, equip_cost: float) -> int:
	var cc: Dictionary = GameData.db().construction["chassis_cost"]
	var t := float(d.tons)
	var c := 0.0
	c += float(COCKPIT_COST.get(d.cockpit, 200000))
	c += float(cc["life_support"])
	c += float(cc["sensors_per_ton"]) * t
	c += float(MYOMER_COST.get(d.myomer, 2000)) * t
	c += float(STRUCT_COST.get(d.structure, 400)) * t
	var act: Dictionary = cc["actuators_per_ton"]
	for loc in ["LA", "RA"]:
		var row: Array = d.slots[loc]
		c += float(act["upper_arm"]) * t
		if "lower_arm" in row:
			c += float(act["lower_arm"]) * t
		if "hand" in row:
			c += float(act["hand"]) * t
	c += (float(act["upper_leg"]) + float(act["lower_leg"]) + float(act["foot"])) * t * 2.0
	c += float(ENGINE_COST.get(d.engine_type, 5000)) * d.engine_rating * t / 75.0
	c += float(GYRO_COST.get(d.gyro, 300000)) * gyro_tons(d.engine_rating, d.gyro)
	c += 200.0 * t * d.jump * d.jump
	if d.hs_type == "single":
		c += 2000.0 * maxi(0, d.hs_count - 10)
	else:
		c += 6000.0 * d.hs_count
	c += float(ARMOR_COST.get(d.armor_type, 10000)) * armor_tons(d.armor_total(), d.armor_type)
	c += equip_cost
	c *= 1.0 + t / 100.0
	return int(round(c))


static func tmm_for_hexes(hexes: int) -> int:
	if hexes <= 2:
		return 0
	if hexes <= 4:
		return 1
	if hexes <= 6:
		return 2
	if hexes <= 9:
		return 3
	if hexes <= 17:
		return 4
	if hexes <= 24:
		return 5
	return 6


## Battle Value, following the BV2 structure (defensive + offensive, speed and heat adjusted).
static func battle_value(d: MechDesign, rep: Dictionary) -> int:
	var db := GameData.db()
	var ipts: Dictionary = rep["internal"]
	var is_total := 0
	for loc in ipts:
		is_total += int(ipts[loc])
	var struct_mult := 1.0
	match d.structure:
		"industrial", "composite":
			struct_mult = 0.5
		"reinforced":
			struct_mult = 2.0
	var armor_mult := 1.0
	match d.armor_type:
		"hardened":
			armor_mult = 2.0
		"commercial":
			armor_mult = 0.5
		"reactive", "reactive_clan", "reflective", "reflective_clan", "ballistic_reinforced":
			armor_mult = 1.5
		"ferro_lamellor", "anti_penetrative", "heat_dissipating":
			armor_mult = 1.2
	var engine_mult := 1.0
	match d.engine_type:
		"xl":
			engine_mult = 0.5
		"xl_clan", "light":
			engine_mult = 0.75
		"xxl":
			engine_mult = 0.25
		"xxl_clan":
			engine_mult = 0.5
	var def := float(rep["armor_points"]) * 2.5 * armor_mult
	def += is_total * 1.5 * struct_mult * engine_mult
	def += d.tons * (1.0 if d.gyro == "heavy_duty" else 0.5)
	var def_equip := 0.0
	var off_weapons: Array = []
	var ammo_bv := {}
	var weapon_bv_by_ammo := {}
	for m in rep["mounts"]:
		var it := db.item(m["id"])
		var bv := float(it.get("bv", 0)) if it.get("bv") != null else 0.0
		match it.get("kind", ""):
			"weapon":
				if it.get("wtype", "") == "ams":
					def_equip += bv
					continue
				var heat := float(it.get("heat", 0))
				if it.get("wtype", "") == "uac":
					heat *= 2.0
				off_weapons.append({"bv": bv * (0.5 if m["rear"] else 1.0), "heat": heat})
				var key: String = it.get("ammo", "")
				if key != "":
					weapon_bv_by_ammo[key] = float(weapon_bv_by_ammo.get(key, 0.0)) + bv
			"ammo":
				var key2: String = it.get("ammo", "")
				ammo_bv[key2] = float(ammo_bv.get(key2, 0.0)) + bv
				if it.get("explosive", true) and not rep["case"].get(m["loc"], false):
					def -= 15.0
			"misc":
				if it.get("misc", "") in ["ecm", "probe"]:
					def_equip += bv
	def += def_equip
	var best_move := maxi(d.run_mp(), d.jump)
	var tmm := tmm_for_hexes(best_move)
	if d.jump > 0 and d.jump >= d.run_mp():
		tmm += 1
	def *= 1.0 + tmm / 10.0
	def = maxf(1.0, def)

	var heat_eff := 6 + int(rep["heat"]["dissipation"]) - maxi(2, int(rep["heat"]["jump"]))
	off_weapons.sort_custom(func(a, b): return a["bv"] > b["bv"])
	var wsum := 0.0
	var heat := 0.0
	for w in off_weapons:
		heat += w["heat"]
		wsum += w["bv"] if heat <= heat_eff else w["bv"] * 0.5
	var asum := 0.0
	for key in ammo_bv:
		asum += minf(ammo_bv[key], weapon_bv_by_ammo.get(key, 0.0))
	var off := wsum + asum + d.tons * (1.5 if d.myomer == "tsm" else (1.15 if d.myomer == "industrial_tsm" else 1.0))
	var sf := pow(((d.run_mp() + round(d.jump / 2.0)) - 5.0) / 10.0 + 1.0, 1.2)
	off *= snappedf(sf, 0.01)
	return int(round(def + off))


## True if every component and item can be bought on an Inner Sphere market in `year`.
static func buildable_in(d: MechDesign, year: int) -> bool:
	if d.is_vehicle():
		return VehicleConstruction.buildable_in(d as VehicleDesign, year)
	var db := GameData.db()
	for pair in [["engine", d.engine_type], ["structure", d.structure], ["armor", d.armor_type],
			["gyro", d.gyro], ["cockpit", d.cockpit], ["hs", d.hs_type], ["myomer", d.myomer]]:
		if not db.component_available(pair[0], pair[1], year):
			return false
	for loc in MechDesign.LOCS:
		for s in d.slots[loc]:
			if s == "" or MechDesign.is_fixed(s):
				continue
			if not db.item_available(MechDesign.base_id(s), year):
				return false
	return true
