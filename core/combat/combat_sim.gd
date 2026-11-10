class_name CombatSim
extends RefCounted
## Real-time arena fight. Fixed 20 Hz tick, one seeded RNG, BattleMech Manual rules converted to real time:
## 1 turn = 10 s, 1 hex = 30 m, 1 MP = 3 m/s, each weapon recycles every 10 s.
## Deterministic: the same arena, sides, orders, seed and corner calls (by tick) always give the same fight.
## Any number of teams: duels, tag teams, lances and free-for-all melees.
## Merc battles (bout "merc"): 'Mechs and combat vehicles, player commands (move, attack, hold,
## withdraw) recorded by tick, map-edge exits, reinforcements, spotting and forced withdrawal.

const DT := 0.05
const TURN := 10.0
const HEX := 30.0
const MPS := 3.0
const SNAP_EVERY := 2
const STRIDE := 29
const ARMOR_KEYS := ["HD", "CT", "LT", "RT", "LA", "RA", "LL", "RL", "CTR", "LTR", "RTR"]
const TRANSFER := {"LA": "LT", "RA": "RT", "LL": "LT", "RL": "RT", "LT": "CT", "RT": "CT", "CT": "", "HD": ""}
const P_HIT := [1.0, 1.0, 1.0, 35.0 / 36, 33.0 / 36, 30.0 / 36, 26.0 / 36, 21.0 / 36, 15.0 / 36, 10.0 / 36, 6.0 / 36, 3.0 / 36, 1.0 / 36]
const MISSILE_TYPES := ["lrm", "srm", "mrm", "atm", "mml", "elrm", "xlrm", "rl", "tbolt", "streak_srm", "streak_lrm",
	"lrt", "srt", "mortar"]
const ENERGY_TYPES := ["laser", "pulse", "ppc", "flamer", "plasma", "tsemp", "taser"]
const AREA_TYPES := ["artillery", "artcannon"]
## The kind of damage being applied right now ("energy", "ballistic", "missile", "physical", "fall",
## "area", "other"): the newer armor types answer each differently.
var _dclass := "other"
const CALLS := {
	"press": "Press the attack",
	"back_off": "Back off",
	"flank": "Flank",
	"cool": "Cool down",
	"focus": "Focus target",
	"yield": "Yield",
}

var arena: Arena
var mechs: Array = []
var rng: SimRng
var t := 0.0
var ticks := 0
var next_turn := TURN
var events: Array = []
var frames: Array = []
var record := true
var bout: Dictionary = {}
var conditions: Dictionary = {}
var finished := false
var result: Dictionary = {}
var ai: CombatAI
var tables: Dictionary
var inputs: Array = []
var _scheduled: Array = []
var _los_cache: Dictionary = {}
var _los_tick := -1
var _hz_was_active: Dictionary = {}
var team_count := 2
var merc := false
var initial_bv: Dictionary = {}     # team -> BV at the start
var unit_bv: Dictionary = {}        # index -> BV
var recon_done: Array = []
var _routed: Dictionary = {}
var support: Array = []            # per team: {"artillery": n, "air_strike": n, "auto", "next", "gap"}
var strikes: Array = []            # missions on the way: {"kind", "team", "pos", "ang", "at"}


## sides: Array (per team) of Array of {"design": MechDesign, "warrior": Dictionary, "orders": Dictionary, "condition": Dictionary}
## bout_: {"to_death", "time_limit", "conditions": {"light", "weather", "floodlights"}, "calls": n}
## scheduled_inputs: corner calls to replay, [{"tick", "m", "call", "arg"}]
static func create(arena_: Arena, sides: Array, seed_value: int, bout_ := {}, record_ := true, scheduled_inputs := []) -> CombatSim:
	var s := CombatSim.new()
	s.arena = arena_
	s.rng = SimRng.new(seed_value)
	s.bout = bout_
	s.record = record_
	s.tables = GameData.db().tables
	s.ai = CombatAI.new(s)
	s.team_count = sides.size()
	s.conditions = bout_.get("conditions", {})
	s._apply_conditions()
	var calls := int(bout_.get("calls", s.tables.get("corner_calls_per_fight", 3)))
	s.merc = bool(bout_.get("merc", false))
	var idx := 0
	for team in sides.size():
		var k := 0
		for e in sides[team]:
			var m := CombatMech.create_any(e["design"], e.get("warrior", {}), e.get("orders", {}), team, idx, e.get("condition", {}))
			var sp: Array = arena_.spawns[team]
			var start: Vector2 = e["spawn"] if e.has("spawn") else sp[k % sp.size()]
			if not arena_.passable_p(start, m.mover):
				start = arena_.center_of(arena_.nearest_passable(arena_.cell_of(start), m.mover))
			m.pos = start
			m.spawn_pos = start
			m.facing = arena_.spawn_facing[team]
			m.goal = m.pos
			m.trail = [[0.0, m.pos]]
			m.calls_left = calls
			m.controller = str(e.get("controller", "ai"))
			if float(e.get("arrive", 0.0)) > 0.0:
				m.reserve_t = float(e["arrive"])
				m.out = true
				m.out_reason = "reserve"
			if s.merc:
				var bv := int(e.get("bv", 0))
				if bv <= 0:
					bv = int(Construction.analyze(m.design).get("bv", 500))
				s.unit_bv[idx] = bv
				s.initial_bv[team] = int(s.initial_bv.get(team, 0)) + bv
			s.mechs.append(m)
			# stagger first shots so weapons don't all fire on the same tick
			for wi in m.weapons:
				m.mounts[wi]["cooldown"] = s.rng.randf_range(0.0, 2.5)
			idx += 1
			k += 1
	for _rp in arena_.objectives.get("recon_points", []):
		s.recon_done.append(false)
	var sup: Array = bout_.get("support", [])
	for team in sides.size():
		var sd: Dictionary = sup[team] if team < sup.size() else {}
		s.support.append({"artillery": int(sd.get("artillery", 0)), "air_strike": int(sd.get("air_strike", 0)),
			"auto": bool(sd.get("auto", false)), "next": float(sd.get("first", 45.0)), "gap": float(sd.get("gap", 60.0))})
	for inp in scheduled_inputs:
		s._scheduled.append(inp)
	s._scheduled.sort_custom(func(a, b): return int(a["tick"]) < int(b["tick"]))
	s.ai.init_all()
	s._snapshot()
	return s


func _apply_conditions() -> void:
	var w: String = conditions.get("weather", "clear")
	var wd: Dictionary = tables["conditions"]["weather"].get(w, {})
	arena.max_los_m = float(wd.get("max_los_m", INF))
	if w == "wind":
		var dirs := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
		arena.wind = dirs[rng.randi_range(0, 3)]


func time_limit() -> float:
	return float(bout.get("time_limit", tables["time_limit_seconds"]))


func run_to_end(max_seconds := 9999.0) -> Dictionary:
	while not finished and t < max_seconds:
		step()
	return result


func step() -> void:
	if finished:
		return
	arena.now = t
	if _los_tick != ticks:
		_los_cache.clear()
		_los_tick = ticks
	while not _scheduled.is_empty() and int(_scheduled[0]["tick"]) <= ticks:
		var inp: Dictionary = _scheduled.pop_front()
		if inp.has("cmd"):
			_do_command(inp)
		else:
			_do_call(int(inp["m"]), str(inp["call"]), int(inp.get("arg", -1)))
	if merc:
		_merc_tick()
	for m: CombatMech in mechs:
		if m.out:
			continue
		ai.think(m)
	for m: CombatMech in mechs:
		_move(m)
		if merc and not m.out:
			_check_exit(m)
		_heat_tick(m)
		for wi in m.weapons:
			m.mounts[wi]["cooldown"] = maxf(0.0, m.mounts[wi]["cooldown"] - DT)
	_hazards_tick()
	_support_tick()
	t += DT
	ticks += 1
	if ticks % 10 == 0:
		for m: CombatMech in mechs:
			if not m.out:
				m.trail.append([t, m.pos])
				while m.trail.size() > 22:
					m.trail.pop_front()
	if t >= next_turn - 0.0001:
		_turn_phase()
		next_turn += TURN
	if record and ticks % SNAP_EVERY == 0:
		_snapshot()
	_check_end()


# ------------------------------------------------------------------ corner calls

## A radio call from the stable owner during a live fight. Recorded by tick so a replay with the same
## inputs is identical. Returns false when the warrior has no calls left or can't act.
func issue_call(i: int, call: String, arg := -1) -> bool:
	if finished or i < 0 or i >= mechs.size():
		return false
	var m: CombatMech = mechs[i]
	if m.out or m.calls_left <= 0 or not CALLS.has(call):
		return false
	var inp := {"tick": ticks, "m": i, "call": call, "arg": arg}
	inputs.append(inp)
	_do_call(i, call, arg)
	return true


func _do_call(i: int, call: String, arg: int) -> void:
	var m: CombatMech = mechs[i]
	if m.out:
		return
	m.calls_left = maxi(0, m.calls_left - 1)
	if not inputs.has({"tick": ticks, "m": i, "call": call, "arg": arg}):
		inputs.append({"tick": ticks, "m": i, "call": call, "arg": arg})
	match call:
		"press":
			m.orders["range"] = "close"
			m.orders["heat"] = "hot"
			m.orders["position"] = "brawl"
		"back_off":
			m.orders["range"] = "long"
			m.orders["heat"] = "cool"
			m.orders["position"] = "cover"
		"flank":
			m.orders["position"] = "flank"
			if m.orders["range"] == "long":
				m.orders["range"] = "optimal"
		"cool":
			m.orders["heat"] = "cool"
		"focus":
			ai.force_target(m, arg)
		"yield":
			if not bout.get("to_death", false):
				m.yielded = true
				log_event({"k": "yield", "tg": m.index})
				set_out(m, "yielded")
			else:
				m.ejected = true
				log_event({"k": "eject", "tg": m.index})
				set_out(m, "ejected")
	ai.on_orders_changed(m)
	log_event({"k": "call", "m": i, "call": call, "arg": arg})


# ------------------------------------------------------------------ commands (merc battles)

const COMMANDS := {"move": "Move", "attack": "Attack", "hold": "Hold position", "free": "Fight freely",
	"withdraw": "Withdraw", "range": "Range", "heat": "Heat", "jump": "Jump jets", "shell": "Fire on the building"}


## An order from the player to some of their units. Recorded by tick so a replay is identical.
## move: arg [x, y] (meters; units spread into a line), attack: arg target index, hold, free, withdraw,
## range: "close"/"optimal"/"long", heat: "cool"/"balanced"/"hot", jump: "on"/"off".
func issue_command(units: Array, cmd: String, arg: Variant = null) -> bool:
	if finished or not COMMANDS.has(cmd):
		return false
	var ok: Array = []
	for i in units:
		var ii := int(i)
		if ii >= 0 and ii < mechs.size() and not mechs[ii].out and mechs[ii].controller == "player":
			ok.append(ii)
	if ok.is_empty():
		return false
	if cmd == "attack" and (arg == null or int(arg) < 0 or int(arg) >= mechs.size() or mechs[int(arg)].out):
		return false
	var a: Variant = arg
	if arg is Vector2:
		a = [snappedf((arg as Vector2).x, 0.1), snappedf((arg as Vector2).y, 0.1)]
	var inp := {"tick": ticks, "units": ok, "cmd": cmd, "arg": a}
	inputs.append(inp)
	_do_command(inp, false)
	return true


func _do_command(inp: Dictionary, from_replay := true) -> void:
	if from_replay and not inputs.has(inp):
		inputs.append(inp)
	var cmd := str(inp["cmd"])
	var arg: Variant = inp.get("arg")
	if cmd == "support":
		_call_support(int(arg[0]), str(arg[1]), Vector2(float(arg[2]), float(arg[3])), float(arg[4]))
		return
	var us: Array = []
	for i in inp["units"]:
		var m: CombatMech = mechs[int(i)]
		if not m.out:
			us.append(m)
	if us.is_empty():
		return
	match cmd:
		"move":
			var p := Vector2(float(arg[0]), float(arg[1]))
			var goals := formation(us, p)
			for k in us.size():
				ai.command(us[k], {"type": "move", "pos": goals[k]})
		"attack":
			for m: CombatMech in us:
				ai.command(m, {"type": "attack", "target": int(arg)})
				ai.force_target(m, int(arg))
		"hold":
			for m: CombatMech in us:
				ai.command(m, {"type": "hold", "pos": m.pos})
		"free":
			for m: CombatMech in us:
				ai.command(m, {"type": "free"})
		"withdraw":
			for m: CombatMech in us:
				ai.command(m, {"type": "withdraw", "edge": home_edge(m.team)})
		"shell":
			var cells := building_cells(int(arg))
			for m: CombatMech in us:
				ai.command(m, {"type": "attack_cell", "cells": cells})
		"range":
			for m: CombatMech in us:
				m.orders["range"] = str(arg)
				ai.on_orders_changed(m)
		"heat":
			for m: CombatMech in us:
				m.orders["heat"] = str(arg)
				ai.on_orders_changed(m)
		"jump":
			for m: CombatMech in us:
				m.orders["jump"] = str(arg)
	log_event({"k": "command", "units": inp["units"], "cmd": cmd, "arg": arg})


## The cells of the building that contains cell ci (flood fill over building cells, capped).
func building_cells(ci: int) -> Array:
	var out: Array = []
	if ci < 0 or ci >= arena.terrain.size() or arena.terrain[ci] != Arena.T.BUILDING:
		return out
	var seen := {ci: true}
	var q: Array = [ci]
	while not q.is_empty() and out.size() < 16:
		var i: int = q.pop_front()
		out.append(i)
		var x := i % arena.w
		var y := i / arena.w
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + o.x
			var ny: int = y + o.y
			if not arena.inside(nx, ny):
				continue
			var j := arena.idx(nx, ny)
			if not seen.has(j) and arena.terrain[j] == Arena.T.BUILDING and int(arena.bld_cf[j]) < 99999:
				seen[j] = true
				q.append(j)
	return out


## Spreads a group's destinations into a line across the direction of travel (two rows past four units),
## ordered so nobody crosses paths.
func formation(us: Array, p: Vector2) -> Array:
	var center := Vector2.ZERO
	for m: CombatMech in us:
		center += m.pos
	center /= float(us.size())
	var dir := (p - center).normalized() if p.distance_to(center) > 1.0 else Vector2.RIGHT
	var perp := dir.orthogonal()
	var order := range(us.size())
	order.sort_custom(func(a, b): return (us[a] as CombatMech).pos.dot(perp) < (us[b] as CombatMech).pos.dot(perp))
	var spacing := float(tables["merc_battle"]["formation_spacing_m"])
	var per_row := 4 if us.size() > 4 else us.size()
	var out: Array = []
	out.resize(us.size())
	for k in order.size():
		var row := k / per_row
		var col := k % per_row
		var n := mini(per_row, us.size() - row * per_row)
		var off := perp * (col - (n - 1) / 2.0) * spacing - dir * row * spacing
		var g := p + off
		var sz := arena.size_m()
		g = Vector2(clampf(g.x, 4.0, sz.x - 4.0), clampf(g.y, 4.0, sz.y - 4.0))
		var m: CombatMech = us[order[k]]
		if not arena.passable_p(g, m.mover):
			g = arena.center_of(arena.nearest_passable(arena.cell_of(g), m.mover))
		out[order[k]] = g
	return out


func home_edge(team: int) -> String:
	if team < arena.edges.size():
		return str(arena.edges[team])
	return "W" if team == 0 else "E"


## Edges a team may leave by: its own, plus the breakthrough edge for the player or the escape edge
## for a fleeing enemy.
func exit_edges(team: int) -> Array:
	var out: Array = [home_edge(team)]
	var ob := arena.objectives
	if team == 0 and str(ob.get("exit_edge", "")) != "":
		out.append(str(ob["exit_edge"]))
	if team != 0 and str(ob.get("enemy_exit_edge", "")) != "":
		out.append(str(ob["enemy_exit_edge"]))
	return out


func _check_exit(m: CombatMech) -> void:
	var c: Dictionary = ai.state[m.index].get("cmd", {})
	var ct := str(c.get("type", "free"))
	if ct != "move" and ct != "withdraw" and ct != "advance":
		return
	var margin := float(tables["merc_battle"]["exit_margin_m"])
	for e in exit_edges(m.team):
		if arena.edge_distance(m.pos, e) <= margin:
			if ct == "move" and arena.edge_distance(c["pos"], e) > margin + 12.0:
				continue
			if ct == "advance" and str(c.get("edge", "")) != str(e):
				continue
			exit_unit(m, e)
			return


func exit_unit(m: CombatMech, edge: String) -> void:
	m.exited = edge
	m.withdrew = true
	log_event({"k": "exit", "tg": m.index, "edge": edge})
	set_out(m, "withdrew")


## Merc battle housekeeping: reinforcements, spotting, recon points and enemy morale.
func _merc_tick() -> void:
	for m: CombatMech in mechs:
		if m.reserve_t >= 0.0 and t >= m.reserve_t and m.out_reason == "reserve":
			m.reserve_t = -1.0
			m.out = false
			m.out_reason = ""
			m.gait = CombatMech.Gait.STAND
			m.trail = [[t, m.pos]]
			log_event({"k": "arrive", "tg": m.index})
	if ticks % int(tables["merc_battle"]["spot_every_ticks"]) == 0:
		_spot()
	if ticks % 100 == 50:
		_morale_check()


func _spot() -> void:
	var rng_m := float(tables["merc_battle"]["spot_range_m"])
	var friends: Array = []
	for o: CombatMech in mechs:
		if o.team == 0 and not o.out:
			friends.append(o)
	for m: CombatMech in mechs:
		if m.team == 0:
			continue
		var seen := false
		if not m.out:
			for f: CombatMech in friends:
				var d := f.pos.distance_to(m.pos)
				if d < 90.0 or (d <= rng_m and los_between(f, m)["clear"]):
					seen = true
					break
		m.spotted = seen
		if seen:
			m.seen_pos = m.pos
			m.seen_t = t
	var pts: Array = arena.objectives.get("recon_points", [])
	for k in pts.size():
		if recon_done[k]:
			continue
		var rp: Vector2 = pts[k]
		for f: CombatMech in friends:
			if f.pos.distance_to(rp) <= float(arena.objectives.get("recon_radius_m", 130.0)):
				recon_done[k] = true
				log_event({"k": "recon", "m": f.index, "point": k})
				break


