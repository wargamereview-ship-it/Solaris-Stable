extends "res://ui/designer/designer.gd"
## The vehicle workshop: the mech lab's workbench for a mercenary company's combat vehicle.
## A refit changes what the vehicle carries and how its armor is spread; the hull, engine, drive and
## turret stay as built. Weapons go in a facing or the turret, ammo in the body, gear anywhere.
## A vehicle has no crit slots: each location is a list, and the item-slot budget is for the whole
## hull. Opened from the Hangar tab (setup_merc); the top bar, parts list, quote and order are the
## mech lab's own.

const VCOLS := [["LS", "#weight"], ["FR", "TU", "RR"], ["RS", "BD"]]
const V_ARMORS := ["standard", "ferro"]
const NO_VEHICLE := ["masc", "tsm", "hatchet", "sword", "mace", "supercharger"]
const VWEIGHT := [Color(0.5, 0.55, 0.62), Color(0.96, 0.64, 0.2), Color(0.76, 0.56, 0.3), Color(0.62, 0.52, 0.9),
	Color(0.5, 0.75, 0.6), Color(0.3, 0.75, 0.85), Color(0.75, 0.75, 0.5), Color(0.3, 0.62, 0.95), Color(0.92, 0.42, 0.36),
	Color(0.45, 0.45, 0.5)]


func _vd() -> VehicleDesign:
	return d as VehicleDesign


func _title() -> String:
	return "VEHICLE WORKSHOP"


func _noun() -> String:
	return "vehicle"


func _crits(_id: String, _df: float) -> int:
	return 1


func _biggest_run() -> int:
	return 99


func _part_ok(it: Dictionary) -> bool:
	return not (str(it.get("misc", "")) in NO_VEHICLE)


func _layout() -> Array:
	return VCOLS


func _locs() -> Array:
	var out: Array = []
	for loc in ["FR", "LS", "RS", "RR", "TU"]:
		if d.armor.has(loc):
			out.append(loc)
	out.append("BD")
	return out


func _sig() -> String:
	var a: Array = []
	for k in d.armor:
		a.append("%s=%d" % [k, int(d.armor[k])])
	a.sort()
	var eq: Array = []
	for e in _vd().equipment:
		eq.append("%s@%s" % [e[0], e[1]])
	eq.sort()
	return JSON.stringify([d.armor_type, a, eq])


func _takes(loc: String, id: String) -> bool:
	return MercCampaign.vehicle_loc_takes(_vd(), loc, GameData.db().item(id))


# ---------------------------------------------------------------- summary strip

func _build_summary() -> Control:
	var h := UI.hbox(20)
	var p := UI.panel(h)
	var sh := CenterContainer.new()
	sh.custom_minimum_size = Vector2(84, 66)
	h.add_child(sh)
	w["sprite_box"] = sh
	w["sprite_path"] = ""
	var nv := UI.vbox(4)
	nv.custom_minimum_size.x = 268
	nv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(nv)
	var nm := UI.title(d.display_name(), 20)
	nm.clip_text = true
	nv.add_child(nm)
	w["name"] = nm
	var ns := UI.label("", 12, UI.DIM)
	nv.add_child(ns)
	w["name_sub"] = ns
	h.add_child(_gauge("g_tons", "Tonnage", "cubes"))
	h.add_child(_gauge("g_crit", "Item slots", "microchip"))
	h.add_child(_gauge("g_heat", "Heat sinks", "fire"))
	h.add_child(_gauge("g_armor", "Armor", "shield"))
	var sv := UI.hbox(18)
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k in [["s_move", "Cruise / flank"], ["s_bv", "Battle value"], ["s_cost", "Vehicle price"]]:
		var v := UI.vbox(-2)
		v.add_child(_caption(k[1]))
		var l := UI.label("", 19, UI.TEXT)
		l.add_theme_font_override("font", UI.font("cond_semi"))
		v.add_child(l)
		w[k[0]] = l
		sv.add_child(v)
	h.add_child(sv)
	return p


