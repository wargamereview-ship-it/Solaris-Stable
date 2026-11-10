extends Control
## The mech lab: refit an owned 'Mech or build a new one on one workbench screen.
##
## Across the top, gauges for the four budgets (tonnage, crit slots, heat, armor). On the left the
## frame (engine, movement, structure, sinks) and the armor doll. In the middle one card per location,
## laid out like the 'Mech's body, each with its armor and its crit slots. On the right the parts list.
## Along the bottom the legality checks, the quote and the order button.
##
## The lab serves both game modes. In the stable game (setup) it draws on the stable's stores and the
## parts market and the refit is paid on the spot. In the mercenary game (setup_merc) the parts list
## holds everything made at the campaign's date: ordering the refit sets aside what the warehouse has
## and puts the rest on the logistics shopping list, and the techs start once every part is in.
##
## The screen is built once (_ready) and then only refreshed in place: every change calls _rebuild(),
## which waits for the next idle and re-reads the design into the controls. Each refresh also compares
## the design with the last one it saw and files the old one for undo, so every edit is undoable
## without the edit having to say so.
##
## Parts can be dragged as well as clicked: from the parts list onto a location to mount them, from
## one location to another to move them, and back onto the parts list to take them off. While a part
## is in the air `drag` describes it, the locations that can take it light up and a marker shows the
## exact slots it would land in.

const ENGINES := ["standard", "xl", "light", "compact", "xxl"]
const STRUCTS := ["standard", "endo", "endo_composite", "composite", "reinforced"]
const ARMORS := ["standard", "ferro", "light_ferro", "heavy_ferro", "hardened", "reactive", "reflective",
	"ballistic_reinforced", "impact_resistant", "anti_penetrative", "heat_dissipating"]
const GYROS := ["standard", "xl", "compact", "heavy_duty"]
const COCKPITS := ["standard", "small", "torso"]
const HS := ["single", "double"]
## The location cards, column by column, as the 'Mech stands facing you.
const ROW_H := 28
const NICE := {"xl": "XL", "xxl": "XXL", "endo": "Endo steel", "ferro": "Ferro-fibrous",
	"light_ferro": "Light ferro-fibrous", "heavy_ferro": "Heavy ferro-fibrous", "heavy_duty": "Heavy-duty",
	"torso": "Torso-mounted", "tsm": "TSM", "xl_clan": "XL (Clan)", "xxl_clan": "XXL (Clan)", "ice": "Combustion",
	"fuel_cell": "Fuel cell", "endo_clan": "Endo steel (Clan)", "endo_composite": "Endo-composite",
	"endo_composite_clan": "Endo-composite (Clan)", "endo_proto": "Endo steel prototype",
	"ferro_clan": "Ferro-fibrous (Clan)", "ferro_lamellor": "Ferro-lamellor", "reflective": "Laser-reflective",
	"reflective_clan": "Laser-reflective (Clan)", "reactive_clan": "Reactive (Clan)",
	"heavy_industrial": "Heavy industrial", "ballistic_reinforced": "Ballistic-reinforced",
	"impact_resistant": "Impact-resistant", "anti_penetrative": "Anti-penetrative ablation",
	"heat_dissipating": "Heat-dissipating", "ferro_proto": "Ferro-fibrous prototype", "none": "None",
	"primitive_industrial": "Primitive industrial", "command_console": "Command console",
	"double_clan": "Double (Clan)", "industrial_tsm": "Industrial TSM", "super_cooled": "Super-cooled"}
## The weight groups of Construction.analyze's breakdown, in its order, and their colors on the bar.
const WEIGHT := [["Structure", Color(0.5, 0.55, 0.62)], ["Engine", Color(0.96, 0.64, 0.2)],
	["Gyro", Color(0.74, 0.5, 0.2)], ["Cockpit", Color(0.62, 0.48, 0.86)], ["Armor", Color(0.38, 0.68, 0.98)],
	["Heat sinks", Color(0.3, 0.8, 0.78)], ["Weapons, gear", Color(0.92, 0.42, 0.36)]]
const HIDDEN_MISC := ["heat_sink", "double_heat_sink", "jump_jet", "tsm", "other", "stealth", "c3", "command_console"]
const WEIGHTLESS_OK := ["masc", "hatchet", "sword", "mace", "tc", "supercharger"]

var c: Campaign                # the stable game (null in the mercenary game)
var mc: MercCampaign           # the mercenary game (null in the stable game)
var mu: MercUnit               # the mercenary 'Mech on the bench
var _tn_base := 0              # the admin's parts roll before the part's own rarity
var uid := -1
var d: MechDesign
var orig: MechDesign
var sel_item := ""
var note := ""
var filter := "weapons"
var search := ""
var sort_col := 0
var sort_desc := false
var rep: Dictionary = {}       # Construction.analyze of d, as of the last refresh
var quote: Dictionary = {}     # the refit or build quote, as of the last refresh
var doll                       # the armor doll (PaperDoll)
var w := {}                    # the controls a refresh writes to, by name

var _base: Dictionary = {}     # the design this session started from
var _base_sig := ""
var _last: Dictionary = {}     # the design as of the last refresh
var _last_sig := ""
var _undo: Array = []
var _redo: Array = []
var _syncing := false          # a refresh is writing values into controls: their signals are not edits
var _rebuild_queued := false
var _tree_key := ""
var _card_sb: Dictionary = {}
var drag: Dictionary = {}      # the part being dragged: id, slot, from (location or ""), idx, n, name, weapon, auto
var _land_loc := ""            # the location the landing marker is showing in


## One bar of colored segments: [[fraction, color], ...] laid left to right.
class SegBar extends Control:
	var segs: Array = []
	var over := false

	func _init(h := 8) -> void:
		custom_minimum_size = Vector2(40, h)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS

	func show_segs(s: Array, is_over := false) -> void:
		segs = s
		over = is_over
		queue_redraw()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.07))
		var x := 0.0
		for s in segs:
			var sw := minf(clampf(float(s[0]), 0.0, 1.0) * size.x, size.x - x)
			if sw >= 1.0:
				draw_rect(Rect2(x, 0, maxf(1.0, sw - 1.0), size.y), s[1])
			x += sw
		if over:
			draw_rect(Rect2(Vector2(0.5, 0.5), size - Vector2.ONE), UI.BAD, false, 1.0)


func setup(camp: Campaign, mech_uid: int, fresh: MechDesign) -> void:
	c = camp
	uid = mech_uid
	if uid >= 0:
		orig = c.mechs[uid].design
		d = orig.copy()
	else:
		d = fresh
		d.year = c.year
		d.tech = "IS"
		d.chassis = "Custom"
		d.model = "SOL-%d" % d.tons
		orig = null
	_base = d.to_dict().duplicate(true)
	_base_sig = _sig()
	_last = _base
	_last_sig = _base_sig


## The mercenary game: refit one of the company's 'Mechs.
func setup_merc(camp: MercCampaign, unit_id: int) -> void:
	mc = camp
	uid = unit_id
	mu = mc.units[uid]
	orig = mu.design
	d = orig.copy()
	_base = d.to_dict().duplicate(true)
	_base_sig = _sig()
	_last = _base
	_last_sig = _base_sig


func _year() -> int:
	return mc.year() if mc != null else c.year


func _leave() -> void:
	if mc != null:
		Game.show_merc_hub("hangar")
	else:
		Game.show_hub("bay")


## The warehouse key of an item in the mercenary game.
func _part_key(id: String) -> String:
	return ("ammo:" if GameData.db().item(id).get("kind", "") == "ammo" else "item:") + id


## How many of an item are on the shelves (the mercenary warehouse counts ammo in tons).
func _have(id: String) -> float:
	if mc != null:
		return float(mc.warehouse.get(_part_key(id), 0.0))
	return float(c.player().inventory.get(id, 0))


## The weekly 2d6 roll the company's admin needs to find an item; -1 when nobody sells it.
func _find_tn(id: String) -> int:
	var info := MercRepair.part_info(_part_key(id), mc.year())
	if str(info["avail"]) == "X":
		return -1
	return _tn_base + int(mc.rules["procurement"]["avail_mod"].get(str(info["avail"]), 0))


