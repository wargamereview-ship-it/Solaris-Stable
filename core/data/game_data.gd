class_name GameData
extends RefCounted
## All static game data, loaded once from res://data. Use GameData.db().
## Every rules number lives in JSON so it can be checked against the rulebooks.

const LOCS := ["HD", "CT", "LT", "RT", "LA", "RA", "LL", "RL"]

static var _inst: GameData

var construction: Dictionary = {}
var components: Dictionary = {}
var items: Dictionary = {}
var canonical: Dictionary = {}
var designs: Array = []
var design_by_id: Dictionary = {}
var factions: Dictionary = {}
var eras: Array = []
var tables: Dictionary = {}
var rules: Dictionary = {}
var arenas: Dictionary = {}
var events: Array = []
var names: Dictionary = {}

var vehicles: Array = []
var vehicle_by_id: Dictionary = {}
var _vehicle_library: Array = []
var infantry: Array = []          # platoons and battle armour squads (data/infantry.json)
var _infantry_library: Array = []
var _merc: Dictionary = {}        # lazily loaded merc-mode data (systems, factions, force tables, rules)

var std_engine: Dictionary = {}   # int rating -> float tons
var is_points: Dictionary = {}    # int tonnage -> {loc: int}
var library: Array = []           # stock design ids that pass the validator exactly


static func db() -> GameData:
	if _inst == null:
		_inst = GameData.new()
		_inst._load()
	return _inst


static func read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("GameData: cannot open %s" % path)
		return null
	var v: Variant = JSON.parse_string(f.get_as_text())
	if v == null:
		push_error("GameData: bad JSON in %s" % path)
	return v


func _load() -> void:
	construction = read_json("res://data/construction.json")
	components = read_json("res://data/game/components.json")
	var it: Dictionary = read_json("res://data/game/items.json")
	items = it["items"]
	canonical = it["canonical"]
	var ds: Dictionary = read_json("res://data/game/designs.json")
	designs = ds["designs"]
	for d in designs:
		design_by_id[d["id"]] = d
	var fx: Dictionary = read_json("res://data/game/factions.json")
	factions = fx["factions"]
	eras = fx["eras"]
	var vs: Dictionary = read_json("res://data/game/vehicles.json")
	vehicles = vs["vehicles"]
	for v in vehicles:
		vehicle_by_id[v["id"]] = v
	# Infantry share the vehicle id table (so any id resolves to a design) but stay out of `vehicles`:
	# they are not built in the workshop and the vehicle force tables never roll them.
	infantry = (read_json("res://data/infantry.json") as Dictionary).get("units", [])
	for u in infantry:
		vehicle_by_id[u["id"]] = u
	tables = read_json("res://data/combat_tables.json")
	rules = read_json("res://data/rules.json")
	arenas = read_json("res://data/arenas.json")
	events = _load_events()
	names = read_json("res://data/names.json")
	var eng: Dictionary = construction["engine"]["standard_weight_by_rating"]
	for k in eng:
		std_engine[int(k)] = float(eng[k])
	var pts: Dictionary = construction["internal_structure"]["points_by_tonnage"]
	for k in pts:
		var row := {}
		for loc in pts[k]:
			row[loc] = int(pts[k][loc])
		is_points[int(k)] = row


func item(id: String) -> Dictionary:
	return items.get(id, {})


var _used_items: Dictionary = {}


## Item ids mounted on at least one library design: the equipment the bay designer offers.
func used_items() -> Dictionary:
	if not _used_items.is_empty():
		return _used_items
	for e in get_library():
		var d: Dictionary = design_by_id[e["id"]]
		for loc in d["slots"]:
			for s in d["slots"][loc]:
				if s != "":
					_used_items[MechDesign.base_id(str(s))] = true
	return _used_items


## Stock designs that rebuild exactly under the construction rules (the game's design library).
## Each entry: {"id", "tons", "tech", "cost", "bv", "role", "year", "avail"}.
func get_library() -> Array:
	if not library.is_empty():
		return library
	for d in designs:
		var md := MechDesign.from_dict(d)
		var r := Construction.analyze(md)
		if not r.get("valid", false) or absf(float(r["tons_used"]) - md.tons) > 0.01:
			continue
		library.append({"id": md.id, "tons": md.tons, "tech": md.tech, "cost": r["cost"], "bv": r["bv"],
			"role": md.role, "year": md.year, "avail": d.get("avail", {}), "chassis": md.chassis})
	return library


