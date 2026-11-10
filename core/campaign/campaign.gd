class_name Campaign
extends RefCounted
## The whole campaign world: calendar, stables, warriors, 'Mechs, market, fight cards, rankings,
## timeline events and the weekly loop. Pure logic; the UI reads it and calls its commands.

const CLASSES := ["light", "medium", "heavy", "assault"]
const ROLE_PREFS := {
	"brawler": ["Brawler", "Juggernaut", "Striker", "Ambusher"],
	"sniper": ["Sniper", "Missile Boat", "Skirmisher", "Fire Support"],
	"balanced": [],
}
const AI_ORDERS := {
	"brawler": {"range": "close", "heat": "hot", "position": "brawl", "retreat": 0.6},
	"sniper": {"range": "long", "heat": "balanced", "position": "cover", "retreat": 0.5},
	"balanced": {"range": "optimal", "heat": "balanced", "position": "cover", "retreat": 0.55},
	"flanker": {"range": "optimal", "heat": "balanced", "position": "flank", "retreat": 0.55},
}

var year := 3015
var week := 1
var seed_value := 0
var rng: SimRng
var stables: Array = []
var warriors: Dictionary = {}
var mechs: Dictionary = {}
var next_id := 1
var player_id := 0
var market: Dictionary = {"mechs": [], "agents": [], "parts": {}}
var offers: Array = []
var bookings: Array = []
var ai_card: Array = []
var results: Array = []
var news: Array = []
var champions: Dictionary = {"light": -1, "medium": -1, "heavy": -1, "assault": -1, "grand": -1}
var effects: Array = []
var fired_events: Dictionary = {}
var championship: Dictionary = {}
var phase := "booking"
var merc_jobs: Array = []        # off-world contracts on offer this week (the stable hires its fighters out)
var deployment: Dictionary = {}  # the one running: {"job", "entries": [{"warrior", "mech"}], "weeks_left", "fee", "paid"}
var last_deployment: Dictionary = {}
var settings: Dictionary = {}    # the dials of the setup screen; anything missing reads SETTING_DEFAULTS
var _pool_cache: Dictionary = {}

## purses, prices, upkeep, sponsors, injuries: multipliers. timeline: canon events make the news and
## take effect. merc_work: agents offer off-world jobs.
const SETTING_DEFAULTS := {"purses": 1.0, "prices": 1.0, "upkeep": 1.0, "sponsors": 1.0, "injuries": 1.0,
	"timeline": true, "merc_work": true}

var db: GameData
var rules: Dictionary


func _init() -> void:
	db = GameData.db()
	rules = db.rules


# ================================================================== setup

func opt(key: String) -> float:
	return float(settings.get(key, SETTING_DEFAULTS.get(key, 1.0)))


func flag(key: String) -> bool:
	return bool(settings.get(key, SETTING_DEFAULTS.get(key, true)))


## What a new stable starts with (data/rules.json "start"), with anything in `over` replacing it.
## Keys: year, cash, fame, bays, techs, warriors, mechs (weight classes), rivals (how many other
## stables), rival_skill (shift of their warriors' quality, 0 = as usual).
static func start_setup(over := {}) -> Dictionary:
	var R: Dictionary = GameData.db().rules
	var S: Dictionary = R["start"]
	var s := {"year": int(S["year"]), "cash": int(S["cash"]), "fame": float(S["fame"]), "bays": int(S["bays"]),
		"techs": int(S["techs"]), "warriors": int(S["warriors"]), "mechs": (S["mechs"] as Array).duplicate(),
		"rivals": int(R["ai_stables"]), "rival_skill": 0.0}
	for k in over:
		s[k] = over[k]
	return s


## setup: see start_setup. play: the campaign settings (SETTING_DEFAULTS).
static func new_game(stable_name: String, sector: String, seed_v: int, color := Color(-1, 0, 0), setup := {}, play := {}) -> Campaign:
	var c := Campaign.new()
	var st := start_setup(setup)
	for k in play:
		c.settings[k] = play[k]
	c.seed_value = seed_v
	c.rng = SimRng.new(seed_v)
	c.year = maxi(3015, int(st["year"]))
	c.week = 1
	var sec := c.sector_info(sector)
	var ps := Stable.new()
	ps.id = 0
	ps.name = stable_name
	ps.sector = sector
	ps.house = str(sec.get("house", ""))
	var sc: Array = sec.get("color", [0.6, 0.6, 0.6])
	ps.color = color if color.r >= 0.0 else Color(float(sc[0]), float(sc[1]), float(sc[2]))
	ps.camo = str(sec.get("camo", ""))
	ps.is_player = true
	ps.cash = int(st["cash"])
	ps.fame = float(st["fame"])
	ps.bays = maxi(int(st["bays"]), (st["mechs"] as Array).size())
	ps.techs = int(st["techs"])
	c.stables.append(ps)
	var culture := ps.house if ps.house != "" else "Mercenary"
	for k in int(st["warriors"]):
		var w := c._gen_warrior(culture if c.rng.chance(0.6) else c._random_culture(), 0.35 + k * 0.1)
		c._sign(w, ps, int(w.fair_salary(c.rules)), 52)
	var start_classes: Array = st["mechs"]
	for cls in start_classes:
		var did := c._pick_design(cls, ps.philosophy, int({"medium": 4500000, "heavy": 7500000, "assault": 11000000}.get(cls, 2500000)))
		if did != "":
			var om := c._add_mech(did, ps)
			om.condition = {}
	c._auto_assign(ps)
	# rivals
	var sectors: Array = c.db.arenas["sectors"]
	for i in int(st["rivals"]):
		var s := Stable.new()
		s.id = i + 1
		var sec2: Dictionary = sectors[c.rng.randi_range(0, sectors.size() - 1)]
		s.sector = str(sec2["id"])
		s.house = str(sec2["house"])
		s.philosophy = ["brawler", "sniper", "balanced", "balanced"][c.rng.randi_range(0, 3)]
		var cc: Array = sec2["color"]
		s.color = Color.from_hsv(c.rng.randf(), c.rng.randf_range(0.35, 0.85), c.rng.randf_range(0.45, 0.9))
		if c.rng.chance(0.3):
			s.color = Color(float(cc[0]), float(cc[1]), float(cc[2])).lightened(c.rng.randf_range(-0.2, 0.3))
		s.camo = str(sec2.get("camo", "")) if c.rng.chance(0.4) else ""
		s.name = c._stable_name(s.house if s.house != "" else "Mercenary")
		s.fame = c.rng.randf_range(2.0, 40.0)
		s.cash = c.rng.randi_range(2000000, 9000000) + int(s.fame * 60000)
		s.bays = 8
		s.techs = 6
		c.stables.append(s)
		var nw := c.rng.randi_range(int(c.rules["ai_warriors_per_stable"][0]), int(c.rules["ai_warriors_per_stable"][1]))
		var qual := clampf(s.fame / 40.0 * (1.0 + float(st["rival_skill"])), 0.1, 1.0)
		for k in nw:
			var cul := s.house if (s.house != "" and c.rng.chance(0.7)) else c._random_culture()
			var w2 := c._gen_warrior(cul, qual * c.rng.randf_range(0.6, 1.2))
			w2.fame = c.rng.randf_range(0.0, s.fame)
			w2.elo = float(c.rules["elo_start"]) + (9 - w2.gunnery - w2.piloting) * 35.0 + w2.fame * 3.0 + c.rng.randf_range(-60, 60)
			w2.wins = c.rng.randi_range(0, int(w2.fame / 2.0) + 3)
			w2.losses = c.rng.randi_range(0, 6)
			c._sign(w2, s, w2.fair_salary(c.rules), c.rng.randi_range(20, 120))
			var cls2: String = CLASSES[c.rng.weighted_index([3, 4, 3, 2])]
			var did2 := c._pick_design(cls2, s.philosophy, 12000000)
			if did2 != "":
				c._add_mech(did2, s)
		c._auto_assign(s)
	# free agents
	for k in 14:
		c._gen_free_agent(c.rng.randf_range(0.1, 0.8))
	# initial champions: best Elo in each class among AI
	for cls in CLASSES:
		var r := c.rankings(cls)
		if not r.is_empty():
			c.champions[cls] = r[0]
	c.add_news("welcome", "A new stable on the Game World", "%s opens its doors in %s. The %s season begins." % [ps.name, ps.sector, c.year])
	c.start_week()
	return c


func sector_info(sector: String) -> Dictionary:
	for s in db.arenas["sectors"]:
		if s["id"] == sector:
			return s
	return db.arenas["sectors"][db.arenas["sectors"].size() - 1]


func _random_culture() -> String:
	var keys: Array = db.names["cultures"].keys()
	return keys[rng.randi_range(0, keys.size() - 1)]


func _stable_name(culture: String) -> String:
	var n: Dictionary = db.names
	var form: String = n["stable_forms"][rng.randi_range(0, n["stable_forms"].size() - 1)]
	var cul: Dictionary = n["cultures"].get(culture, n["cultures"]["Mercenary"])
	var s := form.replace("{a}", rng.pick(n["stable_words_a"])).replace("{b}", rng.pick(n["stable_words_b"]))
	return s.replace("{last}", rng.pick(cul["last"]))


func new_id() -> int:
	next_id += 1
	return next_id


func player() -> Stable:
	return stables[player_id]


func week_index() -> int:
	return (year - 3015) * 52 + week


func date_str() -> String:
	return "Week %d, %d" % [week, year]


# ================================================================== generation

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


func _gen_warrior(culture: String, quality: float) -> Warrior:
	var w := Warrior.new()
	w.id = new_id()
	w.culture = culture
	w.gender = "f" if rng.chance(0.4) else "m"
	var cul: Dictionary = db.names["cultures"].get(culture, db.names["cultures"]["Mercenary"])
	w.first = rng.pick(cul["female" if w.gender == "f" else "male"])
	w.last = rng.pick(cul["last"])
	if rng.chance(0.55):
		w.callsign = rng.pick(db.names["callsigns"])
	var pl := _portrait_list(w.gender)
	if not pl.is_empty():
		w.portrait = pl[rng.randi_range(0, pl.size() - 1)]
	var q := clampf(quality, 0.0, 1.2)
	w.gunnery = clampi(int(round(rng.gauss(4.6 - q * 1.8, 0.7))), 1, 6)
	w.piloting = clampi(int(round(rng.gauss(5.6 - q * 1.8, 0.7))), 2, 7)
	w.birth_year = year - rng.randi_range(19, 24) - int(q * rng.randi_range(0, 14))
	var trait_keys: Array = CombatMech.TRAITS.keys()
	var nt := rng.weighted_index([4, 4, 2])
	for k in nt:
		var tr: String = trait_keys[rng.randi_range(0, trait_keys.size() - 1)]
		if not (tr in w.traits):
			w.traits.append(tr)
	w.morale = rng.randf_range(45, 75)
	w.elo = float(rules["elo_start"]) + (9 - w.gunnery - w.piloting) * 35.0
	w.purse_share = snappedf(rng.randf_range(float(rules["purse_share"][0]), float(rules["purse_share"][1])), 0.01)
	w.salary = w.fair_salary(rules)
	warriors[w.id] = w
	return w


func _gen_free_agent(quality: float) -> Warrior:
	var w := _gen_warrior(_random_culture(), quality)
	w.fame = rng.randf_range(0.0, 15.0) * quality
	w.salary = int(w.fair_salary(rules) * rng.randf_range(0.9, 1.3))
	w.stable_id = -1
	return w


func _sign(w: Warrior, s: Stable, salary: int, weeks: int) -> void:
	w.stable_id = s.id
	w.salary = salary
	w.contract_weeks = weeks
	if not (w.id in s.warriors):
		s.warriors.append(w.id)


## Market pool: library designs on sale in the current year, with weights.
func market_pool() -> Array:
	var key := year
	if _pool_cache.has(key):
		return _pool_cache[key]
	var era := GameData.mul_era(year)
	var pool: Array = []
	for e in db.get_library():
		if e["tech"] == "Clan":
			continue
		if e["year"] != null and int(e["year"]) > year:
			continue
		var av: Dictionary = e["avail"]
		var fac: Array = av.get(era, [])
		var sphere := 0
		for f in fac:
			if int(f) != 18:  # ComStar-only machines don't reach the open market
				sphere += 1
		if sphere == 0:
			continue
		var md := MechDesign.from_stock(e["id"])
		if not Construction.buildable_in(md, year):
			continue
		pool.append({"id": e["id"], "tons": e["tons"], "cost": e["cost"], "bv": e["bv"], "role": e["role"], "w": sphere})
	_pool_cache[key] = pool
	return pool


func _pick_design(cls: String, philosophy: String, budget: int) -> String:
	var pool := market_pool()
	var cands: Array = []
	var weights: Array = []
	var prefs: Array = ROLE_PREFS.get(philosophy, [])
	for e in pool:
		if db.weight_class(int(e["tons"])) != cls or int(e["cost"]) > budget:
			continue
		var wgt := float(e["w"])
		if not prefs.is_empty() and str(e["role"]) in prefs:
			wgt *= 2.5
		cands.append(e["id"])
		weights.append(wgt)
	if cands.is_empty():
		for e in pool:
			if db.weight_class(int(e["tons"])) == cls:
				cands.append(e["id"])
				weights.append(1.0)
	var i := rng.weighted_index(weights)
	return cands[i] if i >= 0 else ""


func _add_mech(design_id: String, s: Stable) -> OwnedMech:
	var om := OwnedMech.new()
	om.uid = new_id()
	om.design = MechDesign.from_stock(design_id)
	om.stable_id = s.id
	om.paid = om.base_cost()
	mechs[om.uid] = om
	s.mechs.append(om.uid)
	return om


func _auto_assign(s: Stable) -> void:
	var free_mechs: Array = []
	for uid in s.mechs:
		var taken := false
		for wid in s.warriors:
			if warriors[wid].mech_uid == uid:
				taken = true
		if not taken:
			free_mechs.append(uid)
	for wid in s.warriors:
		var w: Warrior = warriors[wid]
		if w.mech_uid == -1 or not (w.mech_uid in s.mechs):
			w.mech_uid = free_mechs.pop_front() if not free_mechs.is_empty() else -1


