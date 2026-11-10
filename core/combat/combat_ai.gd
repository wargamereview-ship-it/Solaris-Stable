class_name CombatAI
extends RefCounted
## Warrior behavior. You don't pilot: the warrior follows your pre-fight orders (and any corner calls),
## bent by their traits.
## Orders: range ("close", "optimal", "long"), heat ("cool", "balanced", "hot"),
## position ("cover", "flank", "brawl"), retreat (0.2-0.9, damage before yielding),
## focus ("focus", "spread", "protect") for team fights, ammo {family: munition}.

const DEFAULT_ORDERS := {"range": "optimal", "heat": "balanced", "position": "cover", "retreat": 0.55, "focus": "focus"}

var sim: CombatSim
var state: Dictionary = {}   # mech index -> memory


func _init(s: CombatSim) -> void:
	sim = s


func init_all() -> void:
	for m: CombatMech in sim.mechs:
		var o: Dictionary = DEFAULT_ORDERS.duplicate()
		for k in m.orders:
			o[k] = m.orders[k]
		m.orders = o
		state[m.index] = {"next_plan": 0.1 + m.index * 0.13, "target": -1, "profile_at": -100.0, "desired": 150.0,
			"orbit": 1.0 if (m.index % 2 == 0) else -1.0, "next_yield": 1.0, "goal": m.pos, "next_fire": 0.0,
			"seen_at": 0.0, "press": 1.0, "forced": -1, "cmd": {}}


func target_of(m: CombatMech) -> CombatMech:
	var ti: int = state[m.index]["target"]
	if ti < 0 or ti >= sim.mechs.size():
		return null
	var tm: CombatMech = sim.mechs[ti]
	return null if tm.out else tm


func force_target(m: CombatMech, ti: int) -> void:
	if ti >= 0 and ti < sim.mechs.size() and sim.mechs[ti].team != m.team:
		state[m.index]["forced"] = ti
		state[m.index]["target"] = ti


## A standing order from the player (or the scenario): {"type": "move", "pos"} / "attack" / "hold" /
## "free" / "withdraw" with "edge". Targets are still picked by the AI unless the order is "attack".
func command(m: CombatMech, c: Dictionary) -> void:
	var st: Dictionary = state[m.index]
	st["cmd"] = c
	if str(c.get("type", "")) != "attack":
		st["forced"] = -1
	st["next_plan"] = sim.t
	m.path = PackedVector2Array()


func on_orders_changed(m: CombatMech) -> void:
	var st: Dictionary = state[m.index]
	st["profile_at"] = -100.0
	st["next_plan"] = sim.t
	st["next_fire"] = sim.t


func heat_cap(m: CombatMech) -> float:
	if m.is_vehicle:
		return 99.0
	var cap := 9.0
	match str(m.orders["heat"]):
		"cool":
			cap = 5.0
		"hot":
			cap = 14.0
	if m.has_trait("hot_blooded"):
		cap += 4.0
	if m.has_trait("cool_under_fire"):
		cap = minf(cap, 10.0)
	return cap


func max_tn(m: CombatMech) -> int:
	var tn := 10
	if str(m.orders["heat"]) == "hot" or m.has_trait("hot_blooded"):
		tn = 11
	if m.has_trait("cool_under_fire"):
		tn = 9
	return tn


func think(m: CombatMech) -> void:
	if not m.can_act():
		return
	var st: Dictionary = state[m.index]
	if sim.t >= float(st["next_plan"]):
		st["next_plan"] = sim.t + 0.6
		_choose_target(m, st)
		_plan_move(m, st)
	if sim.t >= float(st["next_yield"]):
		st["next_yield"] = sim.t + 0.5
		_consider_yield(m)
		if m.out:
			return
	if m.gait == CombatMech.Gait.JUMP or m.gait == CombatMech.Gait.PRONE:
		if m.gait == CombatMech.Gait.PRONE:
			_fire(m, st)
		return
	if m.is_vehicle and m.crew_stunned(sim.t):
		return
	_fire(m, st)
	_physical(m)


# ------------------------------------------------------------------ targeting

