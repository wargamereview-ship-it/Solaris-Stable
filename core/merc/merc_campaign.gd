class_name MercCampaign
extends RefCounted
## The Mercenary Company mode: a MekHQ / Against the Bot style campaign with real-time battles.
## Day by day: travel between star systems, contracts, weekly battles per lance, salvage, repairs by
## techs using spare parts, procurement, markets, payroll. Everything is seeded and saved as JSON.

const VERSION := 1
const CULTURE := {"LA": "Lyran Commonwealth", "DC": "Draconis Combine", "CC": "Capellan Confederation",
	"FWL": "Free Worlds League", "FS": "Federated Suns", "FC": "Federated Suns"}
const MONTHS := ["January", "February", "March", "April", "May", "June", "July", "August", "September",
	"October", "November", "December"]

var mode := "merc"
var name := ""
var color := Color(0.6, 0.55, 0.3)
var camo := ""
var seed_value := 0
var rng: SimRng
var day := 0                      # Julian day number
var cash := 0
var ledger: Array = []            # {"day", "text", "amount", "kind"}
var people: Dictionary = {}       # id -> MercPerson
var units: Dictionary = {}        # id -> MercUnit
var lances: Array = []            # {"id", "name", "role", "units": [uid]}
var next_id := 1
var location := -1                # system index (or where the last jump ended)
var travel: Dictionary = {}       # {"route": [sys], "leg": int, "leg_days": int, "days_left": int, "dest": sys}
var astechs := 0
var medics := 0
var warehouse: Dictionary = {}    # part key -> quantity (count, or tons for armor and ammo)
var orders: Array = []            # parts on the way: {"key", "qty", "days"}
var shopping: Array = []          # parts being searched for: {"key", "qty", "next": day}
var repair_mode := "standard"
var market_units: Array = []
var market_people: Array = []
var contract_offers: Array = []
var contract: Dictionary = {}
var history: Array = []
var scenarios: Array = []
var salvage: Array = []           # pending salvage choice after a battle
var log: Array = []               # {"day", "kind", "text"}
var loan: Dictionary = {}
var stats: Dictionary = {"contracts_ok": 0, "contracts_partial": 0, "contracts_failed": 0, "battles": 0, "victories": 0,
	"defeats": 0, "kills": 0, "losses": 0}
var settings: Dictionary = {"auto_withdraw": true, "difficulty": "Regular"}
var game_over := false
var _market_month := -1
var arena_offers: Array = []     # duels the Solaris VII promoters offer while the company is on-world and free
var _arena_week := -1
var _spare_minutes := 0.0         # tech time left over after the day's repairs (refits use it)
var news: Array = []              # the Inner Sphere's news: {"day", "kind", "title", "text", "major"}
var events_day := 0               # the timeline has been read up to this day
var front_day := 0                # worlds changing hands have been reported up to this day
var _tl_day := -1
var _tl_active: Array = []

var db: GameData
var rules: Dictionary
var sm: StarMap


func _init() -> void:
	db = GameData.db()
	rules = db.merc()["rules"]
	sm = StarMap.get_map()
	rng = SimRng.new(1)


# ================================================================== calendar

static func jdn(y: int, m: int, d: int) -> int:
	var a := (14 - m) / 12
	var yy := y + 4800 - a
	var mm := m + 12 * a - 3
	return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045


static func ymd(j: int) -> Array:
	var a := j + 32044
	var b := (4 * a + 3) / 146097
	var c := a - 146097 * b / 4
	var d := (4 * c + 3) / 1461
	var e := c - 1461 * d / 4
	var m := (5 * e + 2) / 153
	var dd := e - (153 * m + 2) / 5 + 1
	var mo := m + 3 - 12 * (m / 10)
	var yr := 100 * b + d - 4800 + m / 10
	return [yr, mo, dd]


func year() -> int:
	return int(ymd(day)[0])


func month() -> int:
	return int(ymd(day)[1])


func dom() -> int:
	return int(ymd(day)[2])


func year_f() -> float:
	var t := ymd(day)
	return float(t[0]) + (day - jdn(int(t[0]), 1, 1)) / 365.25


## 0 = Monday.
func weekday() -> int:
	return day % 7


static func date_label(j: int) -> String:
	var t := ymd(j)
	return "%d %s %d" % [t[2], MONTHS[int(t[1]) - 1], t[0]]


func date_str() -> String:
	return date_label(day)


static func add_months(j: int, n: int) -> int:
	var t := ymd(j)
	var y := int(t[0])
	var m := int(t[1]) + n
	while m > 12:
		m -= 12
		y += 1
	return jdn(y, m, mini(int(t[2]), 28))


# ================================================================== new game

## The campaign's dials, set on the setup screen and kept in `settings`. A save without one of them
## plays by the default here. enemy_strength 0 means "by the difficulty name" (data/merc_rules.json).
const SETTING_DEFAULTS := {"difficulty": "Regular", "enemy_strength": 0.0, "enemy_skill": 0, "battle_tempo": 1.0,
	"enemy_support": true, "enemy_infantry": true, "pay": 1.0, "prices": 1.0, "supply": 0, "repair_speed": 1.0,
	"upkeep": 1.0, "news": true, "trade_effects": true, "industrial": true, "lethality": 1.0, "auto_withdraw": true}


func opt(key: String) -> float:
	return float(settings.get(key, SETTING_DEFAULTS.get(key, 1.0)))


func flag(key: String) -> bool:
	return bool(settings.get(key, SETTING_DEFAULTS.get(key, true)))


## Enemy strength as a share of the player's (after skill), from the slider or the difficulty name.
func enemy_strength() -> float:
	if opt("enemy_strength") > 0.0:
		return opt("enemy_strength")
	return float(rules["difficulty"].get(str(settings.get("difficulty", "Regular")), 0.8))


## The difficulty name nearest an enemy strength (the arena card and old saves go by the name).
static func difficulty_name(strength: float) -> String:
	var D: Dictionary = GameData.db().merc()["rules"]["difficulty"]
	var best := "Regular"
	var gap := 99.0
	for k in ["Green", "Regular", "Veteran", "Elite"]:
		if absf(float(D[k]) - strength) < gap:
			gap = absf(float(D[k]) - strength)
			best = k
	return best


## What a new company starts with: one of the packages of data/merc_rules.json, with anything in
## `over` replacing it. Keys: year, month, hall, mechs, vehicles, infantry, mech_bv, vehicle_bv,
## infantry_bv, mech_tons_max, crew (shift of crew quality, 0 = the usual mix), worn (gear starts used),
## techs, astechs, doctors, medics, admins, cash.
static func start_setup(package: String, over := {}) -> Dictionary:
	var R: Dictionary = GameData.db().merc()["rules"]["start"]
	var pk: Dictionary = R["packages"].get(package, R["packages"]["lance"])
	var s := {"year": int(R["default_year"]), "month": 1, "hall": "Galatea", "mechs": int(pk["mechs"]),
		"vehicles": int(pk["vehicles"]), "infantry": 0, "mech_bv": int(pk["mech_bv"]), "vehicle_bv": int(pk["vehicle_bv"]),
		"infantry_bv": 0, "mech_tons_max": 65, "crew": 0.0, "worn": false, "techs": int(pk["techs"]),
		"astechs": int(pk["astechs"]), "doctors": int(pk["doctors"]), "medics": int(pk["medics"]),
		"admins": int(pk["admins"]), "cash": int(pk["cash"])}
	for k in over:
		s[k] = over[k]
	return s


static func new_game(company: String, col: Color, start_year: int, hall_id: String, package: String, seed_v: int, difficulty := "Regular") -> MercCampaign:
	return new_custom(company, col, start_setup(package, {"year": start_year, "hall": hall_id}), seed_v, {"difficulty": difficulty})


## A new company from a setup (see start_setup) and the campaign settings to play by.
static func new_custom(company: String, col: Color, setup: Dictionary, seed_v: int, play := {}) -> MercCampaign:
	var c := MercCampaign.new()
	for k in play:
		c.settings[k] = play[k]
	if float(c.settings.get("enemy_strength", 0.0)) > 0.0:
		c.settings["difficulty"] = difficulty_name(float(c.settings["enemy_strength"]))
	var start_year := int(setup["year"])
	c.name = company
	c.color = col
	c.seed_value = seed_v
	c.rng = SimRng.new(seed_v)
	c.day = jdn(start_year, clampi(int(setup.get("month", 1)), 1, 12), 1)
	c.events_day = c.day
	c.front_day = c.day
	c.sm.year_hint = c.year_f()
	c.location = c.sm.index_of(str(setup["hall"]))
	if c.location < 0:
		c.location = c.sm.index_of("Galatea")
	c.cash = int(setup["cash"])
	c.astechs = int(setup["astechs"])
	c.medics = int(setup["medics"])
	var crew_shift := float(setup.get("crew", 0.0))
	var n_mechs := int(setup["mechs"])
	var tons_max := int(setup.get("mech_tons_max", 65))
	# a new company starts with fighting 'Mechs, not militarized loaders
	var mech_ids: Array = []
	if n_mechs > 0:
		mech_ids = ForceGen.force("MERC", start_year, int(setup["mech_bv"]), c.rng, {"mech_share": 1.0, "max_units": n_mechs, "tons_max": tons_max, "combat_only": true})
	while mech_ids.size() < n_mechs:
		var extra := ForceGen.pick("MERC", start_year, "mech", c.rng, 20, mini(55, tons_max))
		for k in 8:
			if not ForceGen.industrial(extra):
				break
			extra = ForceGen.pick("MERC", start_year, "mech", c.rng, 20, mini(55, tons_max))
		mech_ids.append(extra)
	var veh_ids: Array = []
	if int(setup["vehicles"]) > 0:
		veh_ids = ForceGen.force("MERC", start_year, int(setup["vehicle_bv"]), c.rng, {"mech_share": 0.0, "max_units": int(setup["vehicles"]), "tons_max": 70})
		while veh_ids.size() < int(setup["vehicles"]):
			veh_ids.append(ForceGen.pick("MERC", start_year, "vehicle", c.rng, 20, 60))
	var inf_ids: Array = []
	if int(setup.get("infantry", 0)) > 0:
		var ibv := int(setup.get("infantry_bv", 0))
		inf_ids = ForceGen.infantry("MERC", start_year, ibv if ibv > 0 else int(setup["infantry"]) * 120, c.rng, {"max_units": int(setup["infantry"])})
	var mech_units: Array = []
	for id in mech_ids:
		if id != "":
			var u := c.add_unit(db_design(id), "start")
			mech_units.append(u.id)
			var p := c.gen_person("mechwarrior", clampf(c.rng.randf_range(0.35, 0.75) + crew_shift, 0.0, 1.0), "Mercenary")
			c.assign(p.id, u.id)
	var veh_units: Array = []
	for id in veh_ids:
		if id != "":
			var u2 := c.add_unit(db_design(id), "start")
			veh_units.append(u2.id)
			var p2 := c.gen_person("vehicle_crew", clampf(c.rng.randf_range(0.3, 0.7) + crew_shift, 0.0, 1.0), "Mercenary")
			p2.crew = maxi(0, (u2.design as VehicleDesign).crew_size() - 1)
			c.assign(p2.id, u2.id)
	var inf_units: Array = []
	for id in inf_ids:
		var u3 := c.add_unit(db_design(str(id)), "start")
		inf_units.append(u3.id)
		var lead := c.gen_person("vehicle_crew", clampf(c.rng.randf_range(0.2, 0.7) + crew_shift, 0.0, 1.0), "Mercenary")
		lead.crew = 0
		c.assign(lead.id, u3.id)
	for k in int(setup["techs"]):
		c.gen_person("tech", clampf(c.rng.randf_range(0.3, 0.7) + crew_shift, 0.0, 1.0), "Mercenary")
	for k in int(setup["doctors"]):
		c.gen_person("doctor", clampf(c.rng.randf_range(0.3, 0.7) + crew_shift, 0.0, 1.0), "Mercenary")
	for k in int(setup["admins"]):
		c.gen_person("admin", clampf(c.rng.randf_range(0.35, 0.75) + crew_shift, 0.0, 1.0), "Mercenary")
	var groups: Array = []
	var i := 0
	while i < mech_units.size():
		groups.append(mech_units.slice(i, i + 4))
		i += 4
	i = 0
	while i < veh_units.size():
		groups.append(veh_units.slice(i, i + 4))
		i += 4
	i = 0
	while i < inf_units.size():
		groups.append(inf_units.slice(i, i + 4))
		i += 4
	var names := ["Command Lance", "Battle Lance", "Fire Lance", "Striker Lance", "Recon Lance", "Armor Lance"]
	for g in groups.size():
		var nm: String = names[g] if g < names.size() else "Lance %d" % (g + 1)
		if groups[g].size() > 0 and c.units[groups[g][0]].is_vehicle():
			nm = "Armor Lance" if not c._lance_named("Armor Lance") else "Armor Lance %d" % g
		c.new_lance(nm, groups[g])
	for uid in c.units:
		var su: MercUnit = c.units[uid]
		var rep := su.analysis()
		for mt in rep.get("mounts", []):
			var it := c.db.item(str(mt["id"]))
			if it.get("kind", "") == "ammo":
				c.warehouse["ammo:" + str(mt["id"])] = 1.0
		var ak := "armor:" + su.design.armor_type
		c.warehouse[ak] = float(c.warehouse.get(ak, 0.0)) + 2.0
	if setup.get("worn", false):
		# second-hand gear: every machine starts with some of its armor gone
		for uid2 in mech_units + veh_units:
			var wu: MercUnit = c.units[uid2]
			wu.condition = c._used_condition(wu.design, c.rng.randf_range(0.6, 0.85))
			wu.status = "damaged"
			MercRepair.normalize(wu)
	c.add_log("company", "%s is founded on %s. %d 'Mechs, %d vehicles and %d people." % [company, c.sm.name_of(c.location), mech_units.size(), veh_units.size(), c.people.size()])
	c.refresh_markets()
	c.refresh_arena()
	return c


static func db_design(id: String) -> MechDesign:
	return GameData.db().stock_design(id)


func _lance_named(n: String) -> bool:
	for l in lances:
		if str(l["name"]) == n:
			return true
	return false


func new_id() -> int:
	next_id += 1
	return next_id


func add_log(kind: String, text: String) -> void:
	log.append({"day": day, "kind": kind, "text": text})
	if log.size() > 600:
		log = log.slice(log.size() - 600)


func add_money(amount: int, text: String, kind: String) -> void:
	cash += amount
	ledger.append({"day": day, "text": text, "amount": amount, "kind": kind})
	if ledger.size() > 800:
		ledger = ledger.slice(ledger.size() - 800)


# ================================================================== people

var _portraits: Dictionary = {}


func _portrait_list(gender: String) -> Array:
	if _portraits.is_empty():
		_portraits = {"m": [], "f": []}
		var dir := DirAccess.open("res://assets/megamek/portraits")
		if dir != null:
			for f in dir.get_files():
				if f.ends_with(".png"):
					_portraits[f.substr(0, 1)].append(f)
			_portraits["m"].sort()
			_portraits["f"].sort()
	return _portraits.get(gender, [])


## A new person (added to the company unless hire is false). quality 0..1.
func gen_person(role: String, quality: float, culture := "Mercenary", hire := true) -> MercPerson:
	var p := MercPerson.new()
	p.id = new_id()
	p.role = role
	var g := "f" if rng.chance(0.4) else "m"
	p.gender = "female" if g == "f" else "male"
	var cul: Dictionary = db.names["cultures"].get(culture, db.names["cultures"]["Mercenary"])
	p.first = str(rng.pick(cul["female" if g == "f" else "male"]))
	p.last = str(rng.pick(cul["last"]))
	var q := clampf(quality, 0.0, 1.2)
	p.age = 20 + rng.randi_range(0, 8) + int(q * rng.randi_range(0, 18))
	match role:
		"mechwarrior", "vehicle_crew":
			if rng.chance(0.6):
				p.callsign = str(rng.pick(db.names["callsigns"]))
			var pl := _portrait_list(g)
			if not pl.is_empty() and role == "mechwarrior":
				p.portrait = pl[rng.randi_range(0, pl.size() - 1)]
			p.gunnery = clampi(int(round(rng.gauss(4.6 - q * 1.8, 0.6))), 1, 6)
			p.piloting = clampi(int(round(rng.gauss(5.6 - q * 1.8, 0.6))), 1, 7)
			if rng.chance(0.25):
				var tk: Array = CombatMech.TRAITS.keys()
				p.traits.append(tk[rng.randi_range(0, tk.size() - 1)])
		"tech":
			p.tech = clampi(int(round(rng.gauss(6.8 - q * 2.2, 0.5))), 3, 8)
		"doctor":
			p.medical = clampi(int(round(rng.gauss(6.8 - q * 2.2, 0.5))), 3, 8)
		"admin":
			p.admin = clampi(int(round(rng.gauss(6.8 - q * 2.2, 0.5))), 3, 8)
			p.negotiation = clampi(int(round(rng.gauss(7.2 - q * 2.4, 0.6))), 3, 9)
	p.joined = date_str()
	if hire:
		people[p.id] = p
	return p


func active(role: String) -> Array:
	var out: Array = []
	for id in people:
		var p: MercPerson = people[id]
		if p.role == role and p.available():
			out.append(p)
	return out


func roster(include_gone := false) -> Array:
	var out: Array = []
	for id in people:
		var p: MercPerson = people[id]
		if include_gone or p.alive():
			out.append(p)
	return out


func headcount() -> int:
	var n := astechs + medics
	for p in roster():
		n += (p as MercPerson).headcount()
	return n


func monthly_salaries() -> int:
	var t := astechs * int(rules["salaries"]["astech"]) + medics * int(rules["salaries"]["medic"])
	for p in roster():
		t += (p as MercPerson).salary(rules)
	return t