# ================================================================== effects, prices

func effect_mult(kind: String) -> float:
	var v := 1.0
	if kind == "purse_mult":
		v = opt("purses")
	elif kind == "price_mult":
		v = opt("prices")
	for e in effects:
		if e["kind"] == kind and int(e["until"]) >= week_index():
			v *= float(e["value"])
	return v


func flag_active(kind: String) -> bool:
	for e in effects:
		if e["kind"] == kind and int(e["until"]) >= week_index():
			return true
	return false


func price_mult() -> float:
	return effect_mult("price_mult")


# ================================================================== market

func refresh_market() -> void:
	var m: Dictionary = rules["market"]
	var mk: Array = []
	var pool := market_pool()
	var weights: Array = []
	for e in pool:
		weights.append(float(e["w"]))
	var n := rng.randi_range(int(m["mechs_per_week"][0]), int(m["mechs_per_week"][1]))
	for k in n:
		var i := rng.weighted_index(weights)
		if i < 0:
			break
		var e: Dictionary = pool[i]
		var cond := rng.randf_range(float(m["used_condition"][0]), float(m["used_condition"][1]))
		var md := MechDesign.from_stock(e["id"])
		var condition := _used_condition(md, cond)
		var price := int(float(e["cost"]) * (0.45 + 0.55 * cond) * price_mult() / 1000.0) * 1000
		mk.append({"offer": new_id(), "design": e["id"], "condition": condition, "quality": cond, "price": price, "kind": "used"})
	# rare lostech relics and Clan salvage
	if rng.chance(0.12):
		var relic := _relic_design()
		if relic != "":
			var md2 := MechDesign.from_stock(relic)
			var cost2 := int(Construction.analyze(md2)["cost"])
			mk.append({"offer": new_id(), "design": relic, "condition": _used_condition(md2, 0.6), "quality": 0.6,
				"price": int(cost2 * 2.2 * price_mult() / 1000.0) * 1000, "kind": "relic"})
	if flag_active("clan_salvage") and rng.chance(0.25):
		var cl := _clan_design()
		if cl != "":
			var md3 := MechDesign.from_stock(cl)
			var cost3 := int(Construction.analyze(md3)["cost"])
			mk.append({"offer": new_id(), "design": cl, "condition": _used_condition(md3, 0.45), "quality": 0.45,
				"price": int(cost3 * 2.5 * price_mult() / 1000.0) * 1000, "kind": "clan"})
	market["mechs"] = mk
	# free agents shown this week
	var fa: Array = []
	for wid in warriors:
		var w: Warrior = warriors[wid]
		if w.stable_id == -1 and not w.retired and not w.dead:
			fa.append(wid)
	rng.shuffle(fa)
	market["agents"] = fa.slice(0, rng.randi_range(int(m["agents_per_week"][0]), int(m["agents_per_week"][1])))
	# parts
	var parts := {}
	var col := GameData.era_column(year)
	for id in db.items:
		var it: Dictionary = db.items[id]
		if not it.get("mek", false) or not (it.get("kind", "") in ["weapon", "misc", "ammo"]):
			continue
		if not db.item_available(id, year):
			continue
		var av = it.get("avail")
		var letter := "C"
		if av is Array and (av as Array).size() > col:
			letter = str(av[col])
		var chance := float(m["parts_stock_chance"].get(letter, 0.3))
		if it.get("kind") == "ammo" or it.get("misc", "") in ["heat_sink", "jump_jet"]:
			chance = 1.0
		if rng.chance(chance):
			var base := float(it.get("cost", 0)) if it.get("cost") != null else 0.0
			parts[id] = {"qty": 99 if chance >= 1.0 else rng.randi_range(int(m["parts_quantity"][0]), int(m["parts_quantity"][1])),
				"price": int(base * float(m["rarity_price"].get(letter, 1.2)) * price_mult()), "rarity": letter}
	market["parts"] = parts


func _used_condition(md: MechDesign, quality: float) -> Dictionary:
	if quality > 0.92:
		return {}
	var armor := {}
	for k in md.armor:
		armor[k] = int(round(int(md.armor[k]) * clampf(quality + rng.randf_range(-0.15, 0.2), 0.2, 1.0)))
	var ipts := Construction.internal_points(md.tons)
	var internal := {}
	for loc in ipts:
		internal[loc] = int(ipts[loc])
	if quality < 0.7:
		var loc2: String = MechDesign.LOCS[rng.randi_range(1, 7)]
		internal[loc2] = maxi(1, int(ipts[loc2]) - rng.randi_range(1, 4))
	return {"armor": armor, "internal": internal, "hit_slots": [], "ammo": {}}


func _relic_design() -> String:
	var era := GameData.mul_era(year)
	var c: Array = []
	for e in db.get_library():
		if e["tech"] != "IS" or (e["year"] != null and int(e["year"]) > year):
			continue
		if (e["avail"] as Dictionary).get(era, []).is_empty():
			continue
		if not Construction.buildable_in(MechDesign.from_stock(e["id"]), year):
			c.append(e["id"])
	return c[rng.randi_range(0, c.size() - 1)] if not c.is_empty() else ""


func _clan_design() -> String:
	var c: Array = []
	for e in db.get_library():
		if e["tech"] == "Clan" and (e["year"] == null or int(e["year"]) <= year):
			c.append(e["id"])
	return c[rng.randi_range(0, c.size() - 1)] if not c.is_empty() else ""


func buy_mech(offer_id: int) -> String:
	var p := player()
	for i in (market["mechs"] as Array).size():
		var o: Dictionary = market["mechs"][i]
		if int(o["offer"]) != offer_id:
			continue
		if p.cash < int(o["price"]):
			return "Not enough C-bills"
		if p.mechs.size() >= p.bays:
			return "No free 'Mech bay (you have %d)" % p.bays
		p.add_ledger("Purchases", -int(o["price"]))
		var om := _add_mech(o["design"], p)
		om.condition = o["condition"]
		om.paid = int(o["price"])
		market["mechs"].remove_at(i)
		add_news("market", "New 'Mech in the bay", "%s buys a %s for %s." % [p.name, om.design.display_name(), money(int(o["price"]))], true)
		return ""
	return "Offer gone"


func sell_mech(uid: int) -> String:
	var p := player()
	var om: OwnedMech = mechs.get(uid)
	if om == null or om.stable_id != p.id:
		return "Not your 'Mech"
	for b in bookings:
		if int(b["mech_uid"]) == uid:
			return "That 'Mech is booked for a fight"
	if om.status == "away":
		return "That 'Mech is off-world on a contract"
	var v := int(om.value() * float(rules["market"]["sell_fraction"]))
	p.add_ledger("Sales", v)
	p.mechs.erase(uid)
	for wid in p.warriors:
		if warriors[wid].mech_uid == uid:
			warriors[wid].mech_uid = -1
	mechs.erase(uid)
	return ""


func hire(wid: int, salary: int, weeks: int) -> String:
	var p := player()
	var w: Warrior = warriors.get(wid)
	if w == null or w.stable_id != -1:
		return "Not available"
	var bonus := salary * 4
	if p.cash < bonus:
		return "Signing bonus of %s is more than you have" % money(bonus)
	var ask := int(w.salary)
	if salary < int(ask * 0.85):
		w.morale -= 5
		return "%s turns the offer down (asking %s/week)" % [w.short_name(), money(ask)]
	p.add_ledger("Signing bonuses", -bonus)
	_sign(w, p, salary, weeks)
	w.morale = clampf(w.morale + (salary - ask) / 200.0, 20, 100)
	market["agents"].erase(wid)
	_auto_assign(p)
	add_news("signing", "Signing", "%s signs with %s." % [w.full_name(), p.name], true)
	return ""


func release(wid: int) -> String:
	var p := player()
	var w: Warrior = warriors.get(wid)
	if w == null or w.stable_id != p.id:
		return "Not yours"
	for b in bookings:
		if int(b["warrior_id"]) == wid:
			return "Booked for a fight this week"
	if w.away_weeks > 0:
		return "%s is off-world on a contract" % w.short_name()
	var severance := w.salary * mini(8, w.contract_weeks)
	p.add_ledger("Severance", -severance)
	p.warriors.erase(wid)
	w.stable_id = -1
	w.mech_uid = -1
	w.contract_weeks = 0
	return ""


func extend_contract(wid: int, weeks: int) -> String:
	var w: Warrior = warriors.get(wid)
	if w == null or w.stable_id != player_id:
		return "Not yours"
	var ask := w.fair_salary(rules)
	if w.morale < 30:
		return "%s won't re-sign: morale too low" % w.short_name()
	w.salary = maxi(w.salary, ask)
	w.contract_weeks += weeks
	return ""


func assign(wid: int, uid: int) -> void:
	var p := player()
	if warriors[wid].away_weeks > 0 or (mechs.has(uid) and mechs[uid].status == "away"):
		return
	for other in p.warriors:
		if warriors[other].mech_uid == uid:
			warriors[other].mech_uid = -1
	warriors[wid].mech_uid = uid


func buy_upgrade(kind: String) -> String:
	var p := player()
	var cost := 0
	match kind:
		"bay":
			cost = int(rules["bay_cost"])
		"tech":
			cost = int(rules["tech_salary_week"]) * 8
		"medic":
			if p.medic >= 3:
				return "Medical bay is maxed out"
			cost = 400000 * (p.medic + 1)
		"sim":
			if p.sim_pods >= 3:
				return "Three simulator pods is the limit"
			cost = int(rules["sim_pod_cost"])
	if p.cash < cost:
		return "Costs %s" % money(cost)
	p.add_ledger("Facilities", -cost)
	match kind:
		"bay":
			p.bays += 1
		"tech":
			p.techs += 1
		"medic":
			p.medic += 1
		"sim":
			p.sim_pods += 1
	return ""


# ================================================================== repairs and refits

func start_repair(uid: int) -> String:
	var om: OwnedMech = mechs.get(uid)
	if om == null or not om.is_damaged():
		return "Nothing to repair"
	var est := om.repair_estimate(year, rules)
	var s: Stable = stables[om.stable_id]
	var cost := int(est["cost"] * price_mult()) + int(est["hours"] * float(rules["labor_cost_hour"]))
	if s.cash < cost:
		return "Repair costs %s" % money(cost)
	s.add_ledger("Repairs", -cost)
	om.status = "repair"
	om.work_hours = maxf(1.0, est["hours"])
	om.pending_design = {"missing": est["missing"]}
	return ""


func refit_quote(uid: int, nd: MechDesign) -> Dictionary:
	var om: OwnedMech = mechs.get(uid)
	var errors: Array = []
	var r := Construction.analyze(nd, year)
	if not r["valid"]:
		errors.append_array(r["errors"])
	var old := om.design
	var rh: Dictionary = rules["refit_hours"]
	var hours := 0.0
	var cost := 0.0
	var lines: Array = []
	# components
	if nd.engine_type != old.engine_type or nd.engine_rating != old.engine_rating:
		hours += float(rh["engine"])
		var ec := float(Construction.ENGINE_COST.get(nd.engine_type, 5000)) * nd.engine_rating * nd.tons / 75.0
		cost += ec
		lines.append(["Engine %d %s" % [nd.engine_rating, nd.engine_type], int(ec)])
		if not db.component_available("engine", nd.engine_type, year):
			errors.append("%s engines aren't for sale in %d" % [nd.engine_type, year])
	if nd.structure != old.structure:
		hours += float(rh["structure"])
		var sc := 1600.0 * nd.tons * (1.0 + nd.tons / 100.0)
		cost += sc
		lines.append(["Internal structure", int(sc)])
		if not db.component_available("structure", nd.structure, year):
			errors.append("%s structure isn't for sale in %d" % [nd.structure, year])
	if nd.armor_type != old.armor_type:
		hours += float(rh["armor_type"])
		if not db.component_available("armor", nd.armor_type, year):
			errors.append("%s armor isn't for sale in %d" % [nd.armor_type, year])
	if nd.hs_type != old.hs_type:
		hours += float(rh["heat_sink_type"])
		if not db.component_available("hs", nd.hs_type, year):
			errors.append("%s heat sinks aren't for sale in %d" % [nd.hs_type, year])
	if nd.gyro != old.gyro and not db.component_available("gyro", nd.gyro, year):
		errors.append("%s gyros aren't for sale in %d" % [nd.gyro, year])
	if nd.cockpit != old.cockpit and not db.component_available("cockpit", nd.cockpit, year):
		errors.append("%s cockpits aren't for sale in %d" % [nd.cockpit, year])
	# armor points
	var da := absi(nd.armor_total() - old.armor_total())
	if da > 0 or nd.armor_type != old.armor_type:
		var per := float(Construction.ARMOR_COST.get(nd.armor_type, 10000)) / Construction.armor_ppt(nd.armor_type)
		var pts := nd.armor_total() if nd.armor_type != old.armor_type else maxi(0, nd.armor_total() - old.armor_total())
		cost += pts * per
		hours += da * float(rh["armor_point"])
		if pts > 0:
			lines.append(["Armor (%d points)" % pts, int(pts * per)])
	# equipment: count item ids before and after
	var before := _item_counts(old)
	var after := _item_counts(nd)
	var buy := {}
	var freed := {}
	var p: Stable = stables[om.stable_id]
	for id in after:
		var need: int = after[id] - int(before.get(id, 0))
		if need > 0:
			buy[id] = need
	for id in before:
		var spare: int = before[id] - int(after.get(id, 0))
		if spare > 0:
			freed[id] = spare
	var changed_slots := 0
	for loc in MechDesign.LOCS:
		for i in (nd.slots[loc] as Array).size():
			if nd.slots[loc][i] != old.slots[loc][i]:
				changed_slots += 1
	hours += changed_slots * float(rh["slot"])
	for id in buy:
		var it := db.item(id)
		var in_inv: int = mini(int(p.inventory.get(id, 0)), int(buy[id]))
		var from_market: int = int(buy[id]) - in_inv
		if from_market <= 0:
			continue
		var misc: String = it.get("misc", "")
		var price := 0.0
		if misc in ["heat_sink", "double_heat_sink", "jump_jet"] or it.get("kind", "") == "ammo":
			if not db.item_available(id, year):
				errors.append("%s isn't for sale in %d" % [it.get("name", id), year])
				continue
			price = float(it.get("cost", 0)) if it.get("cost") != null else (2000.0 if misc == "heat_sink" else 6000.0)
			if misc == "jump_jet":
				price = 200.0 * nd.tons
		else:
			var stock: Dictionary = market["parts"].get(id, {})
			if stock.is_empty() or int(stock["qty"]) < from_market:
				errors.append("%s: need %d, market has %d" % [it.get("name", id), from_market, int(stock.get("qty", 0))])
				continue
			price = float(stock["price"])
		cost += price * from_market
		lines.append(["%dx %s" % [from_market, it.get("name", id)], int(price * from_market)])
	cost *= price_mult()
	cost += hours * float(rules["labor_cost_hour"])
	return {"cost": int(cost), "hours": hours, "lines": lines, "buy": buy, "freed": freed, "errors": errors,
		"report": r}