func _choose_target(m: CombatMech, st: Dictionary) -> void:
	var forced: int = st["forced"]
	if forced >= 0 and not sim.mechs[forced].out:
		st["target"] = forced
		return
	st["forced"] = -1
	var focus := str(m.orders.get("focus", "focus"))
	var mates := sim.teammates(m)
	var best := -1
	var best_s := INF
	for o: CombatMech in sim.mechs:
		if o.team == m.team or o.out:
			continue
		var s := m.pos.distance_to(o.pos)
		if not sim.los_between(m, o)["clear"]:
			s *= 1.3
		if not mates.is_empty():
			var on_it := 0
			for mt in mates:
				var tm: CombatMech = mt
				if int(state[tm.index]["target"]) == o.index:
					on_it += 1
			match focus:
				"focus":
					# gang up: the weakest enemy that teammates are already shooting
					s *= (0.35 + o.armor_fraction()) / (1.0 + 0.6 * on_it)
				"spread":
					s *= 1.0 + 0.5 * on_it
				"protect":
					for mt2 in mates:
						var tm2: CombatMech = mt2
						var hurt := tm2.gait == CombatMech.Gait.PRONE or tm2.internal_lost_fraction() > 0.35
						if hurt and int(state[o.index]["target"]) == tm2.index:
							s *= 0.35
		elif focus == "weakest":
			s *= 0.4 + o.armor_fraction()
		if o.index == int(st["target"]):
			s *= 0.85
		if s < best_s:
			best_s = s
			best = o.index
	st["target"] = best


## Expected damage per 10 s at a range (hexes), assuming a moving target.
func expected_damage(m: CombatMech, r: int) -> float:
	var total := 0.0
	for wi in m.weapons:
		var mt: Dictionary = m.mounts[wi]
		if mt["destroyed"] or m.loc_destroyed[mt["loc"]] or mt["rear"]:
			continue
		var it: Dictionary = mt["item"]
		var wt: String = it.get("wtype", "")
		if wt in ["ams", "narc", "inarc", "tag", "other"]:
			continue
		if sim.find_ammo(m, mt) == -1:
			continue
		var band := -1
		if r <= int(it.get("s", 0)):
			band = 0
		elif r <= int(it.get("m", 0)):
			band = 2
		elif r <= int(it.get("l", 0)):
			band = 4
		if band < 0:
			continue
		var tn := m.gunnery + 1 + 2 + band
		var mn := int(it.get("min", 0))
		if mn > 0 and r <= mn:
			tn += mn - r + 1
		if wt == "pulse":
			tn -= 2
		var dmg := float(it.get("dmg", 0))
		if wt in CombatSim.MISSILE_TYPES:
			dmg = float(it.get("rack", 0)) * dmg * (1.0 if wt.begins_with("streak") else 0.6)
			if m.munition_for(mt) == "inferno":
				dmg = float(it.get("rack", 0)) * 0.6 * 1.2  # heat, not damage, but it wins fights
		elif wt == "uac":
			dmg *= 1.5
		elif wt == "rac":
			dmg *= 2.5
		total += CombatSim.p_hit(tn) * dmg
	return total


func _desired_range(m: CombatMech, enemy: CombatMech, st: Dictionary) -> float:
	if sim.t - float(st["profile_at"]) < 5.0:
		return st["desired"]
	st["profile_at"] = sim.t
	var mine: Array = []
	var theirs: Array = []
	var best_mine := 0.0
	for r in range(1, 31):
		var a := expected_damage(m, r)
		mine.append(a)
		theirs.append(expected_damage(enemy, r) if enemy != null else 0.0)
		best_mine = maxf(best_mine, a)
	var want := 6
	match str(m.orders["range"]):
		"close":
			want = 2
		"long":
			for r in range(30, 0, -1):
				if mine[r - 1] >= best_mine * 0.55:
					want = r
					break
		_:
			var best_s := -INF
			for r in range(2, 31):
				var s: float = mine[r - 1] - 0.7 * theirs[r - 1] + r * 0.01
				if s > best_s:
					best_s = s
					want = r
	if m.has_trait("showboat") or m.has_trait("brawler") or str(m.orders["position"]) == "brawl":
		want = mini(want, 3)
	if m.has_trait("cautious"):
		want = maxi(want, 5)
	st["desired"] = maxf(35.0, want * CombatSim.HEX - 10.0)
	return st["desired"]