func best(role: String, skill: String) -> int:
	var b := 12
	for p in active(role):
		b = mini(b, int((p as MercPerson).get(skill)))
	return b


# ================================================================== units and lances

func add_unit(d: MechDesign, origin: String, condition := {}) -> MercUnit:
	var u := MercUnit.new()
	u.id = new_id()
	u.design = d.copy()
	u.origin = origin
	u.acquired = date_str()
	u.condition = condition.duplicate(true)
	u.status = "damaged" if not condition.is_empty() else "ready"
	units[u.id] = u
	return u


func assign(pid: int, uid: int) -> String:
	var p: MercPerson = people.get(pid)
	var u: MercUnit = units.get(uid)
	if p == null or u == null:
		return "Nobody to assign"
	if u.is_vehicle() and p.role != "vehicle_crew":
		return "Vehicles need a vehicle crew"
	if not u.is_vehicle() and p.role != "mechwarrior":
		return "'Mechs need a MechWarrior"
	if p.unit_id >= 0 and units.has(p.unit_id):
		(units[p.unit_id] as MercUnit).crew.erase(pid)
	for other in u.crew.duplicate():
		if people.has(other):
			(people[other] as MercPerson).unit_id = -1
	u.crew = [pid]
	p.unit_id = uid
	return ""


func unassign(pid: int) -> void:
	var p: MercPerson = people.get(pid)
	if p == null:
		return
	if p.unit_id >= 0 and units.has(p.unit_id):
		(units[p.unit_id] as MercUnit).crew.erase(pid)
	p.unit_id = -1


func crew_of(u: MercUnit) -> MercPerson:
	for pid in u.crew:
		var p: MercPerson = people.get(pid)
		if p != null and p.alive():
			return p
	return null


func new_lance(nm: String, uids := []) -> Dictionary:
	var l := {"id": new_id(), "name": nm, "role": "fight", "units": []}
	lances.append(l)
	for uid in uids:
		set_lance(int(uid), int(l["id"]))
	return l


func lance(lid: int) -> Dictionary:
	for l in lances:
		if int(l["id"]) == lid:
			return l
	return {}


func set_lance(uid: int, lid: int) -> String:
	var u: MercUnit = units.get(uid)
	if u == null:
		return "No such unit"
	var l := lance(lid)
	if lid >= 0 and l.is_empty():
		return "No such lance"
	if lid >= 0 and (l["units"] as Array).size() >= 6:
		return "That lance is full"
	for o in lances:
		(o["units"] as Array).erase(uid)
	u.lance = lid
	if lid >= 0:
		(l["units"] as Array).append(uid)
	return ""


func delete_lance(lid: int) -> void:
	var l := lance(lid)
	for uid in (l.get("units", []) as Array).duplicate():
		var u: MercUnit = units.get(int(uid))
		if u != null:
			u.lance = -1
	lances.erase(l)


## Units that can deploy: not a wreck, with a crew member fit to fight.
func deployable(u: MercUnit) -> bool:
	if u.wreck() or u.status == "sold" or u.refitting():
		return false
	var p := crew_of(u)
	return p != null and p.available()


func combat_units() -> Array:
	var out: Array = []
	for id in units:
		var u: MercUnit = units[id]
		if not u.wreck() and u.status != "sold":
			out.append(u)
	return out


func company_value() -> int:
	var v := 0
	for u in combat_units():
		v += (u as MercUnit).base_cost()
	return v


func lance_bv(lid: int) -> int:
	var t := 0
	for uid in lance(lid).get("units", []):
		var u: MercUnit = units.get(int(uid))
		if u != null and deployable(u):
			t += u.bv()
	return t


func _bv_of_units(ids: Array) -> int:
	var t := 0
	for uid in ids:
		var u: MercUnit = units.get(int(uid))
		if u != null:
			t += u.bv()
	return t


# ================================================================== reputation

## Dragoons-style rating from experience, command, tech support, contract record and finances.
func rating() -> Dictionary:
	var parts := {}
	var xp := 0.0
	var n := 0
	var exp_pts := {"green": 0.0, "regular": 5.0, "veteran": 10.0, "elite": 20.0}
	for p in roster():
		var pp: MercPerson = p
		if pp.combat() and pp.unit_id >= 0:
			xp += float(exp_pts.get(pp.experience(rules), 5.0))
			n += 1
	parts["Experience"] = int(round(xp / maxf(1.0, n)))
	parts["Command"] = clampi(8 - best("admin", "negotiation"), 0, 5) * 2
	var need := 0.0
	for u in combat_units():
		need += 1.0
	var techs := active("tech").size()
	var ratio := techs * 4.0 / maxf(1.0, need)
	parts["Support"] = 5 if ratio >= 1.0 else (0 if ratio >= 0.6 else -5)
	parts["Record"] = clampi(int(stats["contracts_ok"]) * 5 + int(stats["contracts_partial"]) * 2 - int(stats["contracts_failed"]) * 10, -30, 30)
	parts["Finances"] = -10 if cash < 0 else 0
	var score := 0
	for k in parts:
		score += int(parts[k])
	var letter := "F"
	for row in rules["rating"]["thresholds"]:
		if score >= int(row[0]):
			letter = str(row[1])
			break
	return {"score": score, "letter": letter, "parts": parts}


# ================================================================== money

func monthly_costs() -> Dictionary:
	var M: Dictionary = rules["monthly"]
	var sal := monthly_salaries()
	var maint := int(company_value() * float(M["maintenance_pct_of_unit_value"]) * opt("upkeep"))
	var over := int(sal * float(M["overhead_pct_of_salaries"]) * opt("upkeep"))
	var food := int(headcount() * int(M["food_housing_per_person"]) * opt("upkeep"))
	var out := {"Salaries": sal, "Maintenance": maint, "Overhead": over, "Food and housing": food}
	if not loan.is_empty():
		out["Loan payment"] = int(loan["monthly"])
	return out


func _month_end() -> void:
	var costs := monthly_costs()
	var support := 0.0
	if not contract.is_empty() and str(contract.get("status", "")) == "active":
		support = float(contract["terms"]["support"]) / 100.0
	for k in costs:
		var amt := int(costs[k])
		if k == "Loan payment":
			add_money(-amt, "Loan payment", "loan")
			loan["months_left"] = int(loan["months_left"]) - 1
			if int(loan["months_left"]) <= 0:
				add_log("money", "The bank loan is paid off.")
				loan = {}
			continue
		add_money(-amt, k, "upkeep")
		if support > 0.0 and k in ["Salaries", "Maintenance"]:
			add_money(int(amt * support), "Employer support (%s)" % k.to_lower(), "contract")
	if not contract.is_empty() and str(contract.get("status", "")) == "active":
		var pay := int(contract["monthly_pay"])
		add_money(pay, "Contract payment (%s)" % contract["employer_name"], "contract")
	if cash < -int(rules["bank"]["fold_debt"]):
		game_over = true
		add_log("company", "The banks call in your debts. %s is finished." % name)


func take_loan(amount: int, months: int) -> String:
	if not loan.is_empty():
		return "Pay off the current loan first"
	var r := rating()
	var mx := int(rules["bank"]["max_by_rating"].get(r["letter"], 2000000))
	if amount <= 0 or amount > mx:
		return "The bank lends up to %s at your rating" % Campaign.money(mx)
	var rate := float(rules["bank"]["rate_by_rating"].get(r["letter"], 0.2))
	var mr := rate / 12.0
	var monthly := int(ceil(amount * mr / (1.0 - pow(1.0 + mr, -months))))
	loan = {"principal": amount, "monthly": monthly, "months_left": months, "rate": rate}
	add_money(amount, "Bank loan", "loan")
	add_log("money", "Took a %s loan over %d months (%d%% a year): %s a month." % [Campaign.money(amount), months, int(rate * 100), Campaign.money(monthly)])
	return ""


# ================================================================== travel

func in_transit() -> bool:
	return not travel.is_empty()


func transport_cost_per_jump() -> int:
	var T: Dictionary = rules["transport"]
	var nm := 0
	var nv := 0
	for u in combat_units():
		if (u as MercUnit).is_vehicle():
			nv += 1
		else:
			nm += 1
	var ships := maxi(1, int(ceil(nm / float(T["mechs_per_dropship"]) + nv / float(T["vehicles_per_dropship"]))))
	return nm * int(T["per_mech"]) + nv * int(T["per_vehicle"]) + headcount() * int(T["per_person"]) + ships * int(T["per_dropship_collar"])


func plan_trip(dest: int) -> Dictionary:
	var r := sm.route(location, dest)
	if r.is_empty():
		return {"ok": false, "why": "No jump route"}
	var jumps := r.size() - 1
	return {"ok": true, "route": r, "jumps": jumps, "days": sm.trip_days(r), "cost": jumps * transport_cost_per_jump()}


func start_travel(dest: int) -> String:
	if in_transit():
		return "Already under way"
	if dest == location:
		return "You're already there"
	if not contract.is_empty() and str(contract.get("status", "")) == "active":
		return "You're under contract on %s" % sm.name_of(int(contract["system"]))
	var tr := plan_trip(dest)
	if not tr["ok"]:
		return str(tr["why"])
	if cash < int(tr["cost"]) and cash < 0:
		return "You can't pay the JumpShip captains"
	var r: Array = tr["route"]
	add_money(-int(tr["cost"]), "Transport: %d jumps to %s" % [int(tr["jumps"]), sm.name_of(dest)], "transport")
	travel = {"route": r, "leg": 0, "days_left": int(tr["days"]), "total": int(tr["days"]), "dest": dest,
		"outbound": sm.transit_days(location), "inbound": sm.transit_days(dest)}
	add_log("travel", "Departing %s for %s: %d jumps, about %d days." % [sm.name_of(location), sm.name_of(dest), int(tr["jumps"]), int(tr["days"])])
	if not contract.is_empty() and str(contract.get("status", "")) == "signed" and dest == int(contract["system"]):
		var reimb := int(int(tr["cost"]) * float(contract["terms"]["transport"]) / 100.0)
		if reimb > 0:
			add_money(reimb, "Transport reimbursed by %s" % contract["employer_name"], "contract")
	return ""


## Where the company is right now along its route (for the map), as a system index pair and a fraction.
func travel_position() -> Dictionary:
	if travel.is_empty():
		return {"a": location, "b": location, "f": 0.0}
	var r: Array = travel["route"]
	var done := int(travel["total"]) - int(travel["days_left"])
	var out_d := int(travel["outbound"])
	if done < out_d:
		return {"a": int(r[0]), "b": int(r[0]), "f": 0.0, "phase": "outbound"}
	var jd := int(rules["calendar"]["jump_recharge_days"])
	var leg := mini((done - out_d) / maxi(1, jd), r.size() - 1)
	if leg >= r.size() - 1:
		return {"a": int(r[-1]), "b": int(r[-1]), "f": 0.0, "phase": "inbound"}
	return {"a": int(r[leg]), "b": int(r[leg + 1]), "f": float((done - out_d) % jd) / jd, "phase": "jumping"}


func _travel_day() -> Array:
	var ev: Array = []
	if travel.is_empty():
		return ev
	travel["days_left"] = int(travel["days_left"]) - 1
	var tp := travel_position()
	location = int(tp["a"])
	if int(travel["days_left"]) <= 0:
		location = int(travel["dest"])
		travel = {}
		add_log("travel", "Arrived at %s." % sm.name_of(location))
		ev.append({"kind": "arrive", "stop": true, "text": "Arrived at %s" % sm.name_of(location)})
		refresh_markets()
		if not contract.is_empty() and str(contract.get("status", "")) == "signed" and location == int(contract["system"]):
			_start_contract()
			ev.append({"kind": "contract", "stop": true, "text": "Contract begins on %s" % sm.name_of(location)})
	return ev


# ================================================================== markets

func hall_level() -> String:
	if location < 0:
		return ""
	return sm.hall(location, year_f())


func refresh_markets() -> void:
	_market_month = year() * 12 + month()
	var lvl := hall_level()
	var M: Dictionary = rules["markets"]
	var y := year()
	var owner := sm.owner(location, year_f())
	var factions: Array = ["MERC"] if lvl != "" else []
	if sm.is_real_faction(owner) and ForceGen.table(owner, y, "mech").size() > 0:
		factions.append(owner)
	if factions.is_empty():
		factions.append("IS")
	market_units = []
	var nu: Array = M["unit_offers"].get(lvl, M["unit_offers"][""])
	for k in rng.randi_range(int(nu[0]), int(nu[1])):
		var f: String = factions[rng.randi_range(0, factions.size() - 1)]
		var kind := "mech" if rng.chance(0.6) else ("vtol" if rng.chance(0.1) else "vehicle")
		var id := ForceGen.pick(f, y, kind, rng)
		if id != "" and not flag("industrial") and ForceGen.industrial(id):
			id = ""          # the setup says no IndustrialMechs on the market
		if id == "":
			continue
		var d := db_design(id)
		var cond := {}
		var quality := rng.randf_range(0.6, 1.0)
		if quality < 0.85:
			cond = _used_condition(d, quality)
		var price := int(Construction.analyze(d).get("cost", 1000000) * rng.randf_range(float(M["unit_price_range"][0]), float(M["unit_price_range"][1])) * (1.0 - (0.85 - quality) * 0.5 if quality < 0.85 else 1.0) * price_mult())
		market_units.append({"offer": new_id(), "design": id, "price": price, "condition": cond, "seller": sm.faction_name(f)})
	# infantry platoons and, once they exist, battle armour squads looking for an employer
	var ni: Array = M["infantry_offers"].get(lvl, M["infantry_offers"][""])
	for k in rng.randi_range(int(ni[0]), int(ni[1])):
		var f2: String = factions[rng.randi_range(0, factions.size() - 1)]
		var got := ForceGen.infantry(f2, y, 1, rng, {"max_units": 1})
		if got.is_empty():
			continue
		var pr: Array = M["infantry_price_range"]
		market_units.append({"offer": new_id(), "design": str(got[0]), "condition": {}, "seller": sm.faction_name(f2),
			"price": int(Construction.analyze(db_design(str(got[0]))).get("cost", 100000) * rng.randf_range(float(pr[0]), float(pr[1])) * price_mult())})
	market_people = []
	var np: Array = M["people_offers"].get(lvl, M["people_offers"][""])
	var roles: Array = M["role_weights"].keys()
	var weights: Array = []
	for r in roles:
		weights.append(float(M["role_weights"][r]))
	for k in int(round(rng.randi_range(int(np[0]), int(np[1])) * timeline_mult("recruits"))):
		var role: String = roles[rng.weighted_index(weights)]
		if role in ["astech", "medic"]:
			market_people.append({"offer": new_id(), "pool": role, "count": rng.randi_range(2, 6)})
			continue
		var p := gen_person(role, rng.randf_range(0.1, 1.0), CULTURE.get(owner, "Mercenary"), false)
		market_people.append({"offer": new_id(), "person": p.to_dict()})
	generate_contracts()


func _used_condition(d: MechDesign, quality: float) -> Dictionary:
	var armor := {}
	for k in d.armor:
		armor[k] = int(round(int(d.armor[k]) * clampf(quality + rng.randf_range(-0.15, 0.15), 0.3, 1.0)))
	if d.is_vehicle():
		var ip := VehicleConstruction.internal_points(d as VehicleDesign)
		return {"armor": armor, "internal": ip.duplicate(), "dead_mounts": [], "ammo": {}, "vstate": {}}
	var ipts := Construction.internal_points(d.tons)
	var internal := ipts.duplicate()
	if quality < 0.7:
		var loc2: String = MechDesign.LOCS[rng.randi_range(1, 7)]
		internal[loc2] = maxi(1, int(ipts[loc2]) - rng.randi_range(1, 4))
	return {"armor": armor, "internal": internal, "hit_slots": [], "ammo": {}}


func buy_unit(offer: int) -> String:
	for o in market_units:
		if int(o["offer"]) == offer:
			if cash < int(o["price"]):
				return "Not enough C-bills"
			var u := add_unit(db_design(str(o["design"])), "bought", o["condition"])
			MercRepair.normalize(u)
			add_money(-int(o["price"]), "Bought %s" % u.label(), "market")
			market_units.erase(o)
			if u.design.is_infantry():
				# infantry sign on as a formed unit, their officer with them
				var lead := gen_person("vehicle_crew", rng.randf_range(0.2, 0.7), CULTURE.get(sm.owner(location, year_f()), "Mercenary"))
				lead.crew = 0
				assign(lead.id, u.id)
				add_log("market", "The %s signs on for %s, led by %s." % [u.label(), Campaign.money(int(o["price"])), lead.full_name()])
				return ""
			add_log("market", "Bought a %s for %s." % [u.label(), Campaign.money(int(o["price"]))])
			return ""
	return "That offer is gone"


func sell_unit(uid: int) -> String:
	var u: MercUnit = units.get(uid)
	if u == null:
		return "No such unit"
	var v := int(u.value() * float(rules["markets"]["sell_fraction"]))
	cancel_refit(uid)
	for pid in u.crew.duplicate():
		unassign(int(pid))
	set_lance(uid, -1)
	units.erase(uid)
	add_money(v, "Sold %s" % u.label(), "market")
	add_log("market", "Sold the %s for %s." % [u.label(), Campaign.money(v)])
	return ""


func strip_unit(uid: int) -> String:
	var u: MercUnit = units.get(uid)
	if u == null:
		return "No such unit"
	cancel_refit(uid)
	var got := MercRepair.strip(u)
	for k in got:
		warehouse[k] = snappedf(float(warehouse.get(k, 0.0)) + float(got[k]), 0.01)
	for pid in u.crew.duplicate():
		unassign(int(pid))
	set_lance(uid, -1)
	units.erase(uid)
	add_log("hangar", "Stripped the %s for parts: %d kinds of parts into the warehouse." % [u.label(), got.size()])
	return ""