## Quote for building a brand-new 'Mech from a design.
func build_quote(nd: MechDesign) -> Dictionary:
	var errors: Array = []
	var r := Construction.analyze(nd, year)
	if not r["valid"]:
		errors.append_array(r["errors"])
	for pair in [["engine", nd.engine_type], ["structure", nd.structure], ["armor", nd.armor_type],
			["gyro", nd.gyro], ["cockpit", nd.cockpit], ["hs", nd.hs_type], ["myomer", nd.myomer]]:
		if not db.component_available(pair[0], pair[1], year):
			errors.append("%s %s isn't for sale in %d" % [str(pair[1]).replace("_", " "), pair[0], year])
	var p := player()
	var counts := _item_counts(nd)
	for id in counts:
		var it := db.item(id)
		var misc: String = it.get("misc", "")
		if misc in ["heat_sink", "double_heat_sink", "jump_jet"] or it.get("kind", "") == "ammo":
			continue
		var need: int = int(counts[id]) - int(p.inventory.get(id, 0))
		if need <= 0:
			continue
		var stock: Dictionary = market["parts"].get(id, {})
		if stock.is_empty() or int(stock["qty"]) < need:
			errors.append("%s: need %d, market has %d" % [it.get("name", id), need, int(stock.get("qty", 0))])
	var hours := 200.0
	var cost := int(float(r.get("cost", 0)) * price_mult() + hours * float(rules["labor_cost_hour"]))
	if p.mechs.size() >= p.bays:
		errors.append("No free 'Mech bay")
	return {"cost": cost, "hours": hours, "errors": errors, "report": r}


func commit_build(nd: MechDesign) -> String:
	var q := build_quote(nd)
	if not (q["errors"] as Array).is_empty():
		return str(q["errors"][0])
	var p := player()
	if p.cash < int(q["cost"]):
		return "Building it costs %s" % money(int(q["cost"]))
	p.add_ledger("Construction", -int(q["cost"]))
	var counts := _item_counts(nd)
	for id in counts:
		var use: int = mini(int(p.inventory.get(id, 0)), int(counts[id]))
		if use > 0:
			p.inventory[id] = int(p.inventory[id]) - use
			if int(p.inventory[id]) <= 0:
				p.inventory.erase(id)
		var from_market: int = int(counts[id]) - use
		if market["parts"].has(id) and int(market["parts"][id]["qty"]) < 99:
			market["parts"][id]["qty"] = maxi(0, int(market["parts"][id]["qty"]) - from_market)
	var om := OwnedMech.new()
	om.uid = new_id()
	om.design = nd.copy()
	om.stable_id = p.id
	om.paid = int(q["cost"])
	om.status = "refit"
	om.work_hours = float(q["hours"])
	om.pending_design = nd.to_dict()
	mechs[om.uid] = om
	p.mechs.append(om.uid)
	add_news("bay", "New 'Mech on the gantry", "%s starts building a %s." % [p.name, nd.display_name()], true)
	return ""


func _item_counts(d: MechDesign) -> Dictionary:
	var out := {}
	for mt in Construction.mounts_of(d):
		out[mt["id"]] = int(out.get(mt["id"], 0)) + 1
	return out


func commit_refit(uid: int, nd: MechDesign) -> String:
	var q := refit_quote(uid, nd)
	if not (q["errors"] as Array).is_empty():
		return str(q["errors"][0])
	var om: OwnedMech = mechs[uid]
	var p: Stable = stables[om.stable_id]
	if p.cash < int(q["cost"]):
		return "Refit costs %s" % money(int(q["cost"]))
	p.add_ledger("Refits", -int(q["cost"]))
	for id in q["buy"]:
		var use: int = mini(int(p.inventory.get(id, 0)), int(q["buy"][id]))
		if use > 0:
			p.inventory[id] = int(p.inventory[id]) - use
			if int(p.inventory[id]) <= 0:
				p.inventory.erase(id)
		var from_market: int = int(q["buy"][id]) - use
		if market["parts"].has(id) and int(market["parts"][id]["qty"]) < 99:
			market["parts"][id]["qty"] = int(market["parts"][id]["qty"]) - from_market
	for id in q["freed"]:
		if db.item(id).get("kind", "") != "ammo":
			p.inventory[id] = int(p.inventory.get(id, 0)) + int(q["freed"][id])
	om.status = "refit"
	om.work_hours = maxf(1.0, float(q["hours"]))
	om.pending_design = nd.to_dict()
	return ""


func sell_part(id: String) -> void:
	var p := player()
	if int(p.inventory.get(id, 0)) <= 0:
		return
	p.inventory[id] = int(p.inventory[id]) - 1
	if p.inventory[id] <= 0:
		p.inventory.erase(id)
	var it := db.item(id)
	p.add_ledger("Sales", int(float(it.get("cost", 0) if it.get("cost") != null else 0) * 0.5))


func _bay_work(s: Stable) -> void:
	var hours := float(s.techs) * float(rules["tech_hours_week"])
	for uid in s.mechs:
		var om: OwnedMech = mechs[uid]
		if om.status == "ready" or om.status == "wrecked" or om.status == "away":
			continue
		var use := minf(hours, om.work_hours)
		om.work_hours -= use
		hours -= use
		if om.work_hours <= 0.01:
			if om.status == "refit":
				var nd := MechDesign.from_dict(om.pending_design)
				om.design = nd
				om.condition = {}
				if s.is_player:
					add_news("bay", "Refit complete", "%s rolls out of the bay." % om.label(), true)
			elif om.status == "repair":
				om.complete_repair(om.pending_design.get("missing", []))
				if s.is_player:
					add_news("bay", "Repairs complete", "%s is ready to fight." % om.label(), true)
			om.status = "ready"
			om.pending_design = {}
		if hours <= 0.0:
			break


# ================================================================== fights: offers, bookings, the card

func purse_for(cls: String, wa: Warrior, wb: Warrior, arena: Dictionary, kind := "regular") -> int:
	var base := float(rules["purse_base"].get(cls, 200000))
	var fame := (wa.fame if wa else 0.0) + (wb.fame if wb else 0.0)
	var p := base * (1.0 + fame * float(rules["fame_purse_bonus_per_point"])) * float(arena.get("prestige", 1.0))
	p *= effect_mult("purse_mult") * effect_mult("tension")
	if kind == "title":
		p *= float(rules["purse_title_mult"])
	return int(p / 1000.0) * 1000


func _arena_pick() -> Dictionary:
	var a: Array = db.arenas["arenas"]
	return a[rng.randi_range(0, a.size() - 1)]


func mech_class(uid: int) -> String:
	var om: OwnedMech = mechs.get(uid)
	return db.weight_class(om.design.tons) if om else ""


func warrior_mech(w: Warrior) -> OwnedMech:
	return mechs.get(w.mech_uid)


func _fight_ready(w: Warrior) -> bool:
	if not w.available():
		return false
	var om := warrior_mech(w)
	return om != null and om.ready()


func _booked(wid: int) -> bool:
	for b in bookings + ai_card:
		if wid in bout_warriors(b):
			return true
	return false


## Every warrior in a bout, whatever the format.
static func bout_warriors(b: Dictionary) -> Array:
	var out: Array = []
	if b.has("sides"):
		for side in b["sides"]:
			for e in side:
				if int(e["warrior"]) >= 0:
					out.append(int(e["warrior"]))
		return out
	for k in ["a", "b"]:
		if b.has(k) and int(b[k]["warrior"]) >= 0:
			out.append(int(b[k]["warrior"]))
	return out


## Light and weather for a bout, drawn from the arena theme's odds.
func _pick_conditions(ar: Dictionary) -> Dictionary:
	var th: Dictionary = db.arenas["themes"].get(ar["theme"], {})
	var co: Dictionary = th.get("conditions", {})
	var light := "day"
	var r := rng.randf()
	if r < float(co.get("night", 0.0)):
		light = "night"
	elif r < float(co.get("night", 0.0)) + float(co.get("dusk", 0.0)):
		light = "dusk"
	var wts: Dictionary = co.get("weather", {"clear": 1})
	var keys: Array = wts.keys()
	var ws: Array = []
	for k in keys:
		ws.append(float(wts[k]))
	var weather: String = keys[rng.weighted_index(ws)]
	return {"light": light, "weather": weather, "floodlights": bool(ar.get("floodlights", false))}


const FORMAT_LABEL := {"duel": "Duel", "tag": "Tag team", "lance": "Lance battle", "melee": "Free-for-all"}


static func conditions_label(cd: Dictionary) -> String:
	var parts: Array = []
	match str(cd.get("light", "day")):
		"night":
			parts.append("night" + (" under floodlights" if cd.get("floodlights", false) else ""))
		"dusk":
			parts.append("dusk")
	if str(cd.get("weather", "clear")) != "clear":
		parts.append(str(cd["weather"]))
	return "clear day" if parts.is_empty() else ", ".join(parts)


func _ai_fighters(cls: String, exclude: Dictionary) -> Array:
	var out: Array = []
	for s in stables:
		if s.is_player:
			continue
		for wid in s.warriors:
			var w: Warrior = warriors[wid]
			if exclude.has(wid) or not _fight_ready(w):
				continue
			if cls == "open" or mech_class(w.mech_uid) == cls:
				out.append(wid)
	return out


func _new_bout(kind: String, cls: String, a_wid: int, b_wid: int) -> Dictionary:
	var ar := _arena_pick()
	var wa: Warrior = warriors.get(a_wid)
	var wb: Warrior = warriors.get(b_wid)
	return {"id": new_id(), "kind": kind, "format": "duel", "class": cls, "arena": ar["id"], "arena_name": ar["name"], "theme": ar["theme"],
		"seed": rng.randi_range(1, 1 << 30), "purse": purse_for(cls, wa, wb, ar, kind),
		"a": {"warrior": a_wid, "mech": wa.mech_uid if wa else -1}, "b": {"warrior": b_wid, "mech": wb.mech_uid if wb else -1},
		"to_death": kind == "grudge", "conditions": _pick_conditions(ar)}


## Team and free-for-all bouts. sides: Array of Array of warrior ids (-1 = the player's open slots).
## cap: tonnage cap per side (lance) or 0.
func _new_team_bout(format: String, cls: String, sides_w: Array, cap := 0) -> Dictionary:
	var ar := _arena_pick()
	var sides: Array = []
	var fame := 0.0
	for side in sides_w:
		var entries: Array = []
		for wid in side:
			var w: Warrior = warriors.get(int(wid))
			entries.append({"warrior": int(wid), "mech": w.mech_uid if w else -1})
			if w:
				fame += w.fame
		sides.append(entries)
	var base_cls := cls if cls in CLASSES else "heavy"
	var n := 0
	for side in sides_w:
		n += (side as Array).size()
	var base := float(rules["purse_base"].get(base_cls, 200000))
	var mult: float = {"tag": 1.2, "lance": 1.25, "melee": 0.9}.get(format, 1.0)
	var purse := base * n * 0.5 * float(mult) * (1.0 + fame / n * float(rules["fame_purse_bonus_per_point"])) * float(ar.get("prestige", 1.0))
	purse *= effect_mult("purse_mult") * effect_mult("tension")
	if format == "lance" and cap > 0:
		purse *= cap / 240.0
	var b := {"id": new_id(), "kind": "regular", "format": format, "class": cls, "cap": cap, "arena": ar["id"],
		"arena_name": ar["name"], "theme": ar["theme"], "seed": rng.randi_range(1, 1 << 30), "purse": int(purse / 1000.0) * 1000,
		"sides": sides, "to_death": false, "conditions": _pick_conditions(ar), "time_limit": 480.0 if format in ["lance", "melee"] else 360.0}
	# a/b point at the first fighter on each of the first two sides, for lists and headlines
	b["a"] = sides[0][0] if not sides[0].is_empty() else {"warrior": -1, "mech": -1}
	b["b"] = sides[1][0] if sides.size() > 1 and not sides[1].is_empty() else {"warrior": -1, "mech": -1}
	return b


## Ready AI fighters of one stable, optionally limited to a class.
func _stable_ready(s: Stable, cls: String, used: Dictionary) -> Array:
	var out: Array = []
	for wid in s.warriors:
		var w: Warrior = warriors[wid]
		if used.has(wid) or not _fight_ready(w):
			continue
		if cls == "open" or cls == "" or mech_class(w.mech_uid) == cls:
			out.append(wid)
	return out