## Enemy sides break and withdraw once their losses pass the rout threshold.
func _morale_check() -> void:
	var left := {}
	for m: CombatMech in mechs:
		if not m.out or m.out_reason == "reserve":
			left[m.team] = int(left.get(m.team, 0)) + int(unit_bv.get(m.index, 0))
	for team in initial_bv:
		if int(team) == 0 or _routed.has(team):
			continue
		var frac := float(left.get(team, 0)) / maxf(1.0, float(initial_bv[team]))
		if frac < float(tables["merc_battle"]["rout_bv_fraction"]):
			_routed[team] = true
			log_event({"k": "rout", "team": team})
			for m: CombatMech in mechs:
				if m.team == team and not m.out:
					ai.command(m, {"type": "withdraw", "edge": home_edge(team)})


# ------------------------------------------------------------------ logging

func log_event(e: Dictionary) -> void:
	e["t"] = snappedf(t, 0.05)
	if record:
		events.append(e)


func mech_label(m: CombatMech) -> String:
	return m.name


# ------------------------------------------------------------------ geometry

static func wrap_angle(a: float) -> float:
	return wrapf(a, -PI, PI)


func angle_to(from: CombatMech, to: CombatMech) -> float:
	return (to.pos - from.pos).angle()


## Which side of `target` faces `attacker`: "front", "rear", "left", "right".
func attack_side(attacker: CombatMech, target: CombatMech) -> String:
	return side_from(attacker.pos, target)


func side_from(p: Vector2, target: CombatMech) -> String:
	var rel := wrap_angle((p - target.pos).angle() - target.facing)
	var deg := rad_to_deg(rel)
	if absf(deg) <= 60.0:
		return "front"
	if absf(deg) >= 120.0:
		return "rear"
	return "right" if deg > 0.0 else "left"


## Can the mount fire at the target given torso twist and arm arcs?
func in_arc(m: CombatMech, mt: Dictionary, target: CombatMech) -> bool:
	var loc: String = mt["loc"]
	if m.is_infantry:
		return true
	if m.is_vehicle:
		var vbase := m.facing + (m.twist if loc == "TU" else 0.0)
		var vrel := rad_to_deg(wrap_angle(angle_to(m, target) - vbase))
		match loc:
			"RR":
				return absf(vrel) >= 120.0
			"LS":
				return vrel <= -30.0 and vrel >= -150.0
			"RS":
				return vrel >= 30.0 and vrel <= 150.0
		return absf(vrel) <= 60.0
	var base := m.facing if loc in ["LL", "RL"] else m.facing + m.twist
	var rel := rad_to_deg(wrap_angle(angle_to(m, target) - base))
	if mt["rear"]:
		return absf(rel) >= 120.0
	match loc:
		"LA":
			return rel >= -120.0 and rel <= 60.0
		"RA":
			return rel >= -60.0 and rel <= 120.0
	return absf(rel) <= 60.0


func in_front_arc(m: CombatMech, target: CombatMech) -> bool:
	return absf(rad_to_deg(wrap_angle(angle_to(m, target) - m.facing))) <= 60.0


func los_between(a: CombatMech, b: CombatMech) -> Dictionary:
	var key := a.index * 64 + b.index
	if _los_cache.has(key):
		return _los_cache[key]
	var l: Dictionary
	if a.is_vehicle or b.is_vehicle:
		l = arena.los(a.pos, b.pos, a.eye_m(arena), b.eye_m(arena), b.airborne)
	else:
		l = arena.los(a.pos, b.pos)
	_los_cache[key] = l
	return l


func range_hexes(a: CombatMech, b: CombatMech) -> int:
	return maxi(1, int(ceil(a.pos.distance_to(b.pos) / HEX - 0.001)))


func hexes_moved(m: CombatMech) -> int:
	if m.trail.is_empty():
		return 0
	var dist := 0.0
	var prev: Vector2 = m.trail[0][1]
	for k in range(1, m.trail.size()):
		var p: Vector2 = m.trail[k][1]
		dist += prev.distance_to(p)
		prev = p
	dist += prev.distance_to(m.pos)
	return int(dist / HEX)


func target_movement_mod(target: CombatMech) -> int:
	var hexes := hexes_moved(target)
	var mod := 0
	for row in tables["target_movement"]:
		if hexes >= int(row[0]) and hexes <= int(row[1]):
			mod = int(row[2])
	if t - target.last_jump_t < TURN:
		mod += int(tables["target_mod"]["jumped"])
	if target.airborne:
		mod += int(tables["vehicle"]["vtol_tmm_bonus"])
	return mod


func attacker_movement_mod(m: CombatMech) -> int:
	var am: Dictionary = tables["attacker_movement"]
	if m.is_infantry:
		return 0
	if m.gait == CombatMech.Gait.PRONE:
		return int(am["prone"])
	if t - m.last_jump_t < 4.0:
		return 2 if m.has_trait("jump_jockey") else int(am["jump"])
	if t - m.last_run_t < 2.0:
		return int(am["run"])
	if t - m.last_walk_t < 2.0:
		return int(am["walk"])
	return 0


func teammates(m: CombatMech) -> Array:
	var out: Array = []
	for o: CombatMech in mechs:
		if o != m and o.team == m.team and not o.out:
			out.append(o)
	return out


func enemies(m: CombatMech) -> Array:
	var out: Array = []
	for o: CombatMech in mechs:
		if o.team != m.team and not o.out:
			out.append(o)
	return out


## True if `m` sits inside an enemy ECM bubble that no friendly ECM counters.
func in_enemy_ecm(m: CombatMech) -> bool:
	var r := float(tables["electronics"]["ecm_m"])
	var hostile := false
	for o: CombatMech in mechs:
		if o.out or not o.ecm:
			continue
		if o.pos.distance_to(m.pos) > r:
			continue
		if o.team == m.team:
			return false
		hostile = true
	return hostile


## Protected by its own side's ECM (cancels incoming Artemis and Narc guidance).
func ecm_protected(target: CombatMech) -> bool:
	var r := float(tables["electronics"]["ecm_m"])
	for o: CombatMech in mechs:
		if not o.out and o.ecm and o.team == target.team and o.pos.distance_to(target.pos) <= r:
			return true
	return false


# ------------------------------------------------------------------ to-hit

## Returns {"ok", "tn", "mods" [[label, value]], "band", "range"}; ok=false with "why" when impossible.
func to_hit(m: CombatMech, mt: Dictionary, target: CombatMech, base_skill := -1) -> Dictionary:
	var it: Dictionary = mt["item"]
	var mods: Array = []
	var skill := m.gunnery if base_skill < 0 else base_skill
	mods.append(["Gunnery", skill])
	var rh := range_hexes(m, target)
	var eff := rh
	var c3_used := false
	# C3: the network uses the range from whichever networked teammate is closest to the target
	if m.c3 and tables["electronics"].get("c3", true) and not in_enemy_ecm(m):
		for o in teammates(m):
			var om: CombatMech = o
			if om.c3 and not in_enemy_ecm(om) and los_between(om, target)["clear"]:
				var r2 := range_hexes(om, target)
				if r2 < eff:
					eff = r2
					c3_used = true
	var band := ""
	if eff <= int(it.get("s", 0)):
		band = "short"
	elif eff <= int(it.get("m", 0)):
		band = "medium"
	elif eff <= int(it.get("l", 0)):
		band = "long"
	elif rh <= int(it.get("l", 0)):
		band = "long"
	else:
		return {"ok": false, "why": "out of range"}
	if rh > int(it.get("l", 0)) and not c3_used:
		return {"ok": false, "why": "out of range"}
	var l := los_between(m, target)
	if not l["clear"]:
		return {"ok": false, "why": "no line of sight"}
	if str(it.get("wtype", "")) in ["lrt", "srt"] and (arena.depth[arena.cell_index(m.pos)] <= 0 or arena.depth[arena.cell_index(target.pos)] <= 0):
		return {"ok": false, "why": "torpedoes need water"}
	var rm := int(tables["range_mod"][band])
	if band == "long" and m.has_trait("sharpshooter"):
		rm -= 1
	for q in ["short", "medium", "long"]:
		if band == q and m.quirks.has("improved_targeting_" + q):
			rm -= 1
		if band == q and m.quirks.has("poor_targeting_" + q):
			rm += 1
	if rm != 0 or c3_used:
		mods.append(["%s range%s" % [band.capitalize(), " (C3)" if c3_used else ""], rm])
	var mn := int(it.get("min", 0))
	if mn > 0 and rh <= mn:
		mods.append(["Minimum range", mn - rh + 1])
	var am := attacker_movement_mod(m)
	if am != 0:
		mods.append(["Attacker moved", am])
	var munition := m.munition_for(mt)
	var mun: Dictionary = tables["munitions"].get(munition, {})
	var tmm := target_movement_mod(target)
	if target.gait == CombatMech.Gait.PRONE:
		tmm = 0
		mods.append(["Target prone", int(tables["target_mod"]["prone_adjacent"]) if rh <= 1 else int(tables["target_mod"]["prone"])])
	if target.shutdown or not target.conscious or target.engine_dead:
		tmm = 0
		mods.append(["Target immobile", int(tables["target_mod"]["immobile"])])
	if munition == "precision":
		tmm = maxi(0, tmm - 2)
	if tmm != 0:
		mods.append(["Target movement", tmm])
	if int(l["woods"]) > 0:
		mods.append(["Intervening woods", int(l["woods"])])
	if int(l.get("smoke", 0)) > 0:
		mods.append(["Smoke", int(l["smoke"])])
	if int(l["target_woods"]) > 0:
		mods.append(["Target in woods", int(l["target_woods"])])
	if int(l.get("target_smoke", 0)) > 0:
		mods.append(["Target in smoke", int(l["target_smoke"])])
	if l["partial"] and target.gait != CombatMech.Gait.PRONE and not target.is_vehicle:
		mods.append(["Partial cover", int(tables["terrain_mod"]["partial_cover"])])
	if target.battle_armor:
		mods.append(["Battle armour", int(tables["infantry"]["ba_to_hit"])])
	var hm := m.heat_to_hit()
	if hm > 0:
		mods.append(["Heat", hm])
	if m.is_vehicle:
		var vt: Dictionary = tables["vehicle"]
		if m.vsensors >= int(vt["sensor_blind_at"]):
			return {"ok": false, "why": "sensors destroyed"}
		if m.vsensors > 0:
			mods.append(["Sensor damage", m.vsensors * int(vt["sensor_to_hit"])])
		if m.commander_hit:
			mods.append(["Commander hit", int(vt["commander_to_hit"])])
		if m.copilot_hit:
			mods.append(["Co-pilot hit", int(vt["copilot_to_hit"])])
		if m.stabilizers.has(str(mt["loc"])) and am != 0:
			mods.append(["Stabilizer damaged", am])
	if m.sensor_hits > 0:
		mods.append(["Sensor damage", m.sensor_hits * int(tables["damage_mod"]["sensor_hit"])])
	var loc: String = mt["loc"]
	if loc in ["LA", "RA"]:
		if m.count_hit(loc, "shoulder") > 0:
			mods.append(["Shoulder hit", int(tables["damage_mod"]["shoulder"])])
		else:
			var a := m.count_hit(loc, "upper_arm") + m.count_hit(loc, "lower_arm")
			if a > 0:
				mods.append(["Arm actuators", a * int(tables["damage_mod"]["arm_actuator"])])
	var wt: String = it.get("wtype", "")
	if wt == "pulse":
		mods.append(["Pulse laser", -2])
	if m.tc and wt in Construction.DIRECT_FIRE:
		mods.append(["Targeting computer", -1])
	var G: Dictionary = tables["gear"]
	var bi_ := ["short", "medium", "long"].find(band)
	for sg in target.signatures_on():
		var sm_ := int((sg["stealth"] as Array)[bi_])
		if sm_ != 0:
			mods.append(["Stealth", sm_])
	if m.cockpit_to_hit != 0:
		mods.append(["Industrial cockpit", m.cockpit_to_hit])
	if m.aes.has(loc) and not m.mounts[int(m.aes[loc])]["destroyed"]:
		mods.append(["Actuator enhancement", int(G["aes_to_hit"])])
	if wt == "mrm" and m.apollo:
		mods.append(["Apollo fire control", int(G["apollo"]["to_hit"])])
	if t < m.emp_until:
		mods.append(["Electronics disrupted", int(G["tsemp"]["to_hit"])])
	if int(mun.get("to_hit", 0)) != 0:
		mods.append([str(mun.get("label", munition)), int(mun["to_hit"])])
	var env := conditions_mod(m, target, wt)
	for e in env:
		mods.append(e)
	var tn := 0
	for md in mods:
		tn += int(md[1])
	if m.sensor_hits >= 2:
		return {"ok": false, "why": "sensors destroyed"}
	return {"ok": true, "tn": tn, "mods": mods, "band": band, "range": rh, "munition": munition}


## Light and weather modifiers for an attack.
func conditions_mod(m: CombatMech, target: CombatMech, wt: String) -> Array:
	var out: Array = []
	if conditions.is_empty():
		return out
	var cd: Dictionary = tables["conditions"]
	var light: String = conditions.get("light", "day")
	var lm := int(cd["light"].get(light, 0))
	if lm > 0:
		var lit := false
		if m.searchlight and m.pos.distance_to(target.pos) <= float(cd["searchlight_m"]):
			lit = true
		var ci := arena.cell_index(target.pos)
		if arena.burning(ci):
			lit = true
		if not lit:
			for row in cd["heat_lit"]:
				if target.heat >= float(row[0]):
					lm = maxi(0, int(cd["light"][light]) - int(row[1]))
			if conditions.get("floodlights", false):
				lm = maxi(0, lm - int(cd["floodlights_reduce"]))
			if lm > 0:
				out.append([light.capitalize(), lm])
	var w: String = conditions.get("weather", "clear")
	var wd: Dictionary = cd["weather"].get(w, {})
	if int(wd.get("all", 0)) > 0:
		out.append([w.capitalize(), int(wd["all"])])
	if int(wd.get("energy", 0)) > 0 and wt in ENERGY_TYPES:
		out.append(["Fog (energy weapons)", int(wd["energy"])])
	if int(wd.get("missile", 0)) > 0 and wt in MISSILE_TYPES:
		out.append(["Wind (missiles)", int(wd["missile"])])
	return out


static func p_hit(tn: int) -> float:
	if tn <= 2:
		return 1.0
	if tn > 12:
		return 0.0
	return P_HIT[tn]


# ------------------------------------------------------------------ firing

## Finds an ammo bin with shots for a weapon. Returns mount index, -2 for no ammo needed, -1 if empty.
func find_ammo(m: CombatMech, mt: Dictionary) -> int:
	var key: String = mt["item"].get("ammo", "")
	if key == "":
		return -2
	for bi in m.bins:
		var b: Dictionary = m.mounts[bi]
		if not b["destroyed"] and int(b["shots"]) > 0 and b["item"].get("ammo", "") == key:
			return bi
	return -1


func weapon_ready(m: CombatMech, wi: int) -> bool:
	var mt: Dictionary = m.mounts[wi]
	if mt["destroyed"] or mt["jammed"] or float(mt["cooldown"]) > 0.0:
		return false
	if m.loc_destroyed[mt["loc"]]:
		return false
	var wt: String = mt["item"].get("wtype", "")
	if wt in ["ams", "tag", "other", "pod", "c3sensors"]:
		return false
	if mt["item"].get("oneshot", false) and mt.get("used", false):
		return false
	if mt["item"].has("salvos") and int(mt.get("fired", 0)) >= int(mt["item"]["salvos"]):
		return false
	if m.is_vehicle:
		if m.crew_stunned(t) or t < float(mt.get("malf_until", -1.0)):
			return false
		if mt["loc"] == "TU" and t < m.turret_jam_until:
			return false
		if m.engine_dead and wt in ["laser", "pulse", "ppc"]:
			return false
	# a 'Mech swinging a club can't fire its arm weapons
	if m.club_uses > 0 and mt["loc"] in ["LA", "RA"]:
		return false
	return find_ammo(m, mt) != -1


func fire(m: CombatMech, wi: int, target: CombatMech) -> void:
	var mt: Dictionary = m.mounts[wi]
	var it: Dictionary = mt["item"]
	var wt: String = it.get("wtype", "")
	var th := to_hit(m, mt, target)
	if not th["ok"]:
		return
	var tn: int = th["tn"]
	var munition: String = th["munition"]
	var mun: Dictionary = tables["munitions"].get(munition, {})
	var roll := rng.roll2d6()
	mt["cooldown"] = TURN
	var G: Dictionary = tables["gear"]
	if wt in ["tsemp", "taser"]:
		mt["cooldown"] = TURN * float(G[wt]["recharge_turns"])
	if wt == "streak_srm" or wt == "streak_lrm":
		if roll < tn:
			log_event({"k": "nolock", "m": m.index, "tg": target.index, "w": it["name"], "tn": tn, "roll": roll})
			return
	var shots_fired := 1
	if wt == "uac":
		shots_fired = 2
	elif wt == "rac":
		shots_fired = 4
	var bi := find_ammo(m, mt)
	if bi >= 0:
		var b: Dictionary = m.mounts[bi]
		shots_fired = mini(shots_fired, int(b["shots"]))
		b["shots"] = int(b["shots"]) - shots_fired
	if it.get("oneshot", false):
		mt["used"] = true
	if it.has("salvos"):
		mt["fired"] = int(mt.get("fired", 0)) + 1
	var charged: bool = mt.has("cap") and not m.mounts[int(mt["cap"])]["destroyed"]
	if not m.is_vehicle:
		var wheat := float(it.get("heat", 0)) * shots_fired
		if charged:
			wheat += float(G["ppc_capacitor"]["heat"])
		if mt.has("cooler") and not m.mounts[int(mt["cooler"])]["destroyed"]:
			wheat = maxf(0.0, wheat - 1.0)
		m.heat += wheat
	m.shots += 1
	var hit := roll >= tn
	if (wt == "uac" or wt == "rac") and roll == 2:
		mt["jammed"] = true
	var wname: String = it["name"]
	if munition != "standard":
		wname += " (%s)" % str(mun.get("label", munition))
	var ev := {"k": "shot", "m": m.index, "tg": target.index, "w": wname, "wt": wt, "tn": tn, "roll": roll,
		"hit": hit, "loc_from": mt["loc"], "mods": th["mods"]}
	if mt["jammed"]:
		ev["jam"] = true
	log_event(ev)
	var tcell := arena.cell_index(target.pos)
	if wt == "artillery":
		# a 'Mech's own tube: the shell is in the air now and comes down where the target stood
		_tube_fire(m, it, target, hit, int(th["range"]))
		return
	if not hit:
		_on_miss(m, target, wt, munition, int(it.get("dmg", 0)) * maxi(1, int(it.get("rack", 1))))
		return
	m.hits += 1
	var side := attack_side(m, target)
	var dmg := int(it.get("dmg", 0))
	if charged:
		dmg += int(G["ppc_capacitor"]["damage"])
	if wt == "ppc" and target.blue_shield:
		dmg = int(ceil(dmg * float(G["blue_shield"])))
	_dclass = damage_class(wt)
	_fire_effect(m, mt, target, th, side, dmg, wname, munition, mun, shots_fired, tcell)
	_dclass = "other"
	m.showmanship += 0.2


