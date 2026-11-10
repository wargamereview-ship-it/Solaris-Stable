class_name StarMap
extends RefCounted
## The Inner Sphere and Periphery from MegaMek Data: 3,186 systems with owners by date, jump routes,
## travel times, faction relations (wars, alliances) and border worlds. StarMap.get_map() loads once.

static var _inst: StarMap

var systems: Array = []
var by_id: Dictionary = {}
var factions: Dictionary = {}
var relations: Dictionary = {}
var rules: Dictionary = {}
var _border_cache: Dictionary = {}   # "year" -> {faction: [system index]}
var _owner_cache: Dictionary = {}    # "year" -> PackedStringArray of owners
var _route_cache: Dictionary = {}
var year_hint := 3025.0              # the campaign's date, for names that change over time


static func get_map() -> StarMap:
	if _inst == null:
		_inst = StarMap.new()
		_inst._load()
	return _inst


func _load() -> void:
	var m := GameData.db().merc()
	systems = m["systems"]
	factions = m["factions"]
	relations = m["relations"]
	rules = m["rules"]
	for i in systems.size():
		by_id[str(systems[i]["id"])] = i


func index_of(id: String) -> int:
	return int(by_id.get(id, -1))


func sys(i: int) -> Dictionary:
	return systems[i]


func name_of(i: int) -> String:
	return str(systems[i]["name"]) if i >= 0 and i < systems.size() else "?"


## The planet portrait that fits a world: assets/planets/<kind>_<0..2>.png (tools/blender/render_planets.py).
func planet_image(i: int) -> String:
	var pl: Dictionary = systems[i].get("planet", {})
	var atmo := str(pl.get("atmo", "")) if pl.get("atmo") != null else ""
	var t := float(pl["temp"]) if pl.get("temp") != null else 25.0
	var w := float(pl["water"]) if pl.get("water") != null else 40.0
	var life := str(pl.get("life", "")) if pl.get("life") != null else ""
	var kind := "steppe"
	if atmo == "NONE" or (life == "NONE" and w < 20.0):
		kind = "barren"
	elif t >= 90.0:
		kind = "volcanic"
	elif atmo.begins_with("TOXIC") or atmo == "TAINTED_CAUSTIC":
		kind = "toxic"
	elif atmo.begins_with("TAINTED"):
		kind = "tainted"
	elif t < 5.0:
		kind = "ice"
	elif w < 15.0 or t >= 48.0:
		kind = "desert"
	elif w >= 75.0:
		kind = "ocean"
	elif w >= 45.0:
		kind = "jungle" if t >= 36.0 else "terran"
	elif t >= 28.0:
		kind = "arid"
	return "res://assets/planets/%s_%d.png" % [kind, absi(hash(name_of(i))) % 3]


func pos(i: int) -> Vector2:
	var s: Dictionary = systems[i]
	return Vector2(float(s["x"]), float(s["y"]))


static func _at(seq: Array, year: float) -> Variant:
	var v: Variant = null
	for e in seq:
		if float(e[0]) <= year + 0.0001:
			v = e[1]
		else:
			break
	return v


## Owner faction key of a system at a (fractional) year: "FS", "LA", "IND", "ABN", "UND"...
func owner(i: int, year: float) -> String:
	var key := str(int(year * 4))
	if not _owner_cache.has(key):
		var arr := PackedStringArray()
		arr.resize(systems.size())
		var yq := floorf(year * 4.0) / 4.0
		for k in systems.size():
			var v: Variant = _at(systems[k]["owners"], yq)
			arr[k] = str(v) if v != null else "UND"
		_owner_cache[key] = arr
		if _owner_cache.size() > 12:
			_owner_cache.erase(_owner_cache.keys()[0])
	return (_owner_cache[key] as PackedStringArray)[i]


## Hiring hall level at a year: "GREAT", "STANDARD", "MINOR", "QUESTIONABLE" or "".
func hall(i: int, year: float) -> String:
	var v: Variant = _at(systems[i].get("halls", []), year)
	if v == null or str(v) == "NONE":
		return ""
	return str(v)


## Socio-industrial code "T-I-R-O-A" (tech, industry, raw materials, output, agriculture), A best.
func socio(i: int, year: float) -> String:
	var v: Variant = _at(systems[i].get("socio", []), year)
	return str(v) if v != null else "C-C-C-C-C"