## Stock vehicles that pass the vehicle construction check with their exact tonnage.
## Each entry: {"id", "tons", "tech", "cost", "bv", "role", "year", "motion", "chassis"}.
func get_vehicle_library() -> Array:
	if not _vehicle_library.is_empty():
		return _vehicle_library
	for v in vehicles:
		var vd := VehicleDesign.vfrom_dict(v)
		var r := VehicleConstruction.analyze(vd)
		if not r.get("valid", false) or absf(float(r["tons_used"]) - vd.tons) > 0.01:
			continue
		var armed := false
		for mt in r["mounts"]:
			if mt["item"].get("kind", "") == "weapon" and not (mt["item"].get("wtype", "") in ["ams", "tag", "other"]):
				armed = true
		_vehicle_library.append({"id": vd.id, "tons": vd.tons, "tech": vd.tech, "cost": r["cost"], "bv": r["bv"],
			"role": vd.role, "year": vd.year, "motion": vd.motion, "chassis": vd.chassis, "kind": "vehicle", "armed": armed,
			"transport": vd.dead_weight >= vd.tons * 0.2})
	return _vehicle_library


## Infantry platoons and battle armour squads: {"id", "tons", "tech", "cost", "bv", "role", "year",
## "motion", "chassis", "kind": "vehicle", "infantry": true, "battle_armor", "cruise"}.
func get_infantry_library() -> Array:
	if not _infantry_library.is_empty():
		return _infantry_library
	for u in infantry:
		var d := VehicleDesign.vfrom_dict(u)
		_infantry_library.append({"id": d.id, "tons": d.tons, "tech": d.tech, "cost": d.fixed_cost, "bv": d.fixed_bv,
			"role": d.role, "year": d.year, "motion": d.motion, "chassis": d.chassis, "kind": "vehicle", "armed": true,
			"transport": false, "infantry": true, "battle_armor": d.is_battle_armor(), "cruise": d.walk})
	return _infantry_library


## Any stock design by id, 'Mech or vehicle.
func stock_design(id: String) -> MechDesign:
	if vehicle_by_id.has(id):
		return VehicleDesign.from_stock_vehicle(id)
	return MechDesign.from_stock(id)


## Merc-mode data, loaded on first use: "systems", "factions", "relations", "force", "rules".
func merc() -> Dictionary:
	if not _merc.is_empty():
		return _merc
	var sy: Dictionary = read_json("res://data/game/systems.json")
	var fx: Dictionary = read_json("res://data/game/merc_factions.json")
	var ft: Dictionary = read_json("res://data/game/force_tables.json")
	_merc = {"systems": sy["systems"], "factions": fx["factions"], "relations": fx["relations"],
		"force": ft["eras"], "rules": read_json("res://data/merc_rules.json")}
	return _merc


## Inner Sphere market availability of an item (or component dict) in a given year.
static func dates_allow(d: Dictionary, year: int) -> bool:
	if d.is_empty():
		return false
	if d.get("clan_only", false) or d.get("tech", "") == "CLAN":
		return false
	var intro = d.get("intro")
	if intro == null or int(intro) > year:
		return false
	var ext = d.get("extinct")
	if ext != null and int(ext) <= year:
		var re = d.get("reintro")
		if re == null or int(re) > year:
			return false
	return true


func item_available(id: String, year: int) -> bool:
	return dates_allow(item(id), year)


func component_available(kind: String, key: String, year: int) -> bool:
	return dates_allow(components.get(kind, {}).get(key, {}), year)


## Index into the A-F availability letters: SL, SW, CI, DA.
static func era_column(year: int) -> int:
	if year < 2781:
		return 0
	if year < 3050:
		return 1
	if year < 3062:
		return 2
	return 3


## MUL era id used for faction availability lists.
static func mul_era(year: int) -> String:
	if year <= 3019:
		return "11"
	if year <= 3049:
		return "12"
	if year <= 3061:
		return "4"
	if year <= 3067:
		return "8"
	if year <= 3080:
		return "5"
	if year <= 3100:
		return "6"
	if year <= 3130:
		return "10"
	if year <= 3150:
		return "7"
	return "13"


func weight_class(tons: int) -> String:
	if tons < 40:
		return "light"
	if tons < 60:
		return "medium"
	if tons < 80:
		return "heavy"
	return "assault"


## The timeline (data/era_events.json), oldest first. Each event's "date" is split into year, month and
## day; "week" is its week of the stable game's 52-week year, and "effects" its stable-game effects.
func _load_events() -> Array:
	var out: Array = (read_json("res://data/era_events.json") as Dictionary)["events"]
	var before := [0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
	for e0 in out:
		var e: Dictionary = e0
		var p := str(e["date"]).split("-")
		e["year"] = int(p[0])
		e["month"] = clampi(int(p[1]), 1, 12)
		e["day"] = clampi(int(p[2]), 1, 31)
		e["week"] = clampi((int(before[int(e["month"]) - 1]) + int(e["day"]) - 1) / 7 + 1, 1, 52)
		e["effects"] = e.get("stable", {})
	out.sort_custom(func(a, b): return str(a["date"]) < str(b["date"]))
	return out