## Picks an AI stable that can field `n` fighters in a class or under a tonnage cap.
func _ai_team(n: int, cls: String, cap: int, used: Dictionary, exclude_stables := {}) -> Array:
	var cands: Array = []
	for s in stables:
		if s.is_player or exclude_stables.has(s.id):
			continue
		var pool := _stable_ready(s, cls, used)
		if pool.size() < n:
			continue
		pool.sort_custom(func(a, b): return warriors[a].elo > warriors[b].elo)
		if cap > 0:
			# heaviest set that still fits under the cap, best warriors first
			pool.sort_custom(func(a, b): return mechs[warriors[a].mech_uid].design.tons < mechs[warriors[b].mech_uid].design.tons)
			var pick: Array = []
			var tons := 0
			for wid in pool:
				var t: int = mechs[warriors[wid].mech_uid].design.tons
				if pick.size() < n and tons + t <= cap - (n - pick.size() - 1) * 20:
					pick.append(wid)
					tons += t
			if pick.size() == n:
				cands.append(pick)
		else:
			cands.append(pool.slice(0, n))
	if cands.is_empty():
		return []
	return cands[rng.randi_range(0, cands.size() - 1)]


func generate_offers() -> void:
	offers = []
	var p := player()
	var used := {}
	for b in ai_card + bookings:
		for wid in bout_warriors(b):
			used[wid] = true
	var classes_here := {}
	for wid in p.warriors:
		var w: Warrior = warriors[wid]
		if w.mech_uid >= 0:
			classes_here[mech_class(w.mech_uid)] = true
	for uid in p.mechs:
		classes_here[mech_class(uid)] = true
	# championship and title fights involving the player come first
	for b in _special_bouts_for_player():
		offers.append(b)
	for cls in CLASSES:
		if not classes_here.has(cls):
			continue
		var pool := _ai_fighters(cls, used)
		rng.shuffle(pool)
		for wid in pool.slice(0, 3):
			used[wid] = true
			var o := _new_bout("regular", cls, -1, wid)
			offers.append(o)
	# one open-class offer and the occasional grudge match
	var open := _ai_fighters("open", used)
	if not open.is_empty():
		var wid2: int = open[rng.randi_range(0, open.size() - 1)]
		used[wid2] = true
		offers.append(_new_bout("open", "open", -1, wid2))
	if rng.chance(0.25) and not open.is_empty():
		var wid3: int = open[rng.randi_range(0, open.size() - 1)]
		if not used.has(wid3):
			var g := _new_bout("grudge", mech_class(warriors[wid3].mech_uid), -1, wid3)
			g["purse"] = int(g["purse"] * 2.0)
			offers.append(g)
	# team bouts: a tag match in any class where you own two 'Mechs, a lance battle once you have four
	var by_class := {}
	for uid in p.mechs:
		var cl := mech_class(uid)
		by_class[cl] = int(by_class.get(cl, 0)) + 1
	var tag_classes: Array = []
	for cl in CLASSES:
		if int(by_class.get(cl, 0)) >= 2:
			tag_classes.append(cl)
	if not tag_classes.is_empty() and p.warriors.size() >= 2:
		var tcl: String = tag_classes[rng.randi_range(0, tag_classes.size() - 1)]
		var opp := _ai_team(2, tcl, 0, used)
		if not opp.is_empty():
			for wid in opp:
				used[wid] = true
			offers.append(_new_team_bout("tag", tcl, [[-1, -1], opp]))
	if p.mechs.size() >= 4 and p.warriors.size() >= 4:
		var caps := [200, 240, 280, 320]
		var cap: int = caps[rng.randi_range(0, caps.size() - 1)]
		var opp2 := _ai_team(4, "open", cap, used)
		if not opp2.is_empty():
			for wid in opp2:
				used[wid] = true
			offers.append(_new_team_bout("lance", "open", [[-1, -1, -1, -1], opp2], cap))
	# a free-for-all: you against five rivals from five different stables
	if rng.chance(0.6):
		var field: Array = [[-1]]
		var stable_used := {}
		for s in stables:
			if s.is_player or field.size() >= 6:
				continue
			var pool2 := _stable_ready(s, "open", used)
			if pool2.is_empty() or stable_used.has(s.id):
				continue
			var pick: int = pool2[rng.randi_range(0, pool2.size() - 1)]
			field.append([pick])
			used[pick] = true
			stable_used[s.id] = true
		if field.size() >= 4:
			offers.append(_new_team_bout("melee", "open", field))


func book(offer_id: int, wid: int, uid: int, orders: Dictionary, wager := 0) -> String:
	var o: Dictionary = {}
	for x in offers:
		if int(x["id"]) == offer_id:
			o = x
	if o.is_empty():
		return "Offer not found"
	if o.has("sides"):
		if o.get("format", "") == "melee":
			return book_team(offer_id, [[wid, uid]], orders, {str(wid): orders.get("ammo", {})}, wager)
		return "Pick %d MechWarriors for this team bout" % (o["sides"][0] as Array).size()
	var w: Warrior = warriors.get(wid)
	var om: OwnedMech = mechs.get(uid)
	if w == null or w.stable_id != player_id:
		return "Pick one of your MechWarriors"
	if o.has("player_wid") and int(o["player_wid"]) != wid:
		return "Only %s can take this bout" % warriors[int(o["player_wid"])].short_name()
	if not w.available():
		return "%s can't fight: %s" % [w.short_name(), w.status_str()]
	if om == null or om.stable_id != player_id or not om.ready():
		return "That 'Mech isn't ready"
	if o["class"] != "open" and db.weight_class(om.design.tons) != o["class"]:
		return "This is a %s bout; the %s is %s" % [o["class"], om.design.display_name(), db.weight_class(om.design.tons)]
	if _booked(wid):
		return "%s is already booked this week" % w.short_name()
	if uid in _booked_mechs():
		return "That 'Mech is already booked"
	if wager > 0:
		var cap := int(player().cash * float(rules["max_wager_fraction"]))
		if wager > cap:
			return "The bookmakers cap your wager at %s" % money(cap)
	var b2: Dictionary = o.duplicate(true)
	b2["a"] = {"warrior": wid, "mech": uid}
	b2["warrior_id"] = wid
	b2["mech_uid"] = uid
	b2["orders"] = orders
	b2["wager"] = wager
	b2["odds"] = odds_for(wid, int(o["b"]["warrior"]))
	b2["resolved"] = false
	bookings.append(b2)
	offers.erase(o)
	return ""


func _booked_mechs() -> Array:
	var out: Array = []
	for b in bookings:
		if b.has("sides"):
			for e in b["sides"][0]:
				out.append(int(e["mech"]))
		else:
			out.append(int(b["mech_uid"]))
	return out


## Books a team or free-for-all bout. entries: [[warrior_id, mech_uid], ...] for your side.
## ammo: {str(warrior_id): {family: munition}}.
func book_team(offer_id: int, entries: Array, orders: Dictionary, ammo := {}, wager := 0) -> String:
	var o: Dictionary = {}
	for x in offers:
		if int(x["id"]) == offer_id:
			o = x
	if o.is_empty() or not o.has("sides"):
		return "Offer not found"
	var need: int = (o["sides"][0] as Array).size()
	if entries.size() != need:
		return "This bout needs %d MechWarriors" % need
	var seen_w := {}
	var seen_m := {}
	var tons := 0
	var booked_m := _booked_mechs()
	for e in entries:
		var wid: int = e[0]
		var uid: int = e[1]
		var w: Warrior = warriors.get(wid)
		var om: OwnedMech = mechs.get(uid)
		if w == null or w.stable_id != player_id:
			return "Pick your own MechWarriors"
		if seen_w.has(wid) or seen_m.has(uid):
			return "Each warrior and each 'Mech can only go in once"
		seen_w[wid] = true
		seen_m[uid] = true
		if not w.available():
			return "%s can't fight: %s" % [w.short_name(), w.status_str()]
		if om == null or om.stable_id != player_id or not om.ready():
			return "%s isn't ready" % (om.label() if om else "That 'Mech")
		if _booked(wid):
			return "%s is already booked this week" % w.short_name()
		if uid in booked_m:
			return "%s is already booked" % om.label()
		if o["class"] in CLASSES and db.weight_class(om.design.tons) != o["class"]:
			return "This is a %s bout; the %s is %s" % [o["class"], om.design.display_name(), db.weight_class(om.design.tons)]
		tons += om.design.tons
	if int(o.get("cap", 0)) > 0 and tons > int(o["cap"]):
		return "Your lance weighs %d tons; the cap is %d" % [tons, int(o["cap"])]
	if wager > 0:
		var cap := int(player().cash * float(rules["max_wager_fraction"]))
		if wager > cap:
			return "The bookmakers cap your wager at %s" % money(cap)
	var b2: Dictionary = o.duplicate(true)
	var side0: Array = []
	var members: Array = []
	for e in entries:
		side0.append({"warrior": int(e[0]), "mech": int(e[1])})
		members.append(int(e[0]))
	b2["sides"][0] = side0
	b2["a"] = side0[0]
	b2["warrior_id"] = int(entries[0][0])
	b2["mech_uid"] = int(entries[0][1])
	b2["members"] = members
	b2["orders"] = orders
	b2["ammo"] = ammo
	b2["wager"] = wager
	b2["odds"] = team_odds(b2)
	b2["resolved"] = false
	bookings.append(b2)
	offers.erase(o)
	return ""


## Win chance for side 0 of a team or free-for-all bout, from ratings.
func team_win_prob(b: Dictionary) -> float:
	var strengths: Array = []
	for side in b["sides"]:
		var tot := 0.0
		var n := 0
		for e in side:
			if int(e["warrior"]) >= 0:
				tot += warriors[int(e["warrior"])].elo
				n += 1
		strengths.append(pow(10.0, (tot / maxi(1, n)) / 400.0))
	var sum := 0.0
	for s in strengths:
		sum += s
	return float(strengths[0]) / maxf(0.0001, sum)


func team_odds(b: Dictionary) -> float:
	var p := clampf(team_win_prob(b), 0.03, 0.95)
	return snappedf((1.0 / p) * (1.0 - float(rules["wager_house_edge"])), 0.01)


## Alternate ammunition a 'Mech can load this year: {family: [munition keys]}.
func munition_options(om: OwnedMech) -> Dictionary:
	var out := {}
	var mun: Dictionary = db.tables["munitions"]
	var fams := {}
	for mt in Construction.mounts_of(om.design):
		var it := db.item(mt["id"])
		if it.get("kind", "") == "weapon" and it.get("ammo", "") != "":
			fams[CombatMech.ammo_family(str(it["ammo"]))] = true
	for key in mun:
		if key.begins_with("_") or key == "standard":
			continue
		var m: Dictionary = mun[key]
		if int(m.get("intro", 0)) > year:
			continue
		for fam in m.get("families", []):
			if fams.has(fam):
				if not out.has(fam):
					out[fam] = ["standard"]
				out[fam].append(key)
	return out


func cancel_booking(i: int) -> void:
	if i >= 0 and i < bookings.size() and not bookings[i]["resolved"] and bookings[i]["kind"] in ["regular", "open", "grudge"]:
		bookings.remove_at(i)


## Probability that warrior a beats warrior b (Elo).
func win_prob(a: int, b: int) -> float:
	var ra: float = warriors[a].elo
	var rb: float = warriors[b].elo
	return 1.0 / (1.0 + pow(10.0, (rb - ra) / 400.0))


## Decimal odds the bookmakers offer on warrior a.
func odds_for(a: int, b: int) -> float:
	var p := clampf(win_prob(a, b), 0.05, 0.95)
	return snappedf((1.0 / p) * (1.0 - float(rules["wager_house_edge"])), 0.01)


func generate_ai_card() -> void:
	ai_card = []
	var used := {}
	for b in offers + bookings:
		for wid in bout_warriors(b):
			used[wid] = true
	# rival team bouts: a tag match every week, a lance battle every other week, a free-for-all every third
	var tcl: String = CLASSES[rng.randi_range(0, 3)]
	var t1 := _ai_team(2, tcl, 0, used)
	if not t1.is_empty():
		var ex := {warriors[t1[0]].stable_id: true}
		for wid in t1:
			used[wid] = true
		var t2 := _ai_team(2, tcl, 0, used, ex)
		if not t2.is_empty():
			for wid in t2:
				used[wid] = true
			ai_card.append(_new_team_bout("tag", tcl, [t1, t2]))
	if week % 2 == 0:
		var cap: int = [200, 240, 280, 320][rng.randi_range(0, 3)]
		var l1 := _ai_team(4, "open", cap, used)
		if not l1.is_empty():
			for wid in l1:
				used[wid] = true
			var l2 := _ai_team(4, "open", cap, used, {warriors[l1[0]].stable_id: true})
			if not l2.is_empty():
				for wid in l2:
					used[wid] = true
				ai_card.append(_new_team_bout("lance", "open", [l1, l2], cap))
	if week % 3 == 0:
		var field: Array = []
		for s in stables:
			if s.is_player or field.size() >= 6:
				continue
			var pool := _stable_ready(s, "open", used)
			if pool.is_empty():
				continue
			var pick: int = pool[rng.randi_range(0, pool.size() - 1)]
			used[pick] = true
			field.append([pick])
		if field.size() >= 4:
			ai_card.append(_new_team_bout("melee", "open", field))
	for cls in CLASSES:
		var pool := _ai_fighters(cls, used)
		pool.sort_custom(func(x, y): return warriors[x].elo > warriors[y].elo)
		var n := mini(pool.size() / 2, 3)
		var i := 0
		var made := 0
		while made < n and i + 1 < pool.size():
			var a: int = pool[i]
			var b: int = pool[i + 1]
			if warriors[a].stable_id == warriors[b].stable_id:
				i += 1
				continue
			used[a] = true
			used[b] = true
			ai_card.append(_new_bout("regular", cls, a, b))
			i += 2
			made += 1


