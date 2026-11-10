class_name CombatMech
extends RefCounted
## Runtime state of one unit in a fight: position, heat, armor, crits, pilot.
## Combat vehicles use the same class (is_vehicle): no heat, no falls; Total Warfare motive damage,
## vehicle critical hits and a turret instead of a torso twist.

enum Gait { STAND, WALK, RUN, JUMP, PRONE, SHUTDOWN, OUT }

const TRAITS := {
	"hot_blooded": "Runs hot and closes in. Ignores heat discipline.",
	"cool_under_fire": "Only takes good shots; steadier when hurt.",
	"showboat": "Loves close range and physical attacks. The crowd loves them.",
	"iron_man": "Fights on long after others would yield.",
	"sharpshooter": "Long-range shots are easier.",
	"brawler": "Better at punches and kicks.",
	"jump_jockey": "Uses jump jets well and often.",
	"cautious": "Yields early and prefers cover.",
	"lucky": "Rerolls one failed piloting or consciousness roll per fight.",
}

var index := 0
var team := 0
var name := ""
var design: MechDesign
var warrior: Dictionary = {}
var orders: Dictionary = {}
var traits: Array = []
var gunnery := 4
var piloting := 5
var quirks: Dictionary = {}

# kinematics (meters, radians: 0 = east, clockwise on screen)
var pos := Vector2.ZERO
var facing := 0.0
var twist := 0.0
var gait: int = Gait.STAND
var move_mode: int = Gait.WALK   # requested by AI
var path := PackedVector2Array()
var goal := Vector2.ZERO
var backing := false
var jump_from := Vector2.ZERO
var jump_to := Vector2.ZERO
var jump_t := 0.0
var jump_dur := 0.0
var jump_ready_at := 0.0
var last_walk_t := -100.0
var last_run_t := -100.0
var last_jump_t := -100.0
var trail: Array = []   # [t, pos] samples for target movement modifier
var prone_since := 0.0
var stand_attempt_at := 0.0

# combat state
var heat := 0.0
var armor: Dictionary = {}
var internal: Dictionary = {}
var max_armor: Dictionary = {}
var max_internal: Dictionary = {}
var loc_destroyed: Dictionary = {}
var slots: Dictionary = {}   # loc -> Array of {"s": String, "hit": bool, "m": mount index}
var mounts: Array = []       # from Construction; plus runtime fields
var weapons: Array = []      # mount indices
var bins: Array = []         # mount indices of ammo
var engine_hits := 0
var gyro_hits := 0
var sensor_hits := 0
var life_support_hit := false
var cockpit_hit := false
var sinks_total := 0
var sinks_lost := 0
var double_sinks := false
var jj_lost := 0
var physical_ready_at := 0.0
var dmg_window := 0.0
var dmg_window_psr := false
var pilot_hits := 0
var conscious := true
var lucky_left := 0
var out := false
var out_reason := ""
var shutdown := false
var yielded := false
var ejected := false
var destroyed := false
var has_case: Dictionary = {}
var artemis := false
var tc := false
var has_ams := false
var physical_weapon := ""
var no_arms := false
var masc := false          # has working MASC
var masc_on := false       # sprinting this turn
var masc_used := false     # used at some point this 10 s turn
var masc_level := 0        # index into the MASC failure table
var ecm := false
var c3 := false
var probe := false
var narced: Dictionary = {}   # team -> true when that team's Narc pod sticks to this 'Mech
var munitions: Dictionary = {}  # ammo family -> munition key chosen for the bout
var club_uses := 0
var club_kind := ""
var dfa_target := -1
var out_time := -1.0
var calls_left := 0
var searchlight := false

# what the chassis and its gear do in a fight (numbers in data/combat_tables.json: armor_types,
# structure_types, gear)
var armor_fx: Dictionary = {}     # the armor type's entry of tables["armor_types"]
var struct_soak := 1.0            # damage one point of internal structure takes up
var signatures: Array = []        # stealth armor and signature systems: [{"stealth", "heat", "needs_ecm", "mount"}]
var wing_mount := -1              # partial wing: extra jump and cooling while it is whole
var no_move_heat := false         # combustion and fuel cell engines, super-cooled myomer
var cockpit_to_hit := 0
var aes: Dictionary = {}          # arm -> mount index of its actuator enhancement system
var apollo := false
var blue_shield := false
var talons := false
var always_strong := false        # industrial triple-strength myomer
var pods: Array = []              # mount indices: anti-infantry pods, used once each
var coolers: Array = []           # [{"kind", "mount", "uses"}]: coolant pods and emergency systems
var harjel: Array = []            # [[mount index, points a turn]]
var booby_trap := false
var emp_until := -1.0             # TSEMP or taser interference: worse shooting until then