func _refresh_summary() -> void:
	var v := _vd()
	if w["sprite_path"] != d.sprite:
		w["sprite_path"] = d.sprite
		UI.clear(w["sprite_box"])
		(w["sprite_box"] as Control).add_child(Views.sprite(d.sprite, Game.tint_material(mc.color, mc.camo), 84))
	(w["name"] as Label).text = d.display_name().to_upper()
	(w["name_sub"] as Label).text = "%s  ·  %d tons  ·  %s%s" % [v.motion_label(), d.tons,
		"Inner Sphere tech" if d.tech == "IS" else str(d.tech).capitalize() + " tech", "  ·  turret" if v.turret else ""]
	var used: float = rep.get("tons_used", 0.0)
	var free := d.tons - used
	var tcol := UI.GOOD if absf(free) < 0.005 else (UI.BAD if free < 0.0 else UI.WARN)
	var segs: Array = []
	var bd: Array = rep.get("breakdown", [])
	for i in bd.size():
		segs.append([float(bd[i][1]) / d.tons, VWEIGHT[i % VWEIGHT.size()]])
	var tsub := "every ton used" if absf(free) < 0.005 else ("%s t over the limit" % _t(-free) if free < 0.0 else "%s t free" % _t(free))
	_set_gauge("g_tons", "%s / %d t" % [_t(used), d.tons], tsub, tcol, segs, free < -0.005)
	var su := int(rep.get("slots_used", 0))
	var sm := int(rep.get("slots_max", 1))
	_set_gauge("g_crit", "%d / %d" % [su, sm], "%d free" % (sm - su) if su <= sm else "%d over the hull's room" % (su - sm),
		UI.TEXT if su <= sm else UI.WARN, [[float(su) / maxf(1.0, sm), UI.BLUE]], su > sm)
	var sinks := int(rep.get("sinks", 0))
	var hsub := "the engine's 10 cover the energy weapons" if sinks == 0 else "%d t beyond the engine's 10" % sinks
	if not v.fusion():
		hsub = "one per point of energy weapon heat" if sinks > 0 else "no energy weapons to cool"
	_set_gauge("g_heat", str(sinks), hsub, UI.TEXT, [[minf(1.0, sinks / 20.0), UI.ACCENT]])
	var ap := int(rep.get("armor_points", 0))
	var am := int(rep.get("armor_max", 1))
	_set_gauge("g_armor", "%d / %d" % [ap, am], "%s t  ·  %d%% of the maximum" % [
		_t(Construction.half_up(ap / VehicleConstruction.armor_ppt(v))), int(round(100.0 * ap / maxf(1.0, am)))],
		UI.TEXT if ap <= am else UI.BAD, [[float(ap) / maxf(1.0, am), UI.BLUE]], ap > am)
	(w["s_move"] as Label).text = "%d / %d" % [d.walk, v.flank_mp()]
	(w["s_bv"] as Label).text = str(int(rep.get("bv", 0)))
	(w["s_cost"] as Label).text = UI.money(int(rep.get("cost", 0)))


# ---------------------------------------------------------------- left column: hull and armor