# ------------------------------------------------------------------ movement

func _cell_danger(arena: Arena, p: Vector2) -> float:
	var i := arena.cell_index(p)
	var d := 0.0
	if arena.burning(i):
		d += 4.0
	for hz in arena.hazards:
		var hp: Vector2 = hz["pos"]
		if hp.distance_to(p) < 16.0:
			d += 2.5
	return d


## Carries out a move or withdraw order: path to the point, running when it's far.
func _go_to(m: CombatMech, st: Dictionary, goal: Vector2, hurry: bool) -> void:
	var d := m.pos.distance_to(goal)
	if d < 10.0:
		m.path = PackedVector2Array()
		var c: Dictionary = st["cmd"]
		if str(c.get("type", "")) == "move":
			st["cmd"] = {"type": "hold", "pos": goal}
		return
	if m.path.is_empty() or m.goal.distance_to(goal) > 6.0:
		m.path = sim.arena.find_path(m.pos, goal, m.mover)
		m.goal = goal
	m.move_mode = CombatMech.Gait.RUN if (hurry or d > 70.0) else CombatMech.Gait.WALK
	m.backing = false
	m.masc_on = m.masc and hurry and d > 150.0 and m.masc_level <= 1


func _plan_move(m: CombatMech, st: Dictionary) -> void:
	var cmd: Dictionary = st.get("cmd", {})
	var ct := str(cmd.get("type", "free"))
	match ct:
		"move":
			_go_to(m, st, cmd["pos"], false)
			return
		"attack_cell":
			var ci := _objective_cell(m, cmd)
			if ci < 0:
				st["cmd"] = {"type": "free"}
			else:
				var cp := sim.arena.center_of_index(ci)
				var tgt0 := target_of(m)
				# fight back when someone gets close; otherwise stand off and shoot the building
				if tgt0 == null or tgt0.pos.distance_to(m.pos) > 350.0:
					var stand := cp + (m.pos - cp).normalized() * 110.0
					if m.pos.distance_to(cp) < 130.0 and sim.arena.los(m.pos, cp)["clear"]:
						m.path = PackedVector2Array()
					else:
						_go_to(m, st, stand, false)
						st["cmd"] = cmd
					return
		"advance":
			# push for the far edge, but stand and fight when the enemy is close
			var edge := str(cmd.get("edge", "E"))
			var t1 := target_of(m)
			var near_edge := sim.arena.edge_distance(m.pos, edge) < 90.0
			if near_edge or t1 == null or t1.pos.distance_to(m.pos) > 450.0:
				_go_to(m, st, sim.arena.edge_point(m.pos, edge, 4.0), true)
				st["cmd"] = cmd
				return
		"guard":
			var gp: Vector2 = cmd["pos"]
			if m.pos.distance_to(gp) > float(cmd.get("radius", 220.0)):
				_go_to(m, st, gp, false)
				st["cmd"] = cmd
				return
		"recon":
			var pts: Array = cmd.get("points", [])
			var bestp := Vector2.INF
			for k in pts.size():
				if k < sim.recon_done.size() and not sim.recon_done[k]:
					var rp: Vector2 = pts[k]
					if bestp == Vector2.INF or m.pos.distance_to(rp) < m.pos.distance_to(bestp):
						bestp = rp
			if bestp == Vector2.INF:
				command(m, {"type": "withdraw", "edge": sim.home_edge(m.team)})
				return
			_go_to(m, st, bestp, true)
			st["cmd"] = cmd
			return
		"withdraw":
			_go_to(m, st, sim.arena.edge_point(m.pos, str(cmd.get("edge", "W")), 4.0), true)
			return
		"hold":
			var hp: Vector2 = cmd.get("pos", m.pos)
			if m.pos.distance_to(hp) > 25.0:
				_go_to(m, st, hp, false)
				st["cmd"] = cmd
			else:
				m.path = PackedVector2Array()
				m.backing = false
			return
	var tgt := target_of(m)
	if tgt == null:
		m.path = PackedVector2Array()
		m.masc_on = false
		return
	var arena := sim.arena
	# Hunt: the longer the target stays out of sight, the closer we press in.
	if sim.los_between(m, tgt)["clear"]:
		st["seen_at"] = sim.t
		st["press"] = minf(1.0, float(st["press"]) + 0.05)
	elif sim.t - float(st["seen_at"]) > 5.0:
		st["press"] = maxf(0.25, float(st["press"]) - 0.08)
	var desired := maxf(35.0, _desired_range(m, tgt, st) * float(st["press"]))
	var pos_kind := str(m.orders["position"])
	var cover_w := 1.2 if pos_kind == "cover" or m.has_trait("cautious") else 0.4
	var flank_w := 2.2 if pos_kind == "flank" else 0.5
	var tdir := Vector2.from_angle(tgt.facing)
	var orbit: float = st["orbit"]
	var hot := m.heat >= heat_cap(m) - 1.0
	var cands: Array = []
	var base_ang := (m.pos - tgt.pos).angle()
	for k in 10:
		var ang := base_ang + deg_to_rad(36.0 * k)
		cands.append(tgt.pos + Vector2.from_angle(ang) * desired)
	cands.append(m.pos)
	cands.append(tgt.pos + (m.pos - tgt.pos).normalized() * desired)
	# a step straight toward the target, so a blocked view always has a way forward
	cands.append(m.pos + (tgt.pos - m.pos).normalized() * minf(90.0, m.pos.distance_to(tgt.pos) * 0.5))
	var best := m.pos
	var best_s := -INF
	var my_dir := Vector2.from_angle(m.facing)
	var mates := sim.teammates(m)
	for c in cands:
		var cp: Vector2 = c
		if not arena.passable_p(cp, m.mover):
			continue
		var s := 0.0
		var d := cp.distance_to(tgt.pos)
		s -= absf(d - desired) / CombatSim.HEX * 1.5
		var shoot := arena.los(cp, tgt.pos)
		if not shoot["clear"]:
			s += 2.0 if hot else -5.0
			s -= d / CombatSim.HEX * 0.3 * (1.0 - float(st["press"]) + 0.2)
		else:
			s -= (int(shoot["woods"]) + int(shoot["target_woods"]) + int(shoot.get("smoke", 0))) * 0.7
			if shoot["partial"]:
				s -= 0.5
		var back := arena.los(tgt.pos, cp)
		if back["clear"]:
			s += (int(back["woods"]) + int(back["target_woods"]) + int(back.get("target_smoke", 0)) + (1 if back["partial"] else 0)) * cover_w
		s += (arena.level_at(cp) - arena.level_at(tgt.pos)) * 0.35
		var to_c := (cp - tgt.pos).normalized()
		s += -tdir.dot(to_c) * flank_w
		s -= m.pos.distance_to(cp) / 100.0
		s -= _cell_danger(arena, cp)
		if m.heat > 7.0:
			var cc := arena.cell_of(cp)
			if arena.depth[arena.idx(cc.x, cc.y)] == 1:
				s += 1.2
		var side := (cp - m.pos)
		if side.length() > 1.0:
			s += 0.25 * orbit * my_dir.orthogonal().dot(side.normalized())
		for o: CombatMech in sim.mechs:
			if o != m and not o.out and o.pos.distance_to(cp) < 22.0:
				s -= 3.0
		for mt in mates:
			var tm: CombatMech = mt
			if tm.pos.distance_to(cp) < 45.0:
				s -= 0.8
		if s > best_s:
			best_s = s
			best = cp
	st["goal"] = best
	var dist_goal := m.pos.distance_to(best)
	var dist_t := m.pos.distance_to(tgt.pos)
	# death from above: brawlers and showboats leap onto a target in jump range
	if _want_dfa(m, tgt, dist_t):
		var land := tgt.pos + (m.pos - tgt.pos).normalized() * 18.0
		if sim.start_jump(m, land, tgt.pos, tgt.index):
			return
	# jump when the path is blocked or a flank is worth it
	if m.jump_mp() > 0 and str(m.orders.get("jump", "on")) != "off" and sim.t >= m.jump_ready_at and m.heat + maxf(3.0, m.jump_mp()) <= heat_cap(m) + 3.0:
		var jr := m.jump_mp() * CombatSim.HEX
		var jumpy := m.has_trait("jump_jockey") or pos_kind == "flank"
		if dist_goal > 25.0 and dist_goal <= jr:
			var path_len := _path_length(arena.find_path(m.pos, best, m.mover), m.pos)
			if path_len > dist_goal * 1.6 or (jumpy and sim.rng.chance(0.5)):
				if sim.start_jump(m, best, tgt.pos):
					return
	if dist_goal < 12.0:
		m.path = PackedVector2Array()
		if sim.rng.chance(0.15):
			st["orbit"] = -orbit
	else:
		var need_new := m.path.is_empty() or m.goal.distance_to(best) > 18.0
		if need_new:
			m.path = arena.find_path(m.pos, best, m.mover)
			m.goal = best
	# gait: run to close distance, walk when fighting; MASC for a long sprint
	var cool_now := str(m.orders["heat"]) == "cool" and m.heat >= 4.0
	if (dist_goal > 90.0 or dist_t > desired + 120.0) and not cool_now:
		m.move_mode = CombatMech.Gait.RUN
	else:
		m.move_mode = CombatMech.Gait.WALK
	m.masc_on = m.masc and m.move_mode == CombatMech.Gait.RUN and dist_goal > 120.0 and m.masc_level <= 1 and not m.has_trait("cautious")
	# back away while keeping the guns forward
	if not m.path.is_empty():
		var mv := (m.path[0] - m.pos)
		var face_t := (tgt.pos - m.pos)
		m.backing = mv.length() > 1.0 and face_t.length() > 1.0 and mv.normalized().dot(face_t.normalized()) < -0.5 and m.move_mode == CombatMech.Gait.WALK
	else:
		m.backing = false


