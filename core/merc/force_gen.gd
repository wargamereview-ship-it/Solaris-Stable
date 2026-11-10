class_name ForceGen
extends RefCounted
## Picks 'Mechs and vehicles a faction would field in a given year, from MegaMek's force generator
## availability tables (data/game/force_tables.json). Availability ratings work like MegaMek's RAT
## generator: each point of rating is worth about 1.41x the weight (2^(rating/2)).
## Used for enemy forces, allies, the unit market and the starting company.

static var _cache: Dictionary = {}   # "era|faction|type" -> [[id, weight]]
const NON_COMBAT := ["civilian", "cargo", "apc", "command", "engineer", "support", "recovery", "minelayer",
	"mine_clearance", "field_gun", "artillery", "spotter", "training", "ground_support"]


static func era_for(year: int) -> String:
	var eras: Dictionary = GameData.db().merc()["force"]
	var best := ""
	var best_y := -1
	var first := ""
	var first_y := 99999
	for k in eras:
		var y := int(k)
		if y <= year and y > best_y:
			best_y = y
			best = k
		if y < first_y:
			first_y = y
			first = k
	return best if best != "" else first


## Faction keys to look up, most specific first: the faction, its fallbacks, its region, "General".
static func lookup_chain(faction: String) -> Array:
	var sm := StarMap.get_map()
	var out: Array = [faction]
	var f: Dictionary = sm.factions.get(faction, {})
	for fb in f.get("fallback", []):
		if not (fb in out):
			out.append(fb)
	var tags: Array = f.get("tags", [])
	if "PIRATE" in tags:
		out.append("PIR")
	if "PERIPHERY" in tags or "DEEP_PERIPHERY" in tags:
		out.append("Periphery")
	if "IS" in tags or "MERC" in tags:
		out.append("IS")
	if "CLAN" in tags:
		out.append("CLAN")
	out.append("General")
	return out


static func _rating(avail: Dictionary, chain: Array) -> float:
	for k in chain:
		if avail.has(k):
			return float(avail[k])
	return -1.0


static func _lib() -> Dictionary:
	if _cache.has("_lib"):
		return _cache["_lib"]
	var lib := {}
	for e in GameData.db().get_library():
		lib[e["id"]] = e
	for e in GameData.db().get_vehicle_library():
		lib[e["id"]] = e
	for e in GameData.db().get_infantry_library():
		lib[e["id"]] = e
	_cache["_lib"] = lib
	return lib


## [[design id, weight]] for a faction, year and kind ("mech", "vehicle" or "vtol").
static func table(faction: String, year: int, kind: String) -> Array:
	var era := era_for(year)
	var key := "%s|%s|%s|%d" % [era, faction, kind, year]
	if _cache.has(key):
		return _cache[key]
	var chain := lookup_chain(faction)
	var lib := _lib()
	var out: Array = []
	var vdb := GameData.db().vehicle_by_id
	for ch in GameData.db().merc()["force"][era]:
		var t: String = ch["type"]
		if kind == "mech" and t != "mech":
			continue
		if kind != "mech" and t != "vehicle":
			continue
		var cr := _rating(ch["avail"], chain)
		if cr <= 0.0:
			continue
		var models: Array = []
		var mtot := 0.0
		for mo in ch["models"]:
			var id: String = mo["id"]
			if not lib.has(id) or int(lib[id].get("year", 3000)) > year or not bool(lib[id].get("armed", true)) or bool(lib[id].get("transport", false)):
				continue
			var non_combat := false
			for r in str(mo.get("roles", "")).split(","):
				if r.strip_edges() in NON_COMBAT:
					non_combat = true
			if non_combat:
				continue
			if kind != "mech":
				var is_vtol: bool = str(vdb.get(id, {}).get("motion", "")) == "vtol"
				if (kind == "vtol") != is_vtol:
					continue
			var mr := _rating(mo["avail"], chain)
			if mr <= 0.0:
				mr = 1.0
			var mw := pow(2.0, mr / 2.0)
			models.append([id, mw])
			mtot += mw
		if models.is_empty():
			continue
		var cw := pow(2.0, cr / 2.0)
		for mm in models:
			out.append([mm[0], cw * float(mm[1]) / mtot])
	_cache[key] = out
	return out