func hire(offer: int) -> String:
	for o in market_people:
		if int(o["offer"]) != offer:
			continue
		if o.has("pool"):
			var n := int(o["count"])
			var fee := n * int(rules["salaries"][str(o["pool"])])
			if cash < fee:
				return "Not enough C-bills"
			add_money(-fee, "Hired %d %ss" % [n, str(o["pool"])], "personnel")
			if str(o["pool"]) == "astech":
				astechs += n
			else:
				medics += n
			market_people.erase(o)
			return ""
		var p := MercPerson.from_dict(o["person"])
		var fee2 := p.salary(rules) * int(rules["hire_fee_months"])
		if cash < fee2:
			return "Not enough C-bills"
		p.id = new_id()
		p.joined = date_str()
		people[p.id] = p
		add_money(-fee2, "Hiring bonus: %s" % p.full_name(), "personnel")
		add_log("personnel", "%s joins as a %s." % [p.full_name(), p.role_label().to_lower()])
		market_people.erase(o)
		return ""
	return "That offer is gone"


func dismiss(pid: int) -> String:
	var p: MercPerson = people.get(pid)
	if p == null:
		return "Nobody by that id"
	unassign(pid)
	p.status = "left"
	add_log("personnel", "%s leaves the company." % p.full_name())
	return ""


## Spend XP on a skill (lower target number). Returns "" or why not.
func improve(pid: int, skill: String) -> String:
	var p: MercPerson = people.get(pid)
	if p == null:
		return "Nobody by that id"
	var cur := int(p.get(skill))
	var costs: Array = rules["skills"]["xp_costs"].get(skill if skill in ["gunnery", "piloting"] else "support", [])
	var next := cur - 1
	if next < 0 or next >= costs.size() or int(costs[next]) <= 0:
		return "Can't improve further"
	var cost := int(costs[next])
	if p.xp < cost:
		return "Needs %d XP" % cost
	p.xp -= cost
	p.set(skill, next)
	add_log("personnel", "%s improves %s to %d." % [p.full_name(), skill, next])
	return ""


func xp_cost(p: MercPerson, skill: String) -> int:
	var costs: Array = rules["skills"]["xp_costs"].get(skill if skill in ["gunnery", "piloting"] else "support", [])
	var next := int(p.get(skill)) - 1
	if next < 0 or next >= costs.size():
		return -1
	return int(costs[next]) if int(costs[next]) > 0 else -1


# ================================================================== contracts

func _employer_mult(f: String) -> float:
	var em: Dictionary = rules["pay"]["employer_mult"]
	return float(em.get(sm.faction_kind(f), em["DEFAULT"]))


func base_monthly_pay() -> int:
	var P: Dictionary = rules["pay"]
	var v := company_value() * float(P["pct_of_unit_value"]) + monthly_salaries() * float(P["salary_mult"])
	return maxi(int(P["min_monthly"]), int(v))


func generate_contracts() -> void:
	contract_offers = []
	var lvl := hall_level()
	var M: Dictionary = rules["markets"]
	var rng_n: Array = M["contract_offers"].get(lvl, M["contract_offers"][""])
	var n := rng.randi_range(int(rng_n[0]), int(rng_n[1]))
	var yf := year_f()
	var bd := sm.borders(yf)
	# employers with someone to fight, weighted by kind and how close they are
	var cands: Array = []
	var weights: Array = []
	var near := sm.within_jumps(location, 12)
	var near_set := {}
	for i in near:
		near_set[int(i)] = true
	for f in bd:
		if not sm.faction_active(f, yf) or sm.faction_kind(f) in ["MERC", "PIRATE", "CLAN"] or f in ["CS", "WOB"]:
			continue
		var w := 3.0 if sm.faction_kind(f) == "MAJOR" else 1.2
		var close := 0
		for o in bd[f]:
			for si in bd[f][o]:
				if near_set.has(int(si)):
					close += 1
		if close == 0 and lvl == "":
			continue
		w *= 1.0 + minf(4.0, close / 4.0)
		# a faction at war on one of its borders hires more; the timeline moves it further
		for o in bd[f]:
			if sm.at_war(f, str(o), yf) and flag("trade_effects"):
				w *= float(rules["timeline"]["war_weight"])
				break
		w *= employer_weight(str(f))
		cands.append(f)
		weights.append(w)
	if cands.is_empty():
		return
	n = int(round(n * timeline_mult("offers")))
	for k in n:
		var f: String = cands[rng.weighted_index(weights)]
		var c := _make_contract(f, yf, bd)
		if not c.is_empty():
			contract_offers.append(c)


func _make_contract(emp: String, yf: float, bd: Dictionary) -> Dictionary:
	var ms: Dictionary = rules["missions"]
	var keys: Array = ms.keys()
	var ws: Array = []
	for k in keys:
		ws.append(float(ms[k]["weight"]))
	var mt: String = keys[rng.weighted_index(ws)]
	var mi: Dictionary = ms[mt]
	var foes: Dictionary = bd.get(emp, {})
	var enemy := ""
	var target := -1
	var hostile: Array = []
	var hw: Array = []
	for o in foes:
		var h := sm.hostility(emp, o, yf)
		if h > 0 and sm.faction_kind(o) != "MERC":
			hostile.append(o)
			hw.append(float(h * h) * (1.0 + (foes[o] as Array).size() * 0.1))
	match str(mi["enemy"]):
		"pirates":
			enemy = "PIR"
		"rebels":
			enemy = "PIR" if rng.chance(0.5) else emp
	if enemy == "" and hostile.is_empty():
		enemy = "PIR"
		if bool(mi["offensive"]):
			mt = "pirate_hunting"
			mi = ms[mt]
	elif enemy == "":
		enemy = hostile[rng.weighted_index(hw)]
	# the world: an enemy border world for offensives, one of the employer's own for the rest
	if bool(mi["offensive"]) and enemy != "PIR":
		var their: Dictionary = bd.get(enemy, {})
		var lst: Array = their.get(emp, [])
		if not lst.is_empty():
			target = int(lst[rng.randi_range(0, lst.size() - 1)])
	if target < 0:
		var own: Array = foes.get(enemy, []) if enemy != "PIR" else []
		if own.is_empty():
			for o2 in foes:
				own = foes[o2]
				break
		if own.is_empty():
			var all := sm.faction_systems(emp, yf)
			if all.is_empty():
				return {}
			own = all
		target = int(own[rng.randi_range(0, own.size() - 1)])
	if enemy == emp:
		enemy = "PIR"
	var months := rng.randi_range(int(mi["months"][0]), int(mi["months"][1]))
	var r := rating()
	var pay := base_monthly_pay() * float(mi["pay"]) * _employer_mult(emp) * float(rules["pay"]["rating_mult"].get(r["letter"], 1.0))
	pay *= rng.randf_range(0.9, 1.15)
	var wartime := enemy != "PIR" and sm.at_war(emp, enemy, yf)
	if wartime and flag("trade_effects"):
		pay *= float(rules["timeline"]["war_pay"])
	pay *= timeline_mult("pay") * opt("pay")
	var T: Dictionary = rules["terms"]
	var ri := ["A*", "A", "B", "C", "D", "F"].find(str(r["letter"]))
	var good := clampf(1.0 - ri * 0.15, 0.2, 1.0)
	var terms := {
		"command": T["command"][clampi(rng.weighted_index([3, 4, 3, 1 + int(good * 3)]), 0, 3)],
		"salvage": int(T["salvage_steps"][clampi(int(round(rng.gauss(2.5 + good * 1.5, 1.2))), 0, T["salvage_steps"].size() - 1)]),
		"exchange": rng.chance(0.25),
		"support": int(T["support_steps"][clampi(int(round(rng.gauss(3.0 + good * 2.0, 1.5))), 0, T["support_steps"].size() - 1)]),
		"blc": int(T["support_steps"][clampi(int(round(rng.gauss(2.0 + good * 2.0, 1.5))), 0, T["support_steps"].size() - 1)]),
		"transport": int(T["transport_steps"][clampi(int(round(rng.gauss(2.0 + good, 1.0))), 0, T["transport_steps"].size() - 1)]),
		"advance": int(T["advance_steps"][clampi(int(round(rng.gauss(1.5 + good, 1.0))), 0, T["advance_steps"].size() - 1)]),
		"signing": int(T["signing_steps"][clampi(int(round(rng.gauss(1.0, 1.0))), 0, T["signing_steps"].size() - 1)]),
	}
	# generous terms come with a little less base pay: priced into the offer once, when it's made
	pay *= 1.0 - float(terms["salvage"]) / 100.0 * 0.25
	pay *= 1.0 - float(terms["support"]) / 100.0 * 0.12
	pay *= 1.0 - float(terms["blc"]) / 100.0 * 0.08
	pay *= 1.0 - float(terms["transport"]) / 100.0 * 0.05
	var trip := plan_trip(target)
	var lances_req := maxi(1, int(round(float(mi["lances"]) * maxi(1, _combat_lances()))))
	var sk: Dictionary = rules["operations"]["enemy_skill_weights"]
	var skill_keys: Array = sk.keys()
	var skill_w: Array = []
	for s in skill_keys:
		skill_w.append(float(sk[s]))
	return {
		"offer": new_id(), "mission": mt, "mission_label": mi["label"], "employer": emp, "employer_name": sm.faction_name(emp),
		"enemy": enemy, "enemy_name": sm.faction_name(enemy), "system": target, "system_name": sm.name_of(target),
		"months": months, "base_pay": int(pay), "terms": terms, "negotiated": {}, "lances": lances_req,
		"enemy_skill": skill_keys[clampi(rng.weighted_index(skill_w) + int(opt("enemy_skill")), 0, skill_keys.size() - 1)],
		"wartime": wartime and flag("trade_effects"),
		"travel_days": int(trip.get("days", 0)), "travel_cost": int(trip.get("cost", 0)), "jumps": int(trip.get("jumps", 0)),
		"expires": day + 30,
	}


func _combat_lances() -> int:
	var n := 0
	for l in lances:
		if (l["units"] as Array).size() > 0:
			n += 1
	return n


## Total value of a contract offer under its current terms (base pay grows and shrinks with the terms
## you negotiate: more salvage, support and transport cost you pay, as in MekHQ).
func contract_value(c: Dictionary) -> Dictionary:
	var t: Dictionary = c["terms"]
	var monthly := float(c["base_pay"])
	var total := int(monthly) * int(c["months"])
	return {"monthly": int(monthly), "total": total, "advance": int(total * float(t["advance"]) / 100.0),
		"signing": int(total * float(t["signing"]) / 100.0)}


## Chance (0-1) that your best admin talks the employer into a better clause.
func negotiation_chance() -> float:
	var need := int(rules["terms"]["negotiate_tn"]) - (8 - best("admin", "negotiation"))
	return CombatSim.p_hit(need)


## One try per clause: roll 2d6 + (8 - negotiation) against the negotiation TN. A success improves that
## clause a step and changes nothing else; a failure leaves the offer as it was.
## Command rights go the way you ask: toward "independence" (you may decline battles, fewer of them, no
## allies) or toward "support" (allied troops and more battles).
func negotiate(offer: int, clause: String, toward := "independence") -> String:
	for c in contract_offers:
		if int(c["offer"]) != offer:
			continue
		var neg: Dictionary = c["negotiated"]
		if neg.has(clause):
			return "You already pushed on that"
		var T: Dictionary = rules["terms"]
		var roll := rng.roll2d6() + (8 - best("admin", "negotiation"))
		var ok := roll >= int(T["negotiate_tn"])
		neg[clause] = ok
		if not ok:
			return "The employer won't budge (rolled %d)." % roll
		var t: Dictionary = c["terms"]
		match clause:
			"pay":
				c["base_pay"] = int(int(c["base_pay"]) * 1.1)
			"command":
				var ci: int = (T["command"] as Array).find(t["command"])
				var to := ci + 1 if toward == "independence" else ci - 1
				if to < 0 or to > 3:
					neg.erase(clause)
					return "The command rights can't go any further that way."
				t["command"] = T["command"][to]
			"salvage", "support", "blc", "transport", "advance", "signing":
				var steps: Array = T[{"salvage": "salvage_steps", "support": "support_steps", "blc": "support_steps", "transport": "transport_steps", "advance": "advance_steps", "signing": "signing_steps"}[clause]]
				# the next step up from the current value (steps load from JSON as floats, so compare numbers)
				var cur := int(t[clause])
				var nxt := cur
				for st in steps:
					if int(st) > cur:
						nxt = int(st)
						break
				if nxt == cur:
					neg.erase(clause)
					return "That's already as good as it gets."
				t[clause] = nxt
		return "Agreed (rolled %d)." % roll
	return "That offer is gone"


func accept_contract(offer: int) -> String:
	if not contract.is_empty() and str(contract.get("status", "")) in ["signed", "active"]:
		return "Finish the current contract first"
	for c in contract_offers:
		if int(c["offer"]) != offer:
			continue
		var v := contract_value(c)
		contract = c.duplicate(true)
		contract["status"] = "signed"
		contract["monthly_pay"] = int((v["total"] - v["advance"]) / maxi(1, int(c["months"])))
		contract["total"] = v["total"]
		contract["score"] = 0
		contract["morale"] = 3
		contract["signed_day"] = day
		contract["deadline_arrive"] = day + int(c["travel_days"]) + 14
		contract["salvage_value"] = 0
		contract["salvage_taken"] = 0
		contract_offers.erase(c)
		add_money(int(v["advance"]) + int(v["signing"]), "Advance and signing bonus (%s)" % c["employer_name"], "contract")
		add_log("contract", "Signed with %s: %s on %s, %d months, %s in all." % [c["employer_name"], c["mission_label"], c["system_name"], int(c["months"]), Campaign.money(int(v["total"]))])
		if location == int(c["system"]) and not in_transit():
			_start_contract()
		return ""
	return "That offer is gone"


func _start_contract() -> void:
	contract["status"] = "active"
	contract["start_day"] = day
	contract["end_day"] = add_months(day, int(contract["months"]))
	if day > int(contract.get("deadline_arrive", day)):
		contract["score"] = int(contract["score"]) - 2
		add_log("contract", "You arrived late. The employer is not pleased.")
	add_log("contract", "The contract begins on %s. It runs until %s." % [contract["system_name"], date_label(int(contract["end_day"]))])


func _end_contract() -> Array:
	var sc := int(contract["score"])
	var res := "success" if sc >= 2 else ("partial" if sc >= 0 else "failure")
	match res:
		"success":
			stats["contracts_ok"] = int(stats["contracts_ok"]) + 1
			var bonus := int(int(contract["total"]) * 0.05)
			add_money(bonus, "Completion bonus (%s)" % contract["employer_name"], "contract")
		"partial":
			stats["contracts_partial"] = int(stats["contracts_partial"]) + 1
		"failure":
			stats["contracts_failed"] = int(stats["contracts_failed"]) + 1
	contract["status"] = "done"
	contract["result"] = res
	history.append(contract.duplicate(true))
	add_log("contract", "The %s contract with %s is over: %s (score %d)." % [contract["mission_label"], contract["employer_name"], res, sc])
	var txt := "Contract ended: %s" % res
	contract = {}
	for s in scenarios.duplicate():
		if str(s["status"]) == "pending":
			scenarios.erase(s)
	return [{"kind": "contract", "stop": true, "text": txt}]


func contract_active() -> bool:
	return not contract.is_empty() and str(contract.get("status", "")) == "active"


# ================================================================== operations: battles

func set_role(lid: int, role: String) -> void:
	var l := lance(lid)
	if not l.is_empty() and rules["operations"]["roles"].has(role):
		l["role"] = role


func _weekly_battles() -> Array:
	var ev: Array = []
	if not contract_active() or in_transit() or location != int(contract["system"]):
		return ev
	var O: Dictionary = rules["operations"]
	var mi: Dictionary = rules["missions"][contract["mission"]]
	var morale_mod := 0.7 + 0.1 * int(contract["morale"])
	for l in lances:
		var role := str(l["role"])
		if role == "reserve" or (l["units"] as Array).is_empty():
			continue
		var ready := 0
		var ready_bv := 0
		for uid in l["units"]:
			var lu: MercUnit = units[int(uid)]
			if deployable(lu) and lu.damage_fraction() < 0.5:
				ready += 1
				ready_bv += lu.bv()
		# a lance too weak to send out isn't called on (but the employer notices: see the contract score)
		if ready < mini(2, (l["units"] as Array).size()) or ready_bv < 500:
			continue
		var busy := false
		for ps in pending_scenarios():
			if int(ps["lance"]) == int(l["id"]):
				busy = true
		if busy:
			continue
		if role == "training":
			for uid2 in l["units"]:
				var p := crew_of(units[int(uid2)])
				if p != null and p.experience(rules) in ["green", "regular"]:
					p.xp += 1
		var chance := float(O["roles"][role]["chance"]) * float(mi["tempo"]) * morale_mod * opt("battle_tempo")
		chance *= float(rules["terms"]["command_tempo"].get(str(contract["terms"]["command"]), 1.0))
		if rng.chance(chance):
			var sc := _new_scenario(l, role)
			scenarios.append(sc)
			ev.append({"kind": "battle", "stop": true, "text": "%s: %s on %s" % [l["name"], sc["label"], contract["system_name"]]})
			add_log("battle", "%s must fight: %s (by %s)." % [l["name"], sc["label"], date_label(int(sc["deadline"]))])
	# monthly big battle on assaults, relief and guerrilla contracts
	if str(contract["mission"]) in O["major_battle_missions"] and dom() <= 7 and _combat_lances() >= 2:
		var lid: int = int(lances[0]["id"]) if not lances.is_empty() else -1
		if lid >= 0:
			var sc2 := _new_scenario(lances[0], "fight", "major_battle")
			scenarios.append(sc2)
			ev.append({"kind": "battle", "stop": true, "text": "Major battle on %s" % contract["system_name"]})
	return ev