func industrial(i: int, year: float) -> bool:
	var s := socio(i, year)
	return s.length() >= 3 and (s[0] in ["A", "B"] or s[2] in ["A", "B"])


func population(i: int, year: float) -> int:
	var p: Array = systems[i].get("pop", [0, 0])
	return int(p[0]) if year < 3046 else int(p[1])


func faction_name(key: String, year := -1.0) -> String:
	var f: Dictionary = factions.get(key, {})
	var y := year_hint if year < 0.0 else year
	var nm := str(f.get("name", key))
	for e in f.get("names", []):
		if float(e[0]) <= y:
			nm = str(e[1])
	return nm


func faction_color(key: String) -> Color:
	var c: Array = factions.get(key, {}).get("color", [128, 128, 128])
	return Color(float(c[0]) / 255.0, float(c[1]) / 255.0, float(c[2]) / 255.0)


func faction_tags(key: String) -> Array:
	return factions.get(key, {}).get("tags", [])


func is_real_faction(key: String) -> bool:
	return not (key in ["UND", "ABN", "NONE", ""])


func faction_active(key: String, year: float) -> bool:
	var f: Dictionary = factions.get(key, {})
	if f.is_empty():
		return false
	if f.get("start") != null and int(f["start"]) > year:
		return false
	if f.get("end") != null and int(f["end"]) < year:
		return false
	return true


## Kind of employer for pay and force mix: "MAJOR", "PERIPHERY", "MINOR", "PIRATE", "CLAN", "MERC".
func faction_kind(key: String) -> String:
	var tags := faction_tags(key)
	if "PIRATE" in tags:
		return "PIRATE"
	if "CLAN" in tags:
		return "CLAN"
	if "MERC" in tags:
		return "MERC"
	if "MAJOR" in tags and "IS" in tags:
		return "MAJOR"
	if "PERIPHERY" in tags:
		return "PERIPHERY"
	return "MINOR"


func _pair_listed(list: Array, a: String, b: String, year: float) -> bool:
	for e in list:
		var ps: Array = e["parties"]
		if not (a in ps and b in ps):
			continue
		if a == b and ps.count(a) < 2:
			continue
		if e.get("start") != null and float(e["start"]) > year:
			continue
		if e.get("end") != null and float(e["end"]) < year:
			continue
		return true
	return false


func at_war(a: String, b: String, year: float) -> bool:
	return _pair_listed(relations.get("wars", []), a, b, year)


func allied(a: String, b: String, year: float) -> bool:
	return _pair_listed(relations.get("alliances", []), a, b, year)


## ComStar and a few others never fight anyone not on their exception list.
func neutral(a: String, b: String, year: float) -> bool:
	for side in [[a, b], [b, a]]:
		var ex: Variant = relations.get("neutral", {}).get(side[0])
		if ex == null:
			continue
		for e in ex:
			if side[1] in e["factions"]:
				if (e.get("start") == null or float(e["start"]) <= year) and (e.get("end") == null or float(e["end"]) >= year):
					return false
		return true
	return false


## How likely a and b fight: 0 never, 1 border skirmishes, 2 at war.
func hostility(a: String, b: String, year: float) -> int:
	if a == b or not is_real_faction(a) or not is_real_faction(b):
		return 0
	if neutral(a, b, year) or allied(a, b, year):
		return 0
	if faction_kind(a) == "MERC" or faction_kind(b) == "MERC":
		return 0
	return 2 if at_war(a, b, year) else 1


## Systems of each faction that border another faction within one jump.
## Returns {faction: {other_faction: [system index]}} for the year (cached).
func borders(year: float) -> Dictionary:
	var key := str(int(year))
	if _border_cache.has(key):
		return _border_cache[key]
	var out := {}
	for i in systems.size():
		var o := owner(i, year)
		if not is_real_faction(o):
			continue
		for nb in systems[i]["nb"]:
			var j := int(nb[0])
			var o2 := owner(j, year)
			if o2 == o or not is_real_faction(o2):
				continue
			if not out.has(o):
				out[o] = {}
			var d: Dictionary = out[o]
			if not d.has(o2):
				d[o2] = []
			var lst: Array = d[o2]
			if lst.is_empty() or int(lst[-1]) != i:
				lst.append(i)
	_border_cache[key] = out
	if _border_cache.size() > 3:
		_border_cache.erase(_border_cache.keys()[0])
	return out