func _ready() -> void:
	add_child(UI.backdrop())
	var root := UI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	root.add_child(_build_top())
	var body := MarginContainer.new()
	for side in ["left", "right"]:
		body.add_theme_constant_override("margin_" + side, 12)
	body.add_theme_constant_override("margin_top", 10)
	body.add_theme_constant_override("margin_bottom", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	var bv := UI.vbox(10)
	body.add_child(bv)
	bv.add_child(_build_summary())
	var cols := UI.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bv.add_child(cols)
	cols.add_child(_build_left())
	cols.add_child(_build_mid())
	cols.add_child(_build_parts())
	root.add_child(_build_bottom())
	_build_marker()
	UI.fade_in(self, 0.2)
	_rebuild()


# ---------------------------------------------------------------- refresh, undo, input

## Every control here calls _rebuild from its own signal, and so do the tests after changing the
## design by hand. The refresh waits for the next idle so a burst of changes costs one pass.
func _rebuild() -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	_rebuild_now.call_deferred()


func _rebuild_now() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	_track()
	rep = Construction.analyze(d, _year())
	if mc != null:
		quote = mc.refit_quote(uid, d)
	else:
		quote = c.refit_quote(uid, d) if uid >= 0 else c.build_quote(d)
	_syncing = true
	_refresh_top()
	_refresh_summary()
	_refresh_frame()
	_refresh_armor()
	_refresh_locs()
	_refresh_parts()
	_refresh_bottom()
	_syncing = false


## What makes two designs the same build: everything but the name.
func _sig() -> String:
	var a: Array = []
	for k in d.armor:
		a.append("%s=%d" % [k, int(d.armor[k])])
	a.sort()
	return JSON.stringify([d.tons, d.tech, d.engine_rating, d.engine_type, d.structure, d.armor_type, d.gyro,
		d.cockpit, d.myomer, d.hs_count, d.hs_type, d.walk, d.jump, a, d.slots, d.sprite])


func _dirty() -> bool:
	return _sig() != _base_sig


## Files the previous design for undo when the design changed since the last refresh.
func _track() -> void:
	var s := _sig()
	if s == _last_sig:
		return
	_undo.append(_last)
	if _undo.size() > 80:
		_undo.pop_front()
	_redo.clear()
	_last = d.to_dict().duplicate(true)
	_last_sig = s


func _restore(snap: Dictionary) -> void:
	d = VehicleDesign.any_from_dict(snap.duplicate(true))
	_last = snap
	_last_sig = _sig()
	note = ""
	_rebuild()


func _undo_step() -> void:
	_track()
	if _undo.is_empty():
		return
	_redo.append(_last)
	_restore(_undo.pop_back())


func _redo_step() -> void:
	if _redo.is_empty() or _sig() != _last_sig:
		return
	_undo.append(_last)
	_restore(_redo.pop_back())


func _revert() -> void:
	_track()
	if not _dirty():
		return
	_undo.append(_last)
	_redo.clear()
	_restore(_base.duplicate(true))


## Renaming is not an undo step: the new name is written through the whole history instead.
func _rename(field: String, text: String) -> void:
	var old: String = d.get(field)
	d.set(field, text)
	for s in _undo + _redo + [_last]:
		if s.get(field, "") == old:
			s[field] = text
	_refresh_top()


func _pick(id: String) -> void:
	sel_item = id
	note = ""
	if id == "" and w.has("tree"):
		(w["tree"] as Tree).deselect_all()
	_rebuild()


func _back() -> void:
	_track()
	if _dirty():
		UI.confirm(self, "Leave the mech lab?", "The changes to this design have not been ordered and will be lost.", _leave)
	else:
		_leave()


func _notification(what: int) -> void:
	# the drag is over, dropped or not: back to the normal look
	if what == NOTIFICATION_DRAG_END and not drag.is_empty():
		drag = {}
		_hide_land()
		_rebuild()


func _input(e: InputEvent) -> void:
	if _land_loc != "" and e is InputEventMouseMotion:
		# the marker leaves with the pointer; the location under it puts it back (_can_drop)
		var cp: Control = w["loc_" + _land_loc]["panel"]
		if not cp.get_global_rect().has_point((e as InputEventMouseMotion).position):
			_hide_land()
	var mb := e as InputEventMouseButton
	if sel_item != "" and mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
		_pick("")
		get_viewport().set_input_as_handled()


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed:
		return
	if k.keycode == KEY_ESCAPE and sel_item != "":
		_pick("")
	elif k.keycode == KEY_Z and k.is_command_or_control_pressed():
		if k.shift_pressed:
			_redo_step()
		else:
			_undo_step()
	elif k.keycode == KEY_Y and k.is_command_or_control_pressed():
		_redo_step()
	else:
		return
	get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- small helpers

## What the vehicle workshop (vehicle_lab.gd, which extends this screen) answers differently.
func _title() -> String:
	return "MECH LAB"


func _noun() -> String:
	return "'Mech"


## Slots a part takes on this design.
func _crits(id: String, df: float) -> int:
	return Construction.item_crits(d, id, df)


## The longest run of free slots in one location: a part that needs more can't go anywhere.
func _biggest_run() -> int:
	var biggest := 0
	for loc in MechDesign.LOCS:
		var run := 0
		for s in d.slots[loc]:
			run = run + 1 if s == "" else 0
			biggest = maxi(biggest, run)
	return biggest


## Whether the parts list offers this kind of part at all.
func _part_ok(_it: Dictionary) -> bool:
	return true


## The location cards, column by column ("#weight" and "#loadout" are the two summary cards).
func _layout() -> Array:
	return [["LA", "#weight"], ["LT", "LL"], ["HD", "CT"], ["RT", "RL"], ["RA", "#loadout"]]


func _caption(text: String, col := UI.DIM) -> Label:
	var l := UI.label(text.to_upper(), 11, col)
	l.add_theme_font_override("font", UI.spaced("cond_semi", 1))
	return l


func _nice(key: String) -> String:
	return NICE.get(key, key.replace("_", " ").capitalize())


## Tons without trailing zeros: 12, 0.5, 2.25.
func _t(x: float) -> String:
	var s := "%.2f" % (0.0 if absf(x) < 0.005 else x)
	return s.rstrip("0").rstrip(".")


## A stat from the item table as text: whole numbers without ".0", nothing for a missing one.
func _num(v) -> String:
	if v == null:
		return ""
	return _t(float(v)) if (v is float or v is int) else str(v)


func _slots(n: int) -> String:
	return "1 slot" if n == 1 else "%d slots" % n


## A titled card; returns the box its rows go in.
func _card(title: String, icon: String) -> VBoxContainer:
	var v := UI.vbox(3)
	UI.panel(v)
	v.add_child(UI.header(title, icon))
	return v


func _avail(kind: String, key: String) -> bool:
	return GameData.db().component_available(kind, key, _year()) or (orig != null and _orig_value(kind) == key)


func _orig_value(kind: String) -> String:
	match kind:
		"engine":
			return orig.engine_type
		"structure":
			return orig.structure
		"armor":
			return orig.armor_type
		"gyro":
			return orig.gyro
		"cockpit":
			return orig.cockpit
		"hs":
			return orig.hs_type
	return ""


## Where a part of `crits` slots would land in a location's row (MechDesign.place's rule), or -1.
func _fit_start(row: Array, crits: int) -> int:
	for start in row.size() - crits + 1:
		var ok := true
		for k in crits:
			if row[start + k] != "":
				ok = false
				break
		if ok:
			return start
	return -1


# ---------------------------------------------------------------- top bar

func _build_top() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.bar_box(true))
	var h := UI.hbox(8)
	bar.add_child(h)
	var ttl := UI.label(UI.ic("wrench") + "  " + _title(), 19, UI.ACCENT)
	ttl.add_theme_font_override("font", UI.spaced("cond", 3))
	h.add_child(ttl)
	var sub := UI.label("", 13, UI.DIM)
	sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub.clip_text = true
	h.add_child(sub)
	w["top_sub"] = sub
	w["undo"] = UI.ibutton("arrow_left", "Undo", _undo_step, "Take back the last change (Ctrl+Z)")
	w["redo"] = UI.ibutton("arrow_right", "Redo", _redo_step, "Put it back (Ctrl+Y)")
	w["revert"] = UI.ibutton("refresh", "Start over", _revert, "Throw away every change made here (can be undone)")
	for k in ["undo", "redo", "revert"]:
		(w[k] as Button).focus_mode = Control.FOCUS_NONE
		h.add_child(w[k])
	var gap := Control.new()
	gap.custom_minimum_size.x = 10
	h.add_child(gap)
	var back := UI.button("Back to the hangar" if mc != null else "Back to the bay", _back)
	back.focus_mode = Control.FOCUS_NONE
	h.add_child(back)
	return bar


func _refresh_top() -> void:
	var what: String = "NEW BUILD  ·  " + d.display_name()
	if mc != null:
		what = "REFIT  ·  " + mu.label()
	elif uid >= 0:
		what = "REFIT  ·  " + c.mechs[uid].label()
	(w["top_sub"] as Label).text = "    %s  ·  parts and tech of %d%s" % [what, _year(), "  ·  unsaved changes" if _dirty() else ""]
	(w["undo"] as Button).disabled = _undo.is_empty()
	(w["redo"] as Button).disabled = _redo.is_empty()
	(w["revert"] as Button).disabled = not _dirty()


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
	if uid >= 0:
		var nm := UI.title(d.display_name(), 20)
		nm.clip_text = true
		nv.add_child(nm)
		w["name"] = nm
	else:
		var nh := UI.hbox(4)
		var ch := LineEdit.new()
		ch.placeholder_text = "Chassis"
		ch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ch.text_changed.connect(func(t): _rename("chassis", t))
		var md := LineEdit.new()
		md.placeholder_text = "Model"
		md.custom_minimum_size.x = 104
		md.text_changed.connect(func(t): _rename("model", t))
		nh.add_child(ch)
		nh.add_child(md)
		nv.add_child(nh)
		w["chassis"] = ch
		w["model"] = md
		var so := OptionButton.new()
		so.tooltip_text = "Start from a stock design instead of a bare chassis"
		so.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		so.add_item("Start from: bare chassis", 0)
		var ids: Array = []
		for e in c.market_pool():
			ids.append(e["id"])
		ids.sort()
		for i in ids.size():
			so.add_item("Start from: " + str(ids[i]), i + 1)
		so.item_selected.connect(func(i):
			if _syncing:
				return
			if i == 0:
				d = MechDesign.blank(d.tons, d.walk)
			else:
				d = MechDesign.from_stock(ids[i - 1])
				d.model = d.model + "-S"
			d.year = c.year
			note = ""
			_rebuild())
		nv.add_child(so)
	var ns := UI.label("", 12, UI.DIM)
	ns.visible = uid >= 0
	nv.add_child(ns)
	w["name_sub"] = ns
	h.add_child(_gauge("g_tons", "Tonnage", "cubes"))
	h.add_child(_gauge("g_crit", "Crit slots", "microchip"))
	h.add_child(_gauge("g_heat", "Heat", "fire"))
	h.add_child(_gauge("g_armor", "Armor", "shield"))
	var sv := UI.hbox(18)
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for k in [["s_move", "Walk / run / jump"], ["s_bv", "Battle value"], ["s_cost", "'Mech price"]]:
		var v := UI.vbox(-2)
		v.add_child(_caption(k[1]))
		var l := UI.label("", 19, UI.TEXT)
		l.add_theme_font_override("font", UI.font("cond_semi"))
		v.add_child(l)
		w[k[0]] = l
		sv.add_child(v)
	h.add_child(sv)
	return p


## A budget gauge: caption and figure, a bar, and a line saying what is left.
func _gauge(key: String, caption: String, icon: String) -> Control:
	var v := UI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	v.custom_minimum_size.x = 150
	var h := UI.hbox(6)
	var cap := _caption(UI.ic(icon) + "  " + caption)
	cap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(cap)
	var val := UI.label("", 17, UI.TEXT)
	val.add_theme_font_override("font", UI.font("cond_semi"))
	h.add_child(val)
	v.add_child(h)
	var bar := SegBar.new(8)
	v.add_child(bar)
	var sub := UI.label("", 12, UI.DIM)
	sub.clip_text = true
	v.add_child(sub)
	w[key + "_val"] = val
	w[key + "_bar"] = bar
	w[key + "_sub"] = sub
	return v


func _set_gauge(key: String, value: String, sub: String, col: Color, segs: Array, over := false) -> void:
	(w[key + "_val"] as Label).text = value
	(w[key + "_val"] as Label).add_theme_color_override("font_color", col)
	(w[key + "_sub"] as Label).text = sub
	(w[key + "_sub"] as Label).add_theme_color_override("font_color", col if over else UI.DIM)
	(w[key + "_bar"] as SegBar).show_segs(segs, over)