# combat vehicles
var is_vehicle := false
var motion := ""             # tracked, wheeled, hover, vtol ("" for a 'Mech)
var mover := "mech"          # pathfinding class
var airborne := false        # VTOL in flight
var cruise_lost := 0         # motive damage (-1 Cruising MP) and rotor hits
var cruise_halved := false   # heavy motive damage
var immobile := false        # motive system destroyed (can't move, but not an immobile target)
var engine_dead := false     # engine hit: immobile target, energy weapons dead, turret locked
var motive_levels: Dictionary = {}   # "minor", "moderate", "heavy" (each driving modifier applies once)
var crew_stunned_until := -1.0
var commander_hit := false
var driver_hit := false
var copilot_hit := false
var vpilot_hit := false
var crew_killed := false
var stabilizers: Dictionary = {}     # loc -> true (doubles attacker movement for weapons there)
var turret_jam_until := -1.0
var turret_jams := 0
var turret_locked := false
var vsensors := 0
var flight_stabilizer := false
var vcrit_taken: Dictionary = {}     # loc -> {result: true} for one-per-location results

# infantry platoons and battle armour squads (also is_vehicle: no heat, no falls, no pilot)
var is_infantry := false
var battle_armor := false    # a squad of armoured suits, one location each; otherwise one "PL" head count
var troopers_max := 0
var anti_mech := false       # may make leg attacks
var armor_div := 1           # mechanized: casualties divided by this
var snap_locs: Array = []    # the locations a vehicle or squad writes into a snapshot, in order

# merc battles
var exited := ""             # edge the unit left the map by
var withdrew := false
var reserve_t := -1.0        # reinforcements: seconds until arrival (>= 0 while waiting)
var spawn_pos := Vector2.ZERO
var spotted := false         # seen by the player's side (team 0) at the last spotting check
var seen_pos := Vector2.ZERO
var seen_t := -100.0
var controller := "ai"       # "player" for units the player commands

# stats
var dmg_dealt := 0
var dmg_taken := 0
var shots := 0
var hits := 0
var crits_dealt := 0
var kills := 0
var killer := -1
var showmanship := 0.0


static func create(d: MechDesign, w: Dictionary, ord: Dictionary, team_: int, idx: int, condition := {}) -> CombatMech:
	var m := CombatMech.new()
	m.index = idx
	m.team = team_
	m.design = d
	m.warrior = w
	m.orders = ord
	m.traits = (w.get("traits", []) as Array).duplicate()
	m.gunnery = int(w.get("gunnery", 4))
	m.piloting = int(w.get("piloting", 5))
	m.name = str(w.get("callsign", w.get("name", d.display_name())))
	m.lucky_left = 1 if "lucky" in m.traits else 0
	for q in d.quirks:
		m.quirks[q] = true
	var rep := Construction.analyze(d)
	var ipts := Construction.internal_points(d.tons)
	for loc in MechDesign.LOCS:
		m.internal[loc] = int(ipts.get(loc, 0))
		m.max_internal[loc] = m.internal[loc]
		m.loc_destroyed[loc] = false
	for k in d.armor:
		m.armor[k] = int(d.armor[k])
		m.max_armor[k] = m.armor[k]
	for loc in MechDesign.LOCS:
		var row: Array = []
		for s in d.slots[loc]:
			row.append({"s": s, "hit": false, "m": -1})
		m.slots[loc] = row
	m.mounts = []
	var db := GameData.db()
	for mt in rep.get("mounts", []):
		var it := db.item(mt["id"])
		var e := {"id": mt["id"], "loc": mt["loc"], "rear": mt["rear"], "slots": mt["slots"], "item": it,
			"kind": it.get("kind", ""), "destroyed": false, "cooldown": 0.0, "shots": int(it.get("shots", 0)),
			"jammed": false}
		var mi := m.mounts.size()
		m.mounts.append(e)
		for sl in mt["slots"]:
			m.slots[sl[0]][sl[1]]["m"] = mi
		match e["kind"]:
			"weapon":
				if it.get("wtype", "") == "ams":
					m.has_ams = true
				m.weapons.append(mi)
			"ammo":
				m.bins.append(mi)
			"misc":
				match it.get("misc", ""):
					"artemis":
						m.artemis = true
					"tc":
						m.tc = true
					"hatchet", "sword", "mace":
						m.physical_weapon = it["misc"]
					"masc":
						m.masc = true
					"ecm":
						m.ecm = true
						if str(it.get("name", "")).contains("Electronic Warfare"):
							m.probe = true          # the combined suites probe as well as jam
					"c3":
						m.c3 = true
					"probe":
						m.probe = true
		if it.get("c3", false):
			m.c3 = true
	for mi2 in m.mounts.size():
		m._gear_setup(mi2, db.tables)
	m._chassis_setup(db.tables)
	m.searchlight = m.quirks.has("searchlight")
	# ammunition choices for this bout: {"srm": "inferno", "lbx": "lbx_cluster", ...}
	var ammo_orders: Dictionary = ord.get("ammo", {})
	var mun: Dictionary = GameData.db().tables.get("munitions", {})
	for fam in ammo_orders:
		var key: String = ammo_orders[fam]
		if mun.has(key) and key != "standard":
			m.munitions[fam] = key
	for bi in m.bins:
		var b: Dictionary = m.mounts[bi]
		var fam2 := ammo_family(str(b["item"].get("ammo", "")))
		if m.munitions.has(fam2):
			var mult := float(mun[m.munitions[fam2]].get("shots_mult", 1.0))
			b["shots"] = maxi(1, int(int(b["shots"]) * mult))
	m.has_case = rep.get("case", {})
	m.double_sinks = float(Construction.HS_SHED.get(d.hs_type, 1.0)) >= 2.0
	m.sinks_total = d.hs_count
	m.no_arms = m.quirks.has("no_arms")
	m.heat = 0.0
	if not condition.is_empty():
		m.apply_condition(condition)
	return m