func _new_scenario(l: Dictionary, role: String, force_type := "") -> Dictionary:
	var O: Dictionary = rules["operations"]
	var tbl: Array = O["role_scenarios"].get(role, [["standup", 1]])
	var types: Array = []
	var ws: Array = []
	for e in tbl:
		types.append(e[0])
		ws.append(float(e[1]))
	var st: String = force_type if force_type != "" else str(types[rng.weighted_index(ws)])
	var info: Dictionary = O["scenarios"][st]
	var sysd: Dictionary = sm.sys(int(contract["system"]))
	var bio: Dictionary = sysd.get("biomes", {"plains": 1.0})
	var bk: Array = bio.keys()
	var bw: Array = []
	for b in bk:
		bw.append(float(bio[b]))
	var biome := "bf_" + str(bk[rng.weighted_index(bw)])
	var dl: Array = O["deadline_days"]
	return {"id": new_id(), "type": st, "label": info["label"], "desc": info["desc"], "lance": int(l["id"]),
		"status": "pending", "created": day, "deadline": day + rng.randi_range(int(dl[0]), int(dl[1])), "biome": biome,
		"seed": rng.randi_range(1, 1 << 30), "major": st == "major_battle"}


func pending_scenarios() -> Array:
	var out: Array = []
	for s in scenarios:
		if str(s["status"]) == "pending":
			out.append(s)
	return out


func scenario(sid: int) -> Dictionary:
	for s in scenarios:
		if int(s["id"]) == sid:
			return s
	return {}


## Default deployment for a battle: the lance's ready units (every ready unit for a major battle).
func default_deployment(sc: Dictionary) -> Array:
	var out: Array = []
	if sc.get("major", false):
		for u in combat_units():
			if deployable(u) and not _deployed_elsewhere((u as MercUnit).id, int(sc["id"])):
				out.append((u as MercUnit).id)
		return out.slice(0, 12)
	for uid in lance(int(sc["lance"])).get("units", []):
		if deployable(units[int(uid)]) and not _deployed_elsewhere(int(uid), int(sc["id"])):
			out.append(int(uid))
	return out


func _deployed_elsewhere(uid: int, sid: int) -> bool:
	for s in scenarios:
		if int(s["id"]) != sid and str(s["status"]) == "pending" and uid in s.get("deployed", []):
			return true
	return false


## Builds the battle for a scenario with the units the player sends: battlefield, both sides
## (and allies), conditions. Returns {"sim", "battle"}; battle maps sim indices back to the company.
## Off-board support for a battle. Yours comes with the contract: the tighter the employer's
## command, the more of its artillery and fighters you may call on, and only in set-piece fights.
## The enemy's is its own roll (so the rest of the battle rolls as before); its fire control calls it.
func battle_support(sc: Dictionary) -> Dictionary:
	var S: Dictionary = rules["operations"]["support"]
	var type := str(sc.get("type", ""))
	var mine := {"artillery": 0, "air_strike": 0}
	var theirs := {"artillery": 0, "air_strike": 0, "auto": true, "first": float(S["enemy_first_s"]), "gap": float(S["enemy_gap_s"])}
	if contract.is_empty():
		return {"player": mine, "enemy": theirs}
	if type in S["player_scenarios"]:
		var base: Dictionary = S["player"].get(str(contract["terms"]["command"]), {})
		for k in mine:
			mine[k] = int(base.get(k, 0)) + (int(S["major_battle_bonus"].get(k, 0)) if type == "major_battle" else 0)
	var srng := SimRng.new(int(sc.get("seed", 0)) + 104729)
	if srng.chance(float(S["enemy_chance"].get(type, 0.0))) and flag("enemy_support"):
		var kind := StarMap.get_map().faction_kind(str(contract.get("enemy", "PIR")))
		var kinds: Array = S["enemy_kinds"].get(kind, S["enemy_kinds"]["DEFAULT"])
		for k2 in kinds:
			theirs[k2] = srng.randi_range(1, int(S["enemy_max"][k2]))
	return {"player": mine, "enemy": theirs}


func make_battle(sid: int, uids: Array, record := true, inputs := []) -> Dictionary:
	var sc := scenario(sid)
	if sc.is_empty() or uids.is_empty():
		return {}
	sc["deployed"] = uids.duplicate()
	var O: Dictionary = rules["operations"]
	var info: Dictionary = O["scenarios"][sc["type"]]
	var brng := SimRng.new(int(sc["seed"]))
	var y := year()
	# the enemy sizes up what you actually bring, damage included
	var player_bv := 0
	for uid0 in uids:
		var du: MercUnit = units[int(uid0)]
		player_bv += int(du.bv() * (1.0 - 0.6 * du.damage_fraction()))
	var morale := int(contract.get("morale", 3))
	var skill: Array = O["enemy_skill"][contract.get("enemy_skill", "regular")]
	# BV doesn't count skill: scale both sides by the Total Warfare-style skill multiplier
	var pm := 0.0
	for uid1 in uids:
		var pp1 := crew_of(units[int(uid1)])
		pm += skill_mult(pp1.gunnery + pp1.piloting if pp1 != null else 11)
	pm /= maxf(1.0, uids.size())
	var em := skill_mult(int(skill[0]) + int(skill[1]) + 1)
	var diff := enemy_strength()
	var ebv := int(player_bv * pm / em * diff * float(info["enemy_bv"]) * (0.85 + 0.06 * morale) * brng.randf_range(0.85, 1.15))
	var enemy := str(contract.get("enemy", "PIR"))
	# infantry: part of the enemy's strength may be platoons and battle armour, and a base or a line
	# you defend may have a garrison of its own (its own dice, so the rest of the battle rolls as before)
	var I: Dictionary = O["infantry"]
	var irng := SimRng.new(int(sc["seed"]) + 7919)
	var enemy_attacks: bool = str(sc["type"]) in I["garrison_scenarios"]
	var enemy_inf: Array = []
	if irng.chance(float(I["enemy_chance"].get(str(sc["type"]), 0.0))) and flag("enemy_infantry"):
		enemy_inf = ForceGen.infantry(enemy, y, int(ebv * float(I["bv_share"])), irng, {"mobile_only": enemy_attacks})
		for iid in enemy_inf:
			ebv -= ForceGen.bv_of(iid)
	var garrison: Array = []
	if enemy_attacks and irng.chance(float(I["garrison_chance"])):
		garrison = ForceGen.infantry(str(contract["employer"]), y, irng.randi_range(int(I["garrison_bv"][0]), int(I["garrison_bv"][1])), irng, {"max_units": 3})
	var enemy_ids := ForceGen.force(enemy, y, ebv, brng, {"max_units": 12 if sc.get("major", false) else 8})
	var allies: Array = []
	var ally_chance := float(O["ally_chance"].get(str(contract["terms"]["command"]), 0.0))
	if brng.chance(ally_chance):
		allies = ForceGen.force(str(contract["employer"]), y, int(player_bv * brng.randf_range(0.3, 0.6)), brng, {"max_units": 4})
	var edges := ["W", "E"] if brng.chance(0.5) else ["E", "W"]
	if brng.chance(0.25):
		edges = ["S", "N"] if brng.chance(0.5) else ["N", "S"]
	var opts := {"player_edge": edges[0], "enemy_edge": edges[1], "player_n": uids.size(), "ally_n": allies.size(),
		"enemy_n": enemy_ids.size() + (enemy_inf.size() if enemy_attacks else 0), "scenario": sc["type"]}
	var arena := BattlefieldGenerator.generate(str(sc["biome"]), int(sc["seed"]), opts)
	var sides := [[], []]
	var meta := {"sid": sid, "player": [], "allies": [], "enemies": [], "biome": sc["biome"], "type": sc["type"]}
	var k := 0
	for uid in uids:
		var u: MercUnit = units[int(uid)]
		var p := crew_of(u)
		var w := p.sim_dict() if p != null else {"callsign": "Crew", "gunnery": 5, "piloting": 6}
		sides[0].append({"design": u.design.copy(), "warrior": w, "orders": {}, "condition": u.sim_condition(),
			"controller": "player", "bv": u.bv(), "spawn": arena.spawns[0][k % arena.spawns[0].size()]})
		meta["player"].append({"uid": int(uid), "pid": p.id if p != null else -1})
		k += 1
	var emp_cul: String = CULTURE.get(str(contract["employer"]), "Mercenary")
	for id in allies:
		var ap := gen_person("vehicle_crew" if db.vehicle_by_id.has(id) else "mechwarrior", brng.randf_range(0.3, 0.7), emp_cul, false)
		sides[0].append({"design": db_design(id), "warrior": ap.sim_dict(), "orders": {}, "controller": "ai",
			"bv": ForceGen.bv_of(id), "spawn": arena.spawns[0][k % arena.spawns[0].size()]})
		meta["allies"].append({"design": id, "name": ap.short_name()})
		k += 1
	# the garrison is dug in around what you defend
	var ob0 := arena.objectives
	for gi in garrison.size():
		var gid: String = garrison[gi]
		var gp := gen_person("vehicle_crew", 0.4, emp_cul, false)
		gp.gunnery = irng.randi_range(4, 5)
		gp.piloting = gp.gunnery + 1
		var gpos := _cells_center(arena, ob0.get("defend_cells", [])) + Vector2.from_angle(TAU * gi / garrison.size() + 0.6) * 110.0
		sides[0].append({"design": db_design(gid), "warrior": gp.sim_dict(), "orders": {}, "controller": "ai",
			"bv": ForceGen.bv_of(gid), "spawn": gpos})
		meta["allies"].append({"design": gid, "name": gp.short_name(), "infantry": true})
	var en_cul: String = CULTURE.get(enemy, "Mercenary")
	var reinf: bool = sc["type"] in ["hold_the_line", "base_defense", "major_battle"]
	for j in enemy_ids.size():
		var id2: String = enemy_ids[j]
		var ep := gen_person("vehicle_crew" if db.vehicle_by_id.has(id2) else "mechwarrior", 0.5, en_cul, false)
		ep.gunnery = brng.randi_range(int(skill[0]), int(skill[1]))
		ep.piloting = ep.gunnery + 1
		var e := {"design": db_design(id2), "warrior": ep.sim_dict(), "orders": {}, "controller": "ai", "bv": ForceGen.bv_of(id2)}
		if reinf and j >= enemy_ids.size() / 2 + 1:
			e["arrive"] = brng.randf_range(90.0, 220.0)
		sides[1].append(e)
		meta["enemies"].append({"design": id2, "name": ep.short_name(), "skill": [ep.gunnery, ep.piloting]})
	# enemy infantry: with the attack when they are the ones advancing, around their base when you
	# attack it, otherwise strung out in front of their own line
	for ii in enemy_inf.size():
		var iid2: String = enemy_inf[ii]
		var ip := gen_person("vehicle_crew", 0.5, en_cul, false)
		ip.gunnery = irng.randi_range(int(skill[0]), int(skill[1]))
		ip.piloting = ip.gunnery + 1
		var ie := {"design": db_design(iid2), "warrior": ip.sim_dict(), "orders": {}, "controller": "ai", "bv": ForceGen.bv_of(iid2)}
		if str(sc["type"]) == "base_attack":
			ie["spawn"] = _cells_center(arena, ob0.get("attack_cells", [])) + Vector2.from_angle(TAU * ii / enemy_inf.size() + 0.3) * 120.0
		elif not enemy_attacks:
			var es: Vector2 = arena.spawns[1][ii % arena.spawns[1].size()]
			ie["spawn"] = es.lerp(arena.size_m() / 2.0, irng.randf_range(0.25, 0.45))
		sides[1].append(ie)
		meta["enemies"].append({"design": iid2, "name": ip.short_name(), "skill": [ip.gunnery, ip.piloting], "infantry": true})
	var cond := _battle_conditions(arena, brng)
	var sup := battle_support(sc)
	var bout := {"merc": true, "time_limit": float(info["time_limit"]), "conditions": cond,
		"auto_withdraw": bool(settings.get("auto_withdraw", true)),
		"support": [sup["player"], sup["enemy"]]}
	var sim := CombatSim.create(arena, sides, int(sc["seed"]) + 17, bout, record, inputs)
	# the enemy goes for its objective
	var ob := arena.objectives
	for gi2 in garrison.size():
		var gm: CombatMech = sim.mechs[uids.size() + allies.size() + gi2]
		sim.ai.command(gm, {"type": "guard", "pos": _cells_center(arena, ob.get("defend_cells", [])), "radius": 150.0})
	for m in sim.mechs:
		var cm: CombatMech = m
		if cm.team != 1:
			continue
		match str(sc["type"]):
			"chase":
				sim.ai.command(cm, {"type": "withdraw", "edge": edges[0]})
			"base_defense", "hold_the_line":
				sim.ai.command(cm, {"type": "attack_cell", "cells": ob.get("defend_cells", [])})
			"base_attack":
				sim.ai.command(cm, {"type": "guard", "pos": _cells_center(arena, ob.get("attack_cells", [])), "radius": 260.0})
	meta["conditions"] = cond
	meta["support"] = sup
	meta["edges"] = edges
	meta["player_bv"] = player_bv
	meta["skill_mult"] = [snappedf(pm, 0.01), snappedf(em, 0.01)]
	var ebv_real := 0
	for id3 in enemy_ids + enemy_inf:
		ebv_real += ForceGen.bv_of(id3)
	meta["enemy_bv"] = ebv_real
	meta["label"] = sc["label"]
	meta["desc"] = sc["desc"]
	meta["system"] = contract.get("system_name", "")
	meta["employer"] = contract.get("employer_name", "")
	meta["enemy"] = contract.get("enemy_name", "")
	return {"sim": sim, "battle": meta}


## How much a crew's skill multiplies a unit's worth, close to the Total Warfare BV skill table:
## gunnery 4 / piloting 5 is 1.0, each step better on both is about x1.19 (3/4 = 1.19, 5/6 = 0.84).
static func skill_mult(sum: int) -> float:
	return clampf(pow(1.19, (9 - sum) / 2.0), 0.55, 2.0)


## You hold the field when you still have units on it and the enemy has none (or time ran out).
static func field_held(res: Dictionary) -> bool:
	var mine := false
	var theirs := false
	for r in res["mechs"]:
		if not r["out"]:
			if int(r["team"]) == 0:
				mine = true
			else:
				theirs = true
	return mine and (not theirs or str(res["how"]) in ["time limit", "objective destroyed"])


static func _cells_center(arena: Arena, cells: Array) -> Vector2:
	var c := Vector2.ZERO
	for ci in cells:
		c += arena.center_of_index(int(ci))
	return c / maxf(1.0, cells.size()) if not cells.is_empty() else arena.size_m() / 2.0


## Orders the AI gives your units when it fights the battle for you: go for the objective.
static func objective_orders(sim: CombatSim, scenario_type: String, edges: Array) -> void:
	var ob := sim.arena.objectives
	for m in sim.mechs:
		var cm: CombatMech = m
		if cm.team != 0:
			continue
		match scenario_type:
			"breakthrough":
				sim.ai.command(cm, {"type": "advance", "edge": str(edges[1])})
			"base_attack":
				sim.ai.command(cm, {"type": "attack_cell", "cells": ob.get("attack_cells", [])})
			"base_defense", "hold_the_line":
				sim.ai.command(cm, {"type": "guard", "pos": _cells_center(sim.arena, ob.get("defend_cells", [])), "radius": 200.0})
			"recon", "probe":
				sim.ai.command(cm, {"type": "recon", "points": ob.get("recon_points", [])})


func _battle_conditions(arena: Arena, r: SimRng) -> Dictionary:
	var th: Dictionary = db.arenas["themes"].get(arena.theme, {})
	var cd: Dictionary = th.get("conditions", {})
	var light := "day"
	var roll := r.randf()
	if roll < float(cd.get("night", 0.15)):
		light = "night"
	elif roll < float(cd.get("night", 0.15)) + float(cd.get("dusk", 0.15)):
		light = "dusk"
	var ww: Dictionary = cd.get("weather", {"clear": 1})
	var wk: Array = ww.keys()
	var wv: Array = []
	for k in wk:
		wv.append(float(ww[k]))
	return {"light": light, "weather": wk[r.weighted_index(wv)], "floodlights": false}