func faction_systems(f: String, year: float) -> Array:
	var out: Array = []
	for i in systems.size():
		if owner(i, year) == f:
			out.append(i)
	return out


## Jump route from a to b (system indices, both included), fewest jumps first. Empty if unreachable.
## A* over the one-jump neighbour graph with a binary heap.
func route(a: int, b: int) -> Array:
	if a == b:
		return [a]
	if a < 0 or b < 0:
		return []
	var key := "%d>%d" % [a, b]
	if _route_cache.has(key):
		return (_route_cache[key] as Array).duplicate()
	var g := {a: 0.0}
	var came := {}
	var closed := {}
	var goal := pos(b)
	var heap_f := PackedFloat32Array([pos(a).distance_to(goal) / 30.0])
	var heap_i := PackedInt32Array([a])
	var out: Array = []
	while heap_i.size() > 0:
		var cur := heap_i[0]
		_heap_pop(heap_f, heap_i)
		if closed.has(cur):
			continue
		closed[cur] = true
		if cur == b:
			out = [b]
			while came.has(out[0]):
				out.push_front(came[out[0]])
			break
		for nb in systems[cur]["nb"]:
			var j := int(nb[0])
			if closed.has(j):
				continue
			var ng := float(g[cur]) + 1.0 + float(nb[1]) / 300.0
			if ng < float(g.get(j, INF)):
				g[j] = ng
				came[j] = cur
				_heap_push(heap_f, heap_i, ng + pos(j).distance_to(goal) / 30.0, j)
	_route_cache[key] = out.duplicate()
	if _route_cache.size() > 400:
		_route_cache.clear()
	return out


static func _heap_push(hf: PackedFloat32Array, hi: PackedInt32Array, f: float, i: int) -> void:
	hf.append(f)
	hi.append(i)
	var k := hf.size() - 1
	while k > 0:
		var p := (k - 1) / 2
		if hf[p] <= hf[k]:
			break
		var tf := hf[p]
		hf[p] = hf[k]
		hf[k] = tf
		var ti := hi[p]
		hi[p] = hi[k]
		hi[k] = ti
		k = p


static func _heap_pop(hf: PackedFloat32Array, hi: PackedInt32Array) -> void:
	var last := hf.size() - 1
	hf[0] = hf[last]
	hi[0] = hi[last]
	hf.resize(last)
	hi.resize(last)
	var k := 0
	var n := last
	while true:
		var l := 2 * k + 1
		var r := l + 1
		var m := k
		if l < n and hf[l] < hf[m]:
			m = l
		if r < n and hf[r] < hf[m]:
			m = r
		if m == k:
			break
		var tf := hf[m]
		hf[m] = hf[k]
		hf[k] = tf
		var ti := hi[m]
		hi[m] = hi[k]
		hi[k] = ti
		k = m


## Days between a planet and its jump point, from the star's spectral class.
func transit_days(i: int) -> int:
	var st := str(systems[i].get("star", "G"))
	var c := st.substr(0, 1).to_upper()
	var tbl: Dictionary = rules["calendar"]["transit_days_by_class"]
	return int(tbl.get(c, 7))


## Total travel days along a route: planet to jump point, one recharge per jump, jump point to planet.
func trip_days(r: Array) -> int:
	if r.size() <= 1:
		return 0
	var jumps := r.size() - 1
	return transit_days(int(r[0])) + int(rules["calendar"]["jump_recharge_days"]) * jumps + transit_days(int(r[-1]))


func jumps_between(a: int, b: int) -> int:
	var r := route(a, b)
	return maxi(0, r.size() - 1) if not r.is_empty() else 999


## Systems within n jumps of i (breadth first).
func within_jumps(i: int, n: int) -> Array:
	var seen := {i: 0}
	var q: Array = [i]
	while not q.is_empty():
		var cur: int = q.pop_front()
		var d: int = seen[cur]
		if d >= n:
			continue
		for nb in systems[cur]["nb"]:
			var j := int(nb[0])
			if not seen.has(j):
				seen[j] = d + 1
				q.append(j)
	return seen.keys()