## Either kind of unit from its design.
static func create_any(d: MechDesign, w: Dictionary, ord: Dictionary, team_: int, idx: int, condition := {}) -> CombatMech:
	if d.is_vehicle():
		return create_vehicle(d as VehicleDesign, w, ord, team_, idx, condition)
	return create(d, w, ord, team_, idx, condition)


static func create_vehicle(d: VehicleDesign, w: Dictionary, ord: Dictionary, team_: int, idx: int, condition := {}) -> CombatMech:
	var m := CombatMech.new()
	m.index = idx
	m.team = team_
	m.design = d
	m.is_vehicle = true
	m.motion = d.motion
	m.mover = d.mover()
	m.snap_locs = VehicleDesign.VLOCS
	if d.is_infantry():
		m.is_infantry = true
		m.battle_armor = d.is_battle_armor()
		m.troopers_max = d.troopers
		m.anti_mech = d.anti_mech
		m.armor_div = d.armor_div
		m.snap_locs = d.locs()
	m.airborne = d.motion == "vtol"
	m.warrior = w
	m.orders = ord
	m.traits = (w.get("traits", []) as Array).duplicate()
	m.gunnery = int(w.get("gunnery", 4))
	m.piloting = int(w.get("piloting", w.get("driving", 5)))
	m.name = str(w.get("callsign", w.get("name", d.display_name())))
	for q in d.quirks:
		m.quirks[q] = true
	var ipts := VehicleConstruction.internal_points(d)
	for loc in d.locs():
		m.internal[loc] = int(ipts[loc])
		m.max_internal[loc] = m.internal[loc]
		m.loc_destroyed[loc] = false
		m.armor[loc] = int(d.armor.get(loc, 0))
		m.max_armor[loc] = m.armor[loc]
		m.slots[loc] = []
	m.loc_destroyed["BD"] = false
	m.slots["BD"] = []
	for mt in VehicleConstruction.mounts_of(d):
		var it: Dictionary = mt["item"]
		var e := {"id": mt["id"], "loc": mt["loc"], "rear": mt["loc"] == "RR", "slots": [], "item": it,
			"kind": it.get("kind", ""), "destroyed": false, "cooldown": 0.0, "shots": int(it.get("shots", 0)),
			"jammed": false, "malf_until": -1.0}
		var mi := m.mounts.size()
		m.mounts.append(e)
		match e["kind"]:
			"weapon":
				if it.get("wtype", "") == "ams":
					m.has_ams = true
				m.weapons.append(mi)
			"ammo":
				m.bins.append(mi)
			"misc":
				match it.get("misc", ""):
					"artemis":
						m.artemis = true
					"tc":
						m.tc = true
					"ecm":
						m.ecm = true
					"c3":
						m.c3 = true
					"probe":
						m.probe = true
					"case":
						m.has_case[mt["loc"]] = true
		if it.get("c3", false):
			m.c3 = true
	m._chassis_setup(GameData.db().tables)
	m.no_move_heat = false
	m.cockpit_to_hit = 0
	m.searchlight = m.quirks.has("searchlight")
	var ammo_orders: Dictionary = ord.get("ammo", {})
	var mun: Dictionary = GameData.db().tables.get("munitions", {})
	for fam in ammo_orders:
		var key: String = ammo_orders[fam]
		if mun.has(key) and key != "standard":
			m.munitions[fam] = key
	m.no_arms = true
	if not condition.is_empty():
		m.apply_vehicle_condition(condition)
	if m.is_infantry:
		m.refresh_squad()
	return m