func _refresh_summary() -> void:
	if w["sprite_path"] != d.sprite:
		w["sprite_path"] = d.sprite
		UI.clear(w["sprite_box"])
		(w["sprite_box"] as Control).add_child(Views.sprite(d.sprite,
			Game.tint_material(mc.color, mc.camo) if mc != null else Game.stable_material(c.player_id), 84))
	if uid >= 0:
		(w["name"] as Label).text = d.display_name().to_upper()
	else:
		for f in ["chassis", "model"]:
			var le: LineEdit = w[f]
			if le.text != str(d.get(f)):
				le.text = str(d.get(f))
	(w["name_sub"] as Label).text = "%s  ·  %d tons  ·  %s tech" % [str(d.weight_class()).capitalize(), d.tons, "Inner Sphere" if d.tech == "IS" else str(d.tech).capitalize()]
	# tonnage: the bar stacks the weight groups, so what eats the tons shows at a glance
	var used: float = rep.get("tons_used", 0.0)
	var free := d.tons - used
	var tcol := UI.GOOD if absf(free) < 0.005 else (UI.BAD if free < 0.0 else UI.WARN)
	var segs: Array = []
	var bd: Array = rep.get("breakdown", [])
	for i in mini(bd.size(), WEIGHT.size()):
		segs.append([float(bd[i][1]) / d.tons, WEIGHT[i][1]])
	var tsub := "every ton used" if absf(free) < 0.005 else ("%s t over the limit" % _t(-free) if free < 0.0 else "%s t free" % _t(free))
	_set_gauge("g_tons", "%s / %d t" % [_t(used), d.tons], tsub, tcol, segs, free < -0.005)
	var total := 0
	var open := 0
	for loc in MechDesign.LOCS:
		total += int(MechDesign.SLOT_COUNT[loc])
		open += d.free_slots(loc)
	_set_gauge("g_crit", "%d / %d" % [total - open, total], "%d slots free" % open, UI.TEXT, [[float(total - open) / total, UI.BLUE]])
	var heat: Dictionary = rep.get("heat", {})
	var alpha := int(heat.get("alpha", 0))
	var diss := int(heat.get("dissipation", 0))
	var hcol := UI.GOOD if alpha <= diss else (UI.WARN if alpha <= diss * 1.4 else UI.BAD)
	var hsub := "sinks %d, firing everything makes %d" % [diss, alpha] if alpha <= diss else "%d more than the sinks shed" % (alpha - diss)
	_set_gauge("g_heat", "%d / %d" % [alpha, diss], hsub, hcol, [[float(alpha) / maxf(1.0, diss), hcol]], alpha > diss)
	var ap := int(rep.get("armor_points", 0))
	var am := int(rep.get("armor_max", 1))
	_set_gauge("g_armor", "%d / %d" % [ap, am], "%s t  ·  %d%% of the maximum" % [_t(Construction.armor_tons(d.armor_total(), d.armor_type)), int(round(100.0 * ap / maxf(1.0, am)))], UI.TEXT, [[float(ap) / maxf(1.0, am), UI.BLUE]])
	(w["s_move"] as Label).text = "%d / %d / %d" % [d.walk, d.run_mp(), d.jump]
	(w["s_bv"] as Label).text = str(int(rep.get("bv", 0)))
	(w["s_cost"] as Label).text = UI.money(int(rep.get("cost", 0)))


# ---------------------------------------------------------------- left column: frame and armor

func _build_left() -> Control:
	var v := UI.vbox(10)
	v.custom_minimum_size.x = 296
	var fr := _card("Frame", "cog")
	v.add_child(fr.get_parent())
	_spin(fr, "tons", "Tonnage", 20, 100, 5, func(nv: int):
		var keep := d.copy()
		d.tons = nv
		d.engine_rating = mini(400, d.tons * d.walk)
		d.walk = d.engine_rating / d.tons
		d.engine_rating = d.tons * d.walk
		d.apply_fixed_layout()
		_clamp_armor()
		d.sprite = keep.sprite if keep.tons == nv else "defaults/default_%s.png" % GameData.db().weight_class(nv))
	(w["tons"] as SpinBox).editable = uid < 0
	(w["tons"] as SpinBox).tooltip_text = "" if uid < 0 else "A refit cannot change the chassis weight"
	_spin(fr, "walk", "Walk MP", 1, 20, 1, func(nv: int):
		d.walk = nv
		d.engine_rating = d.tons * nv
		_sync_sinks()
		if d.jump > d.walk:
			_set_jump(d.walk))
	_spin(fr, "jump", "Jump MP", 0, 20, 1, func(nv: int): _set_jump(nv))
	_choice(fr, "engine", "Engine", func(v2: String):
		d.engine_type = v2
		_relayout())
	_choice(fr, "gyro", "Gyro", func(v2: String):
		d.gyro = v2
		_relayout())
	_choice(fr, "cockpit", "Cockpit", func(v2: String):
		d.cockpit = v2
		_relayout())
	_choice(fr, "structure", "Structure", func(v2: String):
		d.structure = v2
		_fillers("endo", Construction.STRUCT_FILLERS.get(v2, 0)))
	_choice(fr, "hs", "Heat sinks", func(v2: String):
		_clear_sinks()
		d.hs_type = v2
		_sync_sinks())
	_spin(fr, "sinks", "Sink count", 10, 60, 1, func(nv: int):
		d.hs_count = nv
		_sync_sinks())
	var ar := _card("Armor", "shield")
	v.add_child(ar.get_parent())
	_choice(ar, "armor", "Type", func(v2: String):
		d.armor_type = v2
		_fillers("ferro", Construction.ARMOR_FILLERS.get(v2, 0)))
	doll = load("res://ui/widgets/paper_doll.gd").new(1.0)
	var dc := CenterContainer.new()
	dc.add_child(doll)
	ar.add_child(dc)
	var ah := UI.hbox(4)
	for b in [UI.button("Max", _max_armor, "Full armor everywhere, a quarter of each torso to the rear"),
			UI.button("Fit to free tons", _fit_armor, "Spread whatever tonnage is left as armor, evenly"),
			UI.button("Strip", _strip_armor, "Take all the armor off")]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_NONE
		ah.add_child(b)
	ar.add_child(ah)
	var s := UI.scroll(v)
	s.size_flags_horizontal = Control.SIZE_FILL
	s.custom_minimum_size.x = 296
	return s


func _row(parent: Control, caption: String, key: String) -> HBoxContainer:
	var h := UI.hbox(6)
	var l := _caption(caption)
	l.custom_minimum_size.x = 82
	h.add_child(l)
	w[key + "_cap"] = l
	parent.add_child(h)
	return h


## A number row of the frame card: caption, spin box, and a short note of what the number costs.
func _spin(parent: Control, key: String, caption: String, lo: int, hi: int, step: int, apply: Callable) -> void:
	var h := _row(parent, caption, key)
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.value_changed.connect(func(nv):
		if _syncing:
			return
		apply.call(int(nv))
		_rebuild())
	h.add_child(s)
	var t := UI.label("", 12, UI.DIM)
	t.custom_minimum_size.x = 62
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(t)
	w[key] = s
	w[key + "_t"] = t


## A dropdown row; its options are filled at each refresh, with what each one weighs.
func _choice(parent: Control, key: String, caption: String, apply: Callable) -> void:
	var h := _row(parent, caption, key)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.clip_text = true
	ob.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	ob.item_selected.connect(func(i):
		if _syncing:
			return
		apply.call(str(ob.get_item_metadata(i)))
		_rebuild())
	h.add_child(ob)
	w[key] = ob


func _fill(key: String, opts: Array, cur: String, suffix: Callable) -> void:
	var ob: OptionButton = w[key]
	ob.clear()
	var list := opts.duplicate()
	if not (cur in list):
		list.append(cur)        # a stock design's own part, though the lab does not offer it
	for o in list:
		if not (_avail(key, o) or o == cur):
			continue
		ob.add_item(_nice(o) + "    " + str(suffix.call(o)))
		ob.set_item_metadata(ob.item_count - 1, o)
		if o == cur:
			ob.select(ob.item_count - 1)


func _set_spin(key: String, value: int, hi: int, info: String) -> void:
	var s: SpinBox = w[key]
	s.max_value = hi
	s.value = value
	(w[key + "_t"] as Label).text = info


func _refresh_frame() -> void:
	_set_spin("tons", d.tons, 100, str(d.weight_class()))
	_set_spin("walk", d.walk, maxi(1, 400 / d.tons), "run %d" % d.run_mp())
	_set_spin("jump", d.jump, d.walk, "%s t" % _t(Construction.jump_jet_tons(d.tons) * d.jump))
	var heat: Dictionary = rep.get("heat", {})
	_set_spin("sinks", d.hs_count, 60, "%d in engine" % int(heat.get("integral", 0)))
	(w["engine_cap"] as Label).text = "ENGINE %d" % d.engine_rating
	_fill("engine", ENGINES, d.engine_type, func(o): return _t(Construction.engine_tons(d.engine_rating, o)) + " t")
	_fill("gyro", GYROS, d.gyro, func(o): return _t(Construction.gyro_tons(d.engine_rating, o)) + " t")
	_fill("cockpit", COCKPITS, d.cockpit, func(o): return _t(Construction.COCKPIT_TONS[o]) + " t")
	_fill("structure", STRUCTS, d.structure, func(o): return _t(Construction.structure_tons(d.tons, o)) + " t")
	_fill("hs", HS, d.hs_type, func(o): return "1 slot each" if o == "single" else "3 slots each")


func _refresh_armor() -> void:
	_fill("armor", ARMORS, d.armor_type, func(o): return "%s pts/t" % _t(Construction.armor_ppt(o)))
	doll.set_design(d, {})


func _max_armor() -> void:
	for loc in MechDesign.LOCS:
		var mx := Construction.max_armor(d.tons, loc)
		if MechDesign.REAR.has(loc):
			d.armor[MechDesign.REAR[loc]] = int(mx * 0.25)
			d.armor[loc] = mx - int(mx * 0.25)
		else:
			d.armor[loc] = mx
	_rebuild()


func _strip_armor() -> void:
	for k in d.armor:
		d.armor[k] = 0
	_rebuild()


# ---------------------------------------------------------------- middle: the body, one card per location