func _special_bouts_for_player() -> Array:
	var out: Array = []
	# title fights every N weeks
	if week % int(rules["title_fight_every_weeks"]) == 0 and week < 48:
		for cls in CLASSES:
			var champ: int = champions.get(cls, -1)
			var ranks := rankings(cls)
			var contender := -1
			for wid in ranks:
				if wid != champ and _fight_ready(warriors[wid]):
					contender = wid
					break
			if champ < 0 or contender < 0 or not warriors.has(champ) or not _fight_ready(warriors[champ]):
				continue
			var pc: bool = warriors[champ].stable_id == player_id
			var pk: bool = warriors[contender].stable_id == player_id
			if pc and pk:
				continue
			var b := _new_bout("title", cls, champ if pc else contender, contender if pc else champ)
			if pc or pk:
				b["player_wid"] = champ if pc else contender
				out.append(b)
	# the Grand Championship bracket
	if championship.get("active", false):
		for m in championship.get("matches", []):
			if m["done"]:
				continue
			for side in ["a", "b"]:
				var wid2: int = m[side]
				if warriors.has(wid2) and warriors[wid2].stable_id == player_id:
					var other: int = m["b" if side == "a" else "a"]
					var bout := _new_bout("championship", "open", wid2, other)
					bout["round"] = championship["round"]
					bout["match"] = m["id"]
					bout["player_wid"] = wid2
					bout["purse"] = int(bout["purse"] * float(rules["purse_championship_mult"][mini(int(championship["round"]), 2)]))
					out.append(bout)
	return out


## Builds the fight. For a booking, side A is the player's warrior.
func make_sim(b: Dictionary, record := true) -> CombatSim:
	var raw_sides: Array = b["sides"] if b.has("sides") else [[b["a"]], [b["b"]]]
	var team_size := 1
	for s in raw_sides:
		team_size = maxi(team_size, (s as Array).size())
	var arena := ArenaGenerator.generate(b["theme"], int(b["seed"]), team_size, b["arena"], raw_sides.size())
	var sides: Array = []
	var player_side := b.has("orders")
	for ti in raw_sides.size():
		var side: Array = []
		for e in raw_sides[ti]:
			var wid: int = e["warrior"]
			var uid: int = e["mech"]
			var w: Warrior = warriors[wid]
			var om: OwnedMech = mechs[uid]
			var orders: Dictionary
			if ti == 0 and player_side:
				orders = (b["orders"] as Dictionary).duplicate(true)
				var am: Dictionary = b.get("ammo", {})
				if am.has(str(wid)):
					orders["ammo"] = am[str(wid)]
			else:
				orders = _ai_orders(w, om)
			side.append({"design": om.design, "warrior": w.sim_dict(), "orders": orders, "condition": om.sim_condition()})
		sides.append(side)
	var bout := {"to_death": b.get("to_death", false), "conditions": b.get("conditions", {}),
		"time_limit": float(b.get("time_limit", db.tables["time_limit_seconds"])), "calls": int(db.tables.get("corner_calls_per_fight", 3))}
	return CombatSim.create(arena, sides, int(b["seed"]) * 13 + 5, bout, record)


func _ai_orders(w: Warrior, om: OwnedMech = null) -> Dictionary:
	var o: Dictionary
	if not w.orders.is_empty():
		o = w.orders.duplicate(true)
	else:
		var s: Stable = stables[w.stable_id] if w.stable_id >= 0 else null
		var phil: String = s.philosophy if s else "balanced"
		o = AI_ORDERS.get(phil, AI_ORDERS["balanced"]).duplicate()
		if "cautious" in w.traits:
			o["retreat"] = 0.45
	# rivals load special ammo now and then: brawlers love Inferno, everyone likes LB-X cluster
	if om != null:
		var opts := munition_options(om)
		var ammo := {}
		var hb := hash(str(w.id) + ":" + str(week_index()))
		for fam in opts:
			var keys: Array = opts[fam]
			if keys.size() > 1 and (absi(hb) % 100) < (45 if o.get("range", "") == "close" else 25):
				ammo[fam] = keys[1 + absi(hb / 100) % (keys.size() - 1)]
		if not ammo.is_empty():
			o["ammo"] = ammo
	return o


## Records, fame, morale, injuries and 'Mech damage for one fighter after any bout.
func _member_after_fight(w: Warrior, om: OwnedMech, st: Stable, r: Dictionary, won: bool, lost: bool, b: Dictionary, res: Dictionary, vs_wid: int, fame_scale := 1.0) -> void:
	if won:
		w.wins += 1
		st.wins += 1
		w.streak = maxi(1, w.streak + 1)
	elif lost:
		w.losses += 1
		st.losses += 1
		w.streak = mini(-1, w.streak - 1)
	else:
		w.draws += 1
		st.draws += 1
	w.kills += int(r["kills"])
	om.fights += 1
	om.kills += int(r["kills"])
	var fame_gain := float(rules["fame_win"]) if won else float(rules["fame_loss"]) if lost else 0.5
	fame_gain = fame_gain * fame_scale + int(r["kills"]) * float(rules["fame_kill"]) + float(r["showmanship"]) / 25.0
	if "showboat" in w.traits:
		fame_gain *= 1.5
	w.fame = maxf(0.0, w.fame + fame_gain)
	om.fame += maxf(0.0, fame_gain * 0.5)
	st.fame = maxf(0.0, st.fame + fame_gain * 0.3)
	w.xp += int(rules["xp_per_fight"]) + (int(rules["xp_win_bonus"]) if won else 0)
	w.morale = clampf(w.morale + (float(rules["morale_win"]) if won else float(rules["morale_loss"]) if lost else 0.0), 0, 100)
	w.fatigue = minf(100.0, w.fatigue + float(rules["fatigue_per_fight"]))
	var hits := int(r["pilot_hits"])
	if hits >= 6:
		w.dead = true
		add_news("death", "Death in the arena", "%s (%s) is killed at %s." % [w.full_name(), st.name, b["arena_name"]], st.is_player)
	elif hits > 0:
		w.injury_weeks = maxi(w.injury_weeks, int(hits * int(rules["injury_weeks_per_hit"]) * opt("injuries")) - st.medic)
	var cond := {"armor": r["armor"], "internal": r["internal"], "hit_slots": r["hit_slots"], "ammo": r["ammo"]}
	if r["destroyed"]:
		om.status = "wrecked"
		om.condition = cond
	else:
		var pristine := (r["hit_slots"] as Array).is_empty()
		for key in om.design.armor:
			if int(r["armor"].get(key, 0)) < int(om.design.armor[key]):
				pristine = false
		om.condition = {} if pristine else cond
	w.history.append({"y": year, "w": week, "vs": vs_wid, "res": "W" if won else ("L" if lost else "D"),
		"how": res["how"], "arena": b["arena_name"], "kind": b.get("format", "duel") if b.get("format", "duel") != "duel" else b["kind"]})
	while w.history.size() > 30:
		w.history.pop_front()


## Team and free-for-all results: purse split by placement, team ratings, every fighter's record.
func _apply_team_result(b: Dictionary, res: Dictionary) -> Dictionary:
	var winner: int = res["winner"]
	var sides: Array = b["sides"]
	var ms: Array = res["mechs"]
	var format: String = b.get("format", "tag")
	var summary := {"bout": b, "winner": winner, "how": res["how"], "duration": res["duration"], "purse_a": 0}
	# sim index -> (team, entry)
	var members: Array = []
	for ti in sides.size():
		for e in sides[ti]:
			members.append({"team": ti, "warrior": int(e["warrior"]), "mech": int(e["mech"])})
	var purse := int(b["purse"])
	var team_purse := {}
	if format == "melee":
		# placement purses: 50%, 20%, 12%, the rest share 18%
		var placement: Array = res["placement"]
		var shares := [0.5, 0.2, 0.12]
		var rest := 0.18 / maxf(1.0, placement.size() - 3)
		for pi in placement.size():
			var team: int = ms[placement[pi]]["team"]
			team_purse[team] = int(purse * (shares[pi] if pi < shares.size() else rest))
	else:
		var share_w := float(rules["purse_winner_share"])
		for ti in sides.size():
			if winner < 0:
				team_purse[ti] = int(purse / float(sides.size()))
			else:
				team_purse[ti] = int(purse * (share_w if ti == winner else (1.0 - share_w)))
	# ratings: team average vs the field
	var avg := {}
	for ti in sides.size():
		var tot := 0.0
		for e in sides[ti]:
			tot += warriors[int(e["warrior"])].elo
		avg[ti] = tot / maxf(1.0, float((sides[ti] as Array).size()))
	var k := float(rules["elo_k"]) * (0.6 if format != "duel" else 1.0)
	var place_of := {}
	var placement2: Array = res["placement"]
	for pi in placement2.size():
		place_of[int(ms[placement2[pi]]["team"])] = mini(int(place_of.get(int(ms[placement2[pi]]["team"]), 99)), pi)
	for ti in sides.size():
		var delta := 0.0
		for tj in sides.size():
			if ti == tj:
				continue
			var e_ij := 1.0 / (1.0 + pow(10.0, (float(avg[tj]) - float(avg[ti])) / 400.0))
			var s_ij := 0.5
			if format == "melee":
				s_ij = 1.0 if int(place_of.get(ti, 99)) < int(place_of.get(tj, 99)) else 0.0
			elif winner >= 0:
				s_ij = 1.0 if ti == winner else 0.0
			delta += k * (s_ij - e_ij) / maxf(1.0, sides.size() - 1.0)
		for e in sides[ti]:
			warriors[int(e["warrior"])].elo += delta
	# money and records
	var opp_first := {}
	for ti in sides.size():
		opp_first[ti] = int(sides[(ti + 1) % sides.size()][0]["warrior"])
	for ti in sides.size():
		var n: int = (sides[ti] as Array).size()
		for e in sides[ti]:
			var w: Warrior = warriors[int(e["warrior"])]
			var st: Stable = stables[w.stable_id]
			_pay_purse(st, w, int(int(team_purse.get(ti, 0)) / float(n)))
		if ti == 0:
			summary["purse_a"] = int(team_purse.get(0, 0))
	for mi in members.size():
		var me: Dictionary = members[mi]
		var w2: Warrior = warriors[me["warrior"]]
		var om: OwnedMech = mechs[me["mech"]]
		var st2: Stable = stables[w2.stable_id]
		var won: bool = winner >= 0 and me["team"] == winner
		var lost: bool = winner >= 0 and not won
		_member_after_fight(w2, om, st2, ms[mi], won, lost, b, res, opp_first[me["team"]], 1.2 if format == "melee" and won else 1.0)
	if int(b.get("wager", 0)) > 0:
		var wg := int(b["wager"])
		var sa: Stable = stables[warriors[int(sides[0][0]["warrior"])].stable_id]
		if winner == 0:
			var win := int(wg * float(b["odds"])) - wg
			sa.add_ledger("Wagers", win)
			summary["wager"] = win
		elif winner >= 0:
			sa.add_ledger("Wagers", -wg)
			summary["wager"] = -wg
		else:
			summary["wager"] = 0
	var mine := false
	var teams: Array = []
	for ti in sides.size():
		var ids: Array = []
		for e in sides[ti]:
			ids.append(int(e["warrior"]))
			if warriors[int(e["warrior"])].stable_id == player_id:
				mine = true
		teams.append(ids)
	for mi2 in members.size():
		if ms[mi2]["destroyed"]:
			var vw: Warrior = warriors[members[mi2]["warrior"]]
			add_news("kill", "'Mech destroyed", "%s's %s is wrecked in a %s at %s." % [vw.short_name(), mechs[members[mi2]["mech"]].design.display_name(), FORMAT_LABEL.get(format, format).to_lower(), b["arena_name"]], mine)
	if mine or format == "lance":
		var win_names: Array = []
		if winner >= 0:
			for wid in teams[winner]:
				win_names.append(warriors[wid].short_name())
		add_news("team", "%s at %s" % [FORMAT_LABEL.get(format, format), b["arena_name"]],
			("%s win (%s)." % [" & ".join(win_names), res["how"]]) if winner >= 0 else "A draw.", mine)
	b["resolved"] = true
	b["result"] = {"winner": winner, "how": res["how"], "duration": res["duration"], "placement": res["placement"]}
	results.append({"y": year, "w": week, "kind": b["kind"], "format": format, "class": b["class"], "arena": b["arena_name"],
		"a": int(sides[0][0]["warrior"]), "b": int(sides[1][0]["warrior"]), "ma": mechs[int(sides[0][0]["mech"])].design.display_name(),
		"mb": mechs[int(sides[1][0]["mech"])].design.display_name(), "winner": winner, "how": res["how"], "dur": res["duration"],
		"player": mine, "teams": teams})
	while results.size() > 400:
		results.pop_front()
	return summary