## The kind of damage a weapon type does.
static func damage_class(wt: String) -> String:
	if wt in ENERGY_TYPES:
		return "energy"
	if wt in MISSILE_TYPES:
		return "missile"
	if wt in AREA_TYPES:
		return "area"
	if wt in ["ams", "tag", "narc", "inarc", "other", "pod"]:
		return "other"
	return "ballistic"


## A hit: what the weapon does to the target.
func _fire_effect(m: CombatMech, mt: Dictionary, target: CombatMech, th: Dictionary, side: String, dmg: int, wname: String,
		munition: String, mun: Dictionary, shots_fired: int, tcell: int) -> void:
	var it: Dictionary = mt["item"]
	var wt: String = it.get("wtype", "")
	var G: Dictionary = tables["gear"]
	if wt in ["tsemp", "taser"]:
		_emp_hit(m, target, wt)
		if dmg <= 0:
			return
	if wt == "plasma":
		# burning foam: heat on a 'Mech, more damage on anything that has no heat scale
		var dice: Array = G["plasma"].get(str(it.get("fam", "plasma")), [1, 6])
		var extra := 0
		for k in int(dice[0]):
			extra += rng.randi_range(1, int(dice[1]))
		if target.is_vehicle or target.is_infantry:
			dmg += extra
		else:
			var put := float(extra) * float(target.armor_fx.get("external_heat", 1.0))
			target.heat += put
			log_event({"k": "plasma_heat", "m": m.index, "tg": target.index, "heat": int(put)})
		if dmg <= 0:
			return
	if wt == "mpod":
		var by_range: Array = G["mpod"]
		cluster_damage(target, int(by_range[clampi(int(th["range"]) - 1, 0, by_range.size() - 1)]), side, "hit_location", m, wname)
		return
	if wt == "hag":
		var left_h := cluster_hits(int(it.get("rack", 20)), int(G["hag_cluster"].get(str(th["band"]), 0)))
		if target.is_infantry and not target.battle_armor:
			_fire_on_platoon(m, target, it, munition, shots_fired, wname)
			return
		while left_h > 0 and not target.destroyed:
			var nh := mini(5, left_h)
			_hit_location_damage(m, target, side, nh, wname)
			left_h -= nh
		return
	if wt == "artcannon":
		_hit_location_damage(m, target, side, dmg, wname)
		var AC: Dictionary = G["artcannon"]
		for o: CombatMech in mechs:
			if o != target and o != m and not o.out and not o.airborne and o.pos.distance_to(target.pos) <= float(AC["splash_m"]):
				_area_damage(o, int(ceil(dmg * float(AC["splash"]))), m.pos, wname)
		if arena.terrain[tcell] != Arena.T.BUILDING:
			try_ignite(tcell, int(G["artillery"]["ignite_tn"]), "artillery")
		return
	if wt in ["narc", "inarc"]:
		target.narced[m.team] = true
		log_event({"k": "narc", "m": m.index, "tg": target.index})
		return
	if wt == "flamer":
		try_ignite(tcell, int(tables["fire"]["flamer_ignite_tn"]), "flamer")
	if it.get("squad", false):
		_squad_fire(m, mt, target, side, wname)
		m.showmanship += 0.2
		return
	if target.is_infantry and not target.battle_armor:
		_fire_on_platoon(m, target, it, munition, shots_fired, wname)
		m.showmanship += 0.2
		return
	if wt in MISSILE_TYPES:
		var rack := int(it.get("rack", 0))
		var bonus := 0
		var guided := not ecm_protected(target)
		if m.artemis and wt in ["lrm", "srm", "mml"] and guided:
			bonus += int(tables["electronics"]["artemis_cluster_bonus"])
		if wt == "mrm" and m.apollo:
			bonus += int(G["apollo"]["cluster"])
		if target.narced.get(m.team, false) and wt in ["lrm", "srm", "mml"] and guided:
			bonus += int(tables["electronics"]["narc_cluster_bonus"])
		if target.has_ams and not wt.begins_with("streak"):
			var ams_bin := _ams_ammo(target)
			if ams_bin != -1:
				bonus -= 4
				if ams_bin >= 0:
					target.mounts[ams_bin]["shots"] = int(target.mounts[ams_bin]["shots"]) - 1
		var missiles := rack if wt.begins_with("streak") else cluster_hits(rack, bonus)
		if target.is_infantry and munition == "inferno":
			munition = "standard"   # against armoured suits the gel is just another warhead
		if munition == "inferno" and target.is_vehicle:
			# burning gel on a vehicle: a critical hit chance on the side it struck
			log_event({"k": "inferno", "m": m.index, "tg": target.index, "n": missiles, "heat": 0})
			_vehicle_crit(target, _vside_loc(target, side), m, missiles / 4)
			try_ignite(tcell, int(mun.get("ignite_tn", 5)), "inferno")
			return
		if munition == "inferno":
			var hp := float(mun.get("heat_per_missile", 2)) * float(target.armor_fx.get("external_heat", 1.0))
			target.heat += float(missiles) * hp
			log_event({"k": "inferno", "m": m.index, "tg": target.index, "n": missiles, "heat": int(missiles * hp)})
			try_ignite(tcell, int(mun.get("ignite_tn", 5)), "inferno")
			return
		var per := dmg
		if wt == "mml":
			per = 2 if int(th["range"]) <= 6 else 1
		var group := 1 if per >= 2 else maxi(1, int(it.get("group", 5)))
		var left := missiles
		while left > 0:
			var n := mini(group, left)
			_hit_location_damage(m, target, side, n * per, wname)
			left -= n
	elif wt == "lbx" and munition == "lbx_cluster":
		var pellets := cluster_hits(dmg, 0)
		for k in pellets:
			_hit_location_damage(m, target, side, int(mun.get("per_hit", 1)), wname)
	elif wt == "uac" or wt == "rac":
		var n2 := cluster_hits(shots_fired, 0) if shots_fired > 1 else 1
		for k in n2:
			_hit_location_damage(m, target, side, dmg, wname)
	elif dmg > 0:
		var loc := _hit_location_damage(m, target, side, dmg, wname)
		if munition == "armor_piercing" and loc != "" and not target.out:
			log_event({"k": "ap", "m": m.index, "tg": target.index, "loc": loc})
			if target.is_vehicle:
				_vehicle_crit(target, loc, m)
			else:
				crit_check(target, loc, m)


## TSEMP cannons and tasers scramble electronics: worse shooting for a turn, or every weapon off line.
func _emp_hit(m: CombatMech, target: CombatMech, kind: String) -> void:
	var E: Dictionary = tables["gear"][kind]
	if target.is_infantry:
		return
	var cls := "vehicle" if target.is_vehicle else target.design.weight_class()
	var roll := rng.roll2d6() + int(E["mods"].get(cls, 0))
	var res := "none"
	if roll >= int(E["shutdown_at"]):
		res = "shutdown"
		target.emp_until = t + TURN
		for wi in target.weapons:
			target.mounts[wi]["cooldown"] = maxf(float(target.mounts[wi]["cooldown"]), TURN)
	elif roll >= int(E["interfere_at"]):
		res = "interference"
		target.emp_until = t + TURN
	log_event({"k": "emp", "m": m.index, "tg": target.index, "roll": roll, "res": res})


## A 'Mech-mounted artillery piece fires at the ground under its target. A good shot lands there;
## a bad one scatters. Either way it arrives after its flight time and hits whoever is under it.
func _tube_fire(m: CombatMech, it: Dictionary, target: CombatMech, hit: bool, range_h: int) -> void:
	var A: Dictionary = tables["gear"]["artillery"]
	var p := target.pos
	if not hit:
		p += Vector2.from_angle(rng.randf() * TAU) * (0.3 + 0.7 * rng.randf()) * float(A["scatter_m"])
	p = p.clamp(Vector2.ZERO, arena.size_m())
	var at := t + float(A["flight_s"]) + float(A["flight_s_per_hex"]) * range_h
	strikes.append({"kind": "tube", "team": m.team, "pos": p, "ang": 0.0, "at": at, "dmg": int(it.get("dmg", 20)),
		"by": m.index, "w": str(it["name"])})
	log_event({"k": "support_call", "team": m.team, "kind": "artillery", "pos": [p.x, p.y], "ang": 0.0, "at": at, "until": at})
	if hit:
		m.hits += 1


func _tube_lands(st: Dictionary) -> void:
	var A: Dictionary = tables["gear"]["artillery"]
	var p: Vector2 = st["pos"]
	var radius := float(A["radius_m"])
	var inner := HEX * 0.5
	var dmg := int(st["dmg"])
	var by: CombatMech = mechs[int(st["by"])] if int(st.get("by", -1)) >= 0 else null
	log_event({"k": "shell", "team": int(st["team"]), "pos": [p.x, p.y], "r": radius})
	for o: CombatMech in mechs:
		if o.out or o.airborne or o.gait == CombatMech.Gait.JUMP:
			continue
		var d := o.pos.distance_to(p)
		if d <= radius:
			var before := o.dmg_taken
			_area_damage(o, dmg if d <= inner * 2.0 else int(ceil(dmg * float(A["splash"]))), p, str(st["w"]))
			if by != null and o.team != by.team:
				by.dmg_dealt += o.dmg_taken - before
	var c := arena.cell_of(p)
	var rc := int(ceil(radius / Arena.CELL))
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			if not arena.inside(c.x + dx, c.y + dy):
				continue
			var i := arena.idx(c.x + dx, c.y + dy)
			var d2 := arena.center_of_index(i).distance_to(p)
			if d2 > radius:
				continue
			if arena.terrain[i] == Arena.T.BUILDING:
				damage_building(i, int(dmg * float(A["building_damage"])) if d2 <= inner else int(dmg * float(A["building_damage"])) / 4, by)
			elif d2 <= inner * 2.0:
				try_ignite(i, int(A["ignite_tn"]), "artillery")


## Fire at a building cell (objective buildings): it can't dodge (-4), range and movement still count.
func fire_at_cell(m: CombatMech, wi: int, ci: int) -> void:
	var mt: Dictionary = m.mounts[wi]
	var it: Dictionary = mt["item"]
	var cp := arena.center_of_index(ci)
	var d := m.pos.distance_to(cp)
	var rh := maxi(1, int(ceil(d / HEX - 0.001)))
	if rh > int(it.get("l", 0)):
		return
	var l := arena.los(m.pos, cp)
	if not l["clear"] and int(l.get("cover_cell", -1)) != ci:
		return
	var base := m.facing + (m.twist if (not m.is_vehicle or mt["loc"] == "TU") else 0.0)
	if not m.is_vehicle and mt["loc"] in ["LL", "RL"]:
		base = m.facing
	var rel := rad_to_deg(wrap_angle((cp - m.pos).angle() - base))
	if not m.is_infantry and (mt["rear"] or absf(rel) > 75.0):
		return
	var band := 0
	if rh > int(it.get("m", 0)):
		band = 4
	elif rh > int(it.get("s", 0)):
		band = 2
	var tn := m.gunnery + band + attacker_movement_mod(m) + int(tables["target_mod"]["immobile"]) + int(l["woods"])
	var bi := find_ammo(m, mt)
	if bi >= 0:
		m.mounts[bi]["shots"] = int(m.mounts[bi]["shots"]) - 1
	mt["cooldown"] = TURN
	if not m.is_vehicle:
		m.heat += float(it.get("heat", 0))
	m.shots += 1
	var roll := rng.roll2d6()
	var hit := roll >= tn
	var wt: String = it.get("wtype", "")
	log_event({"k": "shot_bld", "m": m.index, "cell": ci, "w": it["name"], "wt": wt, "tn": tn, "roll": roll, "hit": hit})
	if hit:
		var dmg := int(it.get("dmg", 0)) * maxi(1, int(it.get("rack", 1)))
		if wt in MISSILE_TYPES:
			dmg = int(round(dmg * 0.6))
		damage_building(ci, maxi(1, dmg), m)


## Misses still land somewhere: they can chip the building the target hides behind or set woods alight.
func _on_miss(m: CombatMech, target: CombatMech, wt: String, munition: String, dmg: int) -> void:
	var l := los_between(m, target)
	var cc: int = l.get("cover_cell", -1)
	var bdmg := maxi(1, dmg if munition != "inferno" else 2)
	if cc >= 0 and arena.terrain[cc] == Arena.T.BUILDING and rng.chance(float(tables["buildings"]["miss_hit_chance"])):
		damage_building(cc, bdmg, m)
	elif rng.chance(float(tables["buildings"].get("stray_hit_chance", 0.35))):
		# a stray shot slams into the nearest building behind or beside the target
		var near := _nearest_building(target.pos, m.pos, 2)
		if near >= 0:
			damage_building(near, bdmg, m)
	var tcell := arena.cell_index(target.pos)
	if wt == "flamer":
		try_ignite(tcell, int(tables["fire"]["flamer_ignite_tn"]), "flamer")
	elif munition == "inferno":
		try_ignite(tcell, int(tables["munitions"]["inferno"].get("ignite_tn", 5)) + 2, "inferno")
	elif wt in ENERGY_TYPES:
		try_ignite(tcell, int(tables["fire"]["laser_ignite_tn"]), "laser")


## Nearest building cell within r cells of p that lies on the far side from the shooter.
func _nearest_building(p: Vector2, from: Vector2, r: int) -> int:
	var c := arena.cell_of(p)
	var best := -1
	var bd := INF
	var dir := (p - from).normalized()
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var x := c.x + dx
			var y := c.y + dy
			if not arena.inside(x, y):
				continue
			var i := arena.idx(x, y)
			if arena.terrain[i] != Arena.T.BUILDING or int(arena.bld_cf[i]) >= 99999:
				continue
			var cp := arena.center_of(Vector2i(x, y))
			if (cp - p).normalized().dot(dir) < -0.3:
				continue
			var d := cp.distance_to(p)
			if d < bd:
				bd = d
				best = i
	return best


func _ams_ammo(target: CombatMech) -> int:
	for wi in target.weapons:
		var mt: Dictionary = target.mounts[wi]
		if mt["item"].get("wtype", "") == "ams" and not mt["destroyed"]:
			var bi := find_ammo(target, mt)
			if bi >= 0 or bi == -2:
				return bi
	return -1


func cluster_hits(rack: int, bonus: int) -> int:
	var roll := clampi(rng.roll2d6() + bonus, 2, 12)
	var sizes: Array = tables["cluster_sizes"]
	var row: Array = tables["cluster_hits"][str(roll)]
	var col := 0
	for k in sizes.size():
		if int(sizes[k]) <= rack:
			col = k
	var base := int(row[col])
	# racks between table columns scale from the nearest smaller column
	if int(sizes[col]) != rack and int(sizes[col]) > 0:
		return clampi(int(round(base * float(rack) / float(sizes[col]))), 1, rack)
	return mini(base, rack)


## Rolls a hit location and applies damage. Returns the location hit ("" if it hit cover).
func _hit_location_damage(attacker: CombatMech, target: CombatMech, side: String, dmg: int, cause: String) -> String:
	if target.is_vehicle:
		return _vehicle_hit(attacker, target, side, dmg, cause, true)
	var table: Dictionary = tables["hit_location"]["front" if side == "rear" else side]
	var roll := rng.roll2d6()
	var loc: String = table[str(roll)]
	var tac := loc.ends_with("*")
	loc = loc.trim_suffix("*")
	var rear := side == "rear"
	# partial cover: leg hits strike the cover
	if loc in ["LL", "RL"] and attacker != null:
		var l := los_between(attacker, target)
		if l["partial"] and target.gait != CombatMech.Gait.PRONE:
			log_event({"k": "cover", "m": attacker.index, "tg": target.index, "loc": loc})
			var cc: int = l.get("cover_cell", -1)
			if cc >= 0 and arena.terrain[cc] == Arena.T.BUILDING:
				damage_building(cc, dmg, attacker)
			return ""
	apply_damage(target, loc, dmg, rear, attacker, cause)
	if tac and not target.out:
		log_event({"k": "tac", "m": attacker.index if attacker else -1, "tg": target.index, "loc": loc})
		crit_check(target, loc, attacker)
	return loc


# ------------------------------------------------------------------ damage

func apply_damage(target: CombatMech, loc: String, dmg: int, rear: bool, attacker: CombatMech, cause: String) -> void:
	if target.destroyed:
		return
	if target.is_vehicle:
		_vehicle_damage(target, _vloc(target, loc, rear), dmg, attacker, cause)
		return
	var remaining := dmg
	var cur := loc
	var applied := 0
	if loc == "HD" and dmg > 0:
		pilot_hit(target, 1, "head hit")
	var fx: Dictionary = target.armor_fx
	var first_key: String = MechDesign.REAR[loc] if rear and MechDesign.REAR.has(loc) else loc
	var breach := false
	if not fx.is_empty() and not target.loc_destroyed[loc] and int(target.armor.get(first_key, 0)) > 0:
		# the armor type answers this kind of damage, as long as there is armor where it lands
		remaining = _armor_adjust(remaining, fx)
		breach = fx.has("bar") and remaining > int(fx["bar"])
	var soak_a := 2 if fx.get("armor_double", false) else 1
	while remaining > 0 and cur != "":
		if target.loc_destroyed[cur]:
			cur = TRANSFER[cur]
			continue
		var akey: String = MechDesign.REAR[cur] if rear and MechDesign.REAR.has(cur) else cur
		var a: int = target.armor.get(akey, 0)
		var ab := mini(a * soak_a, remaining)
		var gone := int(ceil(float(ab) / soak_a))
		target.armor[akey] = a - gone
		remaining -= ab
		applied += gone
		if breach and gone > 0 and remaining <= 0 and not target.destroyed:
			breach = false
			crit_check(target, cur, attacker)
		if remaining <= 0:
			break
		var s: int = target.internal[cur]
		# composite structure gives way twice as fast, reinforced half as fast
		var sb := mini(s, int(ceil(remaining / target.struct_soak)))
		target.internal[cur] = s - sb
		remaining -= mini(remaining, int(ceil(sb * target.struct_soak)))
		applied += sb
		if sb > 0:
			crit_check(target, cur, attacker)
			if target.destroyed:
				break
		if target.internal[cur] <= 0 and not target.loc_destroyed[cur]:
			destroy_location(target, cur, attacker)
			if target.destroyed:
				break
		if remaining > 0:
			cur = TRANSFER[cur]
	if attacker != null and attacker != target:
		attacker.dmg_dealt += applied
	target.dmg_taken += applied
	log_event({"k": "dmg", "m": attacker.index if attacker else -1, "tg": target.index, "loc": loc, "dmg": dmg,
		"rear": rear, "w": cause})
	target.dmg_window += applied
	if target.dmg_window >= 20.0 and not target.dmg_window_psr and not target.out:
		target.dmg_window_psr = true
		psr(target, int(tables["psr_mod"]["damage_20"]), "20+ damage")