func _want_dfa(m: CombatMech, tgt: CombatMech, dist: float) -> bool:
	if tgt.airborne or str(m.orders.get("jump", "on")) == "off":
		return false
	if m.jump_mp() <= 0 or sim.t < m.jump_ready_at or tgt.gait == CombatMech.Gait.JUMP or sim.t < m.physical_ready_at:
		return false
	if dist < 35.0 or dist > m.jump_mp() * CombatSim.HEX:
		return false
	if m.has_trait("cautious") or m.legs_destroyed() > 0 or m.gyro_hits > 0:
		return false
	var keen := m.has_trait("showboat") or m.has_trait("brawler") or m.has_trait("jump_jockey") or str(m.orders["position"]) == "brawl"
	if not keen:
		return false
	var tn := m.piloting + 3 + sim.target_movement_mod(tgt) + (m.piloting - tgt.piloting)
	# only when the odds are decent and the target is big enough to be worth it
	return tn <= 8 and m.tons() >= tgt.tons() * 0.6 and sim.rng.chance(0.35)


static func _path_length(p: PackedVector2Array, from: Vector2) -> float:
	if p.is_empty():
		return INF
	var l := from.distance_to(p[0])
	for k in range(1, p.size()):
		l += p[k - 1].distance_to(p[k])
	return l