## Scores a finished battle and applies it to the company: damage, casualties, XP, salvage,
## the contract score. Returns a summary for the results screen.
func resolve_battle(meta: Dictionary, res: Dictionary) -> Dictionary:
	var sc := scenario(int(meta["sid"]))
	var ms: Array = res["mechs"]
	var np := (meta["player"] as Array).size()
	var na := (meta["allies"] as Array).size()
	var outcome := _outcome(sc, meta, res)
	var O: Dictionary = rules["operations"]
	var won := outcome == "victory"
	var lost := outcome == "defeat"
	var held := field_held(res) or (won and str(res["how"]) == "objective destroyed")
	sc["status"] = outcome
	sc["resolved"] = day
	sc["inputs"] = res.get("inputs", [])
	stats["battles"] = int(stats["battles"]) + 1
	if won:
		stats["victories"] = int(stats["victories"]) + 1
	elif lost:
		stats["defeats"] = int(stats["defeats"]) + 1
	var summary := {"outcome": outcome, "how": res["how"], "units": [], "people": [], "salvage": [], "money": [], "score": 0,
		"player_bv": int(meta.get("player_bv", 0)), "enemy_bv": int(meta.get("enemy_bv", 0)), "skill": meta.get("skill_mult", [])}
	var sk: Dictionary = rules["skills"]
	var lost_value := 0
	for i in np:
		var r: Dictionary = ms[i]
		var pm: Dictionary = meta["player"][i]
		var u: MercUnit = units.get(int(pm["uid"]))
		if u == null:
			continue
		u.battles += 1
		u.kills += int(r["kills"])
		var left_behind: bool = not held and not r["withdrew"] and (r["destroyed"] or r["crew_killed"] or r["ejected"] or not r["out"] or str(r["reason"]) == "crippled")
		var cond := _condition_from_result(u, r)
		var wreck := _is_wreck(u, r, cond)
		var line := ""
		var wiped: bool = u.design.is_infantry() and r["destroyed"]
		if u.design.is_infantry() and not u.design.is_battle_armor() and held:
			# not every trooper who went down is dead: on a field you hold, the wounded are brought in
			var full := (u.design as VehicleDesign).troopers
			var before := int(u.condition.get("internal", {}).get("PL", full))
			var now := maxi(0, int(cond["internal"].get("PL", 0)))
			var back := int((before - now) * float(rules["operations"]["infantry"]["wounded_return"]))
			if back > 0:
				cond["internal"]["PL"] = now + back
				wiped = false
		if wiped or (left_behind and (r["destroyed"] or wreck or r["ejected"] or str(r["reason"]) == "crippled")):
			line = "%s: %s" % [u.label(), "wiped out" if wiped else "lost on the battlefield"]
			lost_value += u.value()
			for pid in u.crew.duplicate():
				unassign(int(pid))
			set_lance(u.id, -1)
			units.erase(u.id)
			stats["losses"] = int(stats["losses"]) + 1
		else:
			u.condition = cond
			if wreck:
				u.status = "wreck"
				lost_value += int(u.base_cost() * 0.88)
				line = "%s: destroyed, recovered as a wreck" % u.label()
			else:
				u.status = "damaged" if not cond.is_empty() else "ready"
				MercRepair.normalize(u)
				line = "%s: %s" % [u.label(), "%d%% damaged" % int(u.damage_fraction() * 100) if not u.condition.is_empty() else "no damage"]
		summary["units"].append(line)
		var p: MercPerson = people.get(int(pm["pid"]))
		if p != null:
			summary["people"].append(_crew_after(p, u, r, won, lost, left_behind, sk))
	# enemy salvage when you hold the field
	summary["held"] = held
	if held:
		var pool: Array = []
		var tv := 0
		for j in range(np + na, ms.size()):
			var r2: Dictionary = ms[j]
			if r2["withdrew"] or r2["never_arrived"] or not r2["out"]:
				continue
			var e: Dictionary = meta["enemies"][j - np - na]
			if e.get("infantry", false):
				continue
			var d := db_design(str(e["design"]))
			var tmp := MercUnit.new()
			tmp.design = d
			var cnd := _condition_from_result(tmp, r2)
			var wr := _is_wreck(tmp, r2, cnd)
			tmp.condition = cnd
			if wr:
				tmp.status = "wreck"
			var val := tmp.value()
			tv += val
			pool.append({"design": e["design"], "condition": cnd, "wreck": wr, "value": val, "name": d.display_name()})
		var pct := float(contract.get("terms", {}).get("salvage", 0)) / 100.0
		var exchange := bool(contract.get("terms", {}).get("exchange", false))
		contract["salvage_value"] = int(contract.get("salvage_value", 0)) + tv
		if exchange:
			var cash_s := int(tv * pct * 0.5)
			if cash_s > 0:
				add_money(cash_s, "Salvage exchange (%s)" % meta["label"], "salvage")
				summary["money"].append("Salvage exchange: %s" % Campaign.money(cash_s))
		else:
			salvage = []
			for s in pool:
				s["sid"] = sc["id"]
				salvage.append(s)
			summary["salvage_allowance"] = int(tv * pct)
		summary["salvage"] = pool
	# battle loss compensation
	var blc := int(lost_value * float(contract.get("terms", {}).get("blc", 0)) / 100.0)
	if blc > 0:
		add_money(blc, "Battle loss compensation", "contract")
		summary["money"].append("Battle loss compensation: %s" % Campaign.money(blc))
	# contract score and enemy morale
	var delta := 0
	match outcome:
		"victory":
			delta = int(O["score_objective"]) if sc["type"] != "standup" else int(O["score_victory"])
			contract["morale"] = maxi(0, int(contract.get("morale", 3)) - 1)
		"defeat":
			delta = int(O["score_defeat"])
			contract["morale"] = mini(6, int(contract.get("morale", 3)) + 1)
	if not contract.is_empty():
		contract["score"] = int(contract.get("score", 0)) + delta
	summary["score"] = delta
	add_log("battle", "%s (%s): %s." % [sc["label"], meta.get("biome", "").trim_prefix("bf_"), outcome.to_upper()])
	return summary


func _outcome(sc: Dictionary, meta: Dictionary, res: Dictionary) -> String:
	var ms: Array = res["mechs"]
	var np := (meta["player"] as Array).size() + (meta["allies"] as Array).size()
	var mine_on := 0
	var mine_exit_far := 0
	var mine_total := np
	var foe_on := 0
	var foe_escaped := 0
	var foe_total := 0
	var bv_left := [0.0, 0.0]
	var bv_all := [0.0, 0.0]
	for i in ms.size():
		var r: Dictionary = ms[i]
		var team := int(r["team"])
		var on: bool = not r["out"]
		var b := 1.0
		bv_all[team] += b
		if on or r["withdrew"]:
			bv_left[team] += b
		if team == 0:
			if on:
				mine_on += 1
			if str(r["exited"]) != "":
				mine_exit_far += 1
		else:
			foe_total += 1
			if on:
				foe_on += 1
			if str(r["exited"]) != "" and r["withdrew"]:
				foe_escaped += 1
	var t := str(sc["type"])
	var how := str(res["how"])
	match t:
		"base_defense", "hold_the_line":
			var blds: Dictionary = res.get("buildings", {})
			var standing := 0
			for k in blds:
				if blds[k]:
					standing += 1
			if blds.size() > 0 and standing * 2 >= blds.size() and (how == "time limit" or foe_on == 0):
				return "victory"
			if standing == 0 or mine_on == 0:
				return "defeat"
			return "draw"
		"base_attack":
			var blds2: Dictionary = res.get("buildings", {})
			var down := 0
			for k2 in blds2:
				if not blds2[k2]:
					down += 1
			if blds2.size() > 0 and down * 3 >= blds2.size() * 2:
				return "victory"
			return "defeat" if mine_on == 0 else "draw"
		"breakthrough":
			var far := 0
			var far_edge := str((meta.get("edges", ["W", "E"]) as Array)[1])
			var mine_n := (meta["player"] as Array).size()
			for i2 in mine_n:
				var r3: Dictionary = ms[i2]
				if r3["withdrew"] and str(r3["exited"]) == far_edge:
					far += 1
			if far * 2 >= mine_n or (foe_on == 0 and mine_on + far > 0):
				return "victory"
			return "defeat" if mine_on == 0 else "draw"
		"chase":
			if foe_escaped * 2 >= foe_total:
				return "defeat"
			if foe_on == 0:
				return "victory"
			return "draw" if mine_on > 0 else "defeat"
		"recon", "probe":
			var rc: Array = res.get("recon", [])
			var got := 0
			for x in rc:
				if x:
					got += 1
			if rc.size() > 0 and got == rc.size() and (mine_on > 0 or _any_withdrew(ms, np)):
				return "victory"
			if got * 2 >= rc.size() and t == "probe":
				return "victory"
			return "defeat" if mine_on == 0 and not _any_withdrew(ms, np) else "draw"
	if foe_on == 0 and (mine_on > 0 or how == "enemy driven from the field"):
		return "victory"
	if mine_on == 0:
		return "defeat"
	return "draw" if bv_left[0] / maxf(1.0, bv_all[0]) <= bv_left[1] / maxf(1.0, bv_all[1]) + 0.25 else "victory"


func _any_withdrew(ms: Array, np: int) -> bool:
	for i in np:
		if ms[i]["withdrew"]:
			return true
	return false


func _condition_from_result(u: MercUnit, r: Dictionary) -> Dictionary:
	var c := {}
	if u.is_vehicle():
		c = {"armor": r["armor"], "internal": r["internal"], "dead_mounts": r.get("dead_mounts", []), "ammo": r["ammo"],
			"vstate": r.get("vstate", {}).duplicate()}
		(c["vstate"] as Dictionary).erase("crew")
	else:
		c = {"armor": r["armor"], "internal": r["internal"], "hit_slots": r["hit_slots"], "ammo": r["ammo"]}
	return c.duplicate(true)


## Wrecks can only be stripped: a 'Mech with its center torso gone, a vehicle missing a location.
func _is_wreck(u: MercUnit, r: Dictionary, cond: Dictionary) -> bool:
	if not r["destroyed"]:
		return false
	var inner: Dictionary = cond.get("internal", {})
	if u.design.is_infantry():
		return false
	if u.is_vehicle():
		for k in inner:
			if int(inner[k]) <= 0:
				return true
		return str(r["reason"]).find("fuel") >= 0 or str(r["reason"]).find("ammunition") >= 0
	return int(inner.get("CT", 1)) <= 0


func _crew_after(p: MercPerson, u: MercUnit, r: Dictionary, won: bool, lost: bool, left_behind: bool, sk: Dictionary) -> String:
	p.battles += 1
	var kills := int(r["kills"])
	p.kills += kills
	stats["kills"] = int(stats["kills"]) + kills
	p.xp += int(sk["xp_battle"]) + (int(sk["xp_victory"]) if won else 0) + mini(kills, int(sk["xp_kill_cap"])) * int(sk["xp_kill"])
	var hits := int(r["pilot_hits"])
	var reason := str(r["reason"])
	var dead := false
	if u.is_vehicle():
		if (r["crew_killed"] and opt("lethality") > 0.0) or (r["destroyed"] and rng.chance(0.4 * opt("lethality"))):
			dead = true
		elif r["destroyed"]:
			hits = rng.randi_range(1, 3)
		var vs: Dictionary = r.get("vstate", {}).get("crew", {})
		if vs.get("commander", false) or vs.get("driver", false):
			hits = maxi(hits, 1)
		if r["destroyed"] and p.crew > 0:
			p.crew = maxi(0, p.crew - int(ceil(p.crew * 0.4)))
	else:
		dead = hits >= 6 or reason.find("MechWarrior killed") >= 0 or reason.find("head destroyed") >= 0
		if dead and opt("lethality") < 1.0 and not rng.chance(opt("lethality")):
			# pulled from the wreck alive, and badly hurt
			dead = false
			hits = 5
	if dead:
		p.status = "dead"
		unassign(p.id)
		add_log("personnel", "%s was killed in action." % p.full_name())
		return "%s: KILLED IN ACTION" % p.full_name()
	if left_behind and (r["ejected"] or r["destroyed"] or reason == "crippled") and rng.chance(0.5 * minf(1.5, opt("lethality"))):
		p.status = "mia"
		unassign(p.id)
		add_log("personnel", "%s is missing in action." % p.full_name())
		return "%s: missing in action" % p.full_name()
	if hits > 0:
		p.injury_days = maxi(p.injury_days, int((hits * 7 + rng.randi_range(0, 6)) * maxf(0.25, opt("lethality"))))
		p.injury = "%d wound%s" % [hits, "" if hits == 1 else "s"]
		p.status = "injured"
		return "%s: injured, out for %d days (+%d XP)" % [p.full_name(), p.injury_days, p.xp]
	return "%s: %d kill%s (%d XP)" % [p.full_name(), kills, "" if kills == 1 else "s", p.xp]


## After a victory: take salvage up to the contract's allowance. picks = indices into `salvage`.
func claim_salvage(picks: Array) -> String:
	if salvage.is_empty():
		return ""
	var pct := float(contract.get("terms", {}).get("salvage", 0)) / 100.0
	var tv := 0
	for s in salvage:
		tv += int(s["value"])
	var allowance := int(tv * pct)
	var used := 0
	var taken: Array = []
	for i in picks:
		var s2: Dictionary = salvage[int(i)]
		if used + int(s2["value"]) > allowance:
			continue
		used += int(s2["value"])
		taken.append(s2)
	for s3 in taken:
		var u := add_unit(db_design(str(s3["design"])), "salvage", s3["condition"])
		if s3["wreck"]:
			u.status = "wreck"
		else:
			MercRepair.normalize(u)
		add_log("salvage", "Salvaged a %s%s." % [u.label(), " (wreck)" if u.wreck() else ""])
	salvage = []
	return "Took %d units of salvage." % taken.size()


## Best salvage within the allowance, most valuable first (used by auto-resolve and the default pick).
func auto_salvage_picks() -> Array:
	var pct := float(contract.get("terms", {}).get("salvage", 0)) / 100.0
	var tv := 0
	for s in salvage:
		tv += int(s["value"])
	var allowance := int(tv * pct)
	var order := range(salvage.size())
	order.sort_custom(func(a, b): return int(salvage[a]["value"]) > int(salvage[b]["value"]))
	var used := 0
	var out: Array = []
	for i in order:
		if used + int(salvage[i]["value"]) <= allowance:
			used += int(salvage[i]["value"])
			out.append(i)
	return out


## Fights the battle without you: the AI commands your units too.
func auto_resolve(sid: int, uids: Array, auto_claim := true) -> Dictionary:
	var b := make_battle(sid, uids, false)
	if b.is_empty():
		return {}
	var sim: CombatSim = b["sim"]
	for m in sim.mechs:
		var cm: CombatMech = m
		if cm.controller == "player":
			cm.controller = "ai"
	sim.support[0]["auto"] = true
	objective_orders(sim, str(scenario(sid)["type"]), b["battle"]["edges"])
	sim.run_to_end(float(sim.time_limit()) + 60.0)
	var meta: Dictionary = b["battle"]
	var res := sim.result
	res["home_edge"] = sim.home_edge(0)
	var summary := resolve_battle(meta, res)
	if auto_claim and not salvage.is_empty():
		claim_salvage(auto_salvage_picks())
	return summary


## Under Liaison or Independent command you may turn a battle down (a smaller hit than missing it).
func can_decline() -> bool:
	return contract_active() and rules["terms"]["decline_score"].has(str(contract["terms"]["command"]))


func decline_battle(sid: int) -> String:
	var s := scenario(sid)
	if s.is_empty() or str(s["status"]) != "pending":
		return "No such battle"
	if not can_decline():
		return "Your command rights don't let you refuse battles"
	s["status"] = "declined"
	s["resolved"] = day
	var pen := int(rules["terms"]["decline_score"][str(contract["terms"]["command"])])
	contract["score"] = int(contract.get("score", 0)) + pen
	add_log("battle", "You turned down %s%s." % [s["label"], (" (contract score %d)" % pen) if pen != 0 else ""])
	return ""


func _missed_battles() -> Array:
	var ev: Array = []
	for s in scenarios:
		if str(s["status"]) == "pending" and day > int(s["deadline"]):
			s["status"] = "missed"
			if not contract.is_empty():
				contract["score"] = int(contract.get("score", 0)) + int(rules["operations"]["missed_score"])
				contract["morale"] = mini(6, int(contract.get("morale", 3)) + 1)
			add_log("battle", "%s: you never showed up. Counted as a defeat." % s["label"])
			ev.append({"kind": "battle", "stop": true, "text": "Missed battle: %s" % s["label"]})
	return ev


# ================================================================== repairs and logistics

func tech_minutes() -> int:
	var R: Dictionary = rules["repair"]
	var techs := active("tech")
	var need := techs.size() * int(R["astechs_per_tech"])
	var ratio := 1.0 if need == 0 else minf(1.0, astechs / float(need))
	return int(techs.size() * int(R["tech_minutes_per_day"]) * (0.5 + 0.5 * ratio) * opt("repair_speed"))


func repair_queue() -> Array:
	var out: Array = []
	for u in combat_units():
		var uu: MercUnit = u
		if uu.condition.is_empty():
			continue
		for t in MercRepair.tasks(uu):
			out.append({"unit": uu, "task": t})
	return out


func has_part(key: String, qty: float) -> bool:
	if key == "":
		return true
	return float(warehouse.get(key, 0.0)) + 0.001 >= qty


func _use_part(key: String, qty: float) -> void:
	if key == "":
		return
	warehouse[key] = snappedf(float(warehouse.get(key, 0.0)) - qty, 0.01)
	if float(warehouse[key]) <= 0.001:
		warehouse.erase(key)