func _build_left() -> Control:
	var v := UI.vbox(10)
	v.custom_minimum_size.x = 296
	var fr := _card("Hull", "cog")
	v.add_child(fr.get_parent())
	var rows := UI.vbox(3)
	fr.add_child(rows)
	w["hull_rows"] = rows
	var hint := UI.label("A refit keeps the hull, engine, drive and turret as built.", 12, UI.DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fr.add_child(hint)
	var ar := _card("Armor", "shield")
	v.add_child(ar.get_parent())
	_choice(ar, "armor", "Type", func(v2: String): d.armor_type = v2)
	doll = load("res://ui/widgets/vehicle_doll.gd").new(1.25)
	var dc := CenterContainer.new()
	dc.add_child(doll)
	ar.add_child(dc)
	var ah := UI.hbox(4)
	for b in [UI.button("Max", _max_armor, "As much armor as the hull may carry, spread like it is now"),
			UI.button("Fit to free tons", _fit_armor, "Turn whatever tonnage is left into armor, spread like it is now"),
			UI.button("Strip", _strip_armor, "Take all the armor off")]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		ah.add_child(b)
	ar.add_child(ah)
	var s := UI.scroll(v)
	s.size_flags_horizontal = Control.SIZE_FILL
	s.custom_minimum_size.x = 296
	return s


func _refresh_frame() -> void:
	var v := _vd()
	var box: VBoxContainer = w["hull_rows"]
	UI.clear(box)
	for kv in [["Drive", v.motion_label()], ["Tonnage", "%d t" % d.tons], ["Cruise / flank", "%d / %d" % [d.walk, v.flank_mp()]],
			["Engine", "%d %s" % [d.engine_rating, _nice(d.engine_type)]], ["Turret", "yes" if v.turret else "no"],
			["Crew", str(v.crew_size())]]:
		box.add_child(_kv(str(kv[0]).to_upper(), str(kv[1]), UI.TEXT))


func _refresh_armor() -> void:
	_fill("armor", V_ARMORS, d.armor_type, func(o):
		var probe := _vd().copy() as VehicleDesign
		probe.armor_type = o
		return "%s pts/t" % _t(VehicleConstruction.armor_ppt(probe)))
	doll.set_design(_vd(), {})


## Spreads `total` armor points over the locations in the proportions they have now (evenly on a
## stripped hull).
func _spread_armor(total: int) -> void:
	var keys: Array = d.armor.keys()
	var cur := d.armor_total()
	var given := 0
	for k in keys:
		var share := float(d.armor[k]) / cur if cur > 0 else 1.0 / keys.size()
		d.armor[k] = int(floor(total * share))
		given += int(d.armor[k])
	var i := 0
	while given < total and not keys.is_empty():
		d.armor[keys[i % keys.size()]] += 1
		given += 1
		i += 1


func _max_armor() -> void:
	_spread_armor(VehicleConstruction.max_armor(_vd()))
	_rebuild()


func _fit_armor() -> void:
	var v := _vd()
	var r := Construction.analyze(d)
	var ppt := VehicleConstruction.armor_ppt(v)
	var budget := float(r.get("tons_free", d.tons - float(r.get("tons_used", 0.0)))) + Construction.half_up(d.armor_total() / ppt)
	# whole half tons only, as the weight of armor rounds up to the half ton
	var pts := int(floor(floorf(budget * 2.0) / 2.0 * ppt))
	_spread_armor(clampi(pts, 0, VehicleConstruction.max_armor(v)))
	_rebuild()


func _clamp_armor() -> void:
	pass


# ---------------------------------------------------------------- middle: one card per location

func _build_loc(loc: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _loc_box("plain"))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(4)
	p.add_child(v)
	var h := UI.hbox(4)
	var ln := UI.label(str(VehicleDesign.VLOC_NAMES[loc]).to_upper(), 12, UI.ACCENT)
	ln.add_theme_font_override("font", UI.spaced("cond_semi", 1))
	ln.clip_text = true
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ln)
	var fl := UI.label("", 11, UI.DIM)
	h.add_child(fl)
	v.add_child(h)
	var ml := UI.label("", 11, UI.DIM)
	var bar := SegBar.new(3)
	if loc == "BD":
		var bl := UI.label("Ammunition and gear, inside the hull", 11, UI.DIM)
		bl.clip_text = true
		v.add_child(bl)
	elif d.armor.has(loc):
		var ah := UI.hbox(3)
		var ic := UI.label(UI.ic("shield"), 11, UI.DIM)
		ic.tooltip_text = "Armor"
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		ah.add_child(ic)
		ah.add_child(_small_spin(loc, "%s armor" % VehicleDesign.VLOC_NAMES[loc]))
		ml.custom_minimum_size.x = 44
		ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ah.add_child(ml)
		v.add_child(ah)
		v.add_child(bar)
	else:
		var nl := UI.label("This vehicle has no turret", 11, UI.DIM)
		v.add_child(nl)
	var sl := UI.vbox(1)
	sl.custom_minimum_size.y = ROW_H
	v.add_child(sl)
	w["loc_" + loc] = {"panel": p, "free": fl, "max": ml, "bar": bar, "slots": sl}
	_zone(p, loc, -1)
	if loc != "BD":
		p.mouse_entered.connect(func(): doll.highlight = loc)
		p.mouse_exited.connect(func():
			if doll.highlight == loc:
				doll.highlight = "")
	return p