## Living troopers of a platoon or suits of a battle armour squad.
func troopers_alive() -> int:
	if not is_infantry:
		return 0
	if not battle_armor:
		return maxi(0, int(internal.get("PL", 0)))
	var n := 0
	for loc in snap_locs:
		if not loc_destroyed[loc]:
			n += 1
	return n


## A squad's weapons hit as hard as the troopers left to fire them.
func refresh_squad() -> void:
	var alive := troopers_alive()
	for wi in weapons:
		var it: Dictionary = mounts[wi]["item"]
		if it.get("squad", false):
			it["dmg"] = maxi(1, int(ceil(alive * float(it.get("per", 0.27)))))


## Campaign damage for a vehicle: {"armor", "internal", "dead_mounts": [mount index], "ammo": {mi: shots},
## "vstate": {cruise_lost, cruise_halved, immobile, engine_dead, turret_locked, vsensors, stabilizers}}
func apply_vehicle_condition(c: Dictionary) -> void:
	var a: Dictionary = c.get("armor", {})
	for k in a:
		if armor.has(k):
			armor[k] = mini(int(a[k]), int(max_armor.get(k, 0)))
	var s: Dictionary = c.get("internal", {})
	for k in s:
		if internal.has(k):
			internal[k] = mini(int(s[k]), int(max_internal.get(k, 0)))
	for mi in c.get("dead_mounts", []):
		if int(mi) >= 0 and int(mi) < mounts.size():
			_destroy_vmount(int(mi))
	var am: Dictionary = c.get("ammo", {})
	for k in am:
		var bi := int(k)
		if bi >= 0 and bi < mounts.size():
			mounts[bi]["shots"] = mini(int(am[k]), int(mounts[bi]["shots"]))
	var vs: Dictionary = c.get("vstate", {})
	cruise_lost = int(vs.get("cruise_lost", 0))
	cruise_halved = bool(vs.get("cruise_halved", false))
	immobile = bool(vs.get("immobile", false))
	engine_dead = bool(vs.get("engine_dead", false))
	turret_locked = bool(vs.get("turret_locked", false))
	vsensors = int(vs.get("vsensors", 0))
	for loc in vs.get("stabilizers", []):
		stabilizers[str(loc)] = true
	if is_infantry:
		for loc in snap_locs:
			if int(internal[loc]) <= 0:
				loc_destroyed[loc] = true
				armor[loc] = 0


func _destroy_vmount(mi: int) -> void:
	var mt: Dictionary = mounts[mi]
	if mt["destroyed"]:
		return
	mt["destroyed"] = true
	var misc: String = mt["item"].get("misc", "")
	match misc:
		"artemis":
			artemis = false
		"tc":
			tc = false
		"ecm":
			ecm = false
		"c3":
			c3 = false
		"probe":
			probe = false
	if mt["item"].get("wtype", "") == "ams":
		has_ams = false


func vehicle_state() -> Dictionary:
	return {"cruise_lost": cruise_lost, "cruise_halved": cruise_halved, "immobile": immobile, "engine_dead": engine_dead,
		"turret_locked": turret_locked, "vsensors": vsensors, "stabilizers": stabilizers.keys(),
		"crew": {"commander": commander_hit, "driver": driver_hit, "copilot": copilot_hit, "pilot": vpilot_hit,
			"killed": crew_killed}}


func crew_stunned(t: float) -> bool:
	return t < crew_stunned_until