func _repair_day() -> Array:
	var ev: Array = []
	_spare_minutes = 0.0
	var techs := active("tech")
	if techs.is_empty():
		return ev
	var minutes := float(tech_minutes())
	var mode: Dictionary = rules["repair"]["modes"].get(repair_mode, rules["repair"]["modes"]["standard"])
	var best_tn := 12
	for t in techs:
		best_tn = mini(best_tn, (t as MercPerson).tech)
	var queue := repair_queue()
	# units with a pending battle first, then the least damaged (quickest back in the line)
	var urgent := {}
	for s in pending_scenarios():
		for uid in default_deployment(s):
			urgent[int(uid)] = true
	queue.sort_custom(func(a, b):
		var ua: MercUnit = a["unit"]
		var ub: MercUnit = b["unit"]
		if urgent.has(ua.id) != urgent.has(ub.id):
			return urgent.has(ua.id)
		return ua.damage_fraction() < ub.damage_fraction())
	var done_units := {}
	for q in queue:
		if minutes <= 0.0:
			break
		var u: MercUnit = q["unit"]
		var t2: Dictionary = q["task"]
		if str(t2["requires"]) != "" and _task_open(u, str(t2["requires"])):
			continue
		if not has_part(str(t2["part"]), float(t2["qty"])):
			_want(str(t2["part"]), float(t2["qty"]))
			continue
		var need2 := float(t2["minutes"]) * float(mode["time"])
		var have := float(u.progress.get(t2["key"], 0.0))
		var spend := minf(minutes, need2 - have)
		minutes -= spend
		have += spend
		if have + 0.01 < need2:
			u.progress[t2["key"]] = have
			continue
		u.progress.erase(t2["key"])
		var tn := best_tn + int(t2["tn"]) + int(mode["tn"])
		var roll := rng.roll2d6()
		if int(t2["tn"]) <= -50 or roll >= tn:
			_use_part(str(t2["part"]), float(t2["qty"]))
			MercRepair.apply(u, t2)
			done_units[u.id] = u
		elif roll == 2 and str(t2["part"]) != "":
			_use_part(str(t2["part"]), float(t2["qty"]))
			add_log("hangar", "A botched repair on the %s ruins the part (%s)." % [u.label(), t2["label"]])
	for uid in done_units:
		var u2: MercUnit = done_units[uid]
		if u2.condition.is_empty():
			add_log("hangar", "Repairs complete: the %s is ready." % u2.label())
			ev.append({"kind": "repair", "stop": false, "text": "%s repaired" % u2.label()})
	_spare_minutes = maxf(0.0, minutes)
	return ev


func _task_open(u: MercUnit, key: String) -> bool:
	for t in MercRepair.tasks(u):
		if str(t["key"]) == key:
			return true
	return false


## Adds a part to the shopping list (merged with what's already wanted).
func _want(key: String, qty: float) -> void:
	if key == "":
		return
	for s in shopping:
		if str(s["key"]) == key:
			return
	for o in orders:
		if str(o["key"]) == key:
			return
	var info := MercRepair.part_info(key, year())
	var q := qty
	if info["tons"]:
		q = maxf(1.0, ceilf(qty))
	shopping.append({"key": key, "qty": q, "next": day, "auto": true})


func order_part(key: String, qty: float) -> String:
	var info := MercRepair.part_info(key, year())
	if str(info["avail"]) == "X":
		return "Nobody sells that in %d" % year()
	shopping.append({"key": key, "qty": qty, "next": day, "auto": false})
	return ""


func cancel_shopping(i: int) -> void:
	if i >= 0 and i < shopping.size():
		shopping.remove_at(i)


func procurement_tn(key: String) -> Dictionary:
	var P: Dictionary = rules["procurement"]
	var info := MercRepair.part_info(key, year())
	var base := best("admin", "admin")
	var mods: Array = [["Logistics admin", base]]
	var am := int(P["avail_mod"].get(str(info["avail"]), 0))
	mods.append(["Availability %s" % info["avail"], am])
	var yf := year_f()
	if hall_level() != "":
		mods.append(["Hiring hall", int(P["hall_mod"])])
	elif location >= 0 and sm.industrial(location, yf):
		mods.append(["Industrial world", int(P["industrial_mod"])])
	if location >= 0 and "PERIPHERY" in sm.faction_tags(sm.owner(location, yf)):
		mods.append(["Periphery", int(P["periphery_mod"])])
	if contract_active():
		mods.append(["Employer's supply lines", int(P["contract_mod"])])
	if supply_mod() != 0:
		mods.append(["Supply situation", supply_mod()])
	var tn := 0
	for m in mods:
		tn += int(m[1])
	return {"tn": tn, "mods": mods, "possible": str(info["avail"]) != "X"}


func _procurement_day() -> Array:
	var ev: Array = []
	var P: Dictionary = rules["procurement"]
	for s in shopping.duplicate():
		if day < int(s["next"]):
			continue
		var info := part_info(str(s["key"]))
		var tn := procurement_tn(str(s["key"]))
		s["next"] = day + int(P["roll_every_days"])
		if not tn["possible"] or in_transit():
			continue
		var price := int(float(info["price"]) * float(s["qty"]))
		if cash < price:
			continue
		if rng.roll2d6() >= int(tn["tn"]):
			add_money(-price, "Parts: %s x%s" % [info["name"], str(s["qty"])], "parts")
			orders.append({"key": s["key"], "qty": s["qty"], "days": rng.randi_range(int(P["delivery_days"][0]), int(P["delivery_days"][1])),
				"refit": s.get("refit", false)})
			shopping.erase(s)
	for o in orders.duplicate():
		o["days"] = int(o["days"]) - 1
		if int(o["days"]) <= 0:
			warehouse[o["key"]] = snappedf(float(warehouse.get(o["key"], 0.0)) + float(o["qty"]), 0.01)
			orders.erase(o)
			add_log("parts", "Delivered: %s x%s." % [MercRepair.part_info(str(o["key"]), year())["name"], str(o["qty"])])
	return ev


func sell_part(key: String, qty: float) -> void:
	var have := float(warehouse.get(key, 0.0))
	var q := minf(have, qty)
	if q <= 0.0:
		return
	var info := MercRepair.part_info(key, year())
	var v := int(float(info["price"]) * q * float(rules["markets"]["part_sell_fraction"]))
	_use_part(key, q)
	add_money(v, "Sold %s" % info["name"], "market")


# ================================================================== refits

## The heat sink item a 'Mech's heat sink type is made of.
func _sink_item(hs_type: String) -> String:
	if hs_type == "single":
		return "heat_sink"
	if hs_type == "double_clan":
		for id in db.items:
			var it: Dictionary = db.items[id]
			if it.get("misc", "") == "double_heat_sink" and it.get("tech", "") == "CLAN":
				return str(id)
	if hs_type in ["laser", "compact"]:
		for id2 in db.items:
			if str(db.items[id2].get("misc", "")) == hs_type + "_heat_sink":
				return str(id2)
	return "double_heat_sink"


## Everything on a 'Mech a refit can swap, as warehouse parts: part key -> quantity.
## (Armor and the internal structure are handled apart: they aren't taken off in one piece.)
func design_parts(d: MechDesign) -> Dictionary:
	var out := {}
	out["engine:%s:%d:%d" % [d.engine_type, d.engine_rating, d.tons]] = 1.0
	out["gyro:%s:%d" % [d.gyro, int(ceil(d.engine_rating / 100.0))]] = 1.0
	out["cockpit" if d.cockpit == "standard" else "cockpit:" + d.cockpit] = 1.0
	out["item:" + _sink_item(d.hs_type)] = float(d.hs_count)
	for mt in Construction.mounts_of(d):
		var it := db.item(mt["id"])
		if it.get("misc", "") in ["heat_sink", "double_heat_sink"]:
			continue
		var key := "item:" + str(mt["id"])
		var qty := 1.0
		if it.get("kind", "") == "ammo":
			key = "ammo:" + str(mt["id"])
			qty = float(it["tons"]) if it.get("tons") != null else 1.0
		out[key] = float(out.get(key, 0.0)) + qty
	for loc in ["LA", "RA"]:
		for tag in ["lower_arm", "hand"]:
			if tag in d.slots[loc]:
				var k2 := "act:%s:%d" % [tag, d.tons]
				out[k2] = float(out.get(k2, 0.0)) + 1.0
	return out


## Tech minutes to fit one of a part (taking one off costs half).
func _part_minutes(key: String) -> float:
	var R: Dictionary = rules["repair"]
	var f := key.split(":")
	match f[0]:
		"engine", "gyro", "cockpit":
			return float(R["fixed_min"][f[0]])
		"act":
			return float(R["fixed_min"].get(f[1], 90))
		"ammo":
			return float(R["item_min"]["ammo"])
		"item":
			return float(R["item_min"].get(MercRepair._item_kind(db.item(f[1])), 90))
	return 90.0


## How much of a part the admins look for: whole tons of armor and ammo, whole pieces of the rest.
func _shop_qty(key: String, qty: float) -> float:
	if MercRepair.part_info(key, year())["tons"]:
		return maxf(1.0, ceilf(qty - 0.001))
	return ceilf(qty - 0.001)


## What turning a 'Mech (or a vehicle: _vehicle_refit_quote) into the design nd takes. Nothing is paid up front: parts the warehouse lacks
## go on the shopping list and are paid for when the admins find them.
## {"errors", "need": parts fitted, "freed": parts that come off and go back to the warehouse,
##  "missing": what the warehouse can't cover, "buy": the same as the admins would order it,
##  "cost": price of what has to be bought, "minutes": tech time, "lines": [text, quantity text, price],
##  "report": the design analysis}
func refit_quote(uid: int, nd: MechDesign) -> Dictionary:
	var u: MercUnit = units.get(uid)
	if u.is_vehicle():
		return _vehicle_refit_quote(u, nd)
	var y := year()
	var errors: Array = []
	var r := Construction.analyze(nd, y)
	if not r["valid"]:
		errors.append_array(r["errors"])
	var old := u.design
	var R: Dictionary = rules["repair"]
	var need := {}
	var freed := {}
	var minutes := 0.0
	var before := design_parts(old)
	var after := design_parts(nd)
	for k in after:
		var more := float(after[k]) - float(before.get(k, 0.0))
		if more > 0.001:
			need[k] = snappedf(more, 0.01)
			minutes += _part_minutes(k) * ceilf(more - 0.001)
	for k in before:
		var less := float(before[k]) - float(after.get(k, 0.0))
		if less > 0.001:
			freed[k] = snappedf(less, 0.01)
			minutes += _part_minutes(k) * 0.5 * ceilf(less - 0.001)
	# equipment that only changes place
	var place := {}
	var total := {}
	for pair in [[nd, 1], [old, -1]]:
		for mt in Construction.mounts_of(pair[0]):
			var it := db.item(mt["id"])
			if it.get("misc", "") in ["heat_sink", "double_heat_sink"]:
				continue
			var pk := "%s|%s|%s" % [mt["id"], mt["loc"], mt["rear"]]
			place[pk] = int(place.get(pk, 0)) + int(pair[1])
			total[mt["id"]] = int(total.get(mt["id"], 0)) + int(pair[1])
	var moved := {}
	for pk in place:
		if int(place[pk]) > 0:
			var id := str(pk).get_slice("|", 0)
			moved[id] = int(moved.get(id, 0)) + int(place[pk])
	for id in moved:
		var n := int(moved[id]) - maxi(0, int(total.get(id, 0)))
		if n > 0:
			minutes += n * float(R["item_min"].get(MercRepair._item_kind(db.item(id)), 90))
	# armor
	var ppt := Construction.armor_ppt(nd.armor_type)
	var akey := "armor:" + nd.armor_type
	if nd.armor_type != old.armor_type:
		need[akey] = snappedf(nd.armor_total() / ppt, 0.01)
		minutes += nd.armor_total() * float(R["armor_min_per_point"])
	else:
		var pts := 0
		for k in nd.armor:
			pts += absi(int(nd.armor[k]) - int(old.armor.get(k, 0)))
		minutes += pts * float(R["armor_min_per_point"])
		if nd.armor_total() > old.armor_total():
			need[akey] = snappedf((nd.armor_total() - old.armor_total()) / ppt, 0.01)
	# a new internal structure is a new skeleton: every location
	if nd.structure != old.structure:
		need["loc:head:%d" % nd.tons] = 1.0
		need["loc:limb:%d" % nd.tons] = 4.0
		need["loc:torso:%d" % nd.tons] = 3.0
		minutes += 8.0 * float(R["location_replace_min"])
	var dated := {"engine": ["engine", nd.engine_type], "gyro": ["gyro", nd.gyro], "cockpit": ["cockpit", nd.cockpit],
		"armor": ["armor", nd.armor_type], "loc": ["structure", nd.structure]}
	var sup := _refit_supply(need, dated, errors)
	if nd.myomer != old.myomer and not db.component_available("myomer", nd.myomer, y):
		errors.append("%s myomer isn't made in %d" % [nd.myomer.capitalize(), y])
	if nd.hs_type != old.hs_type and not db.component_available("hs", nd.hs_type, y) \
			and (sup["missing"] as Dictionary).has("item:" + _sink_item(nd.hs_type)):
		errors.append("%s heat sinks aren't made in %d" % [nd.hs_type.capitalize(), y])
	return {"errors": errors, "need": need, "freed": freed, "missing": sup["missing"], "buy": sup["buy"], "cost": sup["cost"],
		"minutes": minutes, "lines": sup["lines"], "report": r}


## What the warehouse can't cover of the parts a refit needs, and whether anybody sells the rest.
## `dated`: part kind -> [component kind, key] for the parts whose tech has a date. Adds to `errors`.
func _refit_supply(need: Dictionary, dated: Dictionary, errors: Array) -> Dictionary:
	var y := year()
	var missing := {}
	var buy := {}
	var cost := 0
	var lines: Array = []
	for k in need:
		var info := part_info(str(k))
		var short := float(need[k]) - float(warehouse.get(k, 0.0))
		var unit_txt := " t" if info["tons"] else ""
		if short <= 0.001:
			lines.append([info["name"], "%s%s" % [_qty_str(float(need[k])), unit_txt], "in the warehouse"])
			continue
		missing[k] = snappedf(short, 0.01)
		var kind := str(k).get_slice(":", 0)
		var sold := str(info["avail"]) != "X"
		if dated.has(kind) and not db.component_available(dated[kind][0], dated[kind][1], y):
			sold = false
		if not sold:
			errors.append("%s: nobody sells it in %d (need %s more)" % [info["name"], y, _qty_str(short)])
			continue
		buy[k] = _shop_qty(k, short)
		var price := int(float(info["price"]) * float(buy[k]))
		cost += price
		lines.append([info["name"], "%s%s" % [_qty_str(float(need[k])), unit_txt],
			"search for %s%s, %s" % [_qty_str(float(buy[k])), unit_txt, Campaign.money(price)]])
	return {"missing": missing, "buy": buy, "cost": cost, "lines": lines}


## A vehicle's weapons, ammo and gear as warehouse parts, with the heat sinks its energy weapons need.
func vehicle_parts(d: VehicleDesign) -> Dictionary:
	var out := {}
	for e in d.equipment:
		var it := db.item(str(e[0]))
		var key := "item:" + str(e[0])
		var qty := 1.0
		if it.get("kind", "") == "ammo":
			key = "ammo:" + str(e[0])
			qty = float(it["tons"]) if it.get("tons") != null else 1.0
		out[key] = float(out.get(key, 0.0)) + qty
	var sinks := int(VehicleConstruction.analyze(d).get("sinks", 0))
	if sinks > 0:
		out["item:heat_sink"] = float(out.get("item:heat_sink", 0.0)) + sinks
	return out


## Where a part may sit on a vehicle: weapons in a facing or the turret, ammo in the body, gear anywhere.
static func vehicle_loc_takes(d: VehicleDesign, loc: String, it: Dictionary) -> bool:
	if loc == "RO" or it.is_empty():
		return false
	if loc != "BD" and not d.armor.has(loc):
		return false
	match str(it.get("kind", "")):
		"weapon":
			return loc != "BD"
		"ammo":
			return loc == "BD"
	return true


## refit_quote for a combat vehicle: weapons, ammo, gear and armor change; the hull, engine, drive and
## turret stay as built.
func _vehicle_refit_quote(u: MercUnit, nd0: MechDesign) -> Dictionary:
	var y := year()
	var errors: Array = []
	var old := u.design as VehicleDesign
	var nd := nd0 as VehicleDesign
	if nd == null:
		return {"errors": ["Not a vehicle design"], "need": {}, "freed": {}, "missing": {}, "buy": {}, "cost": 0,
			"minutes": 0.0, "lines": [], "report": {}}
	var r := Construction.analyze(nd, y)
	if not r["valid"]:
		errors.append_array(r["errors"])
	if nd.tons != old.tons or nd.motion != old.motion or nd.walk != old.walk or nd.engine_rating != old.engine_rating \
			or nd.engine_type != old.engine_type or nd.turret != old.turret or nd.armor.size() != old.armor.size():
		errors.append("A refit can't change the hull, engine, drive or turret")
	var was := {}   # a stock vehicle may carry something where a refit would not put it: that stays legal
	for e in old.equipment:
		was["%s|%s" % [e[0], e[1]]] = true
	for e in nd.equipment:
		var it := db.item(str(e[0]))
		if not was.has("%s|%s" % [e[0], e[1]]) and not vehicle_loc_takes(nd, str(e[1]), it):
			errors.append("%s can't go in the %s" % [it.get("name", e[0]), VehicleDesign.VLOC_NAMES.get(str(e[1]), e[1])])
	var R: Dictionary = rules["repair"]
	var need := {}
	var freed := {}
	var minutes := 0.0
	var before := vehicle_parts(old)
	var after := vehicle_parts(nd)
	for k in after:
		var more := float(after[k]) - float(before.get(k, 0.0))
		if more > 0.001:
			need[k] = snappedf(more, 0.01)
			minutes += _part_minutes(k) * ceilf(more - 0.001)
	for k in before:
		var less := float(before[k]) - float(after.get(k, 0.0))
		if less > 0.001:
			freed[k] = snappedf(less, 0.01)
			minutes += _part_minutes(k) * 0.5 * ceilf(less - 0.001)
	# equipment that only changes place
	var place := {}
	var total := {}
	for pair in [[nd, 1], [old, -1]]:
		for e in (pair[0] as VehicleDesign).equipment:
			var pk := "%s|%s" % [e[0], e[1]]
			place[pk] = int(place.get(pk, 0)) + int(pair[1])
			total[e[0]] = int(total.get(e[0], 0)) + int(pair[1])
	var moved := {}
	for pk in place:
		if int(place[pk]) > 0:
			var id := str(pk).get_slice("|", 0)
			moved[id] = int(moved.get(id, 0)) + int(place[pk])
	for id in moved:
		var n := int(moved[id]) - maxi(0, int(total.get(id, 0)))
		if n > 0:
			minutes += n * float(R["item_min"].get(MercRepair._item_kind(db.item(id)), 90))
	# armor
	var ppt := VehicleConstruction.armor_ppt(nd)
	var akey := "armor:" + nd.armor_type
	if nd.armor_type != old.armor_type:
		need[akey] = snappedf(nd.armor_total() / ppt, 0.01)
		minutes += nd.armor_total() * float(R["armor_min_per_point"])
	else:
		var pts := 0
		for k in nd.armor:
			pts += absi(int(nd.armor[k]) - int(old.armor.get(k, 0)))
		minutes += pts * float(R["armor_min_per_point"])
		if nd.armor_total() > old.armor_total():
			need[akey] = snappedf((nd.armor_total() - old.armor_total()) / ppt, 0.01)
	var sup := _refit_supply(need, {"armor": ["armor", nd.armor_type]}, errors)
	return {"errors": errors, "need": need, "freed": freed, "missing": sup["missing"], "buy": sup["buy"], "cost": sup["cost"],
		"minutes": minutes, "lines": sup["lines"], "report": r}