func _build_mid() -> Control:
	var v := UI.vbox(6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# the banner says what a click does right now
	var bp := PanelContainer.new()
	bp.custom_minimum_size.y = 34
	var bh := UI.hbox(8)
	bp.add_child(bh)
	var bl := UI.label("", 13, UI.DIM)
	bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bl.clip_text = true
	bl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	bh.add_child(bl)
	var bx := UI.button("Cancel", func(): _pick(""), "Put the part back (right-click or Esc)")
	bx.focus_mode = Control.FOCUS_NONE
	bx.add_theme_font_size_override("font_size", 12)
	bh.add_child(bx)
	v.add_child(bp)
	w["banner"] = bp
	w["banner_l"] = bl
	w["banner_x"] = bx
	var grid := UI.hbox(6)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for col in _layout():
		var cv := UI.vbox(6)
		cv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cv.size_flags_stretch_ratio = 1.0
		cv.custom_minimum_size.x = 120
		for loc in col:
			if loc == "#weight":
				cv.add_child(_build_weight())
			elif loc == "#loadout":
				cv.add_child(_build_loadout())
			else:
				cv.add_child(_build_loc(loc))
		grid.add_child(cv)
	var s := UI.scroll(grid)
	v.add_child(s)
	return v


func _tight(bg: Color, border: Color, bw := 1) -> StyleBoxFlat:
	var sb := UI.box(bg, 4, border, bw)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 5
	sb.content_margin_bottom = 7
	return sb


## The look of a location card: plain, lit (the picked part fits here) or shut (it does not).
func _loc_box(kind: String) -> StyleBoxFlat:
	if not _card_sb.has(kind):
		match kind:
			"lit":
				_card_sb[kind] = _tight(UI.PANEL.lerp(UI.ACCENT, 0.06), UI.ACCENT, 1)
			_:
				_card_sb[kind] = _tight(UI.PANEL, UI.LINE, 1)
	return _card_sb[kind]


func _small_spin(key: String, tip: String) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = 0
	s.max_value = 99
	s.tooltip_text = tip
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.get_line_edit().add_theme_constant_override("minimum_character_width", 2)
	s.get_line_edit().add_theme_font_size_override("font_size", 13)
	s.value_changed.connect(func(nv):
		if _syncing:
			return
		d.armor[key] = int(nv)
		_clamp_armor()
		_rebuild())
	w["armor_" + key] = s
	return s


func _build_loc(loc: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _loc_box("plain"))
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(4)
	p.add_child(v)
	var h := UI.hbox(4)
	var ln := UI.label(str(MechDesign.LOC_NAMES[loc]).to_upper(), 12, UI.ACCENT)
	ln.add_theme_font_override("font", UI.spaced("cond_semi", 1))
	ln.clip_text = true
	ln.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(ln)
	var fl := UI.label("", 11, UI.DIM)
	h.add_child(fl)
	v.add_child(h)
	var ah := UI.hbox(3)
	var ic := UI.label(UI.ic("shield"), 11, UI.DIM)
	ic.tooltip_text = "Armor"
	ic.mouse_filter = Control.MOUSE_FILTER_STOP
	ah.add_child(ic)
	ah.add_child(_small_spin(loc, "%s armor%s" % [MechDesign.LOC_NAMES[loc], ", front" if MechDesign.REAR.has(loc) else ""]))
	if MechDesign.REAR.has(loc):
		var rl := UI.label("R", 11, UI.DIM)
		rl.tooltip_text = "Rear armor"
		rl.mouse_filter = Control.MOUSE_FILTER_STOP
		ah.add_child(rl)
		ah.add_child(_small_spin(MechDesign.REAR[loc], "%s armor, rear" % MechDesign.LOC_NAMES[loc]))
	var ml := UI.label("", 11, UI.DIM)
	ml.custom_minimum_size.x = 22
	ml.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ah.add_child(ml)
	v.add_child(ah)
	var bar := SegBar.new(3)
	v.add_child(bar)
	var sl := UI.vbox(1)
	v.add_child(sl)
	w["loc_" + loc] = {"panel": p, "free": fl, "max": ml, "bar": bar, "slots": sl}
	_zone(p, loc, -1)
	p.mouse_entered.connect(func(): doll.highlight = loc)
	p.mouse_exited.connect(func():
		if doll.highlight == loc:
			doll.highlight = "")
	return p


## The look of one slot block. Kinds: empty, open (empty and takes the picked part), ghost (where the
## picked part would land), land (the drag marker), lifted (where a part being dragged came from),
## fixed, filler, and weapon / ammo / misc for mounted parts.
func _slot_box(kind: String, hover := false) -> StyleBoxFlat:
	var key := kind + ("+" if hover else "")
	if _card_sb.has(key):
		return _card_sb[key]
	var bg := Color(0, 0, 0, 0.26)
	var stripe := Color(0, 0, 0, 0)
	match kind:
		"open":
			bg = Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.16 if hover else 0.05)
		"ghost":
			bg = Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.34 if hover else 0.2)
			stripe = UI.ACCENT
		"land":
			bg = UI.PANEL.lerp(UI.ACCENT, 0.42)
			stripe = UI.ACCENT.lightened(0.3)
		"lifted":
			bg = Color(1, 1, 1, 0.02)
		"fixed":
			bg = Color(1, 1, 1, 0.05)
		"arm":
			bg = Color(0.9, 0.3, 0.25, 0.2) if hover else Color(1, 1, 1, 0.05)
		"filler":
			bg = Color(1, 1, 1, 0.03)
		"auto":
			stripe = WEIGHT[5][1]
			bg = Color(stripe.r, stripe.g, stripe.b, 0.08)
		"weapon":
			stripe = UI.TEXT
		"ammo":
			stripe = UI.WARN
		"misc":
			stripe = UI.BLUE
	if kind in ["weapon", "ammo", "misc"]:
		bg = Color(0.9, 0.3, 0.25, 0.22) if hover else Color(stripe.r, stripe.g, stripe.b, 0.11)
	var sb := UI.box(bg, 2)
	sb.content_margin_left = 6
	sb.content_margin_right = 4
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	if stripe.a > 0.0:
		sb.border_width_left = 3
		sb.border_color = UI.BAD if hover and kind in ["weapon", "ammo", "misc"] else stripe
		sb.content_margin_left = 5
	_card_sb[key] = sb
	return sb