## Eye height in meters for line of sight: standing 'Mechs 1.6 levels, prone 0.6, vehicles 0.8,
## hover craft on the water surface, VTOLs at their flight elevation.
func eye_m(arena: Arena) -> float:
	var c := arena.cell_of(pos)
	var i := arena.idx(c.x, c.y)
	if is_vehicle:
		var surface := float(arena.height[i]) * Arena.LEVEL_M
		if airborne:
			return surface + float(GameData.db().tables["vehicle"]["vtol_elevation_levels"]) * Arena.LEVEL_M
		return surface + 0.8 * Arena.LEVEL_M
	var base := arena.ground_m(pos)
	return base + (0.6 if gait == Gait.PRONE else 1.6) * Arena.LEVEL_M


## Carries campaign damage into a fight: {"armor": {}, "internal": {}, "hit_slots": [[loc, i]], "ammo": {mount_index: shots}}
func apply_condition(c: Dictionary) -> void:
	var a: Dictionary = c.get("armor", {})
	for k in a:
		armor[k] = mini(int(a[k]), int(max_armor.get(k, 0)))
	var s: Dictionary = c.get("internal", {})
	for k in s:
		internal[k] = mini(int(s[k]), int(max_internal.get(k, 0)))
		if internal[k] <= 0:
			loc_destroyed[k] = true
	for hs in c.get("hit_slots", []):
		_mark_slot_hit(str(hs[0]), int(hs[1]), false)


func _mark_slot_hit(loc: String, i: int, live := true) -> void:
	var sl: Dictionary = slots[loc][i]
	if sl["hit"]:
		return
	sl["hit"] = true
	var s: String = sl["s"]
	match s:
		"engine":
			engine_hits += 1
		"gyro":
			gyro_hits += 1
		"sensors":
			sensor_hits += 1
		"life_support":
			life_support_hit = true
		"cockpit":
			cockpit_hit = true
	var mi: int = sl["m"]
	if mi >= 0:
		var mt: Dictionary = mounts[mi]
		if not mt["destroyed"]:
			mt["destroyed"] = true
			var misc: String = mt["item"].get("misc", "")
			if Construction.HS_MISC.has(misc):
				sinks_lost += Construction.hs_per_item(mt["item"])
			elif misc in ["jump_jet", "improved_jump_jet"]:
				jj_lost += 1
			elif misc == "artemis":
				artemis = false
			elif misc == "tc":
				tc = false
			elif misc == "masc":
				masc = false
				masc_on = false
			elif misc == "ecm":
				ecm = false
			elif misc == "c3":
				c3 = false
			elif misc == "probe":
				probe = false
			if mt["item"].get("wtype", "") == "ams":
				has_ams = false
			# every slot of the mount is gone
			for other in mt["slots"]:
				slots[other[0]][other[1]]["hit"] = true


func tons() -> int:
	return design.tons


func is_active() -> bool:
	return not out


func can_act() -> bool:
	return not out and not shutdown and conscious


func center_internal_fraction() -> float:
	if is_infantry:
		return float(troopers_alive()) / maxf(1.0, float(troopers_max))
	if is_vehicle:
		var worst := 1.0
		for loc in internal:
			worst = minf(worst, float(internal[loc]) / maxf(1.0, float(max_internal[loc])))
		return worst
	return float(internal["CT"]) / maxf(1.0, float(max_internal["CT"]))


func internal_lost_fraction() -> float:
	var lost := 0.0
	var tot := 0.0
	for loc in (internal.keys() if is_vehicle else MechDesign.LOCS):
		lost += float(max_internal[loc] - maxi(0, internal[loc]))
		tot += float(max_internal[loc])
	return lost / maxf(1.0, tot)


func armor_fraction() -> float:
	var a := 0.0
	var t := 0.0
	for k in max_armor:
		a += float(armor[k])
		t += float(max_armor[k])
	return a / maxf(1.0, t)


func count_hit(loc: String, part: String) -> int:
	if is_vehicle:
		return 0
	var n := 0
	for sl in slots[loc]:
		if sl["s"] == part and sl["hit"]:
			n += 1
	return n


func has_part(loc: String, part: String) -> bool:
	if is_vehicle:
		return false
	if loc_destroyed[loc]:
		return false
	for sl in slots[loc]:
		if sl["s"] == part and not sl["hit"]:
			return true
	return false