static func _qty_str(q: float) -> String:
	return str(int(round(q))) if absf(q - round(q)) < 0.005 else "%.2f" % q


## Days the techs need for that many minutes of refit work (-1 = no techs), repairs aside.
func refit_days(minutes: float) -> int:
	var tm := tech_minutes()
	if tm <= 0:
		return -1
	var mode: Dictionary = rules["repair"]["modes"].get(repair_mode, rules["repair"]["modes"]["standard"])
	return maxi(1, int(ceil(minutes * float(mode["time"]) / tm)))


## Orders the refit: sets aside what the warehouse has and puts the rest on the shopping list.
## The work itself starts once every part is in and the 'Mech is repaired.
func commit_refit(uid: int, nd: MechDesign) -> String:
	var u: MercUnit = units.get(uid)
	if u == null or u.wreck() or u.status == "sold":
		return "No such unit"
	if not u.refit.is_empty():
		return "The %s already has a refit on order" % u.label()
	var q := refit_quote(uid, nd)
	if not (q["errors"] as Array).is_empty():
		return str(q["errors"][0])
	if float(q["minutes"]) <= 0.0:
		return "Nothing to change"
	u.refit = {"design": nd.to_dict(), "need": q["need"], "have": {}, "freed": q["freed"], "minutes": float(q["minutes"]),
		"done": 0.0, "ordered": day}
	_refit_gather(u)
	_refit_shop()
	var miss := refit_missing(u)
	if miss.is_empty():
		add_log("hangar", "Refit ordered for the %s: every part is in the warehouse." % u.label())
	else:
		add_log("hangar", "Refit ordered for the %s: %d kinds of parts go on the shopping list." % [u.label(), miss.size()])
	return ""


## Drops a refit on order; the parts set aside for it go back on the shelves.
func cancel_refit(uid: int) -> String:
	var u: MercUnit = units.get(uid)
	if u == null or u.refit.is_empty():
		return "No refit on order"
	var have: Dictionary = u.refit.get("have", {})
	for k in have:
		warehouse[k] = snappedf(float(warehouse.get(k, 0.0)) + float(have[k]), 0.01)
	u.refit = {}
	_refit_shop()
	add_log("hangar", "Refit of the %s called off." % u.label())
	return ""


## Parts a refit on order still waits for: part key -> quantity.
func refit_missing(u: MercUnit) -> Dictionary:
	var out := {}
	var need: Dictionary = u.refit.get("need", {})
	var have: Dictionary = u.refit.get("have", {})
	for k in need:
		var short := float(need[k]) - float(have.get(k, 0.0))
		if short > 0.001:
			out[k] = snappedf(short, 0.01)
	return out


## Parts every refit on order still waits for, together.
func refit_wanted() -> Dictionary:
	var out := {}
	for id in units:
		var u: MercUnit = units[id]
		if u.refit.is_empty():
			continue
		var miss := refit_missing(u)
		for k in miss:
			out[k] = snappedf(float(out.get(k, 0.0)) + float(miss[k]), 0.01)
	return out


## 0..1: how far the techs are with a refit.
func refit_progress(u: MercUnit) -> float:
	if u.refit.is_empty():
		return 0.0
	return clampf(float(u.refit.get("done", 0.0)) / maxf(1.0, float(u.refit.get("minutes", 1.0))), 0.0, 1.0)


## Sets aside whatever the warehouse has of the parts a refit still waits for.
func _refit_gather(u: MercUnit) -> void:
	var have: Dictionary = u.refit["have"]
	var miss := refit_missing(u)
	for k in miss:
		var take := minf(float(miss[k]), float(warehouse.get(k, 0.0)))
		if take > 0.001:
			_use_part(k, take)
			have[k] = snappedf(float(have.get(k, 0.0)) + take, 0.01)


## Keeps the shopping list in step with the refits on order: one search per missing part, sized to
## what's still short after the deliveries already on the way.
func _refit_shop() -> void:
	var short := refit_wanted()
	for o in orders:
		if o.get("refit", false) and short.has(o["key"]):
			short[o["key"]] = float(short[o["key"]]) - float(o["qty"])
	for s in shopping.duplicate():
		if not s.get("refit", false):
			continue
		var k := str(s["key"])
		var want := float(short.get(k, 0.0))
		short.erase(k)
		if want <= 0.001:
			shopping.erase(s)
		else:
			s["qty"] = _shop_qty(k, want)
	for k in short:
		if float(short[k]) > 0.001:
			shopping.append({"key": k, "qty": _shop_qty(k, float(short[k])), "next": day, "auto": true, "refit": true})


## The day's refit work, with the tech time repairs left over. A refit starts once all its parts are
## in, the 'Mech is repaired and no battle is waiting for it; from then on it's off the line.
func _refit_day() -> Array:
	var ev: Array = []
	var minutes := _spare_minutes
	var mode: Dictionary = rules["repair"]["modes"].get(repair_mode, rules["repair"]["modes"]["standard"])
	var urgent := {}
	for s in pending_scenarios():
		for uid in default_deployment(s):
			urgent[int(uid)] = true
	var any := false
	for id in units.keys():
		var u: MercUnit = units[id]
		if u.refit.is_empty():
			continue
		any = true
		if u.wreck() or u.status == "sold":
			cancel_refit(u.id)
			continue
		_refit_gather(u)
		if not refit_missing(u).is_empty() or not u.condition.is_empty() or minutes <= 0.0:
			continue
		if not u.refitting() and urgent.has(u.id):
			continue
		var total := float(u.refit["minutes"])
		var done := float(u.refit.get("done", 0.0))
		var spend := minf(minutes, (total - done) * float(mode["time"]))
		minutes -= spend
		done += spend / float(mode["time"])
		u.refit["done"] = done
		if done + 0.01 < total:
			continue
		var was := u.label()
		var freed: Dictionary = u.refit.get("freed", {})
		for k in freed:
			warehouse[k] = snappedf(float(warehouse.get(k, 0.0)) + float(freed[k]), 0.01)
		u.design = VehicleDesign.any_from_dict(u.refit["design"])
		u.condition = {}
		u.progress = {}
		u.refit = {}
		if u.status == "damaged":
			u.status = "ready"
		add_log("hangar", "Refit complete: the %s leaves the gantry as the %s." % [was, u.design.display_name()])
		ev.append({"kind": "repair", "stop": false, "text": "%s: refit complete" % u.label()})
	if any:
		_refit_shop()
	_spare_minutes = maxf(0.0, minutes)
	return ev


# ================================================================== people over time

func _healing_day() -> void:
	var docs := active("doctor")
	var capacity := docs.size() * 25 + medics * 4
	var patients := 0
	for p in roster():
		if (p as MercPerson).status == "injured":
			patients += 1
	var rate := 1 if capacity >= patients and not docs.is_empty() else 0
	for p in roster():
		var pp: MercPerson = p
		if pp.status != "injured":
			continue
		if rate > 0 or rng.chance(0.5):
			pp.injury_days -= 1
		if pp.injury_days <= 0:
			pp.injury_days = 0
			pp.injury = ""
			pp.status = "active"
			add_log("personnel", "%s is back on duty." % pp.full_name())


# ================================================================== the timeline: canon events, wars, front lines

static func yf_of(j: int) -> float:
	var t := ymd(j)
	return float(t[0]) + (j - jdn(int(t[0]), 1, 1)) / 365.25


static func event_day(e: Dictionary) -> int:
	return jdn(int(e["year"]), int(e["month"]), int(e["day"]))


func add_news(kind: String, title: String, text: String, major := false) -> void:
	news.append({"day": day, "kind": kind, "title": title, "text": text, "major": major})
	var keep := int(rules["timeline"]["news_kept"])
	if news.size() > keep:
		news = news.slice(news.size() - keep)


## Timeline events whose effect on the mercenary trade is in force today: [{"title", "fx", "left", "note"}].
## Nothing is stored: an event counts from its date for its "days", whenever the campaign started.
func timeline_active() -> Array:
	if _tl_day == day:
		return _tl_active
	var out: Array = []
	for e in (db.events if flag("trade_effects") else []):
		if str(e.get("only", "")) == "stable" or not e.has("merc"):
			continue
		var fx: Dictionary = e["merc"]
		var d0 := event_day(e)
		var left := d0 + int(fx.get("days", 365)) - day
		if d0 <= day and left > 0:
			out.append({"title": str(e["title"]), "fx": fx, "left": left, "note": str(fx.get("note", ""))})
	_tl_day = day
	_tl_active = out
	return out


func timeline_mult(key: String) -> float:
	var v := 1.0
	for a in timeline_active():
		v *= float(a["fx"].get(key, 1.0))
	return v


## Parts and units cost this much more (or less) than their list price today.
func price_mult() -> float:
	return timeline_mult("price") * opt("prices")


## Added to every procurement target number: shortages in wartime.
func supply_mod() -> int:
	var v := int(opt("supply"))
	for a in timeline_active():
		v += int(a["fx"].get("supply", 0))
	return v


## How much more (or less) than usual a faction is hiring today.
func employer_weight(f: String) -> float:
	var v := 1.0
	for a in timeline_active():
		v *= float((a["fx"].get("employers", {}) as Dictionary).get(f, 1.0))
	return v


## A part's name, availability and today's price (the list price times price_mult).
func part_info(key: String) -> Dictionary:
	var info := MercRepair.part_info(key, year())
	var pm := price_mult()
	if absf(pm - 1.0) > 0.001:
		info = info.duplicate()
		info["price"] = int(round(float(info["price"]) * pm))
	return info


## What the timeline changes for the company today, in words: [{"title", "text", "left", "note"}].
func timeline_summary() -> Array:
	var out: Array = []
	for a in timeline_active():
		var fx: Dictionary = a["fx"]
		var parts: Array = []
		for k in [["pay", "contract pay"], ["offers", "contracts on offer"], ["price", "prices"], ["recruits", "people for hire"]]:
			if fx.has(k[0]) and absf(float(fx[k[0]]) - 1.0) > 0.005:
				parts.append("%s %+d%%" % [k[1], int(round((float(fx[k[0]]) - 1.0) * 100.0))])
		if int(fx.get("supply", 0)) != 0:
			parts.append("parts harder to find (%+d)" % int(fx["supply"]))
		if parts.is_empty() and str(a["note"]) == "":
			continue
		out.append({"title": a["title"], "text": ", ".join(parts), "left": int(a["left"]), "note": a["note"]})
	return out


## Who hires more and who hires less than usual today, everything in force taken together:
## {"more": [faction names], "less": [faction names]}. Only states that hold worlds are named.
func hiring_outlook() -> Dictionary:
	var net := {}
	for a in timeline_active():
		var emp: Dictionary = a["fx"].get("employers", {})
		for f in emp:
			net[f] = float(net.get(f, 1.0)) * float(emp[f])
	var bd := sm.borders(year_f())
	var more: Array = []
	var less: Array = []
	for f in net:
		if not bd.has(f):
			continue
		if float(net[f]) >= 1.15:
			more.append(sm.faction_name(str(f)))
		elif float(net[f]) <= 0.85:
			less.append(sm.faction_name(str(f)))
	return {"more": more, "less": less}


## The sides of a war in words: "the Federated Suns and the Lyran Commonwealth against the Capellan
## Confederation and the Draconis Combine". The data lists a war as pairs of enemies; here they are
## sorted into the two camps (or named one by one when it is everyone against everyone).
func war_sides(w: Dictionary, yf: float) -> String:
	var adj := {}
	var selfs: Array = []
	for p in w["pairs"]:
		var ps: Array = p
		if ps.size() < 2:
			continue
		var a := str(ps[0])
		var b := str(ps[1])
		if a == b:
			if not (a in selfs):
				selfs.append(a)
			continue
		for side in [[a, b], [b, a]]:
			if not adj.has(side[0]):
				adj[side[0]] = []
			if not (side[1] in adj[side[0]]):
				(adj[side[0]] as Array).append(side[1])
	var parts: Array = []
	var seen := {}
	for start in adj:
		if seen.has(start):
			continue
		var camp := {start: 0}
		var queue: Array = [start]
		var two_camps := true
		while not queue.is_empty():
			var f: String = queue.pop_front()
			seen[f] = true
			for o in adj[f]:
				if not camp.has(o):
					camp[o] = 1 - int(camp[f])
					queue.append(o)
				elif int(camp[o]) == int(camp[f]):
					two_camps = false
		var sa: Array = []
		var sb: Array = []
		for f2 in camp:
			(sa if int(camp[f2]) == 0 else sb).append(_the(sm.faction_name(str(f2), yf)))
		if two_camps:
			parts.append("%s against %s" % [_and_list(sa), _and_list(sb)])
		else:
			parts.append("%s, each against the others" % _and_list(sa + sb))
	for f3 in selfs:
		if not adj.has(f3):
			parts.append("%s against itself" % _the(sm.faction_name(str(f3), yf)))
	return "; ".join(parts)


## A faction's name as it reads in a sentence: "the Draconis Combine", "Clan Wolf".
static func _the(n: String) -> String:
	if n.begins_with("Clan ") or n.begins_with("The ") or n.begins_with("the ") or n in ["ComStar", "Ronin", "Stone's Coalition", "Independent", "Pirate", "Mercenary"]:
		return n
	return "the " + n


static func _and_list(a: Array) -> String:
	if a.size() <= 1:
		return "" if a.is_empty() else str(a[0])
	return ", ".join(a.slice(0, a.size() - 1)) + " and " + str(a[a.size() - 1])


## Is a war's beginning ("war_start") or end ("war_end") told by an entry of the timeline?
func _war_told(war_name: String, key: String) -> bool:
	for e in db.events:
		if war_name in e.get(key, []):
			return true
	return false


## The day's news from the timeline: its dated events, and wars in MegaMek's data it has no entry for.
func _timeline_day() -> Array:
	var ev: Array = []
	if not flag("news"):
		events_day = day
		return ev
	if events_day <= 0 or events_day > day:
		events_day = day - 1
	var y0 := yf_of(events_day)
	var y1 := year_f()
	for e in db.events:
		if str(e.get("only", "")) == "stable":
			continue
		var d0 := event_day(e)
		if d0 <= events_day or d0 > day:
			continue
		var text := str(e["text"])
		var note := str((e.get("merc", {}) as Dictionary).get("note", ""))
		if note != "":
			text += " " + note
		var major := bool(e.get("major", false))
		add_news("event", str(e["title"]), text, major)
		add_log("news", str(e["title"]))
		ev.append({"kind": "news", "stop": major, "text": "%s. %s" % [e["title"], text]})
	for w in sm.wars_turning(y0, y1, "start"):
		if _war_told(str(w["name"]), "war_start"):
			continue
		var sides := war_sides(w, y1)
		if sides == "":
			continue
		add_news("war", str(w["name"]), "War: %s." % sides)
		add_log("news", "War: %s (%s)" % [w["name"], sides])
		ev.append({"kind": "news", "stop": false, "text": "War: %s (%s)" % [w["name"], sides]})
	for w in sm.wars_turning(y0, y1, "end"):
		if _war_told(str(w["name"]), "war_end"):
			continue
		var sides2 := war_sides(w, y0)
		if sides2 == "":
			continue
		add_news("war", "%s: the fighting ends" % w["name"], "The guns are quiet. It was %s." % sides2)
		add_log("news", "%s: the fighting ends" % w["name"])
		ev.append({"kind": "news", "stop": false, "text": "%s: the fighting ends" % w["name"]})
	events_day = day
	return ev