# ------------------------------------------------------------------ firing

## Nearest still-standing building cell of an attack order (-1 when they're all down).
func _objective_cell(m: CombatMech, cmd: Dictionary) -> int:
	var best := -1
	var bd := INF
	for ci in cmd.get("cells", []):
		var i := int(ci)
		if sim.arena.terrain[i] != Arena.T.BUILDING:
			continue
		var d := m.pos.distance_to(sim.arena.center_of_index(i))
		if d < bd:
			bd = d
			best = i
	return best


func _fire(m: CombatMech, st: Dictionary) -> void:
	var tgt := target_of(m)
	var cmd: Dictionary = st.get("cmd", {})
	if str(cmd.get("type", "")) == "attack_cell" and (tgt == null or tgt.pos.distance_to(m.pos) > 350.0):
		if sim.t >= float(st["next_fire"]):
			st["next_fire"] = sim.t + 0.2
			var ci := _objective_cell(m, cmd)
			if ci >= 0:
				for wi in m.weapons:
					if sim.weapon_ready(m, wi):
						sim.fire_at_cell(m, wi, ci)
		return
	if tgt == null:
		return
	if sim.t < float(st["next_fire"]):
		return
	st["next_fire"] = sim.t + 0.2
	var any_ready := false
	for wi in m.weapons:
		if float(m.mounts[wi]["cooldown"]) <= 0.0:
			any_ready = true
			break
	if not any_ready:
		return
	var cap := heat_cap(m)
	var limit := max_tn(m)
	if tgt.internal_lost_fraction() > 0.5:
		limit += 1
	var order: Array = []
	for wi in m.weapons:
		if sim.weapon_ready(m, wi) and sim.in_arc(m, m.mounts[wi], tgt):
			var wt: String = m.mounts[wi]["item"].get("wtype", "")
			if wt in ["narc", "inarc"] and tgt.narced.get(m.team, false):
				continue
			order.append(wi)
	if order.is_empty():
		return
	order.sort_custom(func(a, b): return float(m.mounts[a]["item"].get("dmg", 0)) * maxf(1.0, float(m.mounts[a]["item"].get("rack", 1))) > float(m.mounts[b]["item"].get("dmg", 0)) * maxf(1.0, float(m.mounts[b]["item"].get("rack", 1))))
	for wi in order:
		var mt: Dictionary = m.mounts[wi]
		var th := sim.to_hit(m, mt, tgt)
		if not th["ok"]:
			continue
		var tn: int = th["tn"]
		var lim := limit
		var bi := sim.find_ammo(m, mt)
		if bi >= 0 and int(m.mounts[bi]["shots"]) <= 3:
			lim -= 1
		if tn > lim:
			continue
		var h := float(mt["item"].get("heat", 0)) * (2.0 if mt["item"].get("wtype", "") == "uac" else 1.0)
		# hold fire when the shot would push the 'Mech past its heat discipline, unless it is all but
		# cold: a PPC or a large laser is ten heat or more in one go and has to be fired sometime
		if h > 0.0 and m.heat + h > cap and m.heat > maxf(0.0, cap - 6.0):
			continue
		sim.fire(m, wi, tgt)
		if tgt.out:
			return


