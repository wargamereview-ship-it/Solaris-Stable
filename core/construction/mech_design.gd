class_name MechDesign
extends RefCounted
## A BattleMech design: chassis choices plus a per-slot loadout.
## Slot strings are item ids from data/game/items.json (suffix "@R" = rear-mounted) or fixed
## structural tags: shoulder, upper_arm, lower_arm, hand, hip, upper_leg, lower_leg, foot,
## life_support, sensors, cockpit, engine, gyro, endo, ferro, tsm. "" is an empty slot.

const LOCS := ["HD", "CT", "LT", "RT", "LA", "RA", "LL", "RL"]
const TORSOS := ["CT", "LT", "RT"]
const REAR := {"CT": "CTR", "LT": "LTR", "RT": "RTR"}
const SLOT_COUNT := {"HD": 6, "CT": 12, "LT": 12, "RT": 12, "LA": 12, "RA": 12, "LL": 6, "RL": 6}
const LOC_NAMES := {"HD": "Head", "CT": "Center Torso", "LT": "Left Torso", "RT": "Right Torso",
	"LA": "Left Arm", "RA": "Right Arm", "LL": "Left Leg", "RL": "Right Leg",
	"CTR": "CT (rear)", "LTR": "LT (rear)", "RTR": "RT (rear)"}
const FIXED := ["shoulder", "upper_arm", "lower_arm", "hand", "hip", "upper_leg", "lower_leg", "foot",
	"life_support", "sensors", "cockpit", "engine", "gyro"]
const FILLERS := ["endo", "ferro", "tsm"]

var id := ""
var chassis := ""
var model := ""
var nickname := ""
var tons := 20
var tech := "IS"
var year := 3015
var role := ""
var bv_ref := 0
var engine_rating := 0
var engine_type := "standard"
var structure := "standard"
var armor_type := "standard"
var gyro := "standard"
var cockpit := "standard"
var myomer := "standard"
var hs_count := 10
var hs_type := "single"
var walk := 1
var jump := 0
var armor: Dictionary = {}
var slots: Dictionary = {}
var quirks: Array = []
var sprite := ""
var wreck := ""
var omni := false
var stock_id := ""


static func from_dict(d: Dictionary) -> MechDesign:
	var m := MechDesign.new()
	m.id = str(d.get("id", ""))
	m.chassis = str(d.get("chassis", ""))
	m.model = str(d.get("model", ""))
	m.nickname = str(d.get("nickname", ""))
	m.tons = int(d.get("tons", 20))
	m.tech = str(d.get("tech", "IS"))
	m.year = int(d.get("year", 3015)) if d.get("year") != null else 3015
	m.role = str(d.get("role", "")) if d.get("role") != null else ""
	m.bv_ref = int(d.get("bv", 0)) if d.get("bv") != null else 0
	var eng: Dictionary = d.get("engine", {})
	m.engine_rating = int(eng.get("rating", 0))
	m.engine_type = str(eng.get("type", "standard"))
	m.structure = str(d.get("structure", "standard"))
	m.armor_type = str(d.get("armor_type", "standard"))
	m.gyro = str(d.get("gyro", "standard"))
	m.cockpit = str(d.get("cockpit", "standard"))
	m.myomer = str(d.get("myomer", "standard"))
	var hs: Dictionary = d.get("hs", {})
	m.hs_count = int(hs.get("count", 10))
	m.hs_type = str(hs.get("type", "single"))
	m.walk = int(d.get("walk", 1))
	m.jump = int(d.get("jump", 0))
	m.armor = {}
	var a: Dictionary = d.get("armor", {})
	for loc in LOCS:
		m.armor[loc] = int(a.get(loc, 0))
	for loc in REAR:
		m.armor[REAR[loc]] = int(a.get(REAR[loc], 0))
	m.slots = {}
	var s: Dictionary = d.get("slots", {})
	for loc in LOCS:
		var row: Array = []
		var src: Array = s.get(loc, [])
		for i in SLOT_COUNT[loc]:
			row.append(str(src[i]) if i < src.size() else "")
		m.slots[loc] = row
	m.quirks = (d.get("quirks", []) as Array).duplicate()
	m.sprite = str(d.get("sprite", ""))
	m.wreck = str(d.get("wreck", ""))
	m.omni = bool(d.get("omni", false))
	m.stock_id = str(d.get("stock_id", d.get("id", "")))
	return m