## A hit as an armor type takes it: halved, doubled or shaved by the kind of damage (see armor_types).
func _armor_adjust(dmg: int, fx: Dictionary) -> int:
	var d := dmg
	if _dclass in fx.get("half", []):
		d = maxi(1, d / 2)
	if _dclass in fx.get("double", []):
		d *= 2
	if _dclass in fx.get("third_off", []):
		d = maxi(1, d - d / 3)
	if fx.has("reduce_per"):
		d = maxi(1, d - d / int(fx["reduce_per"]))
	return d


## Damage in 5-point groups, each to its own location (falls, charges, death from above).
func cluster_damage(target: CombatMech, total: int, side: String, table_name: String, attacker: CombatMech, cause: String) -> void:
	var left := total
	var key := "front" if side == "rear" else side
	if target.is_vehicle:
		while left > 0 and not target.destroyed:
			var nv := mini(5, left)
			_vehicle_hit(attacker, target, side, nv, cause, false)
			left -= nv
		return
	while left > 0 and not target.destroyed:
		var n := mini(5, left)
		var loc := ""
		if table_name == "hit_location":
			loc = str(tables[table_name][key][str(rng.roll2d6())]).trim_suffix("*")
		else:
			loc = str(tables[table_name][key][str(rng.d6())])
		apply_damage(target, loc, n, side == "rear", attacker, cause)
		left -= n


func crit_check(target: CombatMech, loc: String, attacker: CombatMech) -> void:
	if target.is_vehicle:
		return
	if target.loc_destroyed[loc] or target.destroyed:
		return
	var roll := rng.roll2d6()
	if target.armor_fx.has("crit_mod") and int(target.armor.get(loc, 0)) > 0:
		roll = clampi(roll + int(target.armor_fx["crit_mod"]), 2, 12)
	var n := int(tables["crit_chance"].get(str(roll), 0))
	if n <= 0:
		return
	if roll == 12 and loc in ["LA", "RA", "LL", "RL", "HD"]:
		log_event({"k": "blown_off", "tg": target.index, "loc": loc})
		destroy_location(target, loc, attacker)
		return
	for k in n:
		if target.destroyed or target.loc_destroyed[loc]:
			return
		apply_crit(target, loc, attacker)


func apply_crit(target: CombatMech, loc: String, attacker: CombatMech) -> void:
	var cand: Array = []
	var row: Array = target.slots[loc]
	for i in row.size():
		var sl: Dictionary = row[i]
		if sl["s"] != "" and not sl["hit"] and not (sl["s"] in MechDesign.FILLERS):
			cand.append(i)
	if cand.is_empty():
		return
	var i: int = cand[rng.randi_range(0, cand.size() - 1)]
	var sl2: Dictionary = row[i]
	var s: String = sl2["s"]
	var mi: int = sl2["m"]
	if attacker != null:
		attacker.crits_dealt += 1
	var label := s.replace("_", " ")
	if mi >= 0:
		label = str(target.mounts[mi]["item"].get("name", s))
	log_event({"k": "crit", "tg": target.index, "loc": loc, "what": label})
	# ammo explodes before the slot is marked destroyed
	if mi >= 0:
		var mt: Dictionary = target.mounts[mi]
		if mt["kind"] == "ammo" and int(mt["shots"]) > 0 and mt["item"].get("explosive", true):
			target._mark_slot_hit(loc, i)
			ammo_explosion(target, mi, attacker)
			return
		if mt["item"].get("explodes", false):
			target._mark_slot_hit(loc, i)
			log_event({"k": "explode", "tg": target.index, "loc": loc, "what": label})
			internal_damage(target, loc, 20, attacker)
			return
	target._mark_slot_hit(loc, i)
	match s:
		"engine":
			if target.engine_hits >= 3:
				kill(target, attacker, "engine destroyed")
		"gyro":
			if target.gyro_hits >= 2:
				fall(target, "gyro destroyed")
			else:
				psr(target, 0, "gyro hit")
		"cockpit":
			pilot_hit(target, 6, "cockpit destroyed")
		"hip", "upper_leg", "lower_leg", "foot":
			psr(target, 0, "leg actuator hit")
		"hand", "lower_arm", "upper_arm", "shoulder":
			if target.club_uses > 0:
				target.club_uses = 0
				log_event({"k": "club_drop", "tg": target.index})


func ammo_explosion(target: CombatMech, bi: int, attacker: CombatMech) -> void:
	var b: Dictionary = target.mounts[bi]
	var key: String = b["item"].get("ammo", "")
	var per := 1
	# damage per shot = the matching weapon's damage per volley
	for wi in target.weapons:
		var w: Dictionary = target.mounts[wi]["item"]
		if w.get("ammo", "") == key:
			per = int(w.get("dmg", 1)) * maxi(1, int(w.get("rack", 1))) if w.get("wtype", "") in MISSILE_TYPES else int(w.get("dmg", 1))
			break
	var dmg := int(b["shots"]) * per
	b["shots"] = 0
	var loc: String = b["loc"]
	log_event({"k": "ammo_explosion", "tg": target.index, "loc": loc, "dmg": dmg, "what": b["item"].get("name", "")})
	_explosion_effects(target.pos)
	pilot_hit(target, int(tables["ammo_explosion_pilot_hits"]), "ammo explosion")
	internal_damage(target, loc, dmg, attacker)


## Damage straight to internal structure (explosions). CASE stops it at the location.
func internal_damage(target: CombatMech, loc: String, dmg: int, attacker: CombatMech) -> void:
	var cur := loc
	var remaining := dmg
	var case_here: bool = target.has_case.get(loc, false)
	while remaining > 0 and cur != "" and not target.destroyed:
		if target.loc_destroyed[cur]:
			if case_here:
				return
			cur = TRANSFER[cur]
			continue
		var s: int = target.internal[cur]
		var sb := mini(s, remaining)
		target.internal[cur] = s - sb
		remaining -= sb
		target.dmg_taken += sb
		if target.internal[cur] <= 0:
			destroy_location(target, cur, attacker)
		if case_here:
			if MechDesign.REAR.has(cur):
				target.armor[MechDesign.REAR[cur]] = 0
			return
		cur = TRANSFER[cur]


func destroy_location(target: CombatMech, loc: String, attacker: CombatMech) -> void:
	if target.loc_destroyed[loc]:
		return
	target.loc_destroyed[loc] = true
	target.internal[loc] = 0
	target.armor[loc] = 0
	if MechDesign.REAR.has(loc):
		target.armor[MechDesign.REAR[loc]] = 0
	var engine_slots := 0
	for i in (target.slots[loc] as Array).size():
		var sl: Dictionary = target.slots[loc][i]
		if sl["s"] == "engine" and not sl["hit"]:
			engine_slots += 1
		if not sl["hit"] and sl["s"] != "":
			sl["hit"] = true
			if int(sl["m"]) >= 0:
				target.mounts[sl["m"]]["destroyed"] = true
				var misc: String = target.mounts[sl["m"]]["item"].get("misc", "")
				match misc:
					"masc":
						target.masc = false
					"ecm":
						target.ecm = false
					"c3":
						target.c3 = false
	log_event({"k": "loc_destroyed", "tg": target.index, "loc": loc})
	match loc:
		"HD":
			pilot_hit(target, 6, "head destroyed")
			kill(target, attacker, "head destroyed")
		"CT":
			kill(target, attacker, "center torso destroyed")
		"LT", "RT":
			var arm := "LA" if loc == "LT" else "RA"
			if not target.loc_destroyed[arm]:
				destroy_location(target, arm, attacker)
			if engine_slots > 0:
				target.engine_hits += mini(engine_slots, 3)
				if target.engine_hits >= 3:
					kill(target, attacker, "engine destroyed")
		"LA", "RA":
			if target.club_uses > 0:
				target.club_uses = 0
		"LL", "RL":
			fall(target, "leg destroyed")


func kill(target: CombatMech, attacker: CombatMech, why: String) -> void:
	if target.destroyed:
		return
	target.destroyed = true
	set_out(target, "destroyed: " + why)
	if attacker != null and attacker != target:
		attacker.kills += 1
		target.killer = attacker.index
		attacker.showmanship += 10.0
	log_event({"k": "destroyed", "tg": target.index, "why": why, "m": attacker.index if attacker else -1})
	if not target.is_infantry:
		_explosion_effects(target.pos)
	if target.booby_trap:
		# rigged to go up with the 'Mech: everything close by is caught in it
		target.booby_trap = false
		var B: Dictionary = tables["gear"]["booby_trap"]
		log_event({"k": "shell", "team": target.team, "pos": [target.pos.x, target.pos.y], "r": float(B["radius_m"])})
		for o: CombatMech in mechs:
			if o != target and not o.out and not o.airborne and o.pos.distance_to(target.pos) <= float(B["radius_m"]):
				_area_damage(o, int(ceil(target.tons() / float(B["per_tons"]))), target.pos, "booby trap")


func set_out(m: CombatMech, why: String) -> void:
	if m.out:
		return
	m.out = true
	m.out_reason = why
	m.out_time = t
	m.gait = CombatMech.Gait.OUT
	m.path = PackedVector2Array()
	m.masc_on = false


func pilot_hit(m: CombatMech, n: int, why: String) -> void:
	if m.destroyed or m.is_vehicle:
		return
	m.pilot_hits = mini(6, m.pilot_hits + n)
	log_event({"k": "pilot", "tg": m.index, "hits": m.pilot_hits, "why": why})
	if m.pilot_hits >= 6:
		m.conscious = false
		kill(m, null, "MechWarrior killed")
		return
	if not m.conscious:
		return
	var need := int(tables["consciousness"][str(m.pilot_hits)])
	if m.has_trait("cool_under_fire") or m.has_trait("iron_man"):
		need -= 1
	var roll := rng.roll2d6()
	if roll < need and m.lucky_left > 0:
		m.lucky_left -= 1
		roll = rng.roll2d6()
	if roll < need:
		m.conscious = false
		log_event({"k": "unconscious", "tg": m.index})
		fall(m, "pilot unconscious")
		set_out(m, "pilot unconscious")


func psr(m: CombatMech, extra: int, why: String) -> bool:
	if m.out or m.gait == CombatMech.Gait.PRONE or m.is_vehicle:
		return true
	var tn := m.piloting + m.psr_base_mods() + extra
	var roll := rng.roll2d6()
	if roll < tn and m.lucky_left > 0:
		m.lucky_left -= 1
		roll = rng.roll2d6()
	var ok := roll >= tn
	log_event({"k": "psr", "tg": m.index, "tn": tn, "roll": roll, "ok": ok, "why": why})
	if not ok:
		fall(m, why)
	return ok


func fall(m: CombatMech, why: String, from_jump := false) -> void:
	if m.gait == CombatMech.Gait.PRONE or m.destroyed or m.is_vehicle:
		return
	var was_jumping := m.gait == CombatMech.Gait.JUMP or from_jump
	m.gait = CombatMech.Gait.PRONE
	m.prone_since = t
	m.stand_attempt_at = t + 3.0
	m.path = PackedVector2Array()
	m.masc_on = false
	log_event({"k": "fall", "tg": m.index, "why": why})
	var dir := rng.d6()
	var side := "front"
	match dir:
		2, 3:
			side = "right"
		4:
			side = "rear"
		5, 6:
			side = "left"
	var dmg := int(ceil(m.tons() / 10.0)) * (2 if was_jumping else 1)
	var was := _dclass
	_dclass = "fall"
	cluster_damage(m, dmg, side, "hit_location", null, "fall")
	_dclass = was
	if not m.destroyed and m.conscious:
		var roll := rng.roll2d6()
		if roll < m.piloting + 1:
			pilot_hit(m, 1, "fall")


func try_stand(m: CombatMech) -> void:
	if m.gyro_hits >= 2 or m.legs_destroyed() >= 2 or m.walk_mp() <= 0:
		if not m.out and t - m.prone_since > 5.0:
			log_event({"k": "crippled", "tg": m.index})
			set_out(m, "crippled")
		return
	var tn := m.piloting + m.psr_base_mods()
	var roll := rng.roll2d6()
	if roll < tn and m.lucky_left > 0:
		m.lucky_left -= 1
		roll = rng.roll2d6()
	if roll >= tn:
		m.gait = CombatMech.Gait.STAND
		m.last_walk_t = t
		log_event({"k": "stand", "tg": m.index, "tn": tn, "roll": roll})
	else:
		log_event({"k": "stand_fail", "tg": m.index, "tn": tn, "roll": roll})
		m.gait = CombatMech.Gait.STAND
		fall(m, "failed to stand")
	m.stand_attempt_at = t + 5.0


# ------------------------------------------------------------------ the battlefield: buildings, fire, hazards

func damage_building(i: int, dmg: int, attacker: CombatMech) -> void:
	if arena.terrain[i] != Arena.T.BUILDING or int(arena.bld_cf[i]) >= 99999:
		return
	arena.bld_cf[i] = int(arena.bld_cf[i]) - dmg
	if arena.bld_cf[i] > 0:
		log_event({"k": "bld_hit", "cell": i, "dmg": dmg, "cf": int(arena.bld_cf[i])})
		return
	# collapse into rubble: passable, no more cover, a cloud of debris
	arena.terrain[i] = Arena.T.RUBBLE
	arena.collapsed_h[i] = arena.bld_h[i]
	arena.bld_h[i] = 0
	arena.collapsed_at[i] = t
	arena.refresh_cell(i)
	_los_cache.clear()
	log_event({"k": "collapse", "cell": i, "m": attacker.index if attacker else -1})
	var c := arena.center_of_index(i)
	for o: CombatMech in mechs:
		if not o.out and o.pos.distance_to(c) < 14.0:
			apply_damage(o, "CT", int(tables["buildings"]["collapse_debris_damage"]), false, null, "falling debris")
	if attacker != null:
		attacker.showmanship += 2.0


func try_ignite(i: int, tn: int, cause: String) -> void:
	var tt: int = arena.terrain[i]
	if tt != Arena.T.LIGHT_WOODS and tt != Arena.T.HEAVY_WOODS:
		return
	if arena.burning(i, t) or arena.burned_at.has(i):
		return
	var w: String = conditions.get("weather", "clear")
	var need := tn + int(tables["conditions"]["weather"].get(w, {}).get("ignite", 0))
	if rng.roll2d6() < need:
		return
	ignite(i, cause)


func ignite(i: int, cause: String) -> void:
	var fc: Dictionary = tables["fire"]
	var key := "heavy_woods" if arena.terrain[i] == Arena.T.HEAVY_WOODS else "light_woods"
	var span: Array = fc["burn_seconds"][key]
	arena.fire_start[i] = t
	arena.fire_end[i] = t + rng.randf_range(float(span[0]), float(span[1]))
	arena.refresh_cell(i)
	_los_cache.clear()
	log_event({"k": "fire", "cell": i, "why": cause})


func _fire_turn() -> void:
	var fc: Dictionary = tables["fire"]
	var w: String = conditions.get("weather", "clear")
	var spread_bonus := int(tables["conditions"]["weather"].get(w, {}).get("spread", 0))
	var ign := int(tables["conditions"]["weather"].get(w, {}).get("ignite", 0))
	var cells := arena.fire_start.keys()
	cells.sort()
	for i in cells:
		if not arena.burning(i, t):
			if t >= float(arena.fire_end[i]) and not arena.burned_at.has(i):
				# burned down: woods are gone, only rough ground and ash remain
				arena.burned_from[i] = arena.terrain[i]
				arena.terrain[i] = Arena.T.ROUGH
				arena.burned_at[i] = arena.fire_end[i]
				arena.refresh_cell(i)
				_los_cache.clear()
			continue
		var x: int = i % arena.w
		var y: int = i / arena.w
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + o.x
			var ny: int = y + o.y
			if not arena.inside(nx, ny):
				continue
			var j := arena.idx(nx, ny)
			var tt: int = arena.terrain[j]
			if (tt != Arena.T.LIGHT_WOODS and tt != Arena.T.HEAVY_WOODS) or arena.fire_start.has(j):
				continue
			var need := int(fc["spread_tn"]) + ign - spread_bonus
			if arena.wind != Vector2i.ZERO and o == arena.wind:
				need = int(fc["spread_tn_downwind"]) + ign - spread_bonus
			if rng.roll2d6() >= need:
				ignite(j, "spreading fire")


func _explosion_effects(p: Vector2) -> void:
	var c := arena.cell_of(p)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := c.x + dx
			var y := c.y + dy
			if not arena.inside(x, y):
				continue
			var i := arena.idx(x, y)
			if arena.terrain[i] == Arena.T.BUILDING:
				damage_building(i, int(tables["buildings"]["explosion_damage"]), null)
			else:
				try_ignite(i, int(tables["fire"]["explosion_ignite_tn"]), "explosion")


func _hazards_tick() -> void:
	for hi in arena.hazards.size():
		var hz: Dictionary = arena.hazards[hi]
		var on := arena.hazard_active(hz, t)
		var was: bool = _hz_was_active.get(hi, false)
		_hz_was_active[hi] = on
		if not on:
			continue
		var p: Vector2 = hz["pos"]
		match hz["type"]:
			"flame_jets":
				if not was:
					log_event({"k": "hazard", "type": "flame_jets", "h": hi})
					var c := arena.cell_of(p)
					for dy in range(-1, 2):
						for dx in range(-1, 2):
							if arena.inside(c.x + dx, c.y + dy):
								try_ignite(arena.idx(c.x + dx, c.y + dy), 6, "flame jet")
				for o: CombatMech in mechs:
					if o.out or o.gait == CombatMech.Gait.JUMP or o.airborne:
						continue
					if o.pos.distance_to(p) < 13.0:
						o.heat += 3.0 * DT
						if not was:
							var leg := "LL" if rng.chance(0.5) else "RL"
							apply_damage(o, leg, 3, false, null, "flame jet")
			"steam_vents":
				for o: CombatMech in mechs:
					if not o.out and o.pos.distance_to(p) < 12.0:
						o.heat += 1.0 * DT
				if not was:
					log_event({"k": "hazard", "type": "steam_vents", "h": hi})
			"shock_pylons":
				if not was:
					var best: CombatMech = null
					var bd := float(hz.get("reach_m", 45.0))
					for o: CombatMech in mechs:
						if o.out:
							continue
						var d := o.pos.distance_to(p)
						if d < bd:
							bd = d
							best = o
					if best != null:
						log_event({"k": "hazard", "type": "shock_pylons", "h": hi, "tg": best.index})
						var side := side_from(p, best)
						if best.is_vehicle:
							_vehicle_hit(null, best, side, int(hz.get("damage", 5)), "shock pylon", false)
						else:
							var table: Dictionary = tables["hit_location"]["front" if side == "rear" else side]
							var loc: String = str(table[str(rng.roll2d6())]).trim_suffix("*")
							apply_damage(best, loc, int(hz.get("damage", 5)), side == "rear", null, "shock pylon")
							best.heat += 2.0


