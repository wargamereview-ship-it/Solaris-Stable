class_name VehicleDesign
extends MechDesign
## A combat vehicle design: tracked, wheeled, hover or VTOL.
## Extends MechDesign so the fight engine and the UI can hold 'Mechs and vehicles in the same slots;
## the 'Mech-only fields (slots, gyro, cockpit) stay empty. `walk` is the vehicle's Cruising MP.
## Locations: FR front, RS right side, LS left side, RR rear, TU turret (optional), RO rotor (VTOL).
## Equipment: [[item_id, loc]] with loc in FR, RS, LS, RR, TU, BD (body: ammo, sinks, electronics).
##
## The same class carries infantry (vtype "infantry": a platoon, one location "PL" whose structure is
## the head count) and battle armour (vtype "battle_armor": a squad, one location per suit "T1".."T6").
## Those are bought whole from data/infantry.json: fixed BV and cost, weapons in `squad_weapons`.

const VLOCS := ["FR", "RS", "LS", "RR", "TU", "RO"]
const VLOC_NAMES := {"FR": "Front", "RS": "Right Side", "LS": "Left Side", "RR": "Rear", "TU": "Turret",
	"RO": "Rotor", "BD": "Body"}
const MOTIONS := {"tracked": "Tracked", "wheeled": "Wheeled", "hover": "Hover", "vtol": "VTOL"}
const MAX_TONS := {"tracked": 100, "wheeled": 80, "hover": 50, "vtol": 30}
const INF_MOTIONS := {"foot": "Foot", "motorized": "Motorized", "jump": "Jump", "mechanized": "Mechanized"}
## What the arena treats each infantry movement type as.
const INF_MOVER := {"foot": "mech", "jump": "mech", "motorized": "wheeled", "mechanized": "tracked"}

var motion := "tracked"
var vtype := "tank"          # "tank" or "vtol"
var equipment: Array = []    # [[item_id, loc]]
var dead_weight := 0.0       # cargo, infantry bays and other gear with no fight effect
var turret := false
var mul_id := 0
var troopers := 0            # infantry: head count of the platoon or suits in the squad
var suit_armor := 0          # battle armour: armour points per suit
var anti_mech := false       # trained for leg attacks on 'Mechs
var armor_div := 1           # mechanized infantry: casualties divided by this
var squad_weapons: Array = []  # [{name, wtype, s, m, l, per, missiles?, salvos?}]
var fixed_bv := 0
var fixed_cost := 0


static func vfrom_dict(d: Dictionary) -> VehicleDesign:
	var v := VehicleDesign.new()
	v.id = str(d.get("id", ""))
	v.chassis = str(d.get("chassis", ""))
	v.model = str(d.get("model", ""))
	v.tons = int(d.get("tons", 20))
	v.tech = str(d.get("tech", "IS"))
	v.year = int(d.get("year", 3015)) if d.get("year") != null else 3015
	v.role = str(d.get("role", "")) if d.get("role") != null else ""
	v.motion = str(d.get("motion", "tracked"))
	v.vtype = str(d.get("type", "tank"))
	v.walk = int(d.get("cruise", d.get("walk", 1)))
	v.jump = 0
	var eng: Dictionary = d.get("engine", {})
	v.engine_rating = int(eng.get("rating", 0))
	v.engine_type = str(eng.get("type", "fusion"))
	v.armor_type = str(d.get("armor_type", "standard"))
	v.armor = {}
	var a: Dictionary = d.get("armor", {})
	for k in a:
		v.armor[str(k)] = int(a[k])
	v.turret = v.armor.has("TU")
	v.equipment = []
	for e in d.get("equipment", []):
		v.equipment.append([str(e[0]), str(e[1])])
	v.dead_weight = float(d.get("dead_weight", 0.0))
	v.quirks = (d.get("quirks", []) as Array).duplicate()
	v.sprite = str(d.get("sprite", "defaults/default_tracked.png"))
	v.wreck = str(d.get("wreck", "wrecks/default_tank_wreck.png"))
	v.omni = bool(d.get("omni", false))
	v.stock_id = str(d.get("stock_id", d.get("id", "")))
	v.mul_id = int(d.get("mul", 0)) if d.get("mul") != null else 0
	v.hs_count = 0
	v.hs_type = "single"
	v.slots = {}
	v.troopers = int(d.get("troopers", 0))
	v.suit_armor = int(d.get("suit_armor", 0))
	v.anti_mech = bool(d.get("anti_mech", false))
	v.armor_div = maxi(1, int(d.get("armor_div", 1)))
	v.squad_weapons = (d.get("weapons", []) as Array).duplicate(true)
	v.fixed_bv = int(d.get("bv", 0)) if d.get("bv") != null else 0
	v.fixed_cost = int(d.get("cost", 0)) if d.get("cost") != null else 0
	if v.is_infantry():
		v.troopers = clampi(v.troopers, 1, 6 if v.is_battle_armor() else 40)
		v.turret = false
		v.armor = {}
		for loc in v.locs():
			v.armor[loc] = v.suit_armor if v.is_battle_armor() else 0
	return v