## One block in a location's slot list, `n` slots tall.
func _block(text: String, n: int, kind: String, col: Color, tip := "", cb := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.add_theme_font_size_override("font_size", 13)
	b.custom_minimum_size.y = ROW_H * n + (n - 1)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	for st in ["normal", "disabled"]:
		b.add_theme_stylebox_override(st, _slot_box(kind))
	for st in ["hover", "pressed"]:
		b.add_theme_stylebox_override(st, _slot_box(kind, cb.is_valid()))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for cn in ["font_color", "font_disabled_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(cn, col)
	if cb.is_valid():
		b.pressed.connect(cb)
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	else:
		b.mouse_filter = Control.MOUSE_FILTER_PASS if tip == "" else Control.MOUSE_FILTER_STOP
		b.disabled = tip == ""
	if n > 1 and kind in ["weapon", "ammo", "misc", "ghost"]:
		var cnt := UI.label("%d slots" % n, 11, Color(col.r, col.g, col.b, 0.55))
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cnt.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cnt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		cnt.position -= Vector2(5, 2)
		b.add_child(cnt)
	return b


func _remove_mount(loc: String, idx: int, id: String) -> void:
	var it := GameData.db().item(id)
	var misc: String = it.get("misc", "")
	if misc in ["heat_sink", "double_heat_sink"]:
		note = "Heat sinks follow the sink count in the frame card."
	elif misc == "jump_jet":
		note = "Jump jets follow Jump MP in the frame card."
	else:
		d.remove_at(loc, idx, Construction.item_crits(d, id, Construction.direct_fire_tons(d, Construction.mounts_of(d))))
		note = ""
	_rebuild()


func _refresh_locs() -> void:
	var db := GameData.db()
	var mounts: Array = Construction.mounts_of(d)
	var at := {}
	for mi in mounts.size():
		for s in mounts[mi]["slots"]:
			at["%s:%d" % [s[0], int(s[1])]] = mi
	# a part in the air (dragged) reads like a picked one, without the "+ Name" block: the marker
	# under the pointer shows where it lands instead
	var dragging := not drag.is_empty()
	var moving := dragging and str(drag["from"]) != ""
	var part: String = str(drag["id"]) if dragging else sel_item
	var picking := part != ""
	var crits := 0
	var pick_name := ""
	if dragging:
		crits = int(drag["n"])
	elif picking:
		crits = Construction.item_crits(d, sel_item, Construction.direct_fire_tons(d, mounts))
	if picking:
		pick_name = db.item(part).get("name", part)
	for loc in MechDesign.LOCS:
		var card: Dictionary = w["loc_" + loc]
		var row: Array = d.slots[loc]
		var free := d.free_slots(loc)
		var ghost := -1
		if dragging:
			ghost = _landing(loc, -1, drag)
		elif picking and crits > 0:
			ghost = _fit_start(row, crits)
		var mx := Construction.max_armor(d.tons, loc)
		var has_rear: bool = MechDesign.REAR.has(loc)
		var front := int(d.armor[loc])
		var back := int(d.armor[MechDesign.REAR[loc]]) if has_rear else 0
		(w["armor_" + loc] as SpinBox).max_value = mx
		(w["armor_" + loc] as SpinBox).value = front
		if has_rear:
			(w["armor_" + MechDesign.REAR[loc]] as SpinBox).max_value = mx
			(w["armor_" + MechDesign.REAR[loc]] as SpinBox).value = back
		(card["max"] as Label).text = "/%d" % mx
		(card["max"] as Label).tooltip_text = "This location carries at most %d armor%s" % [mx, ", front and rear together" if has_rear else ""]
		(card["bar"] as SegBar).show_segs([[float(front) / maxf(1.0, mx), UI.BLUE], [float(back) / maxf(1.0, mx), UI.BLUE.darkened(0.35)]])
		var fl: Label = card["free"]
		fl.text = ("no room" if ghost < 0 else "fits") if picking else ("%d free" % free if free > 0 else "full")
		fl.add_theme_color_override("font_color", (UI.ACCENT if ghost >= 0 else UI.BAD.lerp(UI.DIM, 0.4)) if picking else (UI.GOOD if free > 0 else UI.DIM))
		var pnl: PanelContainer = card["panel"]
		pnl.add_theme_stylebox_override("panel", _loc_box("lit" if picking and ghost >= 0 else "plain"))
		pnl.modulate = Color(1, 1, 1, 0.5) if picking and ghost < 0 else Color.WHITE
		var box: VBoxContainer = card["slots"]
		UI.clear(box)
		var i := 0
		while i < row.size():
			var s: String = row[i]
			var n := 1
			var blk: Button
			if i == ghost and not dragging:
				n = crits
				var rear_ok: bool = db.item(sel_item).get("kind", "") == "weapon" and loc in MechDesign.TORSOS
				blk = _block("+  " + pick_name, n, "ghost", UI.ACCENT.lightened(0.25),
					"Mount it here" + ("  ·  Shift-click to face it rearward" if rear_ok else ""), func(): _place(loc))
			elif moving and loc == str(drag["from"]) and i == int(drag["idx"]):
				n = crits
				blk = _block(pick_name, n, "lifted", UI.DIM.darkened(0.3))
			elif s == "":
				if dragging:
					blk = _block("", 1, "open" if ghost >= 0 else "empty", UI.DIM)
				elif picking and ghost >= 0:
					blk = _block("", 1, "open", UI.DIM, "Mount it in this location", func(): _place(loc))
				else:
					blk = _block("", 1, "empty", UI.DIM)
			elif s in MechDesign.FILLERS:
				blk = _block(_nice(s), 1, "filler", UI.DIM.darkened(0.25))
			elif MechDesign.is_fixed(s):
				if s in ["lower_arm", "hand"]:
					var idx := i
					blk = _block(_nice(s), 1, "arm", UI.DIM,
						"Click to take the %s out: frees the slot, but this arm cannot punch" % _nice(s).to_lower(), func():
							row[idx] = ""
							if s == "lower_arm" and idx + 1 < row.size() and row[idx + 1] == "hand":
								row[idx + 1] = ""
							note = ""
							_rebuild())
				else:
					while i + n < row.size() and row[i + n] == s:
						n += 1
					blk = _block(_nice(s), n, "fixed", UI.DIM.darkened(0.15))
			else:
				var mi2: int = at.get("%s:%d" % [loc, i], -1)
				while i + n < row.size() and at.get("%s:%d" % [loc, i + n], -2) == mi2:
					n += 1
				var id := MechDesign.base_id(s)
				var it := db.item(id)
				var kind: String = it.get("kind", "misc")
				if not kind in ["weapon", "ammo"]:
					kind = "misc"
				var kc := UI.TEXT if kind == "weapon" else (UI.WARN.lerp(UI.TEXT, 0.4) if kind == "ammo" else UI.BLUE.lerp(UI.TEXT, 0.35))
				var start := i
				var label := str(it.get("name", id)) + ("  (R)" if MechDesign.is_rear(s) else "")
				var misc: String = it.get("misc", "")
				var auto: bool = misc in ["heat_sink", "double_heat_sink", "jump_jet"]
				if auto:
					blk = _block(label, n, "auto", WEIGHT[5][1].lerp(UI.DIM, 0.45),
						"Drag to move it. How many there are follows %s in the frame card" % ("Jump MP" if misc == "jump_jet" else "the sink count"))
					blk.mouse_default_cursor_shape = Control.CURSOR_DRAG
				else:
					var tip := "%s  ·  %s t  ·  %s  ·  drag to move it, click to take it off" % [it.get("name", id), _t(Construction.item_tons(d, id, Construction.direct_fire_tons(d, mounts))), _slots(n)]
					blk = _block(label, n, kind, kc, tip, func(): _remove_mount(loc, start, id))
				# a part split over two locations stays put: only whole parts are dragged
				if mi2 >= 0 and not _split(mounts[mi2]):
					_zone(blk, loc, i, _mount_drag.bind({"lab": true, "id": id, "slot": s, "from": loc, "idx": start, "n": n,
						"name": str(it.get("name", id)), "weapon": kind == "weapon", "auto": auto, "jet": misc == "jump_jet"}))
					box.add_child(blk)
					i += n
					continue
			box.add_child(_zone(blk, loc, i))
			i += n
		# an arm that gave up its lower arm or hand can have it back
		if loc in ["LA", "RA"] and not picking:
			if row[2] == "" and not "lower_arm" in row:
				_swap_block(box, 2, "+ lower arm", "Put the lower arm actuator back", func():
					row[2] = "lower_arm"
					_rebuild())
			elif row[3] == "" and "lower_arm" in row and not "hand" in row:
				_swap_block(box, 3, "+ hand", "Put the hand actuator back", func():
					row[3] = "hand"
					_rebuild())
	_refresh_banner()
	_refresh_weight()
	_refresh_loadout(mounts)


## Replaces the single-slot block at slot index `idx` of an arm's list with a clickable one.
func _swap_block(box: VBoxContainer, idx: int, text: String, tip: String, cb: Callable) -> void:
	# slots 0..3 of an arm are always single blocks, so the child index is the slot index
	if idx >= box.get_child_count():
		return
	var old := box.get_child(idx)
	box.remove_child(old)
	old.queue_free()
	var b := _block(text, 1, "open", UI.DIM, tip, cb)
	box.add_child(b)
	box.move_child(b, idx)


func _refresh_banner() -> void:
	var bp: PanelContainer = w["banner"]
	var bl: Label = w["banner_l"]
	var picking := sel_item != ""
	var dragging := not drag.is_empty()
	(w["banner_x"] as Button).visible = picking and not dragging
	var binning := dragging and str(drag["from"]) != "" and not bool(drag["auto"])
	(w["parts_panel"] as PanelContainer).add_theme_stylebox_override("panel", w["parts_sb_lit"] if binning else w["parts_sb"])
	if dragging:
		var shift := ""
		if bool(drag["weapon"]):
			shift = "  Hold Shift over a torso: %s." % ("flip its facing" if str(drag["from"]) != "" else "rear-facing")
		bl.text = "%s   %s  %s  ·  %s   —   drop it on a lit location%s.%s" % [
			UI.ic("crosshairs"), "MOVING" if str(drag["from"]) != "" else "PLACING", str(drag["name"]).to_upper(), _slots(int(drag["n"])),
			", or on the parts list to take it off" if binning else "", shift]
		bl.add_theme_color_override("font_color", UI.ACCENT.lightened(0.2))
		bp.add_theme_stylebox_override("panel", _banner_box("pick"))
	elif picking:
		var it := GameData.db().item(sel_item)
		var df := Construction.direct_fire_tons(d, Construction.mounts_of(d))
		bl.text = "%s   PLACING  %s  ·  %s t  ·  %s   —   click a lit location to mount it.%s%s" % [
			UI.ic("crosshairs"), str(it.get("name", sel_item)).to_upper(), _t(Construction.item_tons(d, sel_item, df)),
			_slots(Construction.item_crits(d, sel_item, df)),
			"  Shift-click a torso: rear-facing." if it.get("kind", "") == "weapon" else "", ("   " + note) if note != "" else ""]
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


func _banner_box(kind: String) -> StyleBoxFlat:
	var key := "banner_" + kind
	if not _card_sb.has(key):
		var col := UI.ACCENT if kind == "pick" else (UI.WARN if kind == "note" else UI.LINE)
		var sb := UI.box(Color(col.r, col.g, col.b, 0.12 if kind != "idle" else 0.0), 4, Color(col.r, col.g, col.b, 0.7 if kind != "idle" else 0.6), 1)
		sb.content_margin_left = 12
		sb.content_margin_right = 6
		sb.content_margin_top = 3
		sb.content_margin_bottom = 3
		_card_sb[key] = sb
	return _card_sb[key]


# ---------------------------------------------------------------- the two cards under the arms

func _side_card(title: String, key: String) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _loc_box("plain"))
	p.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var v := UI.vbox(3)
	p.add_child(v)
	var t := UI.label(title.to_upper(), 12, UI.ACCENT)
	t.add_theme_font_override("font", UI.spaced("cond_semi", 1))
	v.add_child(t)
	var rows := UI.vbox(2)
	v.add_child(rows)
	w[key] = rows
	return p


func _build_weight() -> Control:
	return _side_card("Where the tons go", "weight_rows")


func _build_loadout() -> Control:
	return _side_card("Loadout", "loadout_rows")


func _kv(text: String, value: String, col: Color, dot := Color(0, 0, 0, 0)) -> Control:
	var h := UI.hbox(5)
	if dot.a > 0.0:
		var sq := ColorRect.new()
		sq.color = dot
		sq.custom_minimum_size = Vector2(8, 8)
		sq.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sq)
	var l := UI.label(text, 12, col)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UI.label(value, 12, col))
	return h


func _refresh_weight() -> void:
	var box: VBoxContainer = w["weight_rows"]
	UI.clear(box)
	var bd: Array = rep.get("breakdown", [])
	for i in mini(bd.size(), WEIGHT.size()):
		box.add_child(_kv(WEIGHT[i][0], _t(float(bd[i][1])), UI.TEXT if float(bd[i][1]) > 0.0 else UI.DIM, WEIGHT[i][1]))
	var free := d.tons - float(rep.get("tons_used", 0.0))
	var line := ColorRect.new()
	line.color = UI.LINE
	line.custom_minimum_size.y = 1
	box.add_child(line)
	box.add_child(_kv("Free" if free >= -0.005 else "Over", _t(absf(free)), UI.GOOD if absf(free) < 0.005 else (UI.BAD if free < 0.0 else UI.WARN)))


func _refresh_loadout(mounts: Array) -> void:
	var box: VBoxContainer = w["loadout_rows"]
	UI.clear(box)
	var db := GameData.db()
	var count := {}
	var order: Array = []
	for m in mounts:
		var it := db.item(m["id"])
		if it.get("misc", "") in ["heat_sink", "double_heat_sink", "jump_jet"]:
			continue
		if not count.has(m["id"]):
			count[m["id"]] = 0
			order.append(m["id"])
		count[m["id"]] += 1
	var rank := {"weapon": 0, "ammo": 1}
	order.sort_custom(func(a, b):
		var ra: int = rank.get(db.item(a).get("kind", ""), 2)
		var rb: int = rank.get(db.item(b).get("kind", ""), 2)
		return ra < rb if ra != rb else str(db.item(a).get("name", a)) < str(db.item(b).get("name", b)))
	if order.is_empty():
		var e := UI.label("Nothing mounted yet.", 12, UI.DIM)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(e)
		return
	for id in order.slice(0, 13):
		var it2 := db.item(id)
		var kind: String = it2.get("kind", "")
		var kc := UI.TEXT if kind == "weapon" else (UI.WARN.lerp(UI.TEXT, 0.4) if kind == "ammo" else UI.BLUE.lerp(UI.TEXT, 0.35))
		box.add_child(_kv(str(it2.get("name", id)), "×%d" % int(count[id]), kc))
	if order.size() > 13:
		box.add_child(UI.label("and %d more" % (order.size() - 13), 11, UI.DIM))


# ---------------------------------------------------------------- right: the parts list

const PART_COLS := [["Part", 3], ["t", -36], ["cr", -28], ["ht", -28], ["dmg", -44], ["range", -64], ["have", -44]]
const PART_TIPS := ["", "Tons", "Crit slots", "Heat per shot", "Damage (missiles: rack x damage each)",
	"Short / medium / long range, or shots per ton", "In your stores + on the market"]
const MERC_STOCK_TIP := "x2: that many in the warehouse (ammo in tons).\n7+: none in the warehouse; the weekly 2d6 roll your admin needs to find one."