static func pick(faction: String, year: int, kind: String, rng: SimRng, tons_min := 0, tons_max := 200) -> String:
	var t := table(faction, year, kind)
	var lib := _lib()
	var ids: Array = []
	var ws: Array = []
	for e in t:
		var tons := int(lib[e[0]]["tons"])
		if tons >= tons_min and tons <= tons_max:
			ids.append(e[0])
			ws.append(float(e[1]))
	if ids.is_empty():
		if tons_min > 0 or tons_max < 200:
			return pick(faction, year, kind, rng)
		if faction != "IS":
			return pick("IS", year, kind, rng)
		return ""
	return ids[rng.weighted_index(ws)]


## An IndustrialMech: loaders, loggers and miners, armed or not. Militias and pirates field them.
static func industrial(id: String) -> bool:
	var d: Dictionary = GameData.db().design_by_id.get(id, {})
	return str(d.get("structure", "")) == "industrial" or str(d.get("cockpit", "")).contains("industrial")


static func bv_of(id: String) -> int:
	return int(_lib().get(id, {}).get("bv", 800))


static func info(id: String) -> Dictionary:
	return _lib().get(id, {})


## A force worth about `bv` for a faction: a mix of 'Mechs and vehicles by the faction's kind,
## weight classes leaning on `weights` [light, medium, heavy, assault]. Returns design ids.
static func force(faction: String, year: int, bv: int, rng: SimRng, opts := {}) -> Array:
	var sm := StarMap.get_map()
	var rules: Dictionary = GameData.db().merc()["rules"]["operations"]
	var kind := sm.faction_kind(faction)
	var mshare := float(opts.get("mech_share", rules["mech_share"].get(kind, rules["mech_share"]["DEFAULT"])))
	var vtol := float(rules["vtol_share"])
	var max_units := int(opts.get("max_units", 12))
	var out: Array = []
	var total := 0
	var tries := 0
	while total < bv * 0.92 and out.size() < max_units and tries < 60:
		tries += 1
		var r := rng.randf()
		var k := "mech" if r < mshare else ("vtol" if r < mshare + vtol * (1.0 - mshare) else "vehicle")
		var left := bv - total
		# don't overshoot: aim the next unit at what's left of the budget
		var id := ""
		for attempt in 6:
			var cand := pick(faction, year, k, rng, int(opts.get("tons_min", 0)), int(opts.get("tons_max", 200)))
			if cand == "":
				break
			if opts.get("combat_only", false) and industrial(cand) and attempt < 5:
				continue
			var cb := bv_of(cand)
			if cb <= left * 1.25 + 150 or attempt == 5:
				id = cand
				break
		if id == "":
			continue
		var b := bv_of(id)
		if total > 0 and b > left * 1.6 + 200:
			break
		out.append(id)
		total += b
	if out.is_empty():
		var fb := pick(faction, year, "mech", rng)
		if fb != "":
			out.append(fb)
	return out


## Infantry platoons and battle armour squads worth about `bv` for a faction and year (data/infantry.json).
## Clans field Elementals and nothing else; the Inner Sphere gets battle armour from 3052 on; pirates
## never do. opts: "max_units", "mobile_only" (no foot platoons: the force has to cross the field).
static func infantry(faction: String, year: int, bv: int, rng: SimRng, opts := {}) -> Array:
	var I: Dictionary = GameData.db().merc()["rules"]["operations"]["infantry"]
	var kind := StarMap.get_map().faction_kind(faction)
	var clan := kind == "CLAN"
	var ba_ok := clan or (kind != "PIRATE" and year >= int(I["ba_from_year"]))
	var plat: Array = []
	var suits: Array = []
	for e in GameData.db().get_infantry_library():
		if int(e["year"]) > year or (str(e["tech"]) == "Clan") != clan:
			continue
		if bool(e["battle_armor"]):
			suits.append(e)
		elif not opts.get("mobile_only", false) or int(e["cruise"]) >= 3:
			plat.append(e)
	if clan:
		plat = []
	if not ba_ok:
		suits = []
	var out: Array = []
	var total := 0
	var tries := 0
	var max_units := int(opts.get("max_units", I["max_units"]))
	while total < bv * 0.85 and out.size() < max_units and tries < 30:
		tries += 1
		var pool := suits if (plat.is_empty() or (not suits.is_empty() and rng.chance(float(I["ba_chance"])))) else plat
		if pool.is_empty():
			break
		var e2: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
		if not out.is_empty() and int(e2["bv"]) > (bv - total) * 1.5 + 40:
			continue
		out.append(str(e2["id"]))
		total += int(e2["bv"])
	return out