func _refresh_locs() -> void:
	var db := GameData.db()
	var v := _vd()
	var dragging := not drag.is_empty()
	var moving := dragging and str(drag["from"]) != ""
	var part: String = str(drag["id"]) if dragging else sel_item
	var picking := part != ""
	var pick_name: String = db.item(part).get("name", part) if picking else ""
	var total := d.armor_total()
	var room := VehicleConstruction.max_armor(v) - total
	for loc in ["FR", "LS", "RS", "RR", "TU", "BD"]:
		var card: Dictionary = w["loc_" + loc]
		var exists: bool = loc == "BD" or d.armor.has(loc)
		var ok: bool = picking and exists and _takes(loc, part) and not (moving and str(drag["from"]) == loc)
		if exists and loc != "BD":
			var cur := int(d.armor[loc])
			(w["armor_" + loc] as SpinBox).max_value = maxi(cur, cur + room)
			(w["armor_" + loc] as SpinBox).value = cur
			(card["max"] as Label).text = "%d%%" % int(round(100.0 * cur / maxf(1.0, total)))
			(card["max"] as Label).tooltip_text = "Share of the vehicle's armor on this side"
			(card["max"] as Label).mouse_filter = Control.MOUSE_FILTER_STOP
			(card["bar"] as SegBar).show_segs([[float(cur) / maxf(1.0, total), UI.BLUE]])
		var n_here := 0
		for e in v.equipment:
			if str(e[1]) == loc:
				n_here += 1
		var fl: Label = card["free"]
		fl.text = ("fits" if ok else "not here") if picking else ("%d mounted" % n_here if n_here > 0 else "empty")
		fl.add_theme_color_override("font_color", (UI.ACCENT if ok else UI.BAD.lerp(UI.DIM, 0.4)) if picking else UI.DIM)
		var pnl: PanelContainer = card["panel"]
		pnl.add_theme_stylebox_override("panel", _loc_box("lit" if ok else "plain"))
		pnl.modulate = Color(1, 1, 1, 0.5) if (picking and not ok) or not exists else Color.WHITE
		var box: VBoxContainer = card["slots"]
		UI.clear(box)
		if not exists:
			continue
		for i in v.equipment.size():
			var e: Array = v.equipment[i]
			if str(e[1]) != loc:
				continue
			var id := str(e[0])
			var it := db.item(id)
			var kind: String = it.get("kind", "misc")
			if not kind in ["weapon", "ammo"]:
				kind = "misc"
			var kc := UI.TEXT if kind == "weapon" else (UI.WARN.lerp(UI.TEXT, 0.4) if kind == "ammo" else UI.BLUE.lerp(UI.TEXT, 0.35))
			var blk: Button
			if moving and loc == str(drag["from"]) and i == int(drag["idx"]):
				blk = _block(str(it.get("name", id)), 1, "lifted", UI.DIM.darkened(0.3))
			else:
				var idx := i
				var tip := "%s  ·  %s t  ·  drag to move it, click to take it off" % [it.get("name", id), _t(Construction.item_tons(d, id, 0.0))]
				blk = _block(str(it.get("name", id)), 1, kind, kc, tip, func(): _remove_mount(loc, idx, id))
				_zone(blk, loc, i, _mount_drag.bind({"lab": true, "id": id, "slot": id, "from": loc, "idx": i, "n": 1,
					"name": str(it.get("name", id)), "weapon": kind == "weapon", "auto": false, "jet": false}))
				box.add_child(blk)
				continue
			box.add_child(_zone(blk, loc, i))
		if ok and not dragging:
			box.add_child(_zone(_block("+  " + pick_name, 1, "ghost", UI.ACCENT.lightened(0.25), "Mount it here", func(): _place(loc)), loc, -1))
		elif ok:
			box.add_child(_zone(_block("", 1, "open", UI.DIM), loc, -1))
	_refresh_banner()
	_refresh_weight()


func _refresh_banner() -> void:
	var bp: PanelContainer = w["banner"]
	var bl: Label = w["banner_l"]
	var picking := sel_item != ""
	var dragging := not drag.is_empty()
	(w["banner_x"] as Button).visible = picking and not dragging
	var binning := dragging and str(drag["from"]) != ""
	(w["parts_panel"] as PanelContainer).add_theme_stylebox_override("panel", w["parts_sb_lit"] if binning else w["parts_sb"])
	var rule := "weapons go in a facing or the turret, ammo in the body, gear anywhere"
	if dragging:
		bl.text = "%s   %s  %s   —   drop it on a lit location%s." % [UI.ic("crosshairs"), "MOVING" if binning else "PLACING",
			str(drag["name"]).to_upper(), ", or on the parts list to take it off" if binning else ""]
		bl.add_theme_color_override("font_color", UI.ACCENT.lightened(0.2))
		bp.add_theme_stylebox_override("panel", _banner_box("pick"))
	elif picking:
		var it := GameData.db().item(sel_item)
		bl.text = "%s   PLACING  %s  ·  %s t   —   click a lit location to mount it (%s).%s" % [UI.ic("crosshairs"),
			str(it.get("name", sel_item)).to_upper(), _t(Construction.item_tons(d, sel_item, 0.0)), rule, ("   " + note) if note != "" else ""]
		bl.add_theme_color_override("font_color", UI.ACCENT.lightened(0.2) if note == "" else UI.WARN)
		bp.add_theme_stylebox_override("panel", _banner_box("pick"))
	elif note != "":
		bl.text = "%s   %s" % [UI.ic("warning"), note]
		bl.add_theme_color_override("font_color", UI.WARN)
		bp.add_theme_stylebox_override("panel", _banner_box("note"))
	else:
		bl.text = "%s   Drag a part onto a location, or pick it and click one.  Mounted parts: drag to move, click to take off.  Ctrl+Z undoes." % UI.ic("info")
		bl.add_theme_color_override("font_color", UI.DIM)
		bp.add_theme_stylebox_override("panel", _banner_box("idle"))