# ------------------------------------------------------------------ off-board support

const SUPPORT_KINDS := ["artillery", "air_strike"]


func support_left(team: int, kind: String) -> int:
	if team < 0 or team >= support.size():
		return 0
	return int(support[team].get(kind, 0))


## A fire mission from a battery off the map, or a strafing run by an aerospace fighter. Recorded by
## tick like any other order. pos in meters; ang is the direction of the fighter's run (radians).
func issue_support(team: int, kind: String, pos: Vector2, ang := 0.0) -> bool:
	if finished or not (kind in SUPPORT_KINDS) or support_left(team, kind) <= 0:
		return false
	var p := pos.clamp(Vector2.ZERO, arena.size_m())
	var inp := {"tick": ticks, "units": [], "cmd": "support",
		"arg": [team, kind, snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(ang, 0.001)]}
	inputs.append(inp)
	_do_command(inp, false)
	return true


func _call_support(team: int, kind: String, pos: Vector2, ang: float) -> void:
	if support_left(team, kind) <= 0:
		return
	support[team][kind] = int(support[team][kind]) - 1
	var S: Dictionary = tables["support"][kind]
	var at := t + float(S["delay_s"])
	var last := at
	if kind == "artillery":
		for n in int(S["shells"]):
			last = at + n * float(S["shell_gap_s"])
			strikes.append({"kind": kind, "team": team, "pos": pos, "ang": ang, "at": last})
	else:
		strikes.append({"kind": kind, "team": team, "pos": pos, "ang": ang, "at": at})
	log_event({"k": "support_call", "team": team, "kind": kind, "pos": [pos.x, pos.y], "ang": ang, "at": at, "until": last})


func _support_tick() -> void:
	var i := 0
	while i < strikes.size():
		if t >= float(strikes[i]["at"]):
			var st: Dictionary = strikes[i]
			strikes.remove_at(i)
			if str(st["kind"]) == "artillery":
				_shell_lands(st)
			elif str(st["kind"]) == "tube":
				_tube_lands(st)
			else:
				_strafe(st)
		else:
			i += 1
	if ticks % 20 == 10:
		for team in support.size():
			var sp: Dictionary = support[team]
			if sp["auto"] and t >= float(sp["next"]):
				_auto_support(team)


## One artillery shell: full damage where it lands, less out to the edge of the blast, friend or foe.
func _shell_lands(st: Dictionary) -> void:
	var S: Dictionary = tables["support"]["artillery"]
	var off := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * float(S["scatter_m"])
	var p := ((st["pos"] as Vector2) + off).clamp(Vector2.ZERO, arena.size_m())
	var radius := float(S["radius_m"])
	var inner := HEX * 0.5
	log_event({"k": "shell", "team": int(st["team"]), "pos": [p.x, p.y], "r": radius})
	for o: CombatMech in mechs:
		if o.out or o.airborne or o.gait == CombatMech.Gait.JUMP:
			continue
		var d := o.pos.distance_to(p)
		if d <= radius:
			_area_damage(o, int(S["damage"]) if d <= inner else int(S["splash"]), p, "artillery")
	var c := arena.cell_of(p)
	var rc := int(ceil(radius / Arena.CELL))
	for dy in range(-rc, rc + 1):
		for dx in range(-rc, rc + 1):
			if not arena.inside(c.x + dx, c.y + dy):
				continue
			var i := arena.idx(c.x + dx, c.y + dy)
			var d2 := arena.center_of_index(i).distance_to(p)
			if d2 > radius:
				continue
			if arena.terrain[i] == Arena.T.BUILDING:
				damage_building(i, int(S["building_damage"]) if d2 <= inner else int(S["building_damage"]) / 4, null)
			elif d2 <= inner * 2.0:
				try_ignite(i, int(S["ignite_tn"]), "artillery")


## Blast damage: in 5-point groups on a 'Mech or vehicle, from the side the shell fell on; on every
## suit of a battle armour squad; doubled against a platoon.
func _area_damage(target: CombatMech, dmg: int, from: Vector2, cause: String) -> void:
	if target.destroyed or dmg <= 0:
		return
	if target.is_infantry:
		if target.battle_armor:
			for loc in target.snap_locs.duplicate():
				if not target.loc_destroyed[loc]:
					_trooper_damage(target, loc, dmg, null, cause)
		else:
			var I: Dictionary = tables["infantry"]
			_platoon_losses(target, int(ceil(dmg * float(I["area_mult"]) / float(I["damage_div"]))), null, cause, true)
		return
	var side := side_from(from, target)
	var left := dmg
	var was := _dclass
	_dclass = "area"
	while left > 0 and not target.destroyed:
		var g := mini(5, left)
		left -= g
		_hit_location_damage(null, target, side, g, cause)
	_dclass = was


## A fighter's strafing run along a strip: everything under it is attacked, friend or foe.
func _strafe(st: Dictionary) -> void:
	var S: Dictionary = tables["support"]["air_strike"]
	var dir := Vector2.from_angle(float(st["ang"]))
	var perp := dir.orthogonal()
	var c: Vector2 = (st["pos"] as Vector2) + perp * rng.randf_range(-float(S["scatter_m"]), float(S["scatter_m"]))
	var half := float(S["length_m"]) * 0.5
	var a := c - dir * half
	var b := c + dir * half
	log_event({"k": "strafe", "team": int(st["team"]), "from": [a.x, a.y], "to": [b.x, b.y]})
	for o: CombatMech in mechs:
		if o.out:
			continue
		var rel := o.pos - c
		if absf(rel.dot(dir)) > half or absf(rel.dot(perp)) > float(S["width_m"]) * 0.5:
			continue
		var tn := int(S["to_hit"]) + target_movement_mod(o)
		var roll := rng.roll2d6()
		log_event({"k": "strafe_hit", "tg": o.index, "tn": tn, "roll": roll, "hit": roll >= tn})
		if roll < tn:
			continue
		for _h in int(S["hits"]):
			if o.destroyed:
				break
			if o.is_infantry and not o.battle_armor:
				var I: Dictionary = tables["infantry"]
				_platoon_losses(o, int(ceil(int(S["damage"]) * float(I["area_mult"]) / float(I["damage_div"]))), null, "air strike", true)
			else:
				_hit_location_damage(null, o, side_from(a, o), int(S["damage"]), "air strike")
	var seen := {}
	var steps := int(ceil(half * 2.0 / Arena.CELL))
	for k in steps + 1:
		var q := a.lerp(b, k / float(maxi(1, steps)))
		var cq := arena.cell_of(q)
		if not arena.inside(cq.x, cq.y):
			continue
		var i := arena.idx(cq.x, cq.y)
		if seen.has(i):
			continue
		seen[i] = true
		if arena.terrain[i] == Arena.T.BUILDING:
			damage_building(i, int(S["building_damage"]), null)
		else:
			try_ignite(i, int(S["ignite_tn"]), "air strike")


## Units of the other side this team can see: close by, or in range with a clear line of sight.
func _visible_enemies(team: int) -> Array:
	var out: Array = []
	var rng_m := float(tables["merc_battle"]["spot_range_m"])
	for o: CombatMech in mechs:
		if o.out or o.team == team:
			continue
		if team == 0 and merc:
			if o.spotted:
				out.append(o)
			continue
		for f: CombatMech in mechs:
			if f.out or f.team != team:
				continue
			var d := f.pos.distance_to(o.pos)
			if d < 90.0 or (d <= rng_m and los_between(f, o)["clear"]):
				out.append(o)
				break
	return out


## How a unit has been travelling over the last turn, in meters a second (circling counts for little).
func _drift(m: CombatMech) -> Vector2:
	if m.trail.is_empty() or m.immobile or m.shutdown:
		return Vector2.ZERO
	var dt := t - float(m.trail[0][0])
	if dt < 1.0:
		return Vector2.ZERO
	return (m.pos - (m.trail[0][1] as Vector2)) / dt


## The side's own fire control: calls a mission on the best cluster of enemies it can see, aimed at
## where they are heading, worth less the faster they move, and never close to its own troops.
func _auto_support(team: int) -> void:
	var sp: Dictionary = support[team]
	var kinds: Array = []
	for k in SUPPORT_KINDS:
		if int(sp.get(k, 0)) > 0:
			kinds.append(k)
	if kinds.is_empty():
		sp["auto"] = false
		return
	var seen := _visible_enemies(team)
	if seen.is_empty():
		return
	var best_score := 0.8
	var best: Dictionary = {}
	for kind in kinds:
		var S: Dictionary = tables["support"][kind]
		var lead := float(S["delay_s"]) * 0.85
		for o: CombatMech in seen:
			if o.airborne and kind == "artillery":
				continue
			var v := _drift(o)
			var aim := (o.pos + v * lead).clamp(Vector2.ZERO, arena.size_m())
			var angs := [0.0]
			if kind == "air_strike":
				# along the target's own track if it has one: then being early or late still catches it
				angs = [v.angle()] if v.length() > 1.5 else [0.0, PI * 0.25, PI * 0.5, PI * 0.75]
			for ang in angs:
				var score := _support_score(team, kind, S, aim, float(ang), lead)
				if score > best_score:
					best_score = score
					best = {"kind": kind, "pos": aim, "ang": float(ang)}
	if best.is_empty():
		return
	_call_support(team, str(best["kind"]), best["pos"], float(best["ang"]))
	sp["next"] = t + float(sp["gap"])


## What a mission at p is worth to a team, judged by where everyone should be when it arrives:
## enemies under it count, its own troops anywhere near it rule it out.
func _support_score(team: int, kind: String, S: Dictionary, p: Vector2, ang: float, lead: float) -> float:
	var score := 0.0
	var dir := Vector2.from_angle(ang)
	for o: CombatMech in mechs:
		if o.out:
			continue
		var v := _drift(o)
		var spots := [o.pos + v * lead]
		# its own troops must be well clear, now and when it lands: a unit covers ground in that time
		var clear := 60.0
		if o.team == team:
			spots.append(o.pos)
			spots.append(o.pos + v * lead * 0.5)
			clear = 110.0
		var w := 0.0
		var near := false
		for q: Vector2 in spots:
			if kind == "artillery":
				var d := q.distance_to(p)
				var reach := float(S["radius_m"]) + float(S["scatter_m"])
				near = near or d <= reach + clear
				if d <= HEX * 0.5 + float(S["scatter_m"]) * 0.5:
					w = 1.0
				elif d <= reach:
					w = maxf(w, 0.6)
			else:
				var rel := q - p
				var along := absf(rel.dot(dir))
				var across := absf(rel.dot(dir.orthogonal()))
				near = near or (along <= float(S["length_m"]) * 0.5 + clear and across <= float(S["width_m"]) * 0.5 + float(S["scatter_m"]) + clear)
				if along <= float(S["length_m"]) * 0.5 and across <= float(S["width_m"]) * 0.5:
					# a strip is narrow: a target crossing it is as good as missed
					w = 0.9 / (1.0 + absf(v.dot(dir.orthogonal())) * lead / float(S["width_m"]))
		if o.team == team:
			if near:
				return -1.0
			continue
		if kind == "artillery":
			w /= 1.0 + v.length() * lead / (float(S["radius_m"]) * 2.0)
		if o.is_infantry and not o.battle_armor:
			w *= 0.7
		if o.airborne and kind == "artillery":
			w = 0.0
		score += w
	return score


# ------------------------------------------------------------------ physical attacks

func _phys_tn(m: CombatMech, target: CombatMech, base: int) -> int:
	var tn := m.piloting + base + attacker_movement_mod(m) + target_movement_mod(target)
	if m.has_trait("brawler"):
		tn -= 1
	if target.gait == CombatMech.Gait.PRONE:
		tn += int(tables["target_mod"]["prone_adjacent"])
	if target.shutdown or not target.conscious:
		tn += int(tables["target_mod"]["immobile"])
	return tn


func physical(m: CombatMech, target: CombatMech, kind: String, arm := "") -> void:
	match kind:
		"charge":
			_charge(m, target)
			return
		"push":
			_push(m, target)
			return
		"club":
			_club(m, target)
			return
	var ph: Dictionary = tables["physical"][kind]
	m.physical_ready_at = t + TURN
	var tn := _phys_tn(m, target, int(ph["to_hit"]))
	var dmg := phys_damage(m, ph)
	if kind == "punch":
		var acts := m.count_hit(arm, "upper_arm") + m.count_hit(arm, "lower_arm")
		tn += acts * 2 + m.count_hit(arm, "hand")
		for k in acts:
			dmg = int(ceil(dmg / 2.0))
	elif kind == "kick":
		for leg in ["LL", "RL"]:
			var acts2 := m.count_hit(leg, "upper_leg") + m.count_hit(leg, "lower_leg")
			tn += acts2 * 2 + m.count_hit(leg, "foot")
		if m.talons:
			dmg = int(ceil(dmg * float(tables["gear"]["talons_kick"])))
	if (m.design.myomer == "tsm" and m.heat >= 9.0) or m.always_strong:
		dmg *= 2
	var roll := rng.roll2d6()
	var hit := roll >= tn
	log_event({"k": "physical", "m": m.index, "tg": target.index, "w": kind, "tn": tn, "roll": roll, "hit": hit})
	if arm != "":
		for wi in m.weapons:
			if m.mounts[wi]["loc"] == arm:
				m.mounts[wi]["cooldown"] = maxf(m.mounts[wi]["cooldown"], TURN * 0.5)
	if not hit:
		if kind == "kick":
			psr(m, 0, "missed kick")
		return
	m.showmanship += 3.0
	var side := attack_side(m, target)
	var tbl := "hit_location"
	if kind == "punch":
		tbl = "punch_location"
	elif kind == "kick":
		tbl = "kick_location"
	var key := "front" if side == "rear" else side
	if target.is_vehicle:
		_vehicle_hit(m, target, side, dmg, kind, false)
		return
	var loc := ""
	if tbl == "hit_location":
		loc = str(tables[tbl][key][str(rng.roll2d6())]).trim_suffix("*")
	else:
		loc = str(tables[tbl][key][str(rng.d6())])
	_dclass = "physical"
	apply_damage(target, loc, dmg, side == "rear", m, kind)
	_dclass = "other"
	if kind == "kick" and not target.out:
		psr(target, 0, "kicked")


## Damage of a punch, kick or hand weapon before myomer and damage to the limb.
func phys_damage(m: CombatMech, ph: Dictionary) -> int:
	if ph.has("fixed"):
		return int(ph["fixed"])
	return int(ceil(m.tons() / float(ph["per_tons"]))) + int(ph.get("bonus", 0))


func _charge(m: CombatMech, target: CombatMech) -> void:
	var ph: Dictionary = tables["physical"]["charge"]
	m.physical_ready_at = t + TURN
	var hexes := clampi(hexes_moved(m), 1, maxi(1, m.run_mp()))
	var tn := _phys_tn(m, target, int(ph["to_hit"])) + (m.piloting - target.piloting)
	var roll := rng.roll2d6()
	var hit := roll >= tn
	log_event({"k": "charge", "m": m.index, "tg": target.index, "tn": tn, "roll": roll, "hit": hit, "hexes": hexes})
	if not hit:
		return
	m.showmanship += 6.0
	var dmg := int(ceil(m.tons() / float(ph["per_tons"]))) * hexes
	if (m.design.myomer == "tsm" and m.heat >= 9.0) or m.always_strong:
		dmg *= 2
	if _has_gear(m, "spikes"):
		dmg += int(tables["gear"]["spikes_charge"])
	var back := int(ceil(target.tons() / 10.0))
	if _has_gear(target, "spikes"):
		back += int(tables["gear"]["spikes_charge"])
	_dclass = "physical"
	cluster_damage(target, dmg, attack_side(m, target), "hit_location", m, "charge")
	cluster_damage(m, back, "front", "hit_location", target, "charge recoil")
	_dclass = "other"
	if not target.out:
		psr(target, 2, "charged")
	if not m.out:
		psr(m, 2, "charging")


func _dfa(m: CombatMech, target: CombatMech) -> void:
	var ph: Dictionary = tables["physical"]["dfa"]
	m.physical_ready_at = t + TURN
	var tn := m.piloting + int(ph["to_hit"]) + int(tables["attacker_movement"]["jump"]) + target_movement_mod(target) + (m.piloting - target.piloting)
	if target.gait == CombatMech.Gait.PRONE:
		tn += int(tables["target_mod"]["prone_adjacent"])
	var roll := rng.roll2d6()
	var hit := roll >= tn
	log_event({"k": "dfa", "m": m.index, "tg": target.index, "tn": tn, "roll": roll, "hit": hit})
	if not hit:
		# a missed death from above slams the attacker into the ground
		fall(m, "missed death from above", true)
		return
	m.showmanship += 12.0
	var dmg := int(ceil(m.tons() / float(ph["per_tons"]))) * int(ph["mult"])
	if m.design.myomer == "tsm" and m.heat >= 9.0:
		dmg *= 2
	cluster_damage(target, dmg, attack_side(m, target), "punch_location", m, "death from above")
	cluster_damage(m, int(ceil(m.tons() / float(ph["self_per_tons"]))), "front", "kick_location", null, "death from above landing")
	if not target.out:
		psr(target, 2, "hit by death from above")
	if not m.out:
		psr(m, 4, "death from above landing")


func _push(m: CombatMech, target: CombatMech) -> void:
	var ph: Dictionary = tables["physical"]["push"]
	m.physical_ready_at = t + TURN
	var tn := _phys_tn(m, target, int(ph["to_hit"]))
	var roll := rng.roll2d6()
	var hit := roll >= tn
	log_event({"k": "push", "m": m.index, "tg": target.index, "tn": tn, "roll": roll, "hit": hit})
	if not hit:
		return
	m.showmanship += 2.0
	var dir := (target.pos - m.pos).normalized()
	var dest := target.pos + dir * float(ph["distance_m"])
	var di := arena.cell_index(dest)
	if arena.terrain[di] == Arena.T.BUILDING:
		# shoved into a building: both take a beating
		damage_building(di, int(ceil(target.tons() / 10.0)), m)
		cluster_damage(target, int(ceil(target.tons() / 10.0)), "rear", "hit_location", m, "slammed into a building")
	elif arena.passable_p(dest):
		target.pos = dest
		target.path = PackedVector2Array()
	if not target.out:
		psr(target, 1, "pushed")