static func from_stock(stock_id_: String) -> MechDesign:
	var d: Dictionary = GameData.db().design_by_id.get(stock_id_, {})
	if d.is_empty():
		return null
	var m := from_dict(d)
	m.stock_id = stock_id_
	return m


func to_dict() -> Dictionary:
	var s := {}
	for loc in LOCS:
		s[loc] = (slots[loc] as Array).duplicate()
	return {
		"id": id, "chassis": chassis, "model": model, "nickname": nickname, "tons": tons, "tech": tech,
		"year": year, "role": role, "bv": bv_ref,
		"engine": {"rating": engine_rating, "type": engine_type},
		"structure": structure, "armor_type": armor_type, "gyro": gyro, "cockpit": cockpit, "myomer": myomer,
		"hs": {"count": hs_count, "type": hs_type}, "walk": walk, "jump": jump,
		"armor": armor.duplicate(), "slots": s, "quirks": quirks.duplicate(), "sprite": sprite, "wreck": wreck,
		"omni": omni, "stock_id": stock_id,
	}


func copy() -> MechDesign:
	return MechDesign.from_dict(to_dict())


func display_name() -> String:
	return "%s %s" % [chassis, model]


func is_vehicle() -> bool:
	return false


func is_vtol() -> bool:
	return false


## Infantry platoons and battle armour squads (VehicleDesign answers these).
func is_infantry() -> bool:
	return false


func is_battle_armor() -> bool:
	return false


func run_mp() -> int:
	return int(ceil(walk * 1.5))


func weight_class() -> String:
	return GameData.db().weight_class(tons)


static func base_id(slot: String) -> String:
	var at := slot.find("@")
	return slot if at < 0 else slot.substr(0, at)


static func is_rear(slot: String) -> bool:
	return slot.ends_with("@R")


static func is_fixed(slot: String) -> bool:
	return slot in FIXED or slot in FILLERS


func armor_total() -> int:
	var t := 0
	for k in armor:
		t += int(armor[k])
	return t


## Lays out a blank chassis with fixed components in the MegaMek slot order, all other slots empty.
static func blank(tons_: int, walk_: int) -> MechDesign:
	var m := MechDesign.new()
	m.tons = tons_
	m.walk = walk_
	m.engine_rating = tons_ * walk_
	m.chassis = "Custom"
	m.model = "C-%d" % tons_
	for loc in LOCS:
		var row: Array = []
		row.resize(SLOT_COUNT[loc])
		row.fill("")
		m.slots[loc] = row
	for loc in LOCS:
		m.armor[loc] = 0
	for loc in REAR:
		m.armor[REAR[loc]] = 0
	m.apply_fixed_layout()
	var d := GameData.db()
	m.sprite = "defaults/default_%s.png" % d.weight_class(tons_)
	m.wreck = "wrecks/default_mech_wreck.png"
	return m