func _build_parts() -> Control:
	var v := UI.vbox(6)
	var p := UI.panel(v)
	p.custom_minimum_size.x = 426
	# a mounted part dropped anywhere on this panel comes off the 'Mech
	w["parts_panel"] = p
	w["parts_sb"] = p.get_theme_stylebox("panel")
	var lit: StyleBoxFlat = (w["parts_sb"] as StyleBoxFlat).duplicate()
	lit.border_color = UI.ACCENT
	lit.bg_color = UI.PANEL.lerp(UI.ACCENT, 0.05)
	w["parts_sb_lit"] = lit
	p.set_drag_forwarding(Callable(), _can_bin, _bin)
	v.add_child(UI.header("Parts", "crosshairs"))
	var fh := UI.hbox(2)
	var grp := ButtonGroup.new()
	w["tabs"] = {}
	for f in ["weapons", "ammo", "equipment"]:
		var b := Button.new()
		b.text = f.capitalize()
		b.toggle_mode = true
		b.button_group = grp
		b.focus_mode = Control.FOCUS_NONE
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 13)
		for st in ["normal", "hover", "disabled"]:
			b.add_theme_stylebox_override(st, _tab_box(false))
		for st in ["pressed", "hover_pressed"]:
			b.add_theme_stylebox_override(st, _tab_box(true))
		b.add_theme_color_override("font_color", UI.DIM)
		b.add_theme_color_override("font_hover_color", UI.TEXT)
		for cn in ["font_pressed_color", "font_hover_pressed_color"]:
			b.add_theme_color_override(cn, UI.ACCENT)
		b.pressed.connect(func():
			if _syncing or filter == f:
				return
			filter = f
			_rebuild())
		fh.add_child(b)
		w["tabs"][f] = b
	var gap := Control.new()
	gap.custom_minimum_size.x = 6
	fh.add_child(gap)
	var se := LineEdit.new()
	se.placeholder_text = "Search parts"
	se.clear_button_enabled = true
	se.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	se.text_changed.connect(func(t):
		search = t
		_rebuild())
	fh.add_child(se)
	w["search"] = se
	v.add_child(fh)
	var t := UI.tree(PART_COLS)
	t.custom_minimum_size.y = 200
	t.allow_reselect = false
	t.add_theme_font_size_override("font_size", 14)
	for i in PART_COLS.size():
		t.set_column_clip_content(i, true)
	t.column_title_clicked.connect(func(col: int, _mb: int):
		if col == sort_col:
			sort_desc = not sort_desc
		else:
			sort_col = col
			sort_desc = col in [4, 5, 6]
		_rebuild())
	t.item_selected.connect(func():
		if _syncing or t.get_selected() == null:
			return
		var id := str(t.get_selected().get_metadata(0))
		if id == sel_item:
			return
		sel_item = id
		note = ""
		_rebuild())
	t.set_drag_forwarding(_tree_drag, _can_bin, _bin)
	v.add_child(t)
	w["tree"] = t
	var iv := UI.vbox(2)
	var ip := PanelContainer.new()
	ip.add_theme_stylebox_override("panel", _tight(Color(0, 0, 0, 0.18), UI.LINE, 1))
	ip.custom_minimum_size.y = 74
	ip.add_child(iv)
	ip.set_drag_forwarding(Callable(), _can_bin, _bin)
	var ih := UI.hbox(6)
	var iname := UI.label("", 15, UI.TEXT)
	iname.add_theme_font_override("font", UI.font("cond_semi"))
	iname.clip_text = true
	iname.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ih.add_child(iname)
	var iprice := UI.label("", 13, UI.DIM)
	ih.add_child(iprice)
	iv.add_child(ih)
	var istats := UI.label("", 12, UI.TEXT)
	istats.clip_text = true
	iv.add_child(istats)
	var istock := UI.label("", 12, UI.DIM)
	istock.clip_text = true
	iv.add_child(istock)
	v.add_child(ip)
	w["i_name"] = iname
	w["i_price"] = iprice
	w["i_stats"] = istats
	w["i_stock"] = istock
	return p


func _tab_box(on: bool) -> StyleBoxFlat:
	var key := "tab_on" if on else "tab_off"
	if not _card_sb.has(key):
		var sb := UI.box(Color(UI.ACCENT.r, UI.ACCENT.g, UI.ACCENT.b, 0.12) if on else Color(1, 1, 1, 0.03), 3)
		sb.content_margin_left = 10
		sb.content_margin_right = 10
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		sb.border_width_bottom = 2
		sb.border_color = UI.ACCENT if on else Color(0, 0, 0, 0)
		_card_sb[key] = sb
	return _card_sb[key]


## What the list sorts a part by under the current sort column.
func _sort_key(id: String, df: float):
	var it := GameData.db().item(id)
	match sort_col:
		1:
			return float(Construction.item_tons(d, id, df))
		2:
			return float(_crits(id, df))
		3:
			return float(it.get("heat", 0) if it.get("heat") != null else 0)
		4:
			var dmg := float(it.get("dmg", 0) if it.get("dmg") != null else 0)
			return dmg * maxf(1.0, float(it.get("rack", 0))) if it.get("wtype", "") in CombatSim.MISSILE_TYPES else dmg
		5:
			return float(it.get("l", 0)) if it.get("kind", "") == "weapon" else float(it.get("shots", 0))
		6:
			if mc != null:
				return _have(id) * 1000.0 + float(20 - _find_tn(id) if _find_tn(id) >= 0 else 0)
			var stock: Dictionary = c.market["parts"].get(id, {})
			return _have(id) * 1000.0 + float(stock.get("qty", 0))
	return str(it.get("name", id)).to_lower()


func _refresh_parts() -> void:
	var db := GameData.db()
	var t: Tree = w["tree"]
	if mc != null:
		var ref := mc.procurement_tn("armor:standard")
		_tn_base = int(ref["tn"]) - int(mc.rules["procurement"]["avail_mod"].get(
			str(MercRepair.part_info("armor:standard", mc.year())["avail"]), 0))
	for f in w["tabs"]:
		(w["tabs"][f] as Button).set_pressed_no_signal(f == filter)
	var mounts: Array = rep.get("mounts", Construction.mounts_of(d))
	var df := Construction.direct_fire_tons(d, mounts)
	var on_mech := {}
	for mt in mounts:
		on_mech[mt["id"]] = true
	var ids: Array = []
	var needle := search.strip_edges().to_lower()
	for id in db.items:
		var it: Dictionary = db.items[id]
		var kind: String = it.get("kind", "")
		var misc: String = it.get("misc", "")
		if kind != {"weapons": "weapon", "ammo": "ammo", "equipment": "misc"}[filter]:
			continue
		if misc in HIDDEN_MISC:
			continue
		var mine: bool = _have(id) > 0.0 or on_mech.has(id)
		if not db.used_items().has(id) and not mine:
			continue
		if it.get("tech", "") == "CLAN" and d.tech == "IS" and not mine:
			continue
		if not db.item_available(id, _year()) and not mine:
			continue
		if needle != "" and str(it.get("name", "")).to_lower().find(needle) < 0:
			continue
		if it.get("tons") == null and not (misc in WEIGHTLESS_OK):
			continue
		if not _part_ok(it):
			continue
		ids.append(id)
	var keys := {}
	for id in ids:
		keys[id] = [_sort_key(id, df), str(db.items[id].get("name", id)).to_lower()]
	ids.sort_custom(func(a, b):
		if keys[a][0] == keys[b][0]:
			return keys[a][1] < keys[b][1]
		return keys[a][0] > keys[b][0] if sort_desc else keys[a][0] < keys[b][0])
	for i in PART_COLS.size():
		t.set_column_title(i, str(PART_COLS[i][0]).to_upper() + ((" ▼" if sort_desc else " ▲") if i == sort_col else ""))
		t.set_column_title_tooltip_text(i, MERC_STOCK_TIP if mc != null and i == 6 else PART_TIPS[i])
	# the rows are only made again when the list itself changed; otherwise their cells are rewritten
	var key := "|".join(ids)
	if key != _tree_key:
		_tree_key = key
		var root := t.get_root()
		for ch in root.get_children():
			ch.free()
		for id in ids:
			t.create_item(root).set_metadata(0, id)
		if root.get_first_child() != null:
			t.scroll_to_item(root.get_first_child())
	var free_t := d.tons - float(rep.get("tons_used", 0.0))
	var biggest := _biggest_run()
	var row := t.get_root().get_first_child()
	var k := 0
	while row != null:
		var id: String = row.get_metadata(0)
		var it2: Dictionary = db.items[id]
		var tons := float(Construction.item_tons(d, id, df))
		var crits := _crits(id, df)
		var have := _have(id)
		var stock: Dictionary = c.market["parts"].get(id, {}) if mc == null else {}
		var tn := _find_tn(id) if mc != null else -1
		var dmg := _num(it2.get("dmg"))
		if int(it2.get("rack", 0)) > 0 and it2.get("wtype", "") in CombatSim.MISSILE_TYPES:
			dmg = "%dx%d" % [int(it2["rack"]), int(it2.get("dmg", 1))]
		var rng := ""
		if it2.get("kind") == "weapon":
			rng = "%d/%d/%d" % [int(it2.get("s", 0)), int(it2.get("m", 0)), int(it2.get("l", 0))]
		elif it2.get("kind") == "ammo":
			rng = "%d shots" % int(it2.get("shots", 0))
		var hv := str(int(have))
		if mc != null:
			hv = ("x" + _t(have)) if have > 0.0 else (("%d+" % tn) if tn >= 0 else "—")
		elif not stock.is_empty():
			hv += "+" + ("∞" if int(stock["qty"]) >= 99 else str(int(stock["qty"])))
		var cells := [str(it2.get("name", id)), _t(tons), str(crits), _num(it2.get("heat")), dmg, rng, hv]
		var none := have <= 0.0 and (tn < 0 if mc != null else stock.is_empty())
		for col in cells.size():
			row.set_text(col, cells[col])
			row.set_custom_color(col, UI.DIM if none or col > 0 else UI.TEXT)
			if k % 2 == 1:
				row.set_custom_bg_color(col, Color(1, 1, 1, 0.025))
			else:
				row.clear_custom_bg_color(col)
		if not none:
			row.set_custom_color(6, UI.GOOD if have > 0 else UI.TEXT)
		if tons > free_t + 0.005:
			row.set_custom_color(1, UI.BAD.lerp(UI.DIM, 0.35))
		if crits > biggest:
			row.set_custom_color(2, UI.BAD.lerp(UI.DIM, 0.35))
		var tip := "  ·  none in your stores or on the market" if none else ""
		if mc != null:
			tip = "  ·  nobody sells it in %d" % _year() if none else ("  ·  in the warehouse" if have > 0.0 else "  ·  has to be found: %d+ each week" % tn)
		row.set_tooltip_text(0, "%s%s" % [it2.get("name", id), tip])
		if id == sel_item and not row.is_selected(0):
			row.select(0)
		row = row.get_next()
		k += 1
	_refresh_inspector(df)