func _club(m: CombatMech, target: CombatMech) -> void:
	var ph: Dictionary = tables["physical"]["club"]
	m.physical_ready_at = t + TURN
	var tn := _phys_tn(m, target, int(ph["to_hit"]))
	var roll := rng.roll2d6()
	var hit := roll >= tn
	log_event({"k": "physical", "m": m.index, "tg": target.index, "w": "club", "tn": tn, "roll": roll, "hit": hit, "club": m.club_kind})
	if not hit:
		return
	m.showmanship += 5.0
	var dmg := int(ceil(m.tons() / float(ph["per_tons"])))
	if m.design.myomer == "tsm" and m.heat >= 9.0:
		dmg *= 2
	var side := attack_side(m, target)
	if target.is_vehicle:
		_vehicle_hit(m, target, side, dmg, m.club_kind, false)
	else:
		var loc := str(tables["hit_location"]["front" if side == "rear" else side][str(rng.roll2d6())]).trim_suffix("*")
		apply_damage(target, loc, dmg, side == "rear", m, m.club_kind)
	m.club_uses -= 1
	if m.club_uses <= 0:
		log_event({"k": "club_break", "m": m.index, "club": m.club_kind})


## Rips a tree or a steel girder loose to swing as a club (takes the 'Mech's physical action).
func pick_up_club(m: CombatMech) -> bool:
	if m.club_uses > 0 or not m.arms_free() or t < m.physical_ready_at:
		return false
	var c := arena.cell_of(m.pos)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x := c.x + dx
			var y := c.y + dy
			if not arena.inside(x, y):
				continue
			var tt: int = arena.terrain[arena.idx(x, y)]
			if tt == Arena.T.HEAVY_WOODS or tt == Arena.T.RUBBLE:
				m.club_kind = "tree" if tt == Arena.T.HEAVY_WOODS else "girder"
				m.club_uses = int(tables["physical"]["club"]["uses"])
				m.physical_ready_at = t + TURN
				log_event({"k": "club_pickup", "m": m.index, "club": m.club_kind})
				return true
	return false


# ------------------------------------------------------------------ movement

func start_jump(m: CombatMech, dest: Vector2, face_at: Vector2, dfa_target := -1) -> bool:
	var jmp := m.jump_mp()
	if jmp <= 0 or t < m.jump_ready_at or m.gait == CombatMech.Gait.PRONE:
		return false
	var dist := m.pos.distance_to(dest)
	if dist > jmp * HEX or dist < 20.0 or not arena.passable_p(dest):
		return false
	if dfa_target < 0:
		for o: CombatMech in mechs:
			if o != m and not o.out and o.pos.distance_to(dest) < 20.0:
				return false
	m.jump_from = m.pos
	m.jump_to = dest
	m.jump_t = 0.0
	m.jump_dur = 1.4 + dist / 90.0
	m.gait = CombatMech.Gait.JUMP
	m.last_jump_t = t
	m.jump_ready_at = t + TURN
	m.heat += float(maxi(3, int(ceil(dist / HEX))))
	m.path = PackedVector2Array()
	m.dfa_target = dfa_target
	m.masc_on = false
	m.facing = (face_at - dest).angle() if face_at.distance_to(dest) > 1.0 else m.facing
	log_event({"k": "jump", "m": m.index, "from": [m.pos.x, m.pos.y], "to": [dest.x, dest.y], "dfa": dfa_target})
	return true


func _move(m: CombatMech) -> void:
	if m.out:
		return
	if m.is_vehicle:
		_move_vehicle(m)
		return
	if m.shutdown or not m.conscious:
		return
	if m.gait == CombatMech.Gait.PRONE:
		if t >= m.stand_attempt_at:
			try_stand(m)
		return
	if m.gait == CombatMech.Gait.JUMP:
		m.jump_t += DT
		var f := clampf(m.jump_t / m.jump_dur, 0.0, 1.0)
		m.pos = m.jump_from.lerp(m.jump_to, f)
		if f >= 1.0:
			m.gait = CombatMech.Gait.STAND
			m.last_jump_t = t
			log_event({"k": "land", "m": m.index})
			if m.dfa_target >= 0:
				var tg: CombatMech = mechs[m.dfa_target]
				m.dfa_target = -1
				if not tg.out and tg.gait != CombatMech.Gait.JUMP and tg.pos.distance_to(m.pos) < 34.0:
					# land next to the victim, not inside it
					m.pos = tg.pos + (m.jump_from - tg.pos).normalized() * 18.0
					_dfa(m, tg)
					return
			if m.gyro_hits > 0 or m.count_hit("LL", "hip") + m.count_hit("RL", "hip") > 0 or m.legs_destroyed() > 0:
				psr(m, 0, "landing with damage")
		return
	# twist the torso toward the AI's chosen target
	var tgt: CombatMech = ai.target_of(m)
	if tgt != null:
		var want := clampf(wrap_angle(angle_to(m, tgt) - m.facing), -PI / 3.0, PI / 3.0)
		m.twist = move_toward(m.twist, want, deg_to_rad(120.0) * DT)
	if m.path.is_empty():
		if m.gait != CombatMech.Gait.STAND:
			m.gait = CombatMech.Gait.STAND
		if tgt != null:
			var want_f := angle_to(m, tgt)
			m.facing = _turn(m.facing, want_f, deg_to_rad(6.0 * maxi(1, m.walk_mp())) * DT)
		return
	var wp: Vector2 = m.path[0]
	var dir := wp - m.pos
	if dir.length() < 2.5:
		m.path.remove_at(0)
		return
	var running := m.move_mode == CombatMech.Gait.RUN and m.run_mp() > m.walk_mp()
	var mp := m.run_mp() if running else m.walk_mp()
	if mp <= 0:
		m.gait = CombatMech.Gait.STAND
		return
	if running and m.masc_on:
		m.masc_used = true
	var move_ang := dir.angle()
	var back := m.backing and not running
	var want_face := move_ang + PI if back else move_ang
	m.facing = _turn(m.facing, want_face, deg_to_rad(6.0 * mp + 12.0) * DT)
	var c := arena.cell_of(m.pos)
	var cost := arena.move_cost(c.x, c.y)
	var speed := mp * MPS / cost
	var nxt := arena.cell_of(m.pos + dir.normalized() * 6.0)
	if arena.height[arena.idx(nxt.x, nxt.y)] > arena.height[arena.idx(c.x, c.y)]:
		speed /= 1.5
	var off := absf(wrap_angle(want_face - m.facing))
	if off > deg_to_rad(40.0):
		speed *= 0.25
	var step_len := minf(speed * DT, dir.length())
	var np := m.pos + dir.normalized() * step_len
	if not arena.passable_p(np):
		m.path = PackedVector2Array()
		return
	for o: CombatMech in mechs:
		if o != m and not o.out and o.gait != CombatMech.Gait.JUMP and not o.airborne and np.distance_to(o.pos) < 20.0 and np.distance_to(o.pos) < m.pos.distance_to(o.pos):
			return
	m.pos = np
	if running:
		m.gait = CombatMech.Gait.RUN
		m.last_run_t = t
	else:
		m.gait = CombatMech.Gait.WALK
		m.last_walk_t = t


static func _turn(cur: float, want: float, max_step: float) -> float:
	var d := wrap_angle(want - cur)
	if absf(d) <= max_step:
		return wrap_angle(want)
	return wrap_angle(cur + signf(d) * max_step)


# ------------------------------------------------------------------ heat and the 10-second turn phase

func _heat_tick(m: CombatMech) -> void:
	if (m.out and m.destroyed) or m.is_vehicle:
		return
	var rate := 0.0
	if not m.no_move_heat:
		match m.gait:
			CombatMech.Gait.WALK:
				rate += float(tables["movement_heat_per_turn"]["walk"]) / TURN
			CombatMech.Gait.RUN:
				rate += float(tables["movement_heat_per_turn"]["run"]) / TURN
	for sg in m.signatures_on():
		rate += float(sg["heat"]) / TURN
	rate += m.engine_hits * float(tables["engine_hit_heat"]) / TURN
	var ci := arena.cell_index(m.pos)
	if arena.burning(ci, t):
		rate += float(tables["fire"]["heat_per_turn_in_fire"]) / TURN
	var diss := m.dissipation() / TURN
	var dep := arena.depth[ci]
	if dep > 0:
		diss += minf(6.0, float(dep) * 2.0) / TURN
	m.heat = maxf(0.0, m.heat + (rate - diss) * DT)


func _has_gear(m: CombatMech, misc: String) -> bool:
	for mt in m.mounts:
		if not mt["destroyed"] and str(mt["item"].get("misc", "")) == misc:
			return true
	return false


## Anti-personnel and anti-battle-armour pods go off at infantry climbing the 'Mech. One use each.
func _pods_fire(m: CombatMech, infantry: CombatMech) -> void:
	if m.pods.is_empty() or m.shutdown or not m.conscious:
		return
	var P: Dictionary = tables["gear"]["pods"]
	for mi in m.pods:
		var mt: Dictionary = m.mounts[mi]
		if mt["destroyed"] or mt.get("used", false):
			continue
		mt["used"] = true
		log_event({"k": "pod", "m": m.index, "tg": infantry.index, "w": str(mt["item"]["name"])})
		if infantry.battle_armor:
			for loc in infantry.snap_locs.duplicate():
				if not infantry.loc_destroyed[loc]:
					_trooper_damage(infantry, loc, int(P["suit_damage"]), m, str(mt["item"]["name"]))
		else:
			var d: Array = P["platoon_losses"]
			_platoon_losses(infantry, rng.randi_range(int(d[0]), int(d[1])), m, str(mt["item"]["name"]), true)
		return


## Once a turn: HarJel seals armor back up, and a 'Mech running hot spends a coolant pod or its
## emergency cooling.
func _gear_turn(m: CombatMech) -> void:
	for h in m.harjel:
		var mt: Dictionary = m.mounts[int(h[0])]
		var loc: String = mt["loc"]
		if mt["destroyed"] or m.loc_destroyed[loc]:
			continue
		var mx := int(m.max_armor.get(loc, 0))
		if int(m.armor.get(loc, 0)) < mx:
			m.armor[loc] = mini(mx, int(m.armor[loc]) + int(h[1]))
	if m.shutdown:
		return
	var C: Dictionary = tables["gear"]["coolers"]
	for c in m.coolers:
		var K: Dictionary = C[str(c["kind"])]
		var mt2: Dictionary = m.mounts[int(c["mount"])]
		if int(c["uses"]) <= 0 or mt2["destroyed"] or m.heat < float(K["at_heat"]):
			continue
		c["uses"] = int(c["uses"]) - 1
		if mt2["kind"] == "ammo":
			mt2["shots"] = 0
		var shed := float(K.get("shed", 0.0)) + float(K.get("per_sink", 0.0)) * (m.sinks_total - m.sinks_lost)
		m.heat = maxf(0.0, m.heat - shed)
		log_event({"k": "coolant", "tg": m.index, "w": str(mt2["item"]["name"]), "shed": int(shed)})
		break


func _turn_phase() -> void:
	_fire_turn()
	var masc_tn: Array = tables["masc"]["tn"]
	for m: CombatMech in mechs:
		m.dmg_window = 0.0
		m.dmg_window_psr = false
		if m.out or m.is_vehicle:
			continue
		# MASC: every turn it ran, roll against a climbing target number or wreck the hips
		if m.masc_used:
			var need := int(masc_tn[mini(m.masc_level, masc_tn.size() - 1)])
			var roll2 := rng.roll2d6()
			if roll2 < need:
				log_event({"k": "masc_fail", "tg": m.index, "tn": need, "roll": roll2})
				m.masc_on = false
				for leg in ["LL", "RL"]:
					var row: Array = m.slots[leg]
					for i in row.size():
						if row[i]["s"] == "hip" and not row[i]["hit"]:
							m._mark_slot_hit(leg, i)
				psr(m, 0, "MASC failure")
			m.masc_level = mini(m.masc_level + 1, masc_tn.size() - 1)
		else:
			m.masc_level = maxi(0, m.masc_level - 1)
		m.masc_used = false
		_gear_turn(m)
		var h := m.heat
		if m.shutdown:
			var need0 := 0
			for row in tables["heat_shutdown"]:
				if h >= float(row[0]):
					need0 = int(row[1])
			if need0 == 0 or rng.roll2d6() >= need0:
				m.shutdown = false
				log_event({"k": "restart", "tg": m.index})
			continue
		var need2 := 0
		for row in tables["heat_shutdown"]:
			if h >= float(row[0]):
				need2 = int(row[1])
		if need2 > 0:
			var roll := rng.roll2d6()
			if roll < need2:
				m.shutdown = true
				log_event({"k": "shutdown", "tg": m.index, "heat": int(h), "roll": roll, "tn": need2})
				fall(m, "shutdown")
		var need3 := 0
		for row in tables["heat_ammo"]:
			if h >= float(row[0]):
				need3 = int(row[1])
		if need3 > 0 and rng.roll2d6() < need3:
			var best := -1
			var most := 0
			for bi in m.bins:
				var b: Dictionary = m.mounts[bi]
				if not b["destroyed"] and int(b["shots"]) > most and b["item"].get("explosive", true):
					most = int(b["shots"])
					best = bi
			if best >= 0:
				log_event({"k": "heat_ammo", "tg": m.index})
				var b2: Dictionary = m.mounts[best]
				var slot: Array = b2["slots"][0]
				m._mark_slot_hit(slot[0], slot[1])
				ammo_explosion(m, best, null)
		if m.life_support_hit:
			for row in tables["heat_pilot_life_support"]:
				if h >= float(row[0]):
					pilot_hit(m, int(row[1]), "life support")
					break


# ------------------------------------------------------------------ end of fight

func _check_end() -> void:
	var alive := {}
	for m: CombatMech in mechs:
		if not m.out or m.out_reason == "reserve":
			alive[m.team] = true
	if merc:
		_check_end_merc(alive)
		return
	if alive.size() <= 1:
		var winner: int = alive.keys()[0] if alive.size() == 1 else -1
		_finish(winner, "knockout" if winner >= 0 else "mutual destruction")
	elif t >= time_limit():
		# judges' decision on damage dealt
		var score := {}
		for m: CombatMech in mechs:
			score[m.team] = float(score.get(m.team, 0.0)) + m.dmg_dealt + m.crits_dealt * 3
		var best := -1
		var best_s := -1.0
		var tie := false
		for team in score:
			if score[team] > best_s:
				best_s = score[team]
				best = team
				tie = false
			elif score[team] == best_s:
				tie = true
		_finish(-1 if tie else best, "judges' decision")


func _finish(winner: int, how: String) -> void:
	finished = true
	if record:
		_snapshot()
	var ms: Array = []
	for m: CombatMech in mechs:
		var hit_slots: Array = []
		for loc in ([] if m.is_vehicle else MechDesign.LOCS):
			var row: Array = m.slots[loc]
			for i in row.size():
				if row[i]["hit"] and row[i]["s"] != "":
					hit_slots.append([loc, i])
		var ammo := {}
		for bi in m.bins:
			ammo[str(bi)] = int(m.mounts[bi]["shots"])
		var dead_mounts: Array = []
		if m.is_vehicle:
			for mi in m.mounts.size():
				if m.mounts[mi]["destroyed"]:
					dead_mounts.append(mi)
		ms.append({
			"vehicle": m.is_vehicle, "vstate": m.vehicle_state() if m.is_vehicle else {}, "dead_mounts": dead_mounts,
			"infantry": m.is_infantry, "troopers": m.troopers_alive(),
			"exited": m.exited, "withdrew": m.withdrew, "never_arrived": m.out_reason == "reserve",
			"crew_killed": m.crew_killed, "controller": m.controller, "conscious": m.conscious,
			"index": m.index, "team": m.team, "name": m.name, "out": m.out, "reason": m.out_reason,
			"out_time": m.out_time if m.out else t, "destroyed": m.destroyed, "yielded": m.yielded, "ejected": m.ejected,
			"kills": m.kills, "killer": m.killer, "dmg_dealt": m.dmg_dealt, "dmg_taken": m.dmg_taken, "shots": m.shots,
			"hits": m.hits, "crits": m.crits_dealt, "pilot_hits": m.pilot_hits, "showmanship": m.showmanship,
			"armor": m.armor.duplicate(), "internal": m.internal.duplicate(), "hit_slots": hit_slots, "ammo": ammo,
		})
	# placement for free-for-alls: the last 'Mech standing first, then by how long each lasted
	var order := range(mechs.size())
	order.sort_custom(func(a, b):
		var ma: Dictionary = ms[a]
		var mb: Dictionary = ms[b]
		if (ma["team"] == winner) != (mb["team"] == winner):
			return ma["team"] == winner
		return float(ma["out_time"]) > float(mb["out_time"]))
	result = {"winner": winner, "how": how, "duration": snappedf(t, 0.1), "mechs": ms, "placement": order,
		"inputs": inputs.duplicate(), "teams": team_count}
	if merc:
		var blds := {}
		for key in ["defend_cells", "attack_cells"]:
			for ci in arena.objectives.get(key, []):
				blds[str(ci)] = arena.terrain[int(ci)] == Arena.T.BUILDING
		result["buildings"] = blds
		result["recon"] = recon_done.duplicate()
		result["routed"] = _routed.keys()
	log_event({"k": "end", "winner": winner, "how": how})


# ------------------------------------------------------------------ combat vehicles (Total Warfare)

## A 'Mech location name used by a generic effect (debris, flame jets) mapped onto a vehicle.
func _vloc(target: CombatMech, loc: String, rear := false) -> String:
	if target.internal.has(loc):
		return loc
	if rear:
		return "RR"
	match loc:
		"HD", "CT":
			return "TU" if target.internal.has("TU") else "FR"
		"LT", "LA", "LL":
			return "LS"
		"RT", "RA", "RL":
			return "RS"
		"CTR", "LTR", "RTR":
			return "RR"
	return "FR"


func _vside_loc(target: CombatMech, side: String) -> String:
	match side:
		"rear":
			return "RR"
		"left":
			return "LS"
		"right":
			return "RS"
	return "FR"


