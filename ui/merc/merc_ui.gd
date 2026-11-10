class_name MercUI
extends RefCounted
## Shared pieces for the merc screens: unit and people status, record sheets for 'Mechs and vehicles.

const VehicleDoll := preload("res://ui/widgets/vehicle_doll.gd")
const SquadDoll := preload("res://ui/widgets/squad_doll.gd")


static func unit_status(c: MercCampaign, u: MercUnit) -> Array:
	if u.wreck():
		return ["Wreck", UI.BAD]
	if u.refitting():
		return ["Refitting %d%%" % int(c.refit_progress(u) * 100), UI.ACCENT]
	var p := c.crew_of(u)
	if p == null:
		return ["No crew", UI.WARN]
	if not p.available():
		return ["Crew %s" % p.status, UI.WARN]
	if u.damaged():
		var reload_only := true
		for t in MercRepair.tasks(u):
			if str(t["kind"]) != "reload":
				reload_only = false
		if reload_only:
			return ["Needs ammo", UI.TEXT]
		return ["Damaged %d%%" % maxi(1, int(u.damage_fraction() * 100)), UI.WARN]
	if not u.refit.is_empty():
		return ["Ready (refit)", UI.GOOD]
	return ["Ready", UI.GOOD]


static func person_status(p: MercPerson) -> Array:
	match p.status:
		"active":
			return ["Active", UI.GOOD]
		"injured":
			return ["Injured (%d days)" % p.injury_days, UI.WARN]
		"dead":
			return ["Killed", UI.BAD]
		"mia":
			return ["Missing", UI.BAD]
		"left":
			return ["Left", UI.DIM]
	return [p.status, UI.DIM]