func _refresh_inspector(df: float) -> void:
	var nm: Label = w["i_name"]
	if not drag.is_empty() and str(drag["from"]) != "" and not bool(drag["auto"]):
		nm.text = "Drop here to take it off"
		nm.add_theme_color_override("font_color", UI.ACCENT)
		(w["i_price"] as Label).text = ""
		(w["i_stats"] as Label).text = "%s comes off the %s." % [drag["name"], _noun()]
		(w["i_stats"] as Label).add_theme_color_override("font_color", UI.DIM)
		(w["i_stock"] as Label).text = ""
		return
	if sel_item == "":
		nm.text = "No part picked"
		nm.add_theme_color_override("font_color", UI.DIM)
		(w["i_price"] as Label).text = ""
		(w["i_stats"] as Label).text = "Drag a part onto the %s, or click it to pick it up. Click a column title to sort." % _noun()
		(w["i_stats"] as Label).add_theme_color_override("font_color", UI.DIM)
		(w["i_stock"] as Label).text = "Red tons or slots: it does not fit as the design stands."
		return
	var it := GameData.db().item(sel_item)
	nm.text = str(it.get("name", sel_item))
	nm.add_theme_color_override("font_color", UI.TEXT)
	var bits: Array = ["%s t" % _t(Construction.item_tons(d, sel_item, df)), _slots(_crits(sel_item, df))]
	if it.get("kind", "") == "weapon":
		if it.get("dmg") != null:
			var rack := int(it.get("rack", 0))
			bits.append(("%d x %s damage" % [rack, _num(it["dmg"])]) if rack > 0 and it.get("wtype", "") in CombatSim.MISSILE_TYPES else "%s damage" % _num(it["dmg"]))
		if it.get("heat") != null:
			bits.append("%s heat" % _num(it["heat"]))
		bits.append("range %d / %d / %d" % [int(it.get("s", 0)), int(it.get("m", 0)), int(it.get("l", 0))])
	elif it.get("kind", "") == "ammo":
		bits.append("%d shots per ton" % int(it.get("shots", 0)))
	(w["i_stats"] as Label).text = "  ·  ".join(bits)
	(w["i_stats"] as Label).add_theme_color_override("font_color", UI.TEXT)
	if mc != null:
		var info := mc.part_info(_part_key(sel_item))
		var ammo: bool = it.get("kind", "") == "ammo"
		var tn := _find_tn(sel_item)
		(w["i_price"] as Label).text = UI.money(int(info["price"])) + (" a ton" if ammo else " each")
		var ms := "%s%s in the warehouse" % [_t(_have(sel_item)), " t" if ammo else ""]
		if tn < 0:
			ms += "  ·  nobody sells it in %d" % mc.year()
		elif tn <= 2:
			ms += "  ·  easy to find: a week or two"
		else:
			ms += "  ·  rarity %s: your admin finds it on %d+ (2d6, weekly)" % [info["avail"], tn]
		(w["i_stock"] as Label).text = ms
		return
	var have := int(_have(sel_item))
	var stock: Dictionary = c.market["parts"].get(sel_item, {})
	var st := "%d in your stores" % have
	if not stock.is_empty():
		st += "  ·  market has %s" % ("plenty" if int(stock["qty"]) >= 99 else str(int(stock["qty"])))
		(w["i_price"] as Label).text = UI.money(int(float(stock.get("price", 0)) * c.price_mult())) + " each"
	else:
		(w["i_price"] as Label).text = ""
		if it.get("kind", "") != "ammo":
			st += "  ·  not on the market"
	(w["i_stock"] as Label).text = st


# ---------------------------------------------------------------- bottom bar: checks, quote, order

func _build_bottom() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UI.bar_box(false))
	var h := UI.hbox(22)
	bar.add_child(h)
	var sv := UI.vbox(0)
	sv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sv.custom_minimum_size.y = 40
	sv.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(sv)
	w["status"] = sv
	var caps := [["q_cost", "Refit cost" if uid >= 0 else "Build cost"], ["q_time", "Bay time"], ["q_cash", "Your cash"]]
	if mc != null:
		caps = [["q_cost", "Parts to buy"], ["q_time", "Tech time"], ["q_cash", "Company cash"]]
	for k in caps:
		var v := UI.vbox(-2)
		v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.add_child(_caption(k[1]))
		var l := UI.label("", 17, UI.TEXT)
		l.add_theme_font_override("font", UI.font("cond_semi"))
		v.add_child(l)
		w[k[0]] = l
		h.add_child(v)
	var bill := UI.button("Itemised bill", _show_bill, "What the quote is made of")
	if mc != null:
		bill.text = "Parts list"
		bill.tooltip_text = "Every part the refit takes: what the warehouse has, what has to be found"
	bill.focus_mode = Control.FOCUS_NONE
	bill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bill.visible = uid >= 0
	h.add_child(bill)
	w["bill"] = bill
	var go := UI.primary(UI.ibutton("check", "Order refit" if mc != null else ("Commit refit" if uid >= 0 else "Build this 'Mech"), _commit))
	go.custom_minimum_size = Vector2(210, 40)
	go.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	go.focus_mode = Control.FOCUS_NONE
	h.add_child(go)
	w["go"] = go
	return bar


func _refresh_bottom() -> void:
	var cash: int = mc.cash if mc != null else c.player().cash
	var sv: VBoxContainer = w["status"]
	UI.clear(sv)
	var lines: Array = []
	for e in rep.get("errors", []):
		lines.append(["✖  " + str(e), UI.BAD])
	for e2 in quote.get("errors", []):
		if not (e2 in rep.get("errors", [])):
			lines.append(["✖  " + str(e2), UI.BAD])
	var cost := int(quote.get("cost", 0))
	if mc == null and cash < cost:
		lines.append(["✖  %s short: this costs %s and the stable has %s" % [UI.money(cost - cash), UI.money(cost), UI.money(cash)], UI.BAD])
	var blocked := not lines.is_empty()
	for wn in rep.get("warnings", []):
		lines.append(["!  " + str(wn), UI.WARN])
	var tail := "" if uid < 0 or _dirty() else "  ·  nothing changed yet"
	if mc != null and _dirty() and not blocked:
		# nothing is paid here: say where the parts come from and what else the refit waits for
		var kinds := (quote.get("buy", {}) as Dictionary).size()
		tail = "  ·  every part is in the warehouse" if kinds == 0 else "  ·  %d %s to find: they go on the shopping list" % [kinds, "part" if kinds == 1 else "kinds of parts"]
		if cash < cost:
			lines.append(["!  The parts cost %s and the company has %s: the admins buy each one when the cash is there" % [UI.money(cost), UI.money(cash)], UI.WARN])
		if mu.damaged():
			lines.append(["!  The %s is damaged: the techs repair it before they start the refit" % _noun(), UI.WARN])
		if mc.tech_minutes() <= 0:
			lines.append(["!  The company has no techs: nobody can do the work", UI.WARN])
	if lines.is_empty():
		lines.append(["✔  Design is legal" + tail, UI.GOOD])
	elif not blocked and mc != null:
		lines.push_front(["✔  Design is legal" + tail, UI.GOOD])
	elif not blocked:
		lines.push_front(["✔  Design is legal", UI.GOOD])
	var all: Array = []
	for ln in lines:
		all.append(ln[0])
	for i in mini(2, lines.size()):
		var txt: String = lines[i][0]
		if i == 1 and lines.size() > 2:
			txt += "      + %d more (hover)" % (lines.size() - 2)
		var l := UI.label(txt, 13, lines[i][1])
		l.clip_text = true
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.tooltip_text = "\n".join(all)
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		sv.add_child(l)
	var hours := float(quote.get("hours", 0.0))
	(w["q_cost"] as Label).text = UI.money(cost)
	(w["q_cost"] as Label).add_theme_color_override("font_color", (UI.WARN if mc != null else UI.BAD) if cash < cost else UI.TEXT)
	if mc != null:
		var mins := float(quote.get("minutes", 0.0))
		var days := mc.refit_days(mins)
		(w["q_time"] as Label).text = "%.0f h  ·  %s" % [mins / 60.0, "no techs" if days < 0 else ("%d day%s" % [days, "" if days == 1 else "s"])]
		(w["q_time"] as Label).tooltip_text = "Tech hours of work, and the days it takes if the techs have nothing else to do. The clock starts when the last part arrives."
		(w["q_time"] as Label).mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		(w["q_time"] as Label).text = "%.0f h  ·  %.1f wk" % [hours, hours / maxf(1.0, c.player().techs * float(c.rules["tech_hours_week"]))]
	(w["q_cash"] as Label).text = UI.money(cash)
	(w["bill"] as Button).disabled = (quote.get("lines", []) as Array).is_empty() and (quote.get("freed", {}) as Dictionary).is_empty()
	var go: Button = w["go"]
	var unchanged := uid >= 0 and not _dirty()
	go.disabled = blocked or unchanged
	go.tooltip_text = ("Nothing has changed on this %s yet" % _noun()) if unchanged else ("Fix the problems on the left first" if blocked else "")


func _show_bill() -> void:
	var out: Array = []
	if mc != null:
		if not (quote.get("lines", []) as Array).is_empty():
			out.append("GOES ON")
		for l in quote.get("lines", []):
			out.append("  %-30s %7s   %s" % [str(l[0]).left(30), l[1], l[2]])
		var freed: Dictionary = quote.get("freed", {})
		if not freed.is_empty():
			out.append("")
			out.append("COMES OFF, BACK TO THE WAREHOUSE")
		for k in freed:
			var info := MercRepair.part_info(k, mc.year())
			out.append("  %-30s %7s" % [str(info["name"]).left(30), MercCampaign._qty_str(float(freed[k])) + (" t" if info["tons"] else "")])
		out.append("")
		out.append("Parts to buy: %s, paid as the admins find them. Nothing is charged now." % UI.money(int(quote.get("cost", 0))))
		out.append("Work: %.0f tech hours once every part is in." % (float(quote.get("minutes", 0.0)) / 60.0))
		var md := UI.popup(self, "Refit parts", "")
		md.add_child(Views.mono_label("\n".join(out), 13))
		return
	for l in quote.get("lines", []):
		out.append("%-34s %12s" % [str(l[0]).left(34), UI.money(int(l[1]))])
	var hours := float(quote.get("hours", 0.0))
	out.append("%-34s %12s" % ["Labor, %.0f bay hours" % hours, UI.money(int(hours * float(c.rules["labor_cost_hour"])))])
	out.append("")
	out.append("%-34s %12s" % ["Total (parts at market rates)", UI.money(int(quote.get("cost", 0)))])
	var dlg := UI.popup(self, "Refit bill", "")
	var lab := Views.mono_label("\n".join(out), 13)
	dlg.add_child(lab)


# ---------------------------------------------------------------- drag and drop

func _is_part(data) -> bool:
	return data is Dictionary and bool(data.get("lab", false))


## Makes a control of a location card a place to drop parts (`idx`: the slot it stands for, -1 for the
## card as a whole) and, with `drag_cb`, something to drag from.
func _zone(ctl: Control, loc: String, idx: int, drag_cb := Callable()) -> Control:
	ctl.set_drag_forwarding(drag_cb, _can_drop.bind(loc, idx), _drop.bind(loc, idx))
	return ctl