func _physical(m: CombatMech) -> void:
	if sim.t < m.physical_ready_at:
		return
	var tgt := target_of(m)
	if tgt == null or tgt.gait == CombatMech.Gait.JUMP or tgt.airborne:
		return
	if m.is_infantry:
		# anti-'Mech troops swarm the legs of a 'Mech that lets them get close
		if m.anti_mech and not tgt.is_vehicle and m.troopers_alive() > 0 \
				and m.pos.distance_to(tgt.pos) <= float(sim.tables["infantry"]["leg_attack"]["reach_m"]):
			sim.leg_attack(m, tgt)
		return
	if m.is_vehicle:
		_vehicle_ram(m, tgt)
		return
	var reach := float(sim.tables["physical"]["reach_m"])
	var dist := m.pos.distance_to(tgt.pos)
	# grab a club when brawling next to heavy woods or rubble
	if dist < 90.0 and m.club_uses == 0 and m.physical_weapon == "" and (m.has_trait("brawler") or m.has_trait("showboat") or str(m.orders["position"]) == "brawl"):
		if sim.pick_up_club(m):
			return
	if dist > reach or not sim.in_front_arc(m, tgt):
		return
	var options: Array = []  # [score, kind, arm]
	var legs_ok := m.legs_destroyed() == 0 and m.count_hit("LL", "hip") + m.count_hit("RL", "hip") == 0
	var tsm := 2.0 if (m.design.myomer == "tsm" and m.heat >= 9.0) or m.always_strong else 1.0
	if m.club_uses > 0:
		options.append([CombatSim.p_hit(sim._phys_tn(m, tgt, -1)) * ceilf(m.tons() / 5.0) * tsm * 1.4, "club", ""])
	if m.physical_weapon != "" and not m.loc_destroyed["LA"] and not m.loc_destroyed["RA"] and not tgt.is_vehicle:
		var ph: Dictionary = sim.tables["physical"][m.physical_weapon]
		options.append([CombatSim.p_hit(sim._phys_tn(m, tgt, int(ph["to_hit"]))) * sim.phys_damage(m, ph) * tsm, m.physical_weapon, "RA"])
	if legs_ok and tgt.gait != CombatMech.Gait.PRONE:
		options.append([CombatSim.p_hit(sim._phys_tn(m, tgt, -2)) * ceilf(m.tons() / 5.0) * tsm * 1.1, "kick", ""])
	if not m.no_arms and m.club_uses == 0 and not tgt.is_vehicle:
		for arm in ["RA", "LA"]:
			if m.has_part(arm, "shoulder"):
				options.append([CombatSim.p_hit(sim._phys_tn(m, tgt, 0)) * ceilf(m.tons() / 10.0) * tsm, "punch", arm])
				break
	# charge: only at a run, only if the impact is worth the recoil
	var hexes := sim.hexes_moved(m)
	if sim.t - m.last_run_t < 1.0 and hexes >= 3 and not m.has_trait("cautious") and tgt.gait != CombatMech.Gait.PRONE:
		var tn_c := sim._phys_tn(m, tgt, 0) + (m.piloting - tgt.piloting)
		var dmg_c: float = ceilf(m.tons() / 10.0) * mini(hexes, m.run_mp()) * tsm
		var risk: float = ceilf(tgt.tons() / 10.0) * 0.6
		var keen := 1.3 if m.has_trait("showboat") or str(m.orders["position"]) == "brawl" else 0.8
		options.append([(CombatSim.p_hit(tn_c) * dmg_c - risk) * keen, "charge", ""])
	# push a target that's next to fire, a hazard or a building wall
	if m.arms_free() and tgt.gait != CombatMech.Gait.PRONE and not tgt.is_vehicle:
		var dest := tgt.pos + (tgt.pos - m.pos).normalized() * 30.0
		var bonus := _cell_danger(sim.arena, dest) * 3.0
		if sim.arena.terrain[sim.arena.cell_index(dest)] == Arena.T.BUILDING:
			bonus += 6.0
		if bonus > 0.0:
			options.append([CombatSim.p_hit(sim._phys_tn(m, tgt, -1)) * bonus, "push", ""])
	if options.is_empty():
		return
	options.sort_custom(func(a, b): return a[0] > b[0])
	if float(options[0][0]) <= 0.4:
		return
	sim.physical(m, tgt, options[0][1], options[0][2])