static func portrait(p: MercPerson, size := 80) -> Control:
	var tr := TextureRect.new()
	tr.texture = Game.portrait(p.portrait)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(size, size * 1.25)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.03, 0.035), 3, UI.LINE, 1))
	pc.add_child(tr)
	if tr.texture == null:
		var l := UI.label(p.role_label().substr(0, 1), 28, UI.DIM, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		pc.add_child(l)
	return pc


static func doll(d: MechDesign, condition := {}, s := 1.0) -> Control:
	if d.is_infantry():
		var sd = SquadDoll.new(s)
		sd.set_design(d as VehicleDesign, condition)
		return sd
	if d.is_vehicle():
		var vd = VehicleDoll.new(s)
		vd.set_design(d as VehicleDesign, condition)
		return vd
	return Views.doll(d, condition, s)


## Record sheet for either kind of unit.
static func sheet(d: MechDesign, condition := {}, mat: Material = null, year := -1) -> Control:
	if not d.is_vehicle():
		return Views.sheet(d, condition, mat, year)
	var vd := d as VehicleDesign
	var rep := Construction.analyze(d, year)
	if d.is_infantry():
		return _infantry_sheet(vd, condition, mat, rep)
	var v := UI.vbox(6)
	var h := UI.hbox(12)
	h.add_child(Views.sprite(d.sprite, mat if mat != null else Game.tint_material(Color(0.6, 0.6, 0.6)), 110))
	h.add_child(doll(d, condition, 1.0))
	var info := UI.vbox(2)
	info.add_child(UI.label(d.display_name(), 17, UI.TEXT, true))
	info.add_child(UI.label("%d-ton %s vehicle  ·  %s" % [d.tons, vd.motion_label().to_lower(), d.tech], 13, UI.DIM))
	info.add_child(UI.label("Cruise %d / Flank %d MP  ·  %d %s engine" % [vd.walk, vd.flank_mp(), vd.engine_rating, vd.engine_type.replace("_", " ")], 13))
	info.add_child(UI.label("Armor %d pts  ·  crew %d  ·  %s" % [vd.armor_total(), vd.crew_size(), "turret" if vd.turret else "no turret"], 13))
	info.add_child(UI.label("BV %d  ·  %s" % [int(rep.get("bv", 0)), Campaign.money(int(rep.get("cost", 0)))], 13, UI.DIM))
	h.add_child(info)
	v.add_child(h)
	var w := UI.vbox(1)
	var ammo := {}
	for mt in rep.get("mounts", []):
		var it: Dictionary = mt["item"]
		if it.get("kind", "") == "ammo":
			ammo[str(it.get("ammo", ""))] = int(ammo.get(str(it.get("ammo", "")), 0)) + int(it.get("shots", 0))
	var dead := {}
	for mi in condition.get("dead_mounts", []):
		dead[int(mi)] = true
	var mounts: Array = rep.get("mounts", [])
	for i in mounts.size():
		var mt2: Dictionary = mounts[i]
		var it2: Dictionary = mt2["item"]
		if it2.get("kind", "") != "weapon":
			continue
		var line := "%-22s %-6s  %2d dmg  %d/%d/%d" % [str(it2.get("name", "")), VehicleDesign.VLOC_NAMES.get(mt2["loc"], mt2["loc"]).left(6),
			int(it2.get("dmg", 0)) * maxi(1, int(it2.get("rack", 1))) if str(it2.get("wtype", "")) in CombatSim.MISSILE_TYPES else int(it2.get("dmg", 0)),
			int(it2.get("s", 0)), int(it2.get("m", 0)), int(it2.get("l", 0))]
		if ammo.has(str(it2.get("ammo", ""))):
			line += "  (%d shots)" % int(ammo[str(it2.get("ammo", ""))])
		w.add_child(Views.mono_label(line, 12, UI.BAD if dead.has(i) else UI.TEXT))
	v.add_child(w)
	return v


## Record sheet for a platoon or a battle armour squad: who is left, how they move, what they carry.
static func _infantry_sheet(vd: VehicleDesign, condition: Dictionary, mat: Material, rep: Dictionary) -> Control:
	var v := UI.vbox(6)
	var h := UI.hbox(12)
	h.add_child(Views.sprite(vd.sprite, mat if mat != null else Game.tint_material(Color(0.6, 0.6, 0.6)), 110))
	h.add_child(doll(vd, condition, 1.0))
	var info := UI.vbox(2)
	info.add_child(UI.label(vd.display_name(), 17, UI.TEXT, true))
	var ba := vd.is_battle_armor()
	info.add_child(UI.label("%s  ·  %s  ·  %s" % ["Battle armor squad" if ba else "Infantry platoon", vd.motion_label(), vd.tech], 13, UI.DIM))
	info.add_child(UI.label("Move %d MP%s" % [vd.walk, "  ·  jump %d" % vd.jump if vd.jump > 0 else ""], 13))
	if ba:
		info.add_child(UI.label("%d suits, %d armor each" % [vd.troopers, vd.suit_armor], 13))
	else:
		info.add_child(UI.label("%d troopers%s" % [vd.troopers, "  ·  carried in armored transports" if vd.armor_div > 1 else ""], 13))
	if vd.anti_mech:
		info.add_child(UI.label("Trained to swarm a 'Mech's legs at point-blank range", 13, UI.ACCENT))
	info.add_child(UI.label("BV %d  ·  %s" % [int(rep.get("bv", 0)), Campaign.money(int(rep.get("cost", 0)))], 13, UI.DIM))
	h.add_child(info)
	v.add_child(h)
	var w := UI.vbox(1)
	for sw in vd.squad_weapons:
		var full := maxi(1, int(ceil(vd.troopers * float(sw.get("per", 0.27)))))
		var line := "%-22s %2d dmg at full strength  %d/%d/%d" % [str(sw.get("name", "")), full, int(sw.get("s", 0)), int(sw.get("m", 0)), int(sw.get("l", 0))]
		if int(sw.get("salvos", 0)) > 0:
			line += "  (%d salvos)" % int(sw["salvos"])
		w.add_child(Views.mono_label(line, 12, UI.TEXT))
	v.add_child(w)
	return v