## Picks a part up: remembers it, hangs its name on the pointer and relights the locations.
func _begin_drag(data: Dictionary) -> Dictionary:
	drag = data
	var holder := Control.new()
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", _tight(UI.PANEL.lerp(UI.ACCENT, 0.3), UI.ACCENT))
	tag.add_child(UI.label("%s  ·  %s" % [data["name"], _slots(int(data["n"]))], 13, UI.TEXT))
	tag.position = Vector2(14, 12)
	holder.add_child(tag)
	set_drag_preview(holder)
	(w["land_l"] as Label).text = "+  " + str(data["name"])
	_rebuild()
	return data


func _tree_drag(at: Vector2):
	var item := (w["tree"] as Tree).get_item_at_position(at)
	if item == null:
		return null
	var id := str(item.get_metadata(0))
	var it := GameData.db().item(id)
	var n := _crits(id, Construction.direct_fire_tons(d, Construction.mounts_of(d)))
	if it.is_empty() or n <= 0:
		return null
	return _begin_drag({"lab": true, "id": id, "slot": id, "from": "", "idx": -1, "n": n,
		"name": str(it.get("name", id)), "weapon": it.get("kind", "") == "weapon", "auto": false, "jet": false})


func _mount_drag(_at: Vector2, data: Dictionary):
	return _begin_drag(data.duplicate())


func _split(m: Dictionary) -> bool:
	for sl in m["slots"]:
		if sl[0] != m["loc"]:
			return true
	return false


## The first slot the dragged part would take in `loc`, or -1 when it cannot go there. Dropped on a
## free slot (`idx`) it lands on that slot, sliding up when the room below runs out; dropped anywhere
## else on the card it takes the first run of free slots. The slots it comes from count as free.
func _landing(loc: String, idx: int, data: Dictionary) -> int:
	if bool(data["jet"]) and not loc in ["LL", "RL", "LT", "RT", "CT"]:
		return -1
	var n := int(data["n"])
	var row: Array = d.slots[loc]
	if str(data["from"]) == loc:
		row = row.duplicate()
		for k in n:
			row[int(data["idx"]) + k] = ""
	if idx >= 0 and idx < row.size() and row[idx] == "":
		var start := mini(idx, row.size() - n)
		while start >= 0 and start > idx - n:
			if _run_free(row, start, n):
				return start
			start -= 1
	return _fit_start(row, n)


func _run_free(row: Array, start: int, n: int) -> bool:
	for k in n:
		if row[start + k] != "":
			return false
	return true


func _can_drop(_at: Vector2, data, loc: String, idx: int) -> bool:
	if not _is_part(data) or drag.is_empty():
		return false
	var start := _landing(loc, idx, data)
	if start < 0:
		_hide_land()
		return false
	var box: Control = w["loc_" + loc]["slots"]
	var n := int(data["n"])
	var m: Control = w["land"]
	m.global_position = box.global_position + Vector2(0, start * (ROW_H + 1))
	m.size = Vector2(box.size.x, ROW_H * n + n - 1)
	m.visible = true
	_land_loc = loc
	doll.highlight = loc
	return true


func _drop(_at: Vector2, data, loc: String, idx: int) -> void:
	if not _is_part(data):
		return
	var start := _landing(loc, idx, data)
	if start < 0:
		return
	var n := int(data["n"])
	var from := str(data["from"])
	var slot := str(data["slot"])
	if from != "" and d.slots[from][int(data["idx"])] != slot:
		return  # the design changed under the drag
	var rear := MechDesign.is_rear(slot)
	if Input.is_key_pressed(KEY_SHIFT):
		rear = not rear
	slot = MechDesign.base_id(slot)
	if rear and bool(data["weapon"]) and loc in MechDesign.TORSOS:
		slot += "@R"
	if from != "":
		for k in n:
			d.slots[from][int(data["idx"]) + k] = ""
	for k in n:
		d.slots[loc][start + k] = slot
	note = ""
	if from == "":
		# a part dragged out of the list is placed once; picking it by click keeps it in hand
		sel_item = ""
		(w["tree"] as Tree).deselect_all()
	_rebuild()


## The parts list takes mounted parts back.
func _can_bin(_at: Vector2, data) -> bool:
	return _is_part(data) and str(data["from"]) != "" and not bool(data["auto"])


func _bin(_at: Vector2, data) -> void:
	if not _can_bin(_at, data):
		return
	var from := str(data["from"])
	if d.slots[from][int(data["idx"])] != str(data["slot"]):
		return
	for k in int(data["n"]):
		d.slots[from][int(data["idx"]) + k] = ""
	note = ""
	_rebuild()


## The marker that shows, during a drag, the slots the part would land in.
func _build_marker() -> void:
	var m := PanelContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_stylebox_override("panel", _slot_box("land"))
	m.z_index = 20
	m.visible = false
	var l := UI.label("", 13, Color.WHITE)
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	m.add_child(l)
	add_child(m)
	w["land"] = m
	w["land_l"] = l


func _hide_land() -> void:
	if w.has("land"):
		(w["land"] as Control).visible = false
	if _land_loc != "" and doll != null and doll.highlight == _land_loc:
		doll.highlight = ""
	_land_loc = ""


# ---------------------------------------------------------------- changing the design

func _place(loc: String) -> void:
	if sel_item == "":
		return
	var df := Construction.direct_fire_tons(d, Construction.mounts_of(d))
	var crits := Construction.item_crits(d, sel_item, df)
	var it := GameData.db().item(sel_item)
	var slot := sel_item
	if it.get("kind", "") == "weapon" and loc in ["CT", "LT", "RT"] and Input.is_key_pressed(KEY_SHIFT):
		slot += "@R"
	if not d.place(loc, slot, crits, true):
		note = "%s needs %d contiguous free slots in the %s." % [it.get("name", sel_item), crits, MechDesign.LOC_NAMES[loc]]
	else:
		note = ""
	_rebuild()


func _relayout() -> void:
	var displaced := d.apply_fixed_layout(
		{"LA": "lower_arm" in d.slots["LA"], "RA": "lower_arm" in d.slots["RA"]},
		{"LA": "hand" in d.slots["LA"], "RA": "hand" in d.slots["RA"]})
	if not displaced.is_empty():
		var names: Array = []
		for s in displaced:
			names.append(GameData.db().item(MechDesign.base_id(s)).get("name", s))
		note = "No room any more for: " + ", ".join(names)


func _fillers(tag: String, n: int) -> void:
	for loc in MechDesign.LOCS:
		var row: Array = d.slots[loc]
		for i in row.size():
			if row[i] == tag:
				row[i] = ""
	var left_n := n
	for loc in ["LA", "RA", "LT", "RT", "LL", "RL", "CT", "HD"]:
		while left_n > 0 and d.free_slots(loc) > 0:
			d.place(loc, tag, 1, false)
			left_n -= 1
	if left_n > 0:
		note = "Not enough free slots for %d %s slots." % [n, tag]


func _sink_id() -> String:
	return "heat_sink" if d.hs_type == "single" else "double_heat_sink"


func _clear_sinks() -> void:
	for loc in MechDesign.LOCS:
		var row: Array = d.slots[loc]
		for i in row.size():
			if row[i] in ["heat_sink", "double_heat_sink"]:
				row[i] = ""


func _sync_sinks() -> void:
	var integral := mini(d.hs_count, int(floor(d.engine_rating / 25.0)))
	var need := d.hs_count - integral
	var id := _sink_id()
	var crits := 1 if id == "heat_sink" else 3
	var have := 0
	for loc in MechDesign.LOCS:
		for s in d.slots[loc]:
			if s == id:
				have += 1
	have /= crits
	while have > need:
		var removed := false
		for loc in ["RL", "LL", "RT", "LT", "RA", "LA", "CT", "HD"]:
			var row: Array = d.slots[loc]
			var k := row.rfind(id)
			if k >= 0:
				d.remove_at(loc, k, crits)
				removed = true
				break
		if not removed:
			break
		have -= 1
	while have < need:
		var placed := false
		for loc in ["LL", "RL", "LT", "RT", "LA", "RA", "CT", "HD"]:
			if d.place(loc, id, crits, true):
				placed = true
				break
		if not placed:
			note = "No room for %d more heat sinks." % (need - have)
			break
		have += 1


func _set_jump(v: int) -> void:
	var have := 0
	for loc in MechDesign.LOCS:
		for s in d.slots[loc]:
			if s == "jump_jet":
				have += 1
	while have > v:
		for loc in ["CT", "RT", "LT", "RL", "LL"]:
			var row: Array = d.slots[loc]
			var k := row.rfind("jump_jet")
			if k >= 0:
				row[k] = ""
				break
		have -= 1
	while have < v:
		var ok := false
		for loc in ["LL", "RL", "LT", "RT", "CT"]:
			if d.place(loc, "jump_jet", 1, false):
				ok = true
				break
		if not ok:
			note = "No room for more jump jets."
			break
		have += 1
	d.jump = have


func _clamp_armor() -> void:
	for loc in MechDesign.LOCS:
		var mx := Construction.max_armor(d.tons, loc)
		if MechDesign.REAR.has(loc):
			var rk: String = MechDesign.REAR[loc]
			if int(d.armor[loc]) + int(d.armor[rk]) > mx:
				d.armor[rk] = maxi(0, mx - int(d.armor[loc]))
		elif int(d.armor[loc]) > mx:
			d.armor[loc] = mx


func _fit_armor() -> void:
	var r := Construction.analyze(d)
	var cur_t := Construction.armor_tons(d.armor_total(), d.armor_type)
	var budget: float = float(r.get("tons_free", 0.0)) + cur_t
	var pts := int(floor(budget * Construction.armor_ppt(d.armor_type)))
	var maxes := {}
	var total_max := 0
	for loc in MechDesign.LOCS:
		maxes[loc] = Construction.max_armor(d.tons, loc)
		total_max += int(maxes[loc])
	pts = mini(pts, total_max)
	var f := float(pts) / maxf(1.0, total_max)
	for loc in MechDesign.LOCS:
		var v := int(floor(int(maxes[loc]) * f))
		if MechDesign.REAR.has(loc):
			d.armor[MechDesign.REAR[loc]] = int(v * 0.22)
			d.armor[loc] = v - int(v * 0.22)
		else:
			d.armor[loc] = v
	_rebuild()


func _commit() -> void:
	var err := ""
	if mc != null:
		err = mc.commit_refit(uid, d)
	else:
		err = c.commit_refit(uid, d) if uid >= 0 else c.commit_build(d)
	if err != "":
		note = err
		_rebuild()
		return
	if mc != null:
		Game.save_game("merc_autosave")
	_leave()