## Vehicles ram: only at speed, only when the target is lighter or badly hurt.
func _vehicle_ram(m: CombatMech, tgt: CombatMech) -> void:
	if m.airborne or m.walk_mp() <= 0:
		return
	var reach := float(sim.tables["physical"]["reach_m"])
	if m.pos.distance_to(tgt.pos) > reach or not sim.in_front_arc(m, tgt):
		return
	var hexes := sim.hexes_moved(m)
	if sim.t - m.last_run_t > 1.0 or hexes < 3 or m.has_trait("cautious"):
		return
	var gain := ceilf(m.tons() / 10.0) * mini(hexes, m.run_mp())
	var risk := ceilf(tgt.tons() / 10.0) * 1.5
	if gain > risk and sim.rng.chance(0.4):
		sim.physical(m, tgt, "charge")


# ------------------------------------------------------------------ yielding

## Merc battles: crippled units fall back to their edge (Total Warfare forced withdrawal) instead of
## yielding; a 'Mech that can't move any more ejects.
func _consider_withdraw(m: CombatMech) -> void:
	var st: Dictionary = state[m.index]
	var ct := str((st["cmd"] as Dictionary).get("type", "free"))
	if ct == "withdraw":
		return
	if m.controller == "player" and not sim.bout.get("auto_withdraw", true):
		return
	var crippled := false
	if m.is_infantry:
		# a squad breaks when too few are left standing
		crippled = m.center_internal_fraction() < float(sim.tables["infantry"]["break_fraction"])
	elif m.is_vehicle:
		crippled = m.immobile or m.engine_dead or m.cruise_halved or m.internal_lost_fraction() > 0.5
		for loc in m.internal:
			# a side down to a quarter of its structure; a light hull that starts there is not crippled new
			if int(m.internal[loc]) < int(m.max_internal[loc]) and int(m.internal[loc]) <= int(ceil(m.max_internal[loc] / 4.0)):
				crippled = true
	else:
		crippled = m.legs_destroyed() > 0 or m.engine_hits >= 2 or m.gyro_hits >= 1 or m.pilot_hits >= 4
		crippled = crippled or m.center_internal_fraction() < 0.5 or m.internal_lost_fraction() > 0.45
		var lost := 0
		for loc in ["LA", "RA", "LT", "RT", "LL", "RL"]:
			if m.loc_destroyed[loc]:
				lost += 1
		crippled = crippled or lost >= 2
	var armed := false
	for wi in m.weapons:
		var mt: Dictionary = m.mounts[wi]
		if not mt["destroyed"] and not m.loc_destroyed[mt["loc"]] and sim.find_ammo(m, mt) != -1 and not (mt["item"].get("wtype", "") in ["ams", "tag", "narc", "inarc", "other"]):
			armed = true
			break
	crippled = crippled or not armed
	if m.has_trait("iron_man") and armed and not m.is_vehicle and m.legs_destroyed() == 0:
		crippled = m.center_internal_fraction() < 0.3
	if not crippled:
		return
	if m.walk_mp() <= 0:
		if not m.is_vehicle and (m.legs_destroyed() >= 2 or m.gyro_hits >= 2) and m.center_internal_fraction() < 0.6:
			m.ejected = true
			sim.log_event({"k": "eject", "tg": m.index})
			sim.set_out(m, "ejected")
		return
	sim.log_event({"k": "withdraw_order", "tg": m.index})
	command(m, {"type": "withdraw", "edge": sim.home_edge(m.team)})