## Rewrites the fixed slots (cockpit, engine, gyro, actuators) for the current engine, gyro and cockpit,
## keeping equipment where it still fits. Returns items that no longer fit.
func apply_fixed_layout(keep_lower_arms := {"LA": true, "RA": true}, keep_hands := {"LA": true, "RA": true}) -> Array:
	var displaced: Array = []
	var equipment := {}
	for loc in LOCS:
		var eq: Array = []
		for s in slots[loc]:
			if s != "" and not is_fixed(s):
				eq.append(s)
		equipment[loc] = eq
	var fresh := {}
	for loc in LOCS:
		var row: Array = []
		row.resize(SLOT_COUNT[loc])
		row.fill("")
		fresh[loc] = row
	# Head
	if cockpit == "torso":
		fresh["HD"] = ["sensors", "sensors", "", "", "", ""]
	elif cockpit in ["interface", "command_console"]:
		fresh["HD"] = ["life_support", "sensors", "cockpit", "cockpit", "sensors", "life_support"]
	elif cockpit == "small":
		fresh["HD"] = ["life_support", "sensors", "cockpit", "sensors", "", ""]
	else:
		fresh["HD"] = ["life_support", "sensors", "cockpit", "", "sensors", "life_support"]
	# Center torso: engine 3, gyro N, engine 3 (compact engine = 3 total)
	var ct: Array = fresh["CT"]
	var gy_n := Construction.gyro_slots(gyro)
	var i := 0
	var eng_ct := 3 if engine_type == "compact" else 6
	for k in mini(3, eng_ct):
		ct[i] = "engine"; i += 1
	for k in gy_n:
		ct[i] = "gyro"; i += 1
	for k in eng_ct - 3:
		ct[i] = "engine"; i += 1
	if cockpit == "torso":
		ct[i] = "cockpit"; i += 1
		ct[i] = "life_support"; i += 1
	var side := side_engine_slots()
	for loc in ["LT", "RT"]:
		for k in side:
			fresh[loc][k] = "engine"
	for loc in ["LA", "RA"]:
		fresh[loc][0] = "shoulder"
		fresh[loc][1] = "upper_arm"
		if keep_lower_arms.get(loc, true):
			fresh[loc][2] = "lower_arm"
			if keep_hands.get(loc, true):
				fresh[loc][3] = "hand"
	for loc in ["LL", "RL"]:
		fresh[loc][0] = "hip"
		fresh[loc][1] = "upper_leg"
		fresh[loc][2] = "lower_leg"
		fresh[loc][3] = "foot"
	slots = fresh
	for loc in LOCS:
		for s in equipment[loc]:
			if not place(loc, s, 1, true):
				displaced.append(s)
	return displaced


func side_engine_slots() -> int:
	match engine_type:
		"xl":
			return 3
		"xl_clan", "light":
			return 2
		"xxl":
			return 6
		"xxl_clan":
			return 4
	return 0


## Places `count` copies of a slot string in the first free slots of a location.
## With contiguous=true all copies must fit in one run (used for multi-slot items).
func place(loc: String, slot: String, count: int, contiguous := true) -> bool:
	var row: Array = slots[loc]
	if contiguous:
		for start in row.size() - count + 1:
			var ok := true
			for k in count:
				if row[start + k] != "":
					ok = false
					break
			if ok:
				for k in count:
					row[start + k] = slot
				return true
		return false
	var free := 0
	for s in row:
		if s == "":
			free += 1
	if free < count:
		return false
	var left := count
	for k in row.size():
		if left == 0:
			break
		if row[k] == "":
			row[k] = slot
			left -= 1
	return true


func free_slots(loc: String) -> int:
	var n := 0
	for s in slots[loc]:
		if s == "":
			n += 1
	return n


## Removes the mount that occupies slot index `idx` (the whole multi-slot run). Returns its slot string.
func remove_at(loc: String, idx: int, crits: int) -> String:
	var row: Array = slots[loc]
	var s: String = row[idx]
	if s == "" or s in FIXED:
		return ""
	# find the run containing idx, aligned to crits-sized chunks
	var start := idx
	while start > 0 and row[start - 1] == s:
		start -= 1
	var offset := (idx - start) / maxi(1, crits) * maxi(1, crits)
	var first := start + offset
	var n := 0
	for k in range(first, row.size()):
		if row[k] != s or n >= maxi(1, crits):
			break
		row[k] = ""
		n += 1
	return s