## Once a month: the worlds that changed hands (from the planets' ownership dates) and hiring halls that
## opened or closed. A change on the world the company stands on, or fights for, is worth stopping for.
func _front_report() -> Array:
	var ev: Array = []
	if front_day <= 0 or front_day > day or not flag("news"):
		front_day = day
		return ev
	var y0 := yf_of(front_day)
	var y1 := year_f()
	var last := ymd(day - 1)
	front_day = day
	# a world that changes hands twice in the month counts once, from its first owner to its last
	var first := {}
	var final := {}
	var sys_order: Array = []
	for ch in sm.owner_changes(y0, y1):
		var s0 := int(ch[1])
		if not first.has(s0):
			first[s0] = str(ch[2])
			sys_order.append(s0)
		final[s0] = str(ch[3])
	var groups := {}
	var order: Array = []
	for si in sys_order:
		var from := str(first[si])
		var to := str(final[si])
		if from == to:
			continue
		var mine := (int(si) == location and not in_transit()) or (not contract.is_empty() and int(si) == int(contract.get("system", -1)))
		if mine and sm.is_real_faction(to):
			var txt := "%s now belongs to %s." % [sm.name_of(int(si)), _the(sm.faction_name(to, y1))]
			add_log("news", txt)
			ev.append({"kind": "news", "stop": true, "text": txt})
		if not sm.is_real_faction(from) or not sm.is_real_faction(to):
			continue
		var key := from + ">" + to
		if not groups.has(key):
			groups[key] = {"from": from, "to": to, "sys": []}
			order.append(key)
		(groups[key]["sys"] as Array).append(int(si))
	var lines: Array = []
	if not order.is_empty():
		order.sort_custom(func(a, b): return (groups[a]["sys"] as Array).size() > (groups[b]["sys"] as Array).size())
		var max_lines := int(rules["timeline"]["front_lines"])
		for key in order.slice(0, max_lines):
			var g: Dictionary = groups[key]
			var ss: Array = g["sys"]
			ss.sort_custom(func(a, b): return sm.population(int(a), y1) > sm.population(int(b), y1))
			var names: Array = []
			for si2 in ss.slice(0, 3):
				names.append(sm.name_of(int(si2)))
			var head := "%s to %s" % [sm.faction_name(str(g["from"]), y0), sm.faction_name(str(g["to"]), y1)]
			if ss.size() <= 3:
				lines.append("%s: %s." % [head, _and_list(names)])
			else:
				lines.append("%s: %d worlds (%s and %d more)." % [head, ss.size(), ", ".join(names), ss.size() - 3])
		if order.size() > max_lines:
			lines.append("And smaller changes along %d other borders." % (order.size() - max_lines))
	for h in sm.hall_changes(y0, y1):
		if str(h[1]) == "":
			lines.append("The hiring hall on %s has closed." % sm.name_of(int(h[0])))
		else:
			lines.append("A hiring hall is open on %s (%s)." % [sm.name_of(int(h[0])), str(h[1]).to_lower()])
	if not lines.is_empty():
		var title := "Worlds changing hands, %s %d" % [MONTHS[int(last[1]) - 1], int(last[0])]
		add_news("front", title, "\n".join(lines))
		ev.append({"kind": "news", "stop": false, "text": title})
	return ev


# ================================================================== the day

## One day forward. Returns the day's events: {"kind", "text", "stop"} (stop = worth pausing for).
func advance_day() -> Array:
	if game_over:
		return []
	var ev: Array = []
	var last_month := month()
	day += 1
	sm.year_hint = year_f()
	var trav := _travel_day()
	ev.append_array(trav)
	ev.append_array(_repair_day())
	_healing_day()
	ev.append_array(_procurement_day())
	ev.append_array(_refit_day())
	ev.append_array(_missed_battles())
	ev.append_array(_timeline_day())
	if weekday() == 0:
		ev.append_array(_weekly_battles())
	if month() != last_month:
		_month_end()
		ev.append({"kind": "month", "stop": true, "text": "New month: payroll and contract payments"})
		ev.append_array(_front_report())
		if not in_transit():
			refresh_markets()
	if contract_active() and day >= int(contract["end_day"]):
		ev.append_array(_end_contract())
	for o in contract_offers.duplicate():
		if day > int(o["expires"]):
			contract_offers.erase(o)
	var landed := false
	for e in trav:
		landed = landed or str(e.get("kind", "")) == "arrive"
	ev.append_array(_arena_day(landed))
	if game_over:
		ev.append({"kind": "game_over", "stop": true, "text": "The company has folded"})
	return ev


## Runs days until something worth stopping for happens (or max_days pass).
func advance_to_event(max_days := 45) -> Array:
	var all: Array = []
	for k in max_days:
		var ev := advance_day()
		all.append_array(ev)
		var stop := false
		for e in ev:
			if e.get("stop", false):
				stop = true
		if stop or game_over:
			break
	return all


# ================================================================== Solaris VII: the arenas

const ARENA_TONS := {"light": [20, 35], "medium": [40, 55], "heavy": [60, 75], "assault": [80, 100]}
const ARENA_STYLES := [
	["brawler", {"range": "close", "heat": "hot", "position": "brawl", "retreat": 0.6}],
	["sniper", {"range": "long", "heat": "balanced", "position": "cover", "retreat": 0.5}],
	["all-rounder", {"range": "optimal", "heat": "balanced", "position": "cover", "retreat": 0.55}],
	["flanker", {"range": "optimal", "heat": "balanced", "position": "flank", "retreat": 0.55}],
]


func solaris() -> int:
	return sm.index_of("Solaris")


func on_solaris() -> bool:
	return not in_transit() and location == solaris()


## The promoters only book a company that is free to fight: on Solaris VII and not serving a contract.
func arena_open() -> bool:
	return on_solaris() and not contract_active()


func arena_offer(oid: int) -> Dictionary:
	for o in arena_offers:
		if int(o["id"]) == oid:
			return o
	return {}


## A fresh fight card: one duel offer per slot, in the weight classes the company can field.
func refresh_arena() -> void:
	arena_offers = []
	if not arena_open():
		return
	var S: Dictionary = rules["solaris"]
	var have := {}
	for uid in units:
		var u: MercUnit = units[uid]
		if not u.is_vehicle() and not u.wreck():
			have[db.weight_class(u.tons())] = true
	var classes: Array = have.keys()
	if classes.is_empty():
		return
	var ars: Array = db.arenas["arenas"]
	var diff := str(settings.get("difficulty", "Regular"))
	var shift := int(S["skill_shift"].get(diff, 0))
	for k in int(S["offers"]):
		var cls: String = classes[rng.randi_range(0, classes.size() - 1)]
		var ar: Dictionary = ars[rng.randi_range(0, ars.size() - 1)]
		var prestige := float(ar["prestige"])
		var house := str(ar.get("house", ""))
		var fac := "MERC"
		for key in CULTURE:
			if CULTURE[key] == house:
				fac = key
		var tons: Array = ARENA_TONS[cls]
		var did := ForceGen.pick(fac, year(), "mech", rng, int(tons[0]), int(tons[1]))
		if did == "" or db.weight_class(int(ForceGen.info(did).get("tons", 0))) != cls:
			continue
		var opp := gen_person("mechwarrior", clampf(0.25 + prestige * 0.3, 0.2, 0.9), house if house != "" else "Mercenary", false)
		opp.gunnery = clampi(int(round(5.6 - prestige * 1.3 + rng.randf_range(-0.6, 0.6))) - shift, 1, 6)
		opp.piloting = clampi(opp.gunnery + rng.randi_range(0, 1), 1, 7)
		var n: Dictionary = db.names
		var stable := "%s %s" % [n["stable_words_a"][rng.randi_range(0, n["stable_words_a"].size() - 1)], n["stable_words_b"][rng.randi_range(0, n["stable_words_b"].size() - 1)]]
		var style := rng.randi_range(0, ARENA_STYLES.size() - 1)
		var th: Dictionary = db.arenas["themes"].get(ar["theme"], {})
		var co: Dictionary = th.get("conditions", {})
		var light := "day"
		var lr := rng.randf()
		if lr < float(co.get("night", 0.0)):
			light = "night"
		elif lr < float(co.get("night", 0.0)) + float(co.get("dusk", 0.0)):
			light = "dusk"
		var wts: Dictionary = co.get("weather", {"clear": 1})
		var wk: Array = wts.keys()
		var ws: Array = []
		for w in wk:
			ws.append(float(wts[w]))
		var purse := int(round(float(S["purse"][cls]) * prestige * rng.randf_range(0.9, 1.15) / 1000.0)) * 1000
		arena_offers.append({"id": new_id(), "class": cls, "arena": ar["id"], "arena_name": ar["name"], "sector": ar.get("sector", ""),
			"theme": ar["theme"], "prestige": prestige, "seed": rng.randi_range(1, 2000000000), "purse": purse,
			"conditions": {"light": light, "weather": str(wk[rng.weighted_index(ws)]), "floodlights": bool(ar.get("floodlights", false))},
			"opp": {"design": did, "name": opp.full_name(), "callsign": opp.short_name(), "gunnery": opp.gunnery, "piloting": opp.piloting,
				"traits": opp.traits.duplicate(), "stable": stable, "style": style,
				"color": [snappedf(rng.randf(), 0.01), snappedf(rng.randf_range(0.45, 0.8), 0.01), snappedf(rng.randf_range(0.6, 0.9), 0.01)]},
			"day": day})


## The 'Mechs that may answer an offer: in its weight class, fit to fight and with a MechWarrior aboard.
func arena_entrants(o: Dictionary) -> Array:
	var out: Array = []
	var ids: Array = units.keys()
	ids.sort()
	for uid in ids:
		var u: MercUnit = units[uid]
		if not u.is_vehicle() and deployable(u) and db.weight_class(u.tons()) == str(o.get("class", "")):
			out.append(int(uid))
	return out


func arena_purses(o: Dictionary) -> Array:
	var p := int(o["purse"])
	var share := float(rules["solaris"]["winner_share"])
	return [int(p * share), p - int(p * share)]


## Builds the duel. The bout dictionary is what the fight viewer and resolve_arena() work from.
func make_arena_bout(oid: int, uid: int, orders: Dictionary, record := true) -> Dictionary:
	var o := arena_offer(oid)
	var u: MercUnit = units.get(uid)
	if o.is_empty() or u == null or not arena_open() or not (uid in arena_entrants(o)):
		return {}
	var p := crew_of(u)
	var arena := ArenaGenerator.generate(str(o["theme"]), int(o["seed"]), 1, str(o["arena"]), 2)
	var od: Dictionary = o["opp"]
	var mine := {"design": u.design.copy(), "warrior": p.sim_dict(), "orders": orders.duplicate(true), "condition": u.sim_condition()}
	var theirs := {"design": db_design(str(od["design"])), "orders": (ARENA_STYLES[int(od["style"])][1] as Dictionary).duplicate(),
		"warrior": {"callsign": od["callsign"], "name": od["name"], "gunnery": int(od["gunnery"]), "piloting": int(od["piloting"]), "traits": od.get("traits", [])}}
	var rule := {"to_death": false, "conditions": o["conditions"], "time_limit": float(db.tables["time_limit_seconds"]),
		"calls": int(db.tables.get("corner_calls_per_fight", 3))}
	var sim := CombatSim.create(arena, [[mine], [theirs]], int(o["seed"]) * 13 + 5, rule, record)
	var bout := {"merc_arena": true, "oid": oid, "uid": uid, "pid": p.id, "kind": "regular", "format": "duel", "class": o["class"],
		"arena_name": o["arena_name"], "theme": o["theme"], "purse": o["purse"], "orders": orders, "opp": od}
	return {"sim": sim, "bout": bout}


## Books the result: the purse, the damage (repaired like any other), the MechWarrior's wounds and experience.
func resolve_arena(bout: Dictionary, res: Dictionary) -> Dictionary:
	if bout.get("resolved", false):
		return {}
	bout["resolved"] = true
	var o := arena_offer(int(bout["oid"]))
	var u: MercUnit = units.get(int(bout["uid"]))
	if o.is_empty() or u == null:
		return {}
	arena_offers.erase(o)
	var r: Dictionary = res["mechs"][0]
	var won := int(res["winner"]) == 0
	var draw := int(res["winner"]) < 0
	var purses := arena_purses(o)
	var money: int = purses[0] if won else (int(o["purse"]) / 2 if draw else purses[1])
	var od: Dictionary = o["opp"]
	var what := "%s duel at %s" % [str(o["class"]).capitalize(), o["arena_name"]]
	add_money(money, "%s (%s)" % [what, "won" if won else ("draw" if draw else "lost")], "arena")
	stats["arena_fights"] = int(stats.get("arena_fights", 0)) + 1
	if won:
		stats["arena_wins"] = int(stats.get("arena_wins", 0)) + 1
	u.battles += 1
	u.kills += int(r["kills"])
	var cond := _condition_from_result(u, r)
	var summary := {"won": won, "draw": draw, "purse": money, "how": res["how"], "lines": [], "arena": o["arena_name"],
		"opponent": "%s (%s)" % [od["name"], db_design(str(od["design"])).display_name()]}
	u.condition = cond
	if _is_wreck(u, r, cond):
		u.status = "wreck"
		stats["losses"] = int(stats["losses"]) + 1
		summary["lines"].append("%s: destroyed, hauled out of the arena as a wreck" % u.label())
	else:
		u.status = "damaged" if not cond.is_empty() else "ready"
		MercRepair.normalize(u)
		summary["lines"].append("%s: %s" % [u.label(), "%d%% damaged" % int(u.damage_fraction() * 100) if not u.condition.is_empty() else "no damage"])
	var p: MercPerson = people.get(int(bout["pid"]))
	if p != null:
		summary["lines"].append(_crew_after(p, u, r, won, not won and not draw, false, rules["skills"]))
	add_log("arena", "%s: %s %s %s of %s, %s. Purse %s." % [what, p.full_name() if p != null else u.label(),
		"beat" if won else ("drew with" if draw else "lost to"), od["name"], od["stable"], res["how"], _cb(money)])
	return summary


static func _cb(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if v < 0 else "") + s + out + " C-bills"


## Fights the duel without watching it.
func arena_auto(oid: int, uid: int, orders: Dictionary) -> Dictionary:
	var b := make_arena_bout(oid, uid, orders, false)
	if b.is_empty():
		return {}
	var sim: CombatSim = b["sim"]
	sim.run_to_end()
	return resolve_arena(b["bout"], sim.result)


## New cards go up on arrival and every Monday; they come down when the company leaves or goes to work.
func _arena_day(arrived: bool) -> Array:
	if not arena_open():
		arena_offers = []
		return []
	if arrived or weekday() == 0 or (arena_offers.is_empty() and _arena_week != day / 7):
		_arena_week = day / 7
		refresh_arena()
		if not arena_offers.is_empty():
			return [{"kind": "arena", "stop": arrived, "text": "Solaris VII: %d arena bouts on offer" % arena_offers.size()}]
	return []


# ================================================================== save / load

func to_dict() -> Dictionary:
	var ps := {}
	for id in people:
		ps[str(id)] = (people[id] as MercPerson).to_dict()
	var us := {}
	for id in units:
		us[str(id)] = (units[id] as MercUnit).to_dict()
	return {"mode": "merc", "version": VERSION, "name": name, "color": [color.r, color.g, color.b], "camo": camo,
		"seed": seed_value, "rng": str(rng.get_state()), "day": day, "cash": cash, "ledger": ledger, "people": ps,
		"units": us, "lances": lances, "next_id": next_id, "location": location, "travel": travel, "astechs": astechs,
		"medics": medics, "warehouse": warehouse, "orders": orders, "shopping": shopping, "repair_mode": repair_mode,
		"market_units": market_units, "market_people": market_people, "contract_offers": contract_offers,
		"contract": contract, "history": history, "scenarios": scenarios, "salvage": salvage, "log": log, "loan": loan,
		"stats": stats, "settings": settings, "game_over": game_over, "arena_offers": arena_offers,
		"news": news, "events_day": events_day, "front_day": front_day}


static func from_dict(d: Dictionary) -> MercCampaign:
	var c := MercCampaign.new()
	c.name = str(d["name"])
	var col: Array = d.get("color", [0.6, 0.55, 0.3])
	c.color = Color(float(col[0]), float(col[1]), float(col[2]))
	c.camo = str(d.get("camo", ""))
	c.seed_value = int(d["seed"])
	c.rng = SimRng.new(c.seed_value)
	c.rng.set_state(int(str(d["rng"])))
	c.day = int(d["day"])
	c.sm.year_hint = c.year_f()
	c.cash = int(d["cash"])
	c.ledger = Campaign._fix_ints(d.get("ledger", []))
	for k in d.get("people", {}):
		c.people[int(k)] = MercPerson.from_dict(d["people"][k])
	for k in d.get("units", {}):
		var ud: Dictionary = Campaign._fix_ints(d["units"][k])
		c.units[int(k)] = MercUnit.from_dict(ud)
	c.lances = Campaign._fix_ints(d.get("lances", []))
	c.next_id = int(d["next_id"])
	c.location = int(d["location"])
	c.travel = Campaign._fix_ints(d.get("travel", {}))
	c.astechs = int(d.get("astechs", 0))
	c.medics = int(d.get("medics", 0))
	c.warehouse = d.get("warehouse", {})
	c.orders = Campaign._fix_ints(d.get("orders", []))
	c.shopping = Campaign._fix_ints(d.get("shopping", []))
	c.repair_mode = str(d.get("repair_mode", "standard"))
	c.market_units = Campaign._fix_ints(d.get("market_units", []))
	c.market_people = Campaign._fix_ints(d.get("market_people", []))
	c.contract_offers = Campaign._fix_ints(d.get("contract_offers", []))
	c.contract = Campaign._fix_ints(d.get("contract", {}))
	c.history = Campaign._fix_ints(d.get("history", []))
	c.scenarios = Campaign._fix_ints(d.get("scenarios", []))
	c.salvage = Campaign._fix_ints(d.get("salvage", []))
	c.log = Campaign._fix_ints(d.get("log", []))
	c.loan = Campaign._fix_ints(d.get("loan", {}))
	c.stats = Campaign._fix_ints(d.get("stats", c.stats))
	c.settings = d.get("settings", c.settings)
	c.game_over = bool(d.get("game_over", false))
	c.arena_offers = Campaign._fix_ints(d.get("arena_offers", []))
	c.news = Campaign._fix_ints(d.get("news", []))
	# a save from before the timeline: it starts reading the news today
	c.events_day = int(d.get("events_day", c.day))
	c.front_day = int(d.get("front_day", c.day))
	return c


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true


static func load_from(path: String) -> MercCampaign:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d = JSON.parse_string(f.get_as_text())
	if d == null or str(d.get("mode", "")) != "merc":
		return null
	return from_dict(d)