func _consider_yield(m: CombatMech) -> void:
	if sim.merc:
		_consider_withdraw(m)
		return
	var score := m.internal_lost_fraction()
	# a breached center torso means the reactor is next: most arena fighters yield here
	score += (1.0 - m.center_internal_fraction()) * 0.7
	if float(m.armor.get("CT", 0)) + float(m.armor.get("CTR", 0)) <= 4.0:
		score += 0.15
	if m.engine_hits >= 1:
		score += 0.15
	if m.engine_hits >= 2:
		score += 0.25
	if m.gyro_hits >= 1:
		score += 0.1
	if m.legs_destroyed() > 0:
		score += 0.3
	score += m.pilot_hits * 0.07
	if m.armor_fraction() < 0.2:
		score += 0.15
	var armed := false
	for wi in m.weapons:
		var mt: Dictionary = m.mounts[wi]
		if not mt["destroyed"] and not m.loc_destroyed[mt["loc"]] and sim.find_ammo(m, mt) != -1 and not (mt["item"].get("wtype", "") in ["ams", "tag", "narc", "inarc", "other"]):
			armed = true
			break
	if not armed:
		score += 0.45
	var limit := float(m.orders["retreat"])
	if m.has_trait("iron_man"):
		limit += 0.3
	if m.has_trait("cautious"):
		limit -= 0.15
	if m.has_trait("hot_blooded") or m.has_trait("showboat"):
		limit += 0.1
	# in a team fight, hang on while teammates still need you
	if sim.teammates(m).size() > 0:
		limit += 0.05
	if score < limit:
		return
	if sim.bout.get("to_death", false):
		if score >= limit + 0.3 and not m.has_trait("iron_man"):
			m.ejected = true
			sim.log_event({"k": "eject", "tg": m.index})
			sim.set_out(m, "ejected")
		return
	m.yielded = true
	sim.log_event({"k": "yield", "tg": m.index})
	sim.set_out(m, "yielded")