## One hit on a vehicle: roll the vehicle (or VTOL) hit location table, apply damage, then any
## critical and motive system rolls it calls for. Rotor hits take weapon damage / 10 (rounded up).
func _vehicle_hit(attacker: CombatMech, target: CombatMech, side: String, dmg: int, cause: String, weapon := true) -> String:
	if target.destroyed:
		return ""
	if target.is_infantry:
		return _squad_hit(attacker, target, dmg, cause)
	var col := "front" if side == "front" else ("rear" if side == "rear" else "side")
	var vtol := target.motion == "vtol"
	var tbl: Dictionary = tables["vtol_hit_location" if vtol else "vehicle_hit_location"][col]
	var code: String = tbl[str(rng.roll2d6())]
	var crit := code.find("*") >= 0
	var motive := code.find("!") >= 0
	var loc := code.replace("*", "").replace("!", "")
	if loc == "S":
		loc = "RS" if side == "right" else "LS"
	if loc == "TU" and not target.internal.has("TU"):
		loc = _vside_loc(target, side)
	var d := dmg
	if loc == "RO" and weapon:
		d = int(ceil(dmg / float(tables["vehicle"]["rotor_damage_div"])))
	_vehicle_damage(target, loc, d, attacker, cause)
	if target.destroyed or target.out:
		return loc
	if loc == "RO":
		target.cruise_lost += 1
		log_event({"k": "motive", "tg": target.index, "res": "rotor"})
		if target.airborne and target.walk_mp() <= 0:
			_vtol_engine_out(target, attacker)
	if crit and not target.out:
		_vehicle_crit(target, loc, attacker)
	if motive and not vtol and not target.out:
		_motive_roll(target, side, attacker)
	return loc


## Damage to one vehicle location: armor, then structure. No transfer: a location with no structure
## left destroys the vehicle, and any structure damage forces a critical hit roll.
func _vehicle_damage(target: CombatMech, loc: String, dmg: int, attacker: CombatMech, cause: String) -> void:
	if target.destroyed or dmg <= 0:
		return
	if target.is_infantry:
		_squad_hit(attacker, target, dmg, cause)
		return
	if not target.internal.has(loc):
		loc = _vloc(target, loc)
	var a := int(target.armor.get(loc, 0))
	var vfx: Dictionary = target.armor_fx
	if not vfx.is_empty() and a > 0:
		dmg = _armor_adjust(dmg, vfx)
	var vsoak := 2 if vfx.get("armor_double", false) else 1
	var ab := mini(a * vsoak, dmg)
	var vgone := int(ceil(float(ab) / vsoak))
	target.armor[loc] = a - vgone
	var rem := dmg - ab
	var applied := vgone
	var struct_hit := 0
	if rem > 0:
		var s0 := int(target.internal[loc])
		struct_hit = mini(s0, rem)
		target.internal[loc] = s0 - struct_hit
		applied += struct_hit
	if attacker != null and attacker != target:
		attacker.dmg_dealt += applied
	target.dmg_taken += applied
	log_event({"k": "dmg", "m": attacker.index if attacker else -1, "tg": target.index, "loc": loc, "dmg": dmg,
		"rear": loc == "RR", "w": cause})
	if int(target.internal[loc]) <= 0 and rem > 0:
		target.loc_destroyed[loc] = true
		log_event({"k": "loc_destroyed", "tg": target.index, "loc": loc})
		var why := "%s destroyed" % VehicleDesign.VLOC_NAMES.get(loc, loc).to_lower()
		if loc == "RO":
			why = "rotor destroyed, it crashes"
		kill(target, attacker, why)
		return
	if struct_hit > 0:
		_vehicle_crit(target, loc, attacker)


# ------------------------------------------------------------------ infantry and battle armour

## Damage that reaches a squad. Battle armour: one suit takes the whole hit (armour, then the trooper
## inside; the excess is lost). A platoon loses a trooper for every `damage_div` points, rounded up.
func _squad_hit(attacker: CombatMech, target: CombatMech, dmg: int, cause: String) -> String:
	if target.destroyed or dmg <= 0:
		return ""
	if not target.battle_armor:
		_platoon_losses(target, int(ceil(dmg / float(tables["infantry"]["damage_div"]))), attacker, cause, false)
		return "PL"
	var alive: Array = []
	for loc in target.snap_locs:
		if not target.loc_destroyed[loc]:
			alive.append(loc)
	if alive.is_empty():
		return ""
	var loc: String = alive[rng.randi_range(0, alive.size() - 1)]
	_trooper_damage(target, loc, dmg, attacker, cause)
	return loc


func _trooper_damage(target: CombatMech, loc: String, dmg: int, attacker: CombatMech, cause: String) -> void:
	if target.destroyed or target.loc_destroyed[loc] or dmg <= 0:
		return
	var a := int(target.armor.get(loc, 0))
	var ab := mini(a, dmg)
	target.armor[loc] = a - ab
	var applied := ab
	var dead := dmg > a
	if dead:
		applied += int(target.internal[loc])
		target.internal[loc] = 0
		target.loc_destroyed[loc] = true
	if attacker != null and attacker != target:
		attacker.dmg_dealt += applied
	target.dmg_taken += applied
	log_event({"k": "dmg", "m": attacker.index if attacker else -1, "tg": target.index, "loc": loc, "dmg": dmg,
		"rear": false, "w": cause})
	if not dead:
		return
	target.refresh_squad()
	var left := target.troopers_alive()
	log_event({"k": "trooper", "m": attacker.index if attacker else -1, "tg": target.index, "n": 1, "left": left, "w": cause})
	if left <= 0:
		kill(target, attacker, "squad wiped out")


## Casualties in a conventional platoon. Weapon fire is twice as deadly to troops caught in the open;
## mechanized infantry lose fewer (their carriers take it).
func _platoon_losses(target: CombatMech, n: int, attacker: CombatMech, cause: String, weapon := true) -> void:
	if target.destroyed or n <= 0:
		return
	var I: Dictionary = tables["infantry"]
	if weapon:
		var ter: int = arena.terrain[arena.cell_index(target.pos)]
		if ter == Arena.T.CLEAR or ter == Arena.T.PAVEMENT:
			n *= int(I["open_mult"])
	if target.armor_div > 1:
		n = int(ceil(n / float(target.armor_div)))
	var have := int(target.internal["PL"])
	var lost := mini(have, n)
	target.internal["PL"] = have - lost
	if attacker != null and attacker != target:
		attacker.dmg_dealt += lost
	target.dmg_taken += lost
	target.refresh_squad()
	log_event({"k": "trooper", "m": attacker.index if attacker else -1, "tg": target.index, "n": lost,
		"left": have - lost, "w": cause})
	if have - lost <= 0:
		target.loc_destroyed["PL"] = true
		kill(target, attacker, "platoon wiped out")


## A 'Mech or vehicle weapon that hit a conventional platoon (Total Warfare's non-infantry weapons
## against infantry table): big guns are wasted on men, machine guns and flamers are not.
func _fire_on_platoon(m: CombatMech, target: CombatMech, it: Dictionary, munition: String, shots_fired: int, wname: String) -> void:
	var I: Dictionary = tables["infantry"]
	var wt: String = it.get("wtype", "")
	var dmg := int(it.get("dmg", 0))
	var div := float(I["damage_div"])
	var n := 0
	if I["burst"].has(wt):
		for k in int(I["burst"][wt]):
			n += rng.d6()
	elif wt in MISSILE_TYPES:
		var rack := maxi(1, int(it.get("rack", 1)))
		var missiles := rack if wt.begins_with("streak") else cluster_hits(rack, 0)
		n = int(ceil(missiles * maxi(1, dmg) / float(I["missile_div"])))
	elif wt == "lbx" and munition == "lbx_cluster":
		n = int(ceil(cluster_hits(dmg, 0) / div)) + int(I["lbx_bonus"])
	elif wt == "uac" or wt == "rac":
		var shells := cluster_hits(shots_fired, 0) if shots_fired > 1 else 1
		n = shells * int(ceil(dmg / div))
	else:
		n = int(ceil(dmg / div)) + (int(I["pulse_bonus"]) if wt == "pulse" else 0)
	_platoon_losses(target, maxi(1, n), m, wname)


## A squad's volley that hit. A platoon's fire is one sum from every rifle still firing, landing in
## small groups; each battle armour suit that hits (cluster roll on the suits left) does its own damage.
func _squad_fire(m: CombatMech, mt: Dictionary, target: CombatMech, side: String, wname: String) -> void:
	var I: Dictionary = tables["infantry"]
	var it: Dictionary = mt["item"]
	var wt: String = it.get("wtype", "")
	var alive := m.troopers_alive()
	if alive <= 0:
		return
	var per := float(it.get("per", 0.27))
	var soft := target.is_infantry and not target.battle_armor
	if not m.battle_armor:
		var total := maxi(1, int(ceil(alive * per)))
		if soft:
			_platoon_losses(target, total, m, wname)
			return
		var group := maxi(1, int(I["group"]))
		while total > 0 and not target.destroyed:
			var n := mini(group, total)
			_hit_location_damage(m, target, side, n, wname)
			total -= n
		return
	var hits := 1
	var each := maxi(1, int(round(per)))
	if it.has("missiles"):
		hits = cluster_hits(alive * int(it["missiles"]), 0)
	elif alive > 1:
		hits = cluster_hits(alive, 0)
	if soft:
		var n2 := hits * each
		if I["burst"].has(wt):
			n2 *= 2
		elif wt in MISSILE_TYPES:
			n2 = int(ceil(n2 / float(I["missile_div"]))) + 1
		_platoon_losses(target, maxi(1, n2), m, wname)
		return
	for k in hits:
		if target.destroyed:
			break
		_hit_location_damage(m, target, side, each, wname)


## Anti-'Mech infantry go for a 'Mech's legs: charges on the actuators, a climb to the knee joint.
## The fewer troopers left, the harder it is. A hit damages a leg and rolls for a critical.
func leg_attack(m: CombatMech, target: CombatMech) -> void:
	var L: Dictionary = tables["infantry"]["leg_attack"]
	m.physical_ready_at = t + TURN
	_pods_fire(target, m)
	if m.out:
		return
	var frac := float(m.troopers_alive()) / maxf(1.0, float(m.troopers_max))
	var smod := 0
	for row in L["mods"]:
		if frac >= float(row[0]):
			smod = int(row[1])
			break
	var tn := m.piloting + smod
	if target.gait != CombatMech.Gait.PRONE and not target.shutdown and target.conscious:
		tn += target_movement_mod(target)
	var roll := rng.roll2d6()
	var hit := roll >= tn
	var dmg := int(L["damage_ba"]) if m.battle_armor else maxi(1, int(ceil(m.troopers_alive() * float(L["damage_per_trooper"]))))
	log_event({"k": "leg_attack", "m": m.index, "tg": target.index, "tn": tn, "roll": roll, "hit": hit, "dmg": dmg})
	m.shots += 1
	if not hit:
		return
	m.hits += 1
	var legs: Array = []
	for leg in ["LL", "RL"]:
		if not target.loc_destroyed[leg]:
			legs.append(leg)
	if legs.is_empty():
		return
	var loc: String = legs[rng.randi_range(0, legs.size() - 1)]
	apply_damage(target, loc, dmg, false, m, "leg attack")
	if not target.out and not target.loc_destroyed[loc]:
		crit_check(target, loc, m)
	m.showmanship += 1.0


func _motive_roll(target: CombatMech, side: String, attacker: CombatMech) -> void:
	if target.is_infantry:
		return
	var md: Dictionary = tables["motive_damage"]
	var mods: Dictionary = md["mods"]
	var roll := rng.roll2d6()
	if side == "rear":
		roll += int(mods["rear"])
	elif side == "left" or side == "right":
		roll += int(mods["side"])
	roll += int(mods.get(target.motion, 0))
	var res := "none"
	for row in md["table"]:
		if roll >= int(row[0]) and roll <= int(row[1]):
			res = str(row[2])
	if roll > 12:
		res = "immobile"
	match res:
		"none":
			return
		"minor":
			target.motive_levels["minor"] = true
		"moderate":
			target.motive_levels["moderate"] = true
			target.cruise_lost += 1
		"heavy":
			target.motive_levels["heavy"] = true
			target.cruise_halved = true
		"immobile":
			target.immobile = true
			target.path = PackedVector2Array()
	log_event({"k": "motive", "tg": target.index, "res": res, "roll": roll})
	if (res == "immobile" or target.walk_mp() <= 0) and target.motion == "hover":
		var ci := arena.cell_index(target.pos)
		if arena.depth[ci] >= 1:
			log_event({"k": "motive", "tg": target.index, "res": "sunk"})
			kill(target, attacker, "sank")


## Critical hit roll on a vehicle location. Results that don't apply move down the column (wrapping
## back to 6 once), as the Total Warfare tables say.
func _vehicle_crit(target: CombatMech, loc: String, attacker: CombatMech, mod := 0) -> void:
	if target.out or target.is_infantry:
		return
	var vtol := target.motion == "vtol"
	var col := "front"
	match loc:
		"RR":
			col = "rear"
		"LS", "RS":
			col = "side"
		"TU":
			col = "turret"
		"RO":
			col = "rotor"
	if vtol and col == "turret":
		col = "front"
	var tbl: Dictionary = tables["vtol_crits" if vtol else "vehicle_crits"][col]
	var roll := clampi(rng.roll2d6() + mod, 2, 12)
	if roll <= 5:
		return
	var r := roll
	for tries in 8:
		var res := str(tbl[str(r)])
		if _apply_vcrit(target, loc, res, attacker):
			return
		r += 1
		if r > 12:
			r = 6


func _vcrit_log(target: CombatMech, what: String) -> void:
	log_event({"k": "vcrit", "tg": target.index, "what": what})


func _stun(target: CombatMech, attacker: CombatMech) -> void:
	if target.commander_hit and target.driver_hit:
		_crew_killed(target, attacker)
		return
	target.crew_stunned_until = maxf(target.crew_stunned_until, t) + float(tables["vehicle"]["stun_seconds"])
	_vcrit_log(target, "crew stunned")


func _crew_killed(target: CombatMech, attacker: CombatMech) -> void:
	target.crew_killed = true
	_vcrit_log(target, "crew killed")
	if target.airborne:
		kill(target, attacker, "crew killed, it crashes")
		return
	if attacker != null and attacker != target:
		attacker.kills += 1
		target.killer = attacker.index
	target.conscious = false
	set_out(target, "crew killed")


func _apply_vcrit(target: CombatMech, loc: String, res: String, attacker: CombatMech) -> bool:
	if attacker != null:
		attacker.crits_dealt += 1
	match res:
		"cargo":
			return false
		"driver":
			if target.driver_hit:
				_stun(target, attacker)
			else:
				target.driver_hit = true
				_vcrit_log(target, "driver hit")
			return true
		"commander":
			if not target.commander_hit:
				target.commander_hit = true
				_vcrit_log(target, "commander hit")
			_stun(target, attacker)
			return true
		"crew_stunned":
			_stun(target, attacker)
			return true
		"copilot":
			if target.copilot_hit:
				_crew_killed(target, attacker)
			else:
				target.copilot_hit = true
				_vcrit_log(target, "co-pilot hit")
			return true
		"pilot":
			if target.vpilot_hit:
				_crew_killed(target, attacker)
			else:
				target.vpilot_hit = true
				_vcrit_log(target, "pilot hit")
			return true
		"crew_killed":
			_crew_killed(target, attacker)
			return true
		"weapon_malfunction", "weapon_destroyed":
			var cand: Array = []
			for wi in target.weapons:
				var mt: Dictionary = target.mounts[wi]
				if str(mt["loc"]) == loc and not mt["destroyed"] and (res == "weapon_destroyed" or t >= float(mt.get("malf_until", -1.0))):
					cand.append(wi)
			if cand.is_empty():
				return false
			var wi2: int = cand[rng.randi_range(0, cand.size() - 1)]
			var mt2: Dictionary = target.mounts[wi2]
			if res == "weapon_malfunction":
				mt2["malf_until"] = t + float(tables["vehicle"]["malfunction_seconds"])
				_vcrit_log(target, "%s malfunctions" % mt2["item"].get("name", "weapon"))
				return true
			target._destroy_vmount(wi2)
			_vcrit_log(target, "%s destroyed" % mt2["item"].get("name", "weapon"))
			if mt2["item"].get("explodes", false):
				log_event({"k": "explode", "tg": target.index, "loc": loc, "what": mt2["item"].get("name", "")})
				_vehicle_damage(target, loc, 20, attacker, "explosion")
			return true
		"stabilizer":
			if target.stabilizers.has(loc):
				return false
			target.stabilizers[loc] = true
			_vcrit_log(target, "%s stabilizer damaged" % VehicleDesign.VLOC_NAMES.get(loc, loc).to_lower())
			return true
		"sensors":
			if target.vsensors >= int(tables["vehicle"]["sensor_blind_at"]):
				return false
			target.vsensors += 1
			_vcrit_log(target, "sensors hit (%d)" % target.vsensors)
			return true
		"engine", "engine_damage":
			if target.engine_dead:
				return false
			if target.airborne:
				_vtol_engine_out(target, attacker)
				return true
			target.engine_dead = true
			target.turret_locked = true
			target.path = PackedVector2Array()
			_vcrit_log(target, "engine hit: immobile")
			return true
		"fuel_tank":
			if (target.design as VehicleDesign).fusion():
				return _apply_vcrit(target, loc, "engine", attacker)
			_vcrit_log(target, "fuel tank breached")
			_explosion_effects(target.pos)
			kill(target, attacker, "fuel tank explodes")
			return true
		"ammunition":
			var total := 0
			for bi in target.bins:
				var b: Dictionary = target.mounts[bi]
				if not b["destroyed"] and int(b["shots"]) > 0 and b["item"].get("explosive", true):
					total += int(b["shots"]) * _ammo_per_shot(target, b)
			if total <= 0:
				return _apply_vcrit(target, loc, "weapon_destroyed", attacker)
			for bi in target.bins:
				target.mounts[bi]["shots"] = 0
				target._destroy_vmount(bi)
			log_event({"k": "ammo_explosion", "tg": target.index, "loc": loc, "dmg": total, "what": "ammunition"})
			_explosion_effects(target.pos)
			if target.has_case.size() > 0:
				target.armor["RR"] = maxi(0, int(target.armor.get("RR", 0)) - total)
				_stun(target, attacker)
			else:
				var s1 := int(target.internal[loc])
				target.internal[loc] = maxi(0, s1 - total)
				if int(target.internal[loc]) <= 0:
					target.loc_destroyed[loc] = true
					kill(target, attacker, "ammunition explodes")
			return true
		"turret_jam":
			if not target.internal.has("TU") or target.turret_locked:
				return false
			if target.turret_jams > 0:
				target.turret_locked = true
				_vcrit_log(target, "turret locks")
				return true
			target.turret_jams += 1
			target.turret_jam_until = t + float(tables["vehicle"]["jam_seconds"])
			_vcrit_log(target, "turret jams")
			return true
		"turret_locks":
			if not target.internal.has("TU") or target.turret_locked:
				return false
			target.turret_locked = true
			_vcrit_log(target, "turret locks")
			return true
		"turret_blown_off":
			if not target.internal.has("TU"):
				return false
			_vcrit_log(target, "turret blown off")
			kill(target, attacker, "turret blown off")
			return true
		"rotor_damage":
			target.cruise_lost += 1
			_vcrit_log(target, "rotor damage")
			if target.airborne and target.walk_mp() <= 0:
				_vtol_engine_out(target, attacker)
			return true
		"flight_stabilizer":
			if target.flight_stabilizer:
				return false
			target.flight_stabilizer = true
			_vcrit_log(target, "flight stabilizer hit")
			return true
		"rotors_destroyed":
			_vcrit_log(target, "rotors destroyed")
			kill(target, attacker, "rotors destroyed, it crashes")
			return true
	return false