static func from_stock_vehicle(stock_id_: String) -> VehicleDesign:
	var d: Dictionary = GameData.db().vehicle_by_id.get(stock_id_, {})
	if d.is_empty():
		return null
	var v := vfrom_dict(d)
	v.stock_id = stock_id_
	return v


## A design dictionary of either kind back into the right class.
static func any_from_dict(d: Dictionary) -> MechDesign:
	if str(d.get("kind", "")) == "vehicle":
		return vfrom_dict(d)
	return MechDesign.from_dict(d)


func to_dict() -> Dictionary:
	var eq: Array = []
	for e in equipment:
		eq.append([e[0], e[1]])
	var out := {
		"id": id, "kind": "vehicle", "chassis": chassis, "model": model, "tons": tons, "tech": tech, "year": year,
		"role": role, "type": vtype, "motion": motion, "cruise": walk,
		"engine": {"rating": engine_rating, "type": engine_type}, "armor_type": armor_type,
		"armor": armor.duplicate(), "equipment": eq, "dead_weight": dead_weight, "turret": turret,
		"quirks": quirks.duplicate(), "sprite": sprite, "wreck": wreck, "omni": omni, "stock_id": stock_id,
		"mul": mul_id,
	}
	if is_infantry():
		out.merge({"troopers": troopers, "suit_armor": suit_armor, "anti_mech": anti_mech, "armor_div": armor_div,
			"weapons": squad_weapons.duplicate(true), "bv": fixed_bv, "cost": fixed_cost})
	return out


func copy() -> MechDesign:
	return VehicleDesign.vfrom_dict(to_dict())


func display_name() -> String:
	return ("%s %s" % [chassis, model]).strip_edges()


func is_vehicle() -> bool:
	return true


func is_vtol() -> bool:
	return motion == "vtol"


func is_infantry() -> bool:
	return vtype == "infantry" or vtype == "battle_armor"


func is_battle_armor() -> bool:
	return vtype == "battle_armor"


func flank_mp() -> int:
	if is_infantry():
		return walk
	return int(ceil(walk * 1.5))


func run_mp() -> int:
	return flank_mp()


func locs() -> Array:
	var out: Array = []
	if is_battle_armor():
		for k in troopers:
			out.append("T%d" % (k + 1))
		return out
	if is_infantry():
		return ["PL"]
	for k in VLOCS:
		if armor.has(k):
			out.append(k)
	return out


func motion_label() -> String:
	if is_infantry():
		return INF_MOTIONS.get(motion, motion.capitalize())
	return MOTIONS.get(motion, motion)


## The arena movement class: infantry on foot go where a 'Mech can, their vehicles where vehicles can.
func mover() -> String:
	if is_infantry():
		return INF_MOVER.get(motion, "mech")
	return motion


static func loc_name(loc: String) -> String:
	if loc == "PL":
		return "Platoon"
	if loc.begins_with("T") and loc.length() == 2 and loc != "TU":
		return "Trooper " + loc.substr(1)
	return VLOC_NAMES.get(loc, loc)


func fusion() -> bool:
	return engine_type in ["fusion", "xl", "light", "compact", "xxl"]


## Crew needed: TechManual combat vehicle crew = ceil(tons / 15), at least 1 (VTOLs need a pilot and gunner).
func crew_size() -> int:
	if is_infantry():
		return 1
	return maxi(2 if motion == "vtol" else 1, int(ceil(tons / 15.0)))