func _refresh_weight() -> void:
	var box: VBoxContainer = w["weight_rows"]
	UI.clear(box)
	var bd: Array = rep.get("breakdown", [])
	for i in bd.size():
		box.add_child(_kv(str(bd[i][0]), _t(float(bd[i][1])), UI.TEXT if float(bd[i][1]) > 0.0 else UI.DIM, VWEIGHT[i % VWEIGHT.size()]))
	var free := d.tons - float(rep.get("tons_used", 0.0))
	var line := ColorRect.new()
	line.color = UI.LINE
	line.custom_minimum_size.y = 1
	box.add_child(line)
	box.add_child(_kv("Free" if free >= -0.005 else "Over", _t(absf(free)), UI.GOOD if absf(free) < 0.005 else (UI.BAD if free < 0.0 else UI.WARN)))


# ---------------------------------------------------------------- changing the design

func _place(loc: String) -> void:
	if sel_item == "":
		return
	if not _takes(loc, sel_item):
		note = "%s can't go in the %s." % [GameData.db().item(sel_item).get("name", sel_item), VehicleDesign.VLOC_NAMES[loc]]
	else:
		_vd().equipment.append([sel_item, loc])
		note = ""
	_rebuild()


func _remove_mount(loc: String, idx: int, id: String) -> void:
	var eq: Array = _vd().equipment
	if idx >= 0 and idx < eq.size() and str(eq[idx][0]) == id and str(eq[idx][1]) == loc:
		eq.remove_at(idx)
	note = ""
	_rebuild()


func _landing(loc: String, _idx: int, data: Dictionary) -> int:
	if loc != "BD" and not d.armor.has(loc):
		return -1
	if str(data["from"]) == loc or not _takes(loc, str(data["id"])):
		return -1
	return 0


func _can_drop(_at: Vector2, data, loc: String, idx: int) -> bool:
	if not _is_part(data) or drag.is_empty():
		return false
	if _landing(loc, idx, data) < 0:
		_hide_land()
		return false
	var box: Control = w["loc_" + loc]["slots"]
	var rows := maxi(0, box.get_child_count() - 1)   # the last child is the open row the part lands on
	var m: Control = w["land"]
	m.global_position = box.global_position + Vector2(0, rows * (ROW_H + 1))
	m.size = Vector2(box.size.x, ROW_H)
	m.visible = true
	_land_loc = loc
	if loc != "BD":
		doll.highlight = loc
	return true


func _drop(_at: Vector2, data, loc: String, idx: int) -> void:
	if not _is_part(data) or _landing(loc, idx, data) < 0:
		return
	var eq: Array = _vd().equipment
	var from := str(data["from"])
	if from != "":
		var i := int(data["idx"])
		if i < 0 or i >= eq.size() or str(eq[i][0]) != str(data["id"]) or str(eq[i][1]) != from:
			return  # the design changed under the drag
		eq[i] = [str(data["id"]), loc]
	else:
		eq.append([str(data["id"]), loc])
		sel_item = ""
		(w["tree"] as Tree).deselect_all()
	note = ""
	_rebuild()


func _can_bin(_at: Vector2, data) -> bool:
	return _is_part(data) and str(data["from"]) != ""


func _bin(_at: Vector2, data) -> void:
	if not _can_bin(_at, data):
		return
	_remove_mount(str(data["from"]), int(data["idx"]), str(data["id"]))


func _hide_land() -> void:
	if w.has("land"):
		(w["land"] as Control).visible = false
	if _land_loc != "" and doll != null and doll.highlight == _land_loc:
		doll.highlight = ""
	_land_loc = ""