func _ammo_per_shot(target: CombatMech, b: Dictionary) -> int:
	var key: String = b["item"].get("ammo", "")
	for wi in target.weapons:
		var w: Dictionary = target.mounts[wi]["item"]
		if w.get("ammo", "") == key:
			return int(w.get("dmg", 1)) * maxi(1, int(w.get("rack", 1))) if w.get("wtype", "") in MISSILE_TYPES else int(w.get("dmg", 1))
	return 1


## A flying VTOL losing its engine or all its speed: over open ground the pilot may set it down
## (Driving roll +4); over anything else it crashes.
func _vtol_engine_out(target: CombatMech, attacker: CombatMech) -> void:
	var tt := arena.terrain_at(target.pos)
	var open := tt in [Arena.T.CLEAR, Arena.T.PAVEMENT, Arena.T.ROUGH] and arena.depth[arena.cell_index(target.pos)] == 0
	if open and rng.roll2d6() >= target.piloting + 4:
		target.airborne = false
		target.engine_dead = true
		target.immobile = true
		target.path = PackedVector2Array()
		_vcrit_log(target, "forced landing")
		return
	kill(target, attacker, "crashes")


func _move_vehicle(m: CombatMech) -> void:
	var tgt: CombatMech = ai.target_of(m)
	var vt: Dictionary = tables["vehicle"]
	# the turret tracks the target; a locked or jammed turret stays put
	if m.internal.has("TU") and not m.turret_locked and t >= m.turret_jam_until and tgt != null:
		var want_t := wrap_angle(angle_to(m, tgt) - m.facing)
		m.twist = _turn(m.twist, want_t, deg_to_rad(float(vt["turret_turn_deg_s"])) * DT)
	var mp := m.walk_mp()
	if m.path.is_empty() or mp <= 0:
		if m.gait != CombatMech.Gait.STAND:
			m.gait = CombatMech.Gait.STAND
		if mp <= 0:
			m.path = PackedVector2Array()
			return
		if m.is_infantry:
			if tgt != null:
				m.facing = _turn(m.facing, angle_to(m, tgt), deg_to_rad(90.0) * DT)
			return
		# no turret: swing the hull to bring the guns to bear
		if tgt != null and (not m.internal.has("TU") or m.turret_locked):
			m.facing = _turn(m.facing, angle_to(m, tgt), deg_to_rad(10.0 * maxi(1, mp)) * DT)
		return
	var wp: Vector2 = m.path[0]
	var dir := wp - m.pos
	if dir.length() < 2.5:
		m.path.remove_at(0)
		return
	var running := m.move_mode == CombatMech.Gait.RUN and not m.crew_stunned(t)
	var speed_mp := m.run_mp() if running else mp
	var move_ang := dir.angle()
	m.facing = _turn(m.facing, move_ang, deg_to_rad(6.0 * speed_mp + 24.0) * DT)
	var c := arena.cell_of(m.pos)
	var cost := arena.move_cost(c.x, c.y, m.mover)
	var speed := speed_mp * MPS / cost
	if not m.airborne:
		var nxt := arena.cell_of(m.pos + dir.normalized() * 6.0)
		if arena.height[arena.idx(nxt.x, nxt.y)] > arena.height[arena.idx(c.x, c.y)]:
			speed /= 1.5
	var off := absf(wrap_angle(move_ang - m.facing))
	if m.is_infantry:
		m.facing = _turn(m.facing, move_ang, deg_to_rad(120.0) * DT)
	elif off > deg_to_rad(40.0):
		speed *= 0.3
	var step_len := minf(speed * DT, dir.length())
	var np := m.pos + dir.normalized() * step_len
	if not arena.passable_p(np, m.mover):
		m.path = PackedVector2Array()
		return
	for o: CombatMech in mechs:
		if o == m or o.out or o.gait == CombatMech.Gait.JUMP or o.airborne != m.airborne:
			continue
		if np.distance_to(o.pos) < 18.0 and np.distance_to(o.pos) < m.pos.distance_to(o.pos):
			return
	m.pos = np
	if running:
		m.gait = CombatMech.Gait.RUN
		m.last_run_t = t
	else:
		m.gait = CombatMech.Gait.WALK
		m.last_walk_t = t


## Merc battles end when a side has nothing left on the map, an objective building set is settled,
## or time runs out. The campaign scores the result from the objectives.
func _check_end_merc(alive: Dictionary) -> void:
	var ob := arena.objectives
	var dc: Array = ob.get("defend_cells", [])
	if not dc.is_empty():
		var standing := 0
		for ci in dc:
			if arena.terrain[int(ci)] == Arena.T.BUILDING:
				standing += 1
		if standing == 0:
			_finish(1, "objective destroyed")
			return
	var ac: Array = ob.get("attack_cells", [])
	if not ac.is_empty():
		var standing2 := 0
		for ci in ac:
			if arena.terrain[int(ci)] == Arena.T.BUILDING:
				standing2 += 1
		if standing2 == 0:
			_finish(0, "objective destroyed")
			return
	if not alive.has(0):
		_finish(1 if alive.size() > 0 else -1, "no player units left on the field")
		return
	var enemies_left := false
	for team in alive:
		if int(team) != 0:
			enemies_left = true
	# with the enemy gone there's still time to level the target or finish the recon
	var unfinished := not ac.is_empty()
	for k in recon_done.size():
		if not recon_done[k]:
			unfinished = true
	var player_active := false
	for m: CombatMech in mechs:
		if m.team == 0 and not m.out and m.controller != "ai_ally":
			var ct := str(ai.state[m.index].get("cmd", {}).get("type", "free"))
			if ct in ["attack_cell", "recon", "move", "hold"] or m.controller == "player":
				player_active = true
	if not enemies_left and not (unfinished and player_active):
		_finish(0, "enemy driven from the field")
		return
	if t >= time_limit():
		_finish(-1, "time limit")


# ------------------------------------------------------------------ snapshots for the viewer

func _snapshot() -> void:
	var f := PackedFloat32Array()
	f.resize(mechs.size() * STRIDE)
	for m: CombatMech in mechs:
		var o: int = m.index * STRIDE
		f[o] = m.pos.x
		f[o + 1] = m.pos.y
		f[o + 2] = m.facing
		f[o + 3] = m.twist
		f[o + 4] = m.gait
		f[o + 5] = m.heat
		var jz := 0.0
		if m.gait == CombatMech.Gait.JUMP and m.jump_dur > 0.0:
			jz = sin(PI * clampf(m.jump_t / m.jump_dur, 0.0, 1.0))
		f[o + 6] = jz
		var flags := 0
		if m.gait == CombatMech.Gait.PRONE:
			flags |= 1
		if m.shutdown:
			flags |= 2
		if m.out:
			flags |= 4
		if m.destroyed:
			flags |= 8
		if m.yielded or m.ejected:
			flags |= 16
		if not m.conscious:
			flags |= 32
		if m.masc_on and m.gait == CombatMech.Gait.RUN:
			flags |= 64
		if m.club_uses > 0:
			flags |= 128
		if not m.narced.is_empty():
			flags |= 256
		if m.ecm:
			flags |= 512
		if m.is_vehicle:
			if m.immobile or m.engine_dead:
				flags |= 1024
			if m.crew_stunned(t):
				flags |= 2048
			if m.airborne:
				flags |= 4096
		if m.spotted or m.team == 0:
			flags |= 8192
		if m.withdrew:
			flags |= 16384
		if m.out_reason == "reserve":
			flags |= 32768
		f[o + 7] = flags
		f[o + 8] = m.pilot_hits
		f[o + 9] = t
		if m.is_vehicle:
			f[o + 3] = m.twist
			for k in m.snap_locs.size():
				f[o + 10 + k] = m.armor.get(m.snap_locs[k], 0)
				f[o + 21 + k] = m.internal.get(m.snap_locs[k], 0)
		else:
			for k in ARMOR_KEYS.size():
				f[o + 10 + k] = m.armor.get(ARMOR_KEYS[k], 0)
			for k in MechDesign.LOCS.size():
				f[o + 21 + k] = m.internal[MechDesign.LOCS[k]]
	frames.append(f)


## Human-readable line for a log event.
func describe(e: Dictionary) -> String:
	var who := func(i): return mechs[i].name if i >= 0 and i < mechs.size() else "?"
	match e.get("k", ""):
		"shot":
			var s := "%s fires %s at %s: needs %d, rolls %d, %s" % [who.call(e["m"]), e["w"], who.call(e["tg"]), e["tn"], e["roll"], "HIT" if e["hit"] else "miss"]
			if e.get("jam", false):
				s += " (jammed!)"
			return s
		"nolock":
			return "%s's %s can't get a lock on %s" % [who.call(e["m"]), e["w"], who.call(e["tg"])]
		"dmg":
			var ln: String = MechDesign.LOC_NAMES.get(e["loc"], VehicleDesign.loc_name(str(e["loc"])))
			if e["m"] < 0:
				return "%s takes %d damage to the %s (%s)" % [who.call(e["tg"]), e["dmg"], ln, e["w"]]
			return "  %d damage to %s's %s%s" % [e["dmg"], who.call(e["tg"]), ln, " (rear)" if e.get("rear", false) else ""]
		"trooper":
			if int(e["left"]) <= 0:
				return "  %s loses its last %s (%s)" % [who.call(e["tg"]), "trooper" if int(e["n"]) == 1 else "%d troopers" % int(e["n"]), e["w"]]
			return "  %s loses %s, %d left (%s)" % [who.call(e["tg"]), "a trooper" if int(e["n"]) == 1 else "%d troopers" % int(e["n"]), int(e["left"]), e["w"]]
		"leg_attack":
			return "%s swarms the legs of %s: needs %d, rolls %d, %s" % [who.call(e["m"]), who.call(e["tg"]), e["tn"], e["roll"], "HIT" if e["hit"] else "beaten off"]
		"crit":
			return "  CRITICAL HIT on %s: %s (%s)" % [who.call(e["tg"]), e["what"], e["loc"]]
		"tac":
			return "  Through-armor critical chance on %s" % who.call(e["tg"])
		"ap":
			return "  Armor-piercing round: critical chance on %s's %s" % [who.call(e["tg"]), MechDesign.LOC_NAMES.get(e["loc"], e["loc"])]
		"cover":
			return "  %s's shot hits cover in front of %s's legs" % [who.call(e["m"]), who.call(e["tg"])]
		"blown_off":
			return "  %s's %s is blown off!" % [who.call(e["tg"]), MechDesign.LOC_NAMES.get(e["loc"], e["loc"])]
		"loc_destroyed":
			return "  %s's %s is destroyed" % [who.call(e["tg"]), MechDesign.LOC_NAMES.get(e["loc"], e["loc"])]
		"ammo_explosion":
			return "AMMO EXPLOSION in %s's %s! (%d damage)" % [who.call(e["tg"]), MechDesign.LOC_NAMES.get(e["loc"], e["loc"]), e["dmg"]]
		"explode":
			return "%s's %s explodes!" % [who.call(e["tg"]), e["what"]]
		"pilot":
			return "  %s's MechWarrior is hurt (%s, %d hits)" % [who.call(e["tg"]), e["why"], e["hits"]]
		"unconscious":
			return "%s's MechWarrior is knocked unconscious!" % who.call(e["tg"])
		"psr":
			return "  %s piloting roll (%s): needs %d, rolls %d, %s" % [who.call(e["tg"]), e["why"], e["tn"], e["roll"], "stays up" if e["ok"] else "FALLS"]
		"fall":
			return "%s falls (%s)" % [who.call(e["tg"]), e["why"]]
		"stand":
			return "%s gets back up" % who.call(e["tg"])
		"stand_fail":
			return "%s fails to stand (needs %d, rolls %d)" % [who.call(e["tg"]), e["tn"], e["roll"]]
		"shutdown":
			return "%s SHUTS DOWN from heat (%d)" % [who.call(e["tg"]), e["heat"]]
		"restart":
			return "%s restarts" % who.call(e["tg"])
		"heat_ammo":
			return "%s's ammo cooks off from heat!" % who.call(e["tg"])
		"jump":
			if int(e.get("dfa", -1)) >= 0:
				return "%s leaps at %s: DEATH FROM ABOVE!" % [who.call(e["m"]), who.call(e["dfa"])]
			return "%s jumps" % who.call(e["m"])
		"land":
			return ""
		"physical":
			var w: String = str(e["w"])
			if w == "club":
				w = "swing with a %s" % e.get("club", "club")
			return "%s tries a %s on %s: needs %d, rolls %d, %s" % [who.call(e["m"]), w, who.call(e["tg"]), e["tn"], e["roll"], "HIT" if e["hit"] else "miss"]
		"charge":
			return "%s CHARGES %s (%d hexes): needs %d, rolls %d, %s" % [who.call(e["m"]), who.call(e["tg"]), e["hexes"], e["tn"], e["roll"], "SLAMS INTO THEM" if e["hit"] else "misses"]
		"dfa":
			return "  Death from above on %s: needs %d, rolls %d, %s" % [who.call(e["tg"]), e["tn"], e["roll"], "CRUSHING HIT" if e["hit"] else "MISSES and crashes down"]
		"push":
			return "%s shoves %s: needs %d, rolls %d, %s" % [who.call(e["m"]), who.call(e["tg"]), e["tn"], e["roll"], "pushed back" if e["hit"] else "miss"]
		"club_pickup":
			return "%s rips up a %s to use as a club" % [who.call(e["m"]), e["club"]]
		"club_break":
			return "%s's %s breaks apart" % [who.call(e["m"]), e["club"]]
		"club_drop":
			return "%s drops the club" % who.call(e["tg"])
		"narc":
			return "  A Narc beacon sticks to %s" % who.call(e["tg"])
		"inferno":
			return "  Inferno gel splashes %s: +%d heat" % [who.call(e["tg"]), e["heat"]]
		"masc_fail":
			return "%s's MASC FAILS (needs %d, rolls %d): hip actuators wrecked" % [who.call(e["tg"]), e["tn"], e["roll"]]
		"plasma_heat":
			return "  Burning plasma clings to %s: +%d heat" % [who.call(e["tg"]), e["heat"]]
		"emp":
			match str(e["res"]):
				"shutdown":
					return "  %s's electronics are knocked out: every weapon off line for a turn" % who.call(e["tg"])
				"interference":
					return "  %s's targeting is scrambled for a turn" % who.call(e["tg"])
			return "  %s's electronics shrug the pulse off" % who.call(e["tg"])
		"pod":
			return "%s sets off its %s at %s" % [who.call(e["m"]), e["w"], who.call(e["tg"])]
		"coolant":
			return "%s flushes its %s: %d heat gone" % [who.call(e["tg"]), e["w"], e["shed"]]
		"collapse":
			return "A building COLLAPSES into rubble!"
		"bld_hit":
			return ""
		"fire":
			return "The woods catch fire (%s)" % e["why"] if e["why"] != "spreading fire" else ""
		"hazard":
			match str(e["type"]):
				"flame_jets":
					return "Flame jets roar up from the arena floor"
				"shock_pylons":
					return "A shock pylon arcs into %s!" % who.call(e["tg"])
			return ""
		"call":
			var txt: String = CALLS.get(str(e["call"]), str(e["call"]))
			if str(e["call"]) == "focus" and int(e.get("arg", -1)) >= 0:
				txt += ": " + who.call(int(e["arg"]))
			return "Corner call to %s: \"%s!\"" % [who.call(e["m"]), txt]
		"crippled":
			return "%s is crippled and can't continue" % who.call(e["tg"])
		"motive":
			return "  %s motive system: %s" % [who.call(e["tg"]), {"minor": "minor damage", "moderate": "moderate damage (-1 MP)", "heavy": "heavy damage (half speed)", "immobile": "DESTROYED, the vehicle is immobile", "sunk": "immobile in deep water: it SINKS"}.get(str(e["res"]), str(e["res"]))]
		"vcrit":
			return "  CRITICAL HIT on %s: %s" % [who.call(e["tg"]), str(e["what"])]
		"command":
			var names2: Array = []
			for i in e["units"]:
				names2.append(who.call(int(i)))
			var what: String = COMMANDS.get(str(e["cmd"]), str(e["cmd"]))
			if str(e["cmd"]) == "attack":
				what += " " + who.call(int(e["arg"]))
			elif str(e["cmd"]) in ["range", "heat", "jump"]:
				what += ": " + str(e["arg"])
			return "Orders to %s: %s" % [", ".join(names2), what]
		"support_call":
			var mine := int(e["team"]) == 0
			if str(e["kind"]) == "artillery":
				return ("Fire mission called: shells in %d seconds" % int(round(float(e["at"]) - float(e["t"])))) if mine else "INCOMING! Enemy artillery is ranging in"
			return ("Air strike called: the fighter is %d seconds out" % int(round(float(e["at"]) - float(e["t"])))) if mine else "Enemy fighter inbound!"
		"shell":
			return "An artillery shell lands"
		"strafe":
			return "%s fighter strafes the field" % ("A friendly" if int(e["team"]) == 0 else "An enemy")
		"strafe_hit":
			return "  The fighter fires on %s: needs %d, rolls %d, %s" % [who.call(e["tg"]), e["tn"], e["roll"], "HIT" if e["hit"] else "miss"]
		"exit":
			return "%s leaves the battlefield (%s edge)" % [who.call(e["tg"]), {"W": "west", "E": "east", "N": "north", "S": "south"}.get(str(e["edge"]), str(e["edge"]))]
		"arrive":
			return "%s arrives on the battlefield" % who.call(e["tg"])
		"recon":
			return "%s scouts objective point %d" % [who.call(e["m"]), int(e["point"]) + 1]
		"rout":
			return "The enemy force breaks and falls back!"
		"withdraw_order":
			return "%s falls back, too badly damaged to fight on" % who.call(e["tg"])
		"yield":
			return "%s YIELDS" % who.call(e["tg"])
		"eject":
			return "%s EJECTS!" % who.call(e["tg"])
		"end":
			if int(e["winner"]) < 0:
				return "Fight over: draw (%s)" % e["how"]
			var names: Array = []
			for m: CombatMech in mechs:
				if m.team == int(e["winner"]):
					names.append(m.name)
			return "Fight over: %s win%s by %s" % [" & ".join(names), "s" if names.size() == 1 else "", e["how"]]
	return ""