func legs_destroyed() -> int:
	if is_vehicle:
		return 0
	return int(loc_destroyed["LL"]) + int(loc_destroyed["RL"])


func walk_mp() -> int:
	if is_vehicle:
		if immobile or engine_dead or crew_killed:
			return 0
		var cmp := maxi(0, design.walk - cruise_lost)
		if cruise_halved:
			cmp = int(ceil(cmp / 2.0))
		return cmp
	var mp := design.walk
	for leg in ["LL", "RL"]:
		if loc_destroyed[leg]:
			continue
		if count_hit(leg, "hip") > 0:
			mp = int(ceil(mp / 2.0))
		mp -= count_hit(leg, "upper_leg") + count_hit(leg, "lower_leg") + count_hit(leg, "foot")
	if legs_destroyed() == 1:
		mp = mini(mp, 1)
	elif legs_destroyed() >= 2:
		mp = 0
	mp -= heat_move_penalty()
	# triple-strength myomer kicks in when the 'Mech runs hot
	if design.myomer == "tsm" and heat >= 9.0 and legs_destroyed() == 0:
		mp += 1
	return maxi(0, mp)


func run_mp() -> int:
	if is_infantry:
		return walk_mp()
	if is_vehicle:
		return int(ceil(walk_mp() * 1.5))
	if legs_destroyed() > 0:
		return walk_mp()
	if masc_on and masc:
		return walk_mp() * 2
	return maxi(walk_mp(), int(ceil(walk_mp() * 1.5)) - int(armor_fx.get("run_minus", 0)))


## Ammo family of an ammo key ("srm6" -> "srm", "lbx10c" -> "lbx", "ac20" -> "ac").
static func ammo_family(key: String) -> String:
	var i := 0
	while i < key.length() and not key[i].is_valid_int():
		i += 1
	return key.substr(0, i)


func munition_for(mt: Dictionary) -> String:
	var key: String = mt["item"].get("ammo", "")
	if key == "":
		return "standard"
	return munitions.get(ammo_family(key), "standard")


func arms_free() -> bool:
	if is_vehicle:
		return false
	return not no_arms and has_part("LA", "hand") and has_part("RA", "hand") and has_part("LA", "shoulder") and has_part("RA", "shoulder")


func jump_mp() -> int:
	if is_vehicle:
		return 0
	if legs_destroyed() > 0 or gyro_hits >= 2:
		return 0
	var wing := 0
	if design.jump > 0 and wing_mount >= 0 and not mounts[wing_mount]["destroyed"]:
		wing = int(GameData.db().tables["gear"]["partial_wing"]["jump"].get(design.weight_class(), 1))
	return maxi(0, design.jump + wing - jj_lost - (heat_move_penalty() if design.jump > 0 else 0))


func dissipation() -> float:
	var per := 2.0 if double_sinks else 1.0
	var wing := 0.0
	if wing_mount >= 0 and not mounts[wing_mount]["destroyed"]:
		wing = float(GameData.db().tables["gear"]["partial_wing"]["cooling"])
	return maxf(0.0, (sinks_total - sinks_lost) * per + wing)