## Applies a finished fight to the campaign. Returns a summary dictionary for the UI.
func apply_result(b: Dictionary, res: Dictionary) -> Dictionary:
	if b.has("sides"):
		return _apply_team_result(b, res)
	var wa: Warrior = warriors[b["a"]["warrior"]]
	var wb: Warrior = warriors[b["b"]["warrior"]]
	var ma: OwnedMech = mechs[b["a"]["mech"]]
	var mb: OwnedMech = mechs[b["b"]["mech"]]
	var winner: int = res["winner"]
	var sa: Stable = stables[wa.stable_id]
	var sb: Stable = stables[wb.stable_id]
	var summary := {"bout": b, "winner": winner, "how": res["how"], "duration": res["duration"], "lines": []}
	# Elo
	var ea := 1.0 / (1.0 + pow(10.0, (wb.elo - wa.elo) / 400.0))
	var score_a := 0.5 if winner < 0 else (1.0 if winner == 0 else 0.0)
	var k := float(rules["elo_k"]) * (1.5 if b["kind"] in ["title", "championship"] else 1.0)
	wa.elo += k * (score_a - ea)
	wb.elo += k * ((1.0 - score_a) - (1.0 - ea))
	# purse
	var purse := int(b["purse"])
	var share_w := float(rules["purse_winner_share"])
	var pa := int(purse * (0.5 if winner < 0 else (share_w if winner == 0 else 1.0 - share_w)))
	var pb := purse - pa
	_pay_purse(sa, wa, pa)
	_pay_purse(sb, wb, pb)
	summary["purse_a"] = pa
	summary["purse_b"] = pb
	# wager
	if int(b.get("wager", 0)) > 0:
		var wg := int(b["wager"])
		if winner == 0:
			var win := int(wg * float(b["odds"])) - wg
			sa.add_ledger("Wagers", win)
			summary["wager"] = win
		elif winner == 1:
			sa.add_ledger("Wagers", -wg)
			summary["wager"] = -wg
		else:
			summary["wager"] = 0
	# per side bookkeeping
	var ms: Array = res["mechs"]
	for side in 2:
		var w: Warrior = wa if side == 0 else wb
		var om: OwnedMech = ma if side == 0 else mb
		var st: Stable = sa if side == 0 else sb
		var r: Dictionary = ms[side]
		var won := winner == side
		var lost := winner >= 0 and not won
		if won:
			w.wins += 1
			st.wins += 1
			w.streak = maxi(1, w.streak + 1)
		elif lost:
			w.losses += 1
			st.losses += 1
			w.streak = mini(-1, w.streak - 1)
		else:
			w.draws += 1
			st.draws += 1
		w.kills += int(r["kills"])
		om.fights += 1
		om.kills += int(r["kills"])
		var fame_gain := float(rules["fame_win"]) if won else float(rules["fame_loss"]) if lost else 0.5
		fame_gain += int(r["kills"]) * float(rules["fame_kill"]) + float(r["showmanship"]) / 25.0
		if "showboat" in w.traits:
			fame_gain *= 1.5
		if b["kind"] == "title" and won:
			fame_gain += float(rules["fame_title"])
		w.fame = maxf(0.0, w.fame + fame_gain)
		om.fame += maxf(0.0, fame_gain * 0.5)
		st.fame = maxf(0.0, st.fame + fame_gain * 0.4)
		w.xp += int(rules["xp_per_fight"]) + (int(rules["xp_win_bonus"]) if won else 0)
		w.morale = clampf(w.morale + (float(rules["morale_win"]) if won else float(rules["morale_loss"]) if lost else 0.0), 0, 100)
		w.fatigue = minf(100.0, w.fatigue + float(rules["fatigue_per_fight"]))
		var hits := int(r["pilot_hits"])
		if hits >= 6:
			w.dead = true
			add_news("death", "Death in the arena", "%s (%s) is killed at %s." % [w.full_name(), st.name, b["arena_name"]], st.is_player)
		elif hits > 0:
			w.injury_weeks = maxi(w.injury_weeks, int(hits * int(rules["injury_weeks_per_hit"]) * opt("injuries")) - st.medic)
		# 'Mech damage carries over
		if r["destroyed"]:
			om.status = "wrecked"
			om.condition = {"armor": r["armor"], "internal": r["internal"], "hit_slots": r["hit_slots"], "ammo": r["ammo"]}
		else:
			var cond := {"armor": r["armor"], "internal": r["internal"], "hit_slots": r["hit_slots"], "ammo": r["ammo"]}
			var pristine := true
			for key in om.design.armor:
				if int(r["armor"].get(key, 0)) < int(om.design.armor[key]):
					pristine = false
			if not r["hit_slots"].is_empty():
				pristine = false
			om.condition = {} if pristine else cond
		w.history.append({"y": year, "w": week, "vs": wb.id if side == 0 else wa.id, "res": "W" if won else ("L" if lost else "D"),
			"how": res["how"], "arena": b["arena_name"], "kind": b["kind"]})
		while w.history.size() > 30:
			w.history.pop_front()
	# titles
	if b["kind"] == "title" and winner >= 0:
		var champ_w: Warrior = wa if winner == 0 else wb
		var cls: String = b["class"]
		var old: int = champions.get(cls, -1)
		champions[cls] = champ_w.id
		if old != champ_w.id:
			champ_w.titles.append("%s champion %d" % [cls.capitalize(), year])
			add_news("title", "New %s champion!" % cls, "%s takes the %s title at %s." % [champ_w.full_name(), cls, b["arena_name"]], champ_w.stable_id == player_id)
		else:
			add_news("title", "Title defended", "%s defends the %s title." % [champ_w.full_name(), cls], champ_w.stable_id == player_id)
	if b["kind"] == "championship":
		_championship_result(b, winner)
	# headline for upsets and kills
	var wname := "draw" if winner < 0 else (wa.short_name() if winner == 0 else wb.short_name())
	if (winner == 0 and ea < 0.3) or (winner == 1 and ea > 0.7):
		add_news("upset", "Upset at %s" % b["arena_name"], "%s beats the odds against %s." % [wname, (wb if winner == 0 else wa).short_name()], sa.is_player or sb.is_player)
	if ms[0]["destroyed"] or ms[1]["destroyed"]:
		var victim: Warrior = wa if ms[0]["destroyed"] else wb
		add_news("kill", "'Mech destroyed", "%s's %s is wrecked at %s." % [victim.short_name(), (ma if ms[0]["destroyed"] else mb).design.display_name(), b["arena_name"]], sa.is_player or sb.is_player)
	b["resolved"] = true
	b["result"] = {"winner": winner, "how": res["how"], "duration": res["duration"]}
	results.append({"y": year, "w": week, "kind": b["kind"], "class": b["class"], "arena": b["arena_name"],
		"a": wa.id, "b": wb.id, "ma": ma.design.display_name(), "mb": mb.design.display_name(), "winner": winner,
		"how": res["how"], "dur": res["duration"], "player": sa.is_player or sb.is_player})
	while results.size() > 400:
		results.pop_front()
	return summary


func _pay_purse(s: Stable, w: Warrior, amount: int) -> void:
	var cut := int(amount * w.purse_share)
	s.add_ledger("Purses", amount - cut)
	s.add_ledger("Arena fees", -int(amount * float(rules["arena_entry_fee"])))


func resolve_ai_card() -> void:
	for b in ai_card:
		if b.get("resolved", false):
			continue
		var sim := make_sim(b, false)
		sim.run_to_end()
		apply_result(b, sim.result)


## Title fights between two AI warriors happen off-screen.
func _resolve_ai_specials() -> void:
	if week % int(rules["title_fight_every_weeks"]) == 0 and week < 48:
		for cls in CLASSES:
			var champ: int = champions.get(cls, -1)
			if champ < 0 or not warriors.has(champ) or warriors[champ].stable_id == player_id:
				continue
			var ranks := rankings(cls)
			var contender := -1
			for wid in ranks:
				if wid != champ and _fight_ready(warriors[wid]) and not _booked(wid):
					contender = wid
					break
			if contender < 0 or warriors[contender].stable_id == player_id or not _fight_ready(warriors[champ]):
				continue
			var b := _new_bout("title", cls, champ, contender)
			var sim := make_sim(b, false)
			sim.run_to_end()
			apply_result(b, sim.result)
	if championship.get("active", false):
		for m in championship["matches"]:
			if m["done"]:
				continue
			var pa: bool = warriors[m["a"]].stable_id == player_id
			var pb: bool = warriors[m["b"]].stable_id == player_id
			if pa or pb:
				continue
			var ra := _fight_ready(warriors[m["a"]])
			var rb := _fight_ready(warriors[m["b"]])
			if not ra or not rb:
				# a warrior who can't fight forfeits
				m["winner"] = m["b"] if not ra else m["a"]
				m["done"] = true
				add_news("championship", "Forfeit", "%s can't fight and forfeits the Grand Championship bout." % warriors[m["a"] if not ra else m["b"]].short_name())
				continue
			var b2 := _new_bout("championship", "open", m["a"], m["b"])
			b2["round"] = championship["round"]
			b2["match"] = m["id"]
			var sim2 := make_sim(b2, false)
			sim2.run_to_end()
			apply_result(b2, sim2.result)
			if not m["done"]:
				# a draw: the higher seed advances
				_championship_result(b2, 0)


# ================================================================== the Grand Championship

func _start_championship() -> void:
	var all: Array = []
	for wid in warriors:
		var w: Warrior = warriors[wid]
		if w.stable_id >= 0 and not w.dead and not w.retired and w.mech_uid >= 0:
			all.append(wid)
	all.sort_custom(func(a, b): return warriors[a].elo > warriors[b].elo)
	var seeds := all.slice(0, 8)
	if seeds.size() < 8:
		return
	var matches: Array = []
	for k in 4:
		matches.append({"id": k, "a": seeds[k], "b": seeds[7 - k], "done": false, "winner": -1})
	championship = {"active": true, "year": year, "round": 0, "matches": matches, "seeds": seeds}
	var names: Array = []
	for wid in seeds:
		names.append(warriors[wid].short_name())
	add_news("championship", "Grand Championship field set", "The top eight: %s." % ", ".join(names), false)


func _championship_result(b: Dictionary, winner: int) -> void:
	for m in championship.get("matches", []):
		if int(m["id"]) == int(b.get("match", -1)) and not m["done"]:
			var a_wid: int = b["a"]["warrior"]
			var won_wid: int = b["a"]["warrior"] if winner <= 0 else b["b"]["warrior"]
			if winner < 0:
				won_wid = m["a"]
			m["winner"] = won_wid
			m["done"] = true


func _advance_championship() -> void:
	if not championship.get("active", false):
		return
	var ms: Array = championship["matches"]
	for m in ms:
		if not m["done"]:
			# an unbooked player bout is a forfeit
			var a_player: bool = warriors[m["a"]].stable_id == player_id
			m["winner"] = m["b"] if a_player else m["a"]
			m["done"] = true
			if a_player or warriors[m["b"]].stable_id == player_id:
				add_news("championship", "Forfeit", "A Grand Championship bout is forfeited.", true)
	var winners: Array = []
	for m in ms:
		winners.append(m["winner"])
	if winners.size() == 1:
		var champ: Warrior = warriors[winners[0]]
		champions["grand"] = champ.id
		champ.titles.append("Grand Champion %d" % year)
		champ.fame += 25.0
		var st: Stable = stables[champ.stable_id]
		st.fame += 15.0
		add_news("championship", "GRAND CHAMPION %d" % year, "%s of %s is the Champion of Solaris!" % [champ.full_name(), st.name], champ.stable_id == player_id)
		championship["active"] = false
		championship["champion"] = champ.id
		return
	var nm: Array = []
	for k in winners.size() / 2:
		nm.append({"id": k, "a": winners[k * 2], "b": winners[k * 2 + 1], "done": false, "winner": -1})
	championship["matches"] = nm
	championship["round"] = int(championship["round"]) + 1


# ================================================================== rankings

## Warrior ids in a weight class ("open" = everyone), best Elo first.
func rankings(cls: String) -> Array:
	var out: Array = []
	for wid in warriors:
		var w: Warrior = warriors[wid]
		if w.stable_id < 0 or w.dead or w.retired or w.mech_uid < 0 or not mechs.has(w.mech_uid):
			continue
		if cls == "open" or mech_class(w.mech_uid) == cls:
			out.append(wid)
	out.sort_custom(func(a, b): return warriors[a].elo > warriors[b].elo)
	return out


func stable_rankings() -> Array:
	var out := range(stables.size())
	out.sort_custom(func(a, b): return stables[a].fame > stables[b].fame)
	return out


# ================================================================== the week

func start_week() -> void:
	phase = "booking"
	bookings = []
	_fire_events()
	if week == int(rules["championship_weeks"][0]) and not championship.get("active", false) and championship.get("year", 0) != year:
		_start_championship()
	refresh_market()
	generate_offers()
	generate_ai_card()
	generate_merc_jobs()


func unresolved_bookings() -> Array:
	var out: Array = []
	for b in bookings:
		if not b["resolved"]:
			out.append(b)
	return out


## Runs everything left this week and moves to the next one.
func advance_week() -> void:
	for b in bookings:
		if not b["resolved"]:
			var sim := make_sim(b, false)
			sim.run_to_end()
			apply_result(b, sim.result)
	resolve_ai_card()
	_resolve_ai_specials()
	if championship.get("active", false) and week >= int(rules["championship_weeks"][0]):
		_advance_championship()
	_deployment_week()
	_end_week()
	week += 1
	if week > int(rules["weeks_per_season"]):
		week = 1
		year += 1
		_new_year()
	start_week()


func _end_week() -> void:
	for s in stables:
		# income
		var income := opt("sponsors") if s.is_player else 1.0
		var costs := opt("upkeep") if s.is_player else 1.0
		s.add_ledger("Sponsors", int(s.fame * float(rules["sponsor_per_fame_week"]) * income))
		s.add_ledger("Merchandise", int(s.fame * s.fame * float(rules["merch_per_fame_sq_week"]) / 10.0 * income))
		# costs
		var sal := 0
		for wid in s.warriors:
			sal += int(warriors[wid].salary)
		s.add_ledger("Salaries", -sal)
		s.add_ledger("Techs", -int(s.techs * int(rules["tech_salary_week"]) * costs))
		s.add_ledger("Bay upkeep", -int(s.bays * int(rules["bay_upkeep_week"]) * costs))
		if s.medic > 0:
			s.add_ledger("Medical staff", -int(rules["medic_salary_week"][s.medic]))
		if s.sim_pods > 0:
			s.add_ledger("Simulator pods", -s.sim_pods * int(rules["sim_pod_upkeep_week"]))
		var upkeep := 0.0
		for uid in s.mechs:
			upkeep += float(mechs[uid].paid) * float(rules["mech_upkeep_fraction_week"])
		s.add_ledger("'Mech upkeep", -int(upkeep * costs))
		_bay_work(s)
		if not s.is_player:
			_ai_manage(s)
		s.fame *= float(rules["fame_decay_week"])
		s.close_week(year, week)
	for wid in warriors:
		var w: Warrior = warriors[wid]
		if w.dead or w.retired:
			continue
		w.fatigue = maxf(0.0, w.fatigue - float(rules["fatigue_recover_week"]))
		if w.injury_weeks > 0:
			w.injury_weeks -= 1
		if w.drafted_weeks > 0:
			w.drafted_weeks -= 1
			if w.drafted_weeks == 0 and w.stable_id == player_id:
				add_news("draft", "Back from the front", "%s returns to the stable." % w.full_name(), true)
		w.fame *= float(rules["fame_decay_week"])
		# skill growth from experience and simulator time
		var s2: Stable = stables[w.stable_id] if w.stable_id >= 0 else null
		var xp_need := int(rules["xp_to_improve"])
		if s2 != null and s2.sim_pods > 0 and rng.chance(0.08 * s2.sim_pods):
			w.xp += 1
		if w.xp >= xp_need:
			w.xp -= xp_need
			if w.gunnery > 1 and (w.gunnery + 1 >= w.piloting or rng.chance(0.5)):
				w.gunnery -= 1
				_skill_news(w, "gunnery")
			elif w.piloting > 2:
				w.piloting -= 1
				_skill_news(w, "piloting")
		if w.stable_id >= 0:
			w.contract_weeks -= 1
			if w.contract_weeks <= 0:
				_contract_expired(w)
		if w.stable_id == player_id and w.morale < 15 and rng.chance(0.2):
			add_news("morale", "Unhappy warrior", "%s demands a release." % w.full_name(), true)


func _skill_news(w: Warrior, what: String) -> void:
	if w.stable_id == player_id:
		add_news("skill", "Improvement", "%s's %s improves to %d." % [w.full_name(), what, w.gunnery if what == "gunnery" else w.piloting], true)


func _contract_expired(w: Warrior) -> void:
	var s: Stable = stables[w.stable_id]
	if s.is_player:
		if w.morale >= 40 and rng.chance(0.7):
			w.contract_weeks = 52
			w.salary = maxi(w.salary, w.fair_salary(rules))
			add_news("contract", "Contract renewed", "%s re-signs for a year at %s/week." % [w.full_name(), money(w.salary)], true)
			return
		add_news("contract", "Contract expired", "%s leaves %s as a free agent." % [w.full_name(), s.name], true)
	else:
		if rng.chance(0.75):
			w.contract_weeks = rng.randi_range(26, 104)
			return
	s.warriors.erase(w.id)
	w.stable_id = -1
	w.mech_uid = -1


const CLASS_SHARE := {"light": 0.25, "medium": 0.3, "heavy": 0.25, "assault": 0.2}


## The weight class the rival league is shortest of, so every division keeps a full card.
func _short_class() -> String:
	var counts := {"light": 0, "medium": 0, "heavy": 0, "assault": 0}
	var total := 0
	for s in stables:
		if s.is_player:
			continue
		for uid in s.mechs:
			counts[mech_class(uid)] += 1
			total += 1
	var best := "medium"
	var best_gap := -INF
	for cls in CLASSES:
		var gap: float = float(CLASS_SHARE[cls]) * total - counts[cls] + rng.randf() * 0.5
		if gap > best_gap:
			best_gap = gap
			best = cls
	return best


## Rival stables: keep their rosters and 'Mech bays full so the league stays alive for decades.
func _ai_manage(s: Stable) -> void:
	# backers keep rival stables in business (they're the league, not the player's competitors for cash)
	var floor_cash := 1500000 + int(s.fame * 30000)
	if s.cash < floor_cash:
		s.add_ledger("Patron", floor_cash - s.cash)
	for wid in s.warriors.duplicate():
		if warriors[wid].dead or warriors[wid].retired:
			s.warriors.erase(wid)
	# repairs: rebuild wrecks when affordable, otherwise scrap them
	for uid in s.mechs.duplicate():
		var om: OwnedMech = mechs[uid]
		if om.status == "wrecked":
			var est := om.repair_estimate(year, rules)
			if s.cash > int(est["cost"]) * 2 and rng.chance(0.6):
				s.add_ledger("Repairs", -int(est["cost"]))
				om.status = "repair"
				om.work_hours = 120.0
				om.pending_design = {"missing": []}
			else:
				s.mechs.erase(uid)
				s.add_ledger("Sales", om.value())
				mechs.erase(uid)
		elif om.status == "ready" and om.is_damaged():
			start_repair(uid)
	# roster: 4-6 warriors
	var target := 4 + (1 if s.fame > 25.0 else 0) + (1 if s.fame > 60.0 else 0)
	var tries := 0
	while s.warriors.size() < target and tries < 3:
		tries += 1
		var fa: Array = []
		for wid in warriors:
			var w: Warrior = warriors[wid]
			if w.stable_id == -1 and not w.dead and not w.retired and w.drafted_weeks <= 0 and not (wid in market["agents"]):
				fa.append(wid)
		if fa.is_empty():
			fa.append(_gen_free_agent(rng.randf_range(0.2, 0.7)).id)
		fa.sort_custom(func(a, b): return warriors[a].elo > warriors[b].elo)
		var pick: int = fa[mini(rng.randi_range(0, 4), fa.size() - 1)]
		_sign(warriors[pick], s, warriors[pick].salary, rng.randi_range(26, 104))
	# 'Mechs: one per warrior plus a spare at most
	_auto_assign(s)
	var bought := 0
	for wid in s.warriors:
		var w2: Warrior = warriors[wid]
		if (w2.mech_uid >= 0 and w2.mech_uid in s.mechs) or bought >= 2:
			continue
		var cls := _short_class()
		var did := _pick_design(cls, s.philosophy, mini(int(s.cash * 0.7), 9000000))
		if did != "":
			var om2 := _add_mech(did, s)
			s.add_ledger("Purchases", -om2.base_cost())
			w2.mech_uid = om2.uid
			bought += 1
	while s.mechs.size() > s.warriors.size() + 1:
		var spare := -1
		for uid in s.mechs:
			var used := false
			for wid in s.warriors:
				if warriors[wid].mech_uid == uid:
					used = true
			if not used:
				spare = uid
				break
		if spare < 0:
			break
		s.add_ledger("Sales", int(mechs[spare].value() * 0.6))
		s.mechs.erase(spare)
		mechs.erase(spare)
	_auto_assign(s)


func _new_year() -> void:
	add_news("season", "The %d season" % year, "A new year on Solaris VII. Rankings carry over; the Grand Championship returns in week %d." % int(rules["championship_weeks"][0]))
	championship = {"year": 0}
	var retire: Array = rules["retire_age"]
	for wid in warriors.keys():
		var w: Warrior = warriors[wid]
		if w.dead or w.retired:
			continue
		var a := w.age(year)
		if a > int(rules["decline_age"]) and rng.chance(0.35):
			if rng.chance(0.5):
				w.gunnery = mini(7, w.gunnery + 1)
			else:
				w.piloting = mini(8, w.piloting + 1)
		if a >= int(retire[0]) and (a >= int(retire[1]) or rng.chance(0.25)):
			w.retired = true
			if w.stable_id >= 0:
				var s: Stable = stables[w.stable_id]
				s.warriors.erase(wid)
				add_news("retire", "Retirement", "%s (%d) hangs up the neurohelmet after a %s career." % [w.full_name(), a, w.record_str()], s.is_player)
			w.stable_id = -1
			w.mech_uid = -1
	for k in int(rules["prospects_per_year"]):
		var w2 := _gen_free_agent(rng.randf_range(0.0, 0.6))
		w2.birth_year = year - rng.randi_range(18, 23)
	_pool_cache.clear()


## The timeline (data/era_events.json): every event whose week has come makes the news and takes effect.
func _fire_events() -> void:
	for e in db.events:
		if str(e.get("only", "")) == "merc":
			continue
		var key := "%d-%d-%s" % [int(e["year"]), int(e["week"]), e["title"]]
		if fired_events.has(key):
			continue
		var at := (int(e["year"]) - 3015) * 52 + int(e["week"])
		if at > week_index():
			continue
		fired_events[key] = true
		if not flag("timeline"):
			continue
		var fx: Dictionary = e.get("effects", {})
		if week_index() - at > 2:
			# long past (a save older than this entry of the timeline): no late news, nothing replayed
			if fx.get("clan_salvage", false):
				effects.append({"kind": "clan_salvage", "value": 1.0, "until": at + 52 * 50, "src": str(e["title"])})
			continue
		var text := str(e["text"])
		if e.has("solaris"):
			text += " " + str(e["solaris"])
		add_news("event", e["title"], text)
		_apply_effects(fx, str(e["title"]))


## What the timeline has in force right now, for the office: [{"src", "text", "weeks"}].
func effects_in_force() -> Array:
	var names := {"price_mult": "prices", "purse_mult": "purses", "tension": "crowds", "job_chance": "mercenary work", "job_pay": "mercenary pay"}
	var by_src := {}
	var out: Array = []
	for e in effects:
		var left := int(e["until"]) - week_index()
		if left < 0 or not names.has(str(e["kind"])) or absf(float(e["value"]) - 1.0) < 0.005:
			continue
		var src := str(e.get("src", ""))
		if not by_src.has(src):
			by_src[src] = {"src": src, "parts": [], "weeks": left}
			out.append(by_src[src])
		var row: Dictionary = by_src[src]
		(row["parts"] as Array).append("%s %+d%%" % [names[str(e["kind"])], int(round((float(e["value"]) - 1.0) * 100.0))])
		row["weeks"] = maxi(int(row["weeks"]), left)
	for row in out:
		row["text"] = ", ".join(row["parts"])
	return out


func _apply_effects(fx: Dictionary, src := "") -> void:
	var weeks := int(fx.get("weeks", 52))
	var until := week_index() + weeks
	for kind in ["price_mult", "purse_mult", "tension"]:
		if fx.has(kind):
			effects.append({"kind": kind, "value": float(fx[kind]), "until": until, "src": src})
	if fx.has("jobs"):
		# a war off-world: more agents on Solaris looking for 'Mechs, and better money
		effects.append({"kind": "job_chance", "value": float(fx["jobs"][0]), "until": until, "src": src})
		effects.append({"kind": "job_pay", "value": float(fx["jobs"][1]), "until": until, "src": src})
	if fx.get("clan_salvage", false):
		effects.append({"kind": "clan_salvage", "value": 1.0, "until": week_index() + 52 * 50, "src": src})
	if fx.has("free_agent_boost"):
		for k in int(fx["free_agent_boost"]):
			_gen_free_agent(rng.randf_range(0.4, 1.0))
	if fx.has("draft"):
		var d: Dictionary = fx["draft"]
		for wid in warriors:
			var w: Warrior = warriors[wid]
			if w.stable_id >= 0 and w.culture in d["houses"] and not w.dead and rng.chance(float(d["chance"])):
				w.drafted_weeks = int(d.get("weeks", 26))
				if w.stable_id == player_id:
					add_news("draft", "Recalled to the front", "%s is called up by their House military for %d weeks." % [w.full_name(), w.drafted_weeks], true)


# ================================================================== mercenary work: hiring the stable's fighters out

const JOB_HOUSES := {"LA": "Lyran Commonwealth", "FS": "Federated Suns", "DC": "Draconis Combine",
	"CC": "Capellan Confederation", "FWL": "Free Worlds League"}


func merc_job(jid: int) -> Dictionary:
	for j in merc_jobs:
		if int(j["id"]) == jid:
			return j
	return {}


## A House agent or a mercenary broker on Solaris looks for a few 'Mechs for a short job off-world.
## The stable's fighters and their 'Mechs are gone for the weeks it takes and come back as the battle left them.
func generate_merc_jobs() -> void:
	merc_jobs = []
	var H: Dictionary = rules.get("hire_out", {})
	if H.is_empty() or not deployment.is_empty() or not flag("merc_work"):
		return
	var r := SimRng.new(seed_value * 31 + week_index() * 977 + 5)
	var sm := StarMap.get_map()
	var kinds: Dictionary = H["jobs"]
	var kk: Array = kinds.keys()
	for n in int(H["max_jobs"]):
		if not r.chance(minf(0.95, float(H["chance_week"]) * effect_mult("job_chance"))):
			continue
		var kind: String = kk[r.randi_range(0, kk.size() - 1)]
		var info: Dictionary = kinds[kind]
		var hk: Array = JOB_HOUSES.keys()
		var emp: String = hk[r.randi_range(0, hk.size() - 1)]
		var enemy := "PIR"
		if not info.get("pirates", false):
			enemy = hk[(hk.find(emp) + r.randi_range(1, hk.size() - 1)) % hk.size()]
		var worlds := sm.faction_systems(emp, float(year))
		var world := "a border world"
		var biome := "bf_plains"
		if not worlds.is_empty():
			var wi := int(worlds[r.randi_range(0, worlds.size() - 1)])
			world = sm.name_of(wi)
			var bio: Dictionary = sm.sys(wi).get("biomes", {"plains": 1.0})
			var bk: Array = bio.keys()
			var bw: Array = []
			for b in bk:
				bw.append(float(bio[b]))
			biome = "bf_" + str(bk[r.weighted_index(bw)])
		var wk: Array = H["weeks"]
		var sl: Array = H["slots"]
		merc_jobs.append({"id": new_id(), "kind": kind, "label": str(info["label"]), "desc": str(info["desc"]),
			"employer": emp, "employer_name": sm.faction_name(emp, float(year)), "enemy": enemy,
			"enemy_name": "pirates" if enemy == "PIR" else sm.faction_name(enemy, float(year)), "world": world, "biome": biome,
			"weeks": r.randi_range(int(wk[0]), int(wk[1])), "slots": r.randi_range(int(sl[0]), int(sl[1])),
			"rate": int(round(float(H["fee_per_bv_week"]) * float(info["pay"]) * r.randf_range(0.9, 1.15) * effect_mult("job_pay"))),
			"danger": snappedf(float(info["enemy_bv"]) * r.randf_range(0.9, 1.1), 0.01),
			"skill": [4, 5] if r.chance(0.7) else [3, 4], "seed": r.randi_range(1, 1 << 30)})


## Warriors of yours who could go on a job of this length: fit, with a ready 'Mech, not booked, under contract long enough.
func job_candidates(job: Dictionary) -> Array:
	var out: Array = []
	for wid in player().warriors:
		var w: Warrior = warriors[wid]
		if _fight_ready(w) and not _booked(wid) and w.contract_weeks > int(job.get("weeks", 0)):
			out.append(int(wid))
	return out


## What a job pays for the fighters picked: {"bv", "fee", "advance", "bonus"}.
func job_pay(job: Dictionary, wids: Array) -> Dictionary:
	var H: Dictionary = rules["hire_out"]
	var bv := 0
	for wid in wids:
		var om := warrior_mech(warriors[int(wid)])
		if om != null:
			bv += int(_bv(om) * (1.0 - 0.6 * om.damage_fraction()))
	var fee := int(round(bv * int(job["rate"]) * int(job["weeks"]) / 1000.0)) * 1000
	return {"bv": bv, "fee": fee, "advance": int(fee * float(H["advance"])), "bonus": int(fee * float(H["victory_bonus"]))}