## Sets up what one mounted item does beyond being a weapon, bin or the gear handled in create().
func _gear_setup(mi: int, tables: Dictionary) -> void:
	var mt: Dictionary = mounts[mi]
	var it: Dictionary = mt["item"]
	var G: Dictionary = tables["gear"]
	var loc: String = mt["loc"]
	var nm := str(it.get("name", "")).to_lower()
	if mt["kind"] == "weapon":
		if str(it.get("wtype", "")) == "pod":
			pods.append(mi)
		return
	if mt["kind"] == "ammo":
		if str(it.get("ammo", "")).begins_with("coolant"):
			coolers.append({"kind": "coolant", "mount": mi, "uses": int(G["coolers"]["coolant"]["uses"])})
		return
	match str(it.get("misc", "")):
		"stealth", "void_sig", "chameleon":
			var key := "null_sig" if str(it["misc"]) == "stealth" else str(it["misc"])
			var sg: Dictionary = (G["signature"][key] as Dictionary).duplicate()
			sg["mount"] = mi
			signatures.append(sg)
		"partial_wing":
			wing_mount = mi
		"ppc_capacitor":
			# charges the first PPC beside it that has no capacitor yet
			for wi in weapons:
				var w: Dictionary = mounts[wi]
				if w["loc"] == loc and str(w["item"].get("wtype", "")) == "ppc" and not w.has("cap"):
					w["cap"] = mi
					break
		"laser_insulator":
			for wi in weapons:
				var w2: Dictionary = mounts[wi]
				if w2["loc"] == loc and str(w2["item"].get("wtype", "")) in ["laser", "pulse"] and not w2.has("cooler"):
					w2["cooler"] = mi
					break
		"aes":
			if loc in ["LA", "RA"]:
				aes[loc] = mi
		"apollo":
			apollo = true
		"blue_shield":
			blue_shield = true
		"talons":
			talons = true
		"booby_trap":
			booby_trap = true
		"apod":
			pods.append(mi)
		"shield":
			# a shield is so much more to shoot through on its arm
			var size := "large" if nm.contains("large") else ("medium" if nm.contains("medium") else "small")
			armor[loc] = int(armor.get(loc, 0)) + int(G["shield"][size])
			max_armor[loc] = int(armor[loc])
		"modular_armor":
			armor[loc] = int(armor.get(loc, 0)) + int(G["modular_armor"])
			max_armor[loc] = int(armor[loc])
		"harjel_repair":
			harjel.append([mi, int(G["harjel_repair"]["iii" if nm.contains("iii") else "ii"])])
		"radical_hs", "coolant_system":
			coolers.append({"kind": str(it["misc"]), "mount": mi, "uses": int(G["coolers"][str(it["misc"])]["uses"])})
		"claw", "retractable_blade", "lance", "chain_whip", "chainsaw", "mining_drill", "wrecking_ball", "backhoe", \
				"pile_driver", "dual_saw", "rock_cutter", "combine":
			if physical_weapon == "":
				physical_weapon = str(it["misc"])
		"vibroblade":
			if physical_weapon == "":
				physical_weapon = "vibroblade_" + ("large" if nm.contains("large") else ("medium" if nm.contains("medium") else "small"))


## What the chassis itself brings: armor and structure type, engine, cockpit, myomer.
func _chassis_setup(tables: Dictionary) -> void:
	armor_fx = tables["armor_types"].get(design.armor_type, {})
	if armor_fx.has("stealth"):
		var sg: Dictionary = armor_fx.duplicate()
		sg["mount"] = -1
		signatures.append(sg)
	struct_soak = float((tables["structure_types"].get(design.structure, {}) as Dictionary).get("soak", 1.0))
	no_move_heat = design.engine_type in Construction.AMPLIFIED or design.myomer == "super_cooled"
	always_strong = design.myomer == "industrial_tsm"
	if design.cockpit in ["industrial", "primitive_industrial"]:
		cockpit_to_hit = int(tables["gear"]["industrial_cockpit_to_hit"])


## Signature systems hiding the unit right now (stealth armor needs its ECM suite working).
func signatures_on() -> Array:
	var out_: Array = []
	if shutdown or out:
		return out_
	for sg in signatures:
		if int(sg["mount"]) >= 0 and mounts[int(sg["mount"])]["destroyed"]:
			continue
		if sg.get("needs_ecm", false) and not ecm:
			continue
		out_.append(sg)
	return out_


func heat_move_penalty() -> int:
	if is_vehicle:
		return 0
	var p := 0
	for row in GameData.db().tables["heat_move"]:
		if heat >= float(row[0]):
			p = int(row[1])
	return p


func heat_to_hit() -> int:
	var p := 0
	for row in GameData.db().tables["heat_to_hit"]:
		if heat >= float(row[0]):
			p = int(row[1])
	return p


func psr_base_mods() -> int:
	if is_vehicle:
		return 0
	var t: Dictionary = GameData.db().tables["psr_mod"]
	var mods := gyro_hits * int(t["gyro_hit"])
	for leg in ["LL", "RL"]:
		if loc_destroyed[leg]:
			mods += int(t["leg_destroyed"])
			continue
		mods += count_hit(leg, "hip") * int(t["hip"])
		mods += (count_hit(leg, "upper_leg") + count_hit(leg, "lower_leg") + count_hit(leg, "foot")) * int(t["leg_actuator"])
	if quirks.has("stable"):
		mods -= 1
	if quirks.has("unbalanced") or quirks.has("cramped_cockpit") or quirks.has("hard_to_pilot"):
		mods += 1
	if quirks.has("easy_to_pilot"):
		mods -= 1
	return mods


func has_trait(t: String) -> bool:
	return t in traits