func hire_out(jid: int, wids: Array) -> String:
	var job := merc_job(jid)
	if job.is_empty():
		return "That job is gone"
	if not deployment.is_empty():
		return "You already have fighters off-world"
	if wids.is_empty():
		return "Pick at least one MechWarrior"
	if wids.size() > int(job["slots"]):
		return "The employer only wants %d 'Mechs" % int(job["slots"])
	var ok := job_candidates(job)
	var entries: Array = []
	for wid in wids:
		if not (int(wid) in ok):
			return "%s can't go" % (warriors[int(wid)].short_name() if warriors.has(int(wid)) else "That MechWarrior")
		entries.append({"warrior": int(wid), "mech": int(warriors[int(wid)].mech_uid)})
	var pay := job_pay(job, wids)
	for e in entries:
		warriors[e["warrior"]].away_weeks = int(job["weeks"])
		mechs[e["mech"]].status = "away"
	player().add_ledger("Mercenary work", int(pay["advance"]))
	deployment = {"job": job.duplicate(true), "entries": entries, "weeks_left": int(job["weeks"]), "fee": int(pay["fee"]),
		"paid": int(pay["advance"]), "bonus": int(pay["bonus"])}
	merc_jobs.erase(job)
	var names: Array = []
	for e in entries:
		names.append(warriors[e["warrior"]].short_name())
	add_news("contract", "Off to %s" % job["world"], "%s ship%s out for the %s: %s, %d weeks. %s paid in advance." % [
		_and_list(names), "s" if names.size() == 1 else "", job["employer_name"], str(job["label"]).to_lower(), int(job["weeks"]), money(int(pay["advance"]))], true)
	return ""


static func _bv(om: OwnedMech) -> int:
	return int(Construction.analyze(om.design).get("bv", 0))


static func _and_list(a: Array) -> String:
	if a.size() <= 1:
		return str(a[0]) if a.size() == 1 else ""
	return ", ".join(a.slice(0, a.size() - 1)) + " and " + str(a[-1])


## The battle the job comes down to: the stable's 'Mechs against a force the enemy can field, on an open battlefield.
func make_job_battle(dep: Dictionary, record := false) -> CombatSim:
	var job: Dictionary = dep["job"]
	var br := SimRng.new(int(job["seed"]))
	var skill: Array = job["skill"]
	var bv := 0
	var pm := 0.0
	var mine: Array = []
	for e in dep["entries"]:
		var w: Warrior = warriors.get(int(e["warrior"]))
		var om: OwnedMech = mechs.get(int(e["mech"]))
		if w == null or om == null or w.dead:
			continue
		mine.append([w, om])
		bv += int(_bv(om) * (1.0 - 0.6 * om.damage_fraction()))
		pm += MercCampaign.skill_mult(w.gunnery + w.piloting)
	if mine.is_empty():
		return null
	pm /= mine.size()
	var em := MercCampaign.skill_mult(int(skill[0]) + int(skill[1]) + 1)
	var ebv := int(bv * pm / em * float(job["danger"]))
	var enemy_ids := ForceGen.force(str(job["enemy"]), year, ebv, br, {"max_units": 8})
	var edges := ["W", "E"] if br.chance(0.5) else ["E", "W"]
	var arena := BattlefieldGenerator.generate(str(job["biome"]), int(job["seed"]),
		{"player_edge": edges[0], "enemy_edge": edges[1], "player_n": mine.size(), "ally_n": 0, "enemy_n": enemy_ids.size(), "scenario": "standup"})
	var sides := [[], []]
	var k := 0
	for pair in mine:
		var w2: Warrior = pair[0]
		var om2: OwnedMech = pair[1]
		sides[0].append({"design": om2.design, "warrior": w2.sim_dict(), "orders": {}, "condition": om2.sim_condition(),
			"controller": "ai", "bv": _bv(om2), "spawn": arena.spawns[0][k % arena.spawns[0].size()]})
		k += 1
	for id in enemy_ids:
		var g := br.randi_range(int(skill[0]), int(skill[1]))
		sides[1].append({"design": MercCampaign.db_design(str(id)), "warrior": {"callsign": "Hostile", "name": "Hostile", "gunnery": g, "piloting": g + 1, "traits": []},
			"orders": {}, "controller": "ai", "bv": ForceGen.bv_of(str(id))})
	var bout := {"merc": true, "time_limit": 900.0, "conditions": {"light": "day", "weather": "clear", "floodlights": false}, "auto_withdraw": true}
	return CombatSim.create(arena, sides, int(job["seed"]) + 17, bout, record)


## One week passes for the fighters off-world; when the last one is up they fight the battle and come home.
func _deployment_week() -> void:
	if deployment.is_empty():
		return
	deployment["weeks_left"] = int(deployment["weeks_left"]) - 1
	for e in deployment["entries"]:
		var w: Warrior = warriors.get(int(e["warrior"]))
		if w != null:
			w.away_weeks = maxi(0, int(deployment["weeks_left"]))
	if int(deployment["weeks_left"]) > 0:
		return
	_resolve_deployment()


func _resolve_deployment() -> void:
	var dep := deployment
	deployment = {}
	var job: Dictionary = dep["job"]
	var H: Dictionary = rules["hire_out"]
	var p := player()
	var sim := make_job_battle(dep)
	var lines: Array = []
	var won := false
	var lost := false
	var how := ""
	if sim != null:
		sim.run_to_end(sim.time_limit() + 60.0)
		var res := sim.result
		how = str(res["how"])
		var held := MercCampaign.field_held(res)
		var ms: Array = res["mechs"]
		var n := 0
		var standing := 0
		var foes_left := 0
		for r in ms:
			if int(r["team"]) == 0:
				n += 1
				if not r["out"]:
					standing += 1
			elif not r["out"]:
				foes_left += 1
		won = held
		lost = standing == 0 and foes_left > 0
		var i := 0
		for e in dep["entries"]:
			var w: Warrior = warriors.get(int(e["warrior"]))
			var om: OwnedMech = mechs.get(int(e["mech"]))
			if w == null or om == null or w.dead:
				continue
			var r2: Dictionary = ms[i]
			i += 1
			lines.append(_after_job(w, om, r2, won, lost, held, job))
	for e in dep["entries"]:
		var w3: Warrior = warriors.get(int(e["warrior"]))
		if w3 != null:
			w3.away_weeks = 0
		var om3: OwnedMech = mechs.get(int(e["mech"]))
		if om3 != null and om3.status == "away":
			om3.status = "ready"
	var rest := int(dep["fee"]) - int(dep["paid"])
	var pay := rest
	if won:
		pay += int(dep["bonus"])
		p.fame += float(H["fame_victory"])
	elif lost:
		pay = int(rest * float(H["defeat_share"]))
	p.add_ledger("Mercenary work", pay)
	var head := "VICTORY" if won else ("DEFEAT" if lost else "DRAW")
	last_deployment = {"world": job["world"], "label": job["label"], "employer": job["employer_name"], "enemy": job["enemy_name"],
		"outcome": head, "how": how, "pay": pay + int(dep["paid"]), "lines": lines, "y": year, "w": week}
	add_news("contract", "Back from %s: %s" % [job["world"], head.to_lower()],
		"%s for the %s against %s. %s The contract paid %s in all." % [job["label"], job["employer_name"], job["enemy_name"], " ".join(lines), money(pay + int(dep["paid"]))], true)


## One fighter home from a job: the 'Mech as the battle left it, wounds, experience. A 'Mech that went down on a
## field the enemy kept is gone for good.
func _after_job(w: Warrior, om: OwnedMech, r: Dictionary, won: bool, lost: bool, held: bool, job: Dictionary) -> String:
	var st := player()
	var kills := int(r["kills"])
	w.kills += kills
	om.kills += kills
	om.fights += 1
	w.xp += int(rules["xp_per_fight"]) * 2 + (int(rules["xp_win_bonus"]) if won else 0) + mini(kills, 2)
	w.morale = clampf(w.morale + (float(rules["morale_win"]) if won else float(rules["morale_loss"]) if lost else 0.0), 0, 100)
	w.fatigue = minf(100.0, w.fatigue + float(rules["fatigue_per_fight"]))
	w.history.append({"y": year, "w": week, "vs": -1, "res": "W" if won else ("L" if lost else "D"), "how": str(r["reason"]) if r["out"] else "held the field",
		"arena": job["world"], "kind": "contract"})
	while w.history.size() > 30:
		w.history.pop_front()
	var hits := int(r["pilot_hits"])
	var reason := str(r["reason"])
	var line := ""
	var left_behind: bool = not held and not r["withdrew"] and (r["destroyed"] or r["crew_killed"] or r["ejected"] or reason == "crippled")
	om.condition = {"armor": r["armor"], "internal": r["internal"], "hit_slots": r["hit_slots"], "ammo": r["ammo"]}
	if left_behind:
		line = "%s's %s was left on the field and is lost." % [w.short_name(), om.design.display_name()]
		st.mechs.erase(om.uid)
		mechs.erase(om.uid)
		w.mech_uid = -1
	elif r["destroyed"]:
		om.status = "wrecked"
		line = "%s's %s comes home a wreck." % [w.short_name(), om.design.display_name()]
	else:
		om.status = "ready"
		var pristine := (r["hit_slots"] as Array).is_empty()
		for key in om.design.armor:
			if int(r["armor"].get(key, 0)) < int(om.design.armor[key]):
				pristine = false
		if pristine:
			om.condition = {}
			line = "%s's %s is untouched." % [w.short_name(), om.design.display_name()]
		else:
			line = "%s's %s is %d%% damaged." % [w.short_name(), om.design.display_name(), int(om.damage_fraction() * 100)]
	if kills > 0:
		line += " %d kill%s." % [kills, "" if kills == 1 else "s"]
	if hits >= 6 or r["crew_killed"] or reason.find("MechWarrior killed") >= 0 or reason.find("head destroyed") >= 0:
		w.dead = true
		line += " %s was killed in action." % w.full_name()
	elif hits > 0:
		w.injury_weeks = maxi(w.injury_weeks, int(hits * int(rules["injury_weeks_per_hit"]) * opt("injuries")) - st.medic)
		if w.injury_weeks > 0:
			line += " %s is wounded: %d week%s." % [w.short_name(), w.injury_weeks, "" if w.injury_weeks == 1 else "s"]
	return line


func add_news(kind: String, title: String, text: String, mine := false) -> void:
	news.append({"y": year, "w": week, "kind": kind, "title": title, "text": text, "mine": mine})
	while news.size() > 300:
		news.pop_front()


static func money(v: int) -> String:
	var neg := v < 0
	var s := str(absi(v))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if neg else "") + s + out + " C"


# ================================================================== save / load

func to_dict() -> Dictionary:
	var ss: Array = []
	for s in stables:
		ss.append(s.to_dict())
	var ws := {}
	for wid in warriors:
		ws[str(wid)] = warriors[wid].to_dict()
	var mm := {}
	for uid in mechs:
		mm[str(uid)] = mechs[uid].to_dict()
	return {"version": 1, "year": year, "week": week, "seed": seed_value, "rng": str(rng.get_state()), "stables": ss,
		"warriors": ws, "mechs": mm, "next_id": next_id, "player_id": player_id, "market": market, "offers": offers,
		"bookings": bookings, "ai_card": ai_card, "results": results, "news": news, "champions": champions,
		"effects": effects, "fired_events": fired_events, "championship": championship, "phase": phase,
		"merc_jobs": merc_jobs, "deployment": deployment, "last_deployment": last_deployment, "settings": settings}


static func from_dict(d: Dictionary) -> Campaign:
	var c := Campaign.new()
	c.year = int(d["year"])
	c.week = int(d["week"])
	c.seed_value = int(d["seed"])
	c.rng = SimRng.new(c.seed_value)
	c.rng.set_state(int(str(d["rng"])))
	for sd in d["stables"]:
		c.stables.append(Stable.from_dict(sd))
	for k in d["warriors"]:
		c.warriors[int(k)] = Warrior.from_dict(d["warriors"][k])
	for k in d["mechs"]:
		c.mechs[int(k)] = OwnedMech.from_dict(d["mechs"][k])
	c.next_id = int(d["next_id"])
	c.player_id = int(d.get("player_id", 0))
	c.market = _fix_ints(d["market"])
	c.offers = _fix_ints(d["offers"])
	c.bookings = _fix_ints(d["bookings"])
	c.ai_card = _fix_ints(d["ai_card"])
	c.results = _fix_ints(d["results"])
	c.news = d["news"]
	c.champions = {}
	for k in d["champions"]:
		c.champions[k] = int(d["champions"][k])
	c.effects = d["effects"]
	c.fired_events = d["fired_events"]
	c.championship = _fix_ints(d["championship"])
	c.phase = str(d.get("phase", "booking"))
	c.merc_jobs = _fix_ints(d.get("merc_jobs", []))
	c.deployment = _fix_ints(d.get("deployment", {}))
	c.settings = d.get("settings", {})
	c.last_deployment = d.get("last_deployment", {})
	# market part keys and agent ids
	var agents: Array = []
	for a in c.market.get("agents", []):
		agents.append(int(a))
	c.market["agents"] = agents
	return c


## JSON turns every number into a float; bout and market ids need to be ints again.
static func _fix_ints(v: Variant) -> Variant:
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _fix_ints(v[k])
		return out
	if v is Array:
		var a: Array = []
		for x in v:
			a.append(_fix_ints(x))
		return a
	if v is float and is_equal_approx(v, round(v)) and absf(v) < 9.0e15:
		return int(v)
	return v


func save_to(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict()))
	return true


static func load_from(path: String) -> Campaign:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var d = JSON.parse_string(f.get_as_text())
	if d == null:
		return null
	return from_dict(d)
