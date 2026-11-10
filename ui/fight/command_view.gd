extends "res://ui/fight/fight_view.gd"
## Merc battles in real time with pause and command. Space pauses. Click or drag a box to select your
## units, number keys pick a lance, right-click the ground to move, an enemy to attack, a building to
## shell it. Orders are recorded by tick, so the battle could be replayed exactly.

const VehicleDoll := preload("res://ui/widgets/vehicle_doll.gd")
const SquadDoll := preload("res://ui/widgets/squad_doll.gd")
const Minimap := preload("res://ui/fight/minimap.gd")

var mc: MercCampaign
var meta: Dictionary = {}
var selected: Dictionary = {}       # sim index -> true
var last_seen: Dictionary = {}      # enemy index -> world position (px) when last spotted
var player_idx: Array = []
var lance_of: Dictionary = {}       # sim index -> lance number (1-based)
var cards: Array = []               # per player unit: {"panel", "name", "bar", "status", "cmd", "index"}
var info_box: VBoxContainer
var info_index := -1
var info_doll: Control
var info_lbls: Dictionary = {}
var obj_lbl: Label
var speed_btns: Array = []
var play_btn: Button
var log_panel: PanelContainer
var minimap: Control
var results: PanelContainer
var summary_m: Dictionary = {}
var _drag_from := Vector2.INF
var _drag_to := Vector2.ZERO
var _pan := false
var _info_t := 0.0
var _keys_pan := Vector2.ZERO
var support_btns: Dictionary = {}   # kind -> Button
var hint_lbl: Label
var _aim := ""                      # the support mission being targeted, if any
var _mouse := Vector2.ZERO          # where the pointer last was over the map
var _aim_from := Vector2.INF        # where the air strike was pinned (world px), while its direction is dragged
const HINT := "  Right-click: move, attack, shell a building"


func setup_merc(s: CombatSim, battle_meta: Dictionary) -> void:
	mc = Game.merc
	meta = battle_meta
	setup(s, {"format": "merc"})
	compact = true
	for m in sim.mechs:
		var cm: CombatMech = m
		if cm.controller == "player":
			player_idx.append(cm.index)
	var np := (meta.get("player", []) as Array).size()
	var lance_ids: Array = []
	for l in mc.lances:
		lance_ids.append(int(l["id"]))
	for i in np:
		var u: MercUnit = mc.units.get(int(meta["player"][i]["uid"]))
		if u != null and u.lance >= 0:
			lance_of[i] = lance_ids.find(u.lance) + 1
	playing = false
	speed = 1.0


func _ready() -> void:
	super._ready()
	var svc: Control = get_child(0)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mouse_filter = Control.MOUSE_FILTER_STOP
	follow = false
	var enemy := str(mc.contract.get("enemy", "")) if mc != null else ""
	var employer := str(mc.contract.get("employer", "")) if mc != null else ""
	for k in sim.mechs.size():
		var m: CombatMech = sim.mechs[k]
		var mat: ShaderMaterial
		if m.controller == "player":
			mat = Game.merc_material(0)
		elif m.team == 0:
			mat = Game.merc_material(1, employer)
		else:
			mat = Game.merc_material(1, enemy)
		var sp: Sprite2D = sprites[k]
		sp.material = mat
		var col: Color = mc.color if m.controller == "player" else (StarMap.get_map().faction_color(employer) if m.team == 0 else UI.BAD)
		sp.set_meta("color", col)
	_center_on_deployment()
	minimap.setup(self)


func _center_on_deployment() -> void:
	var c0 := Vector2.ZERO
	for i in player_idx:
		c0 += (sim.mechs[i] as CombatMech).pos
	if not player_idx.is_empty():
		c0 /= float(player_idx.size())
	var mid := sim.arena.size_m() / 2.0
	var vs := get_viewport_rect().size
	var z := clampf(minf((vs.x - 360.0) / (sim.arena.size_m().x * PX * 0.65), (vs.y - 260.0) / (sim.arena.size_m().y * PX * 0.75)), 0.2, 1.2)
	cam.zoom = Vector2(z, z)
	cam.position = c0.lerp(mid, 0.35) * PX
	_clamp_camera()


## Keeps the view on the battlefield (the HUD covers the top bar, the right panel and the bottom).
func _clamp_camera() -> void:
	var vs := get_viewport_rect().size
	var msz := sim.arena.size_m() * PX
	var z := cam.zoom.x
	var m := 30.0
	var lo := Vector2(vs.x / 2.0 / z - m, (vs.y / 2.0 - 40.0) / z - m)
	var hi := Vector2(msz.x - (vs.x / 2.0 - 330.0) / z + m, msz.y - (vs.y / 2.0 - 150.0) / z + m)
	var pos := cam.position
	pos.x = (lo.x + hi.x) / 2.0 if hi.x < lo.x else clampf(pos.x, lo.x, hi.x)
	pos.y = (lo.y + hi.y) / 2.0 if hi.y < lo.y else clampf(pos.y, lo.y, hi.y)
	cam.position = pos


func _fit_camera(instant: bool, delta := 0.0) -> void:
	pass


# ------------------------------------------------------------------ HUD

func _btn(text: String, cb: Callable, tip := "") -> Button:
	var b := UI.button(text, cb, tip)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 13)
	return b


func _build_hud() -> void:
	var top := PanelContainer.new()
	var tsb := UI.bar_box(true)
	tsb.content_margin_top = 5
	tsb.content_margin_bottom = 5
	top.add_theme_stylebox_override("panel", tsb)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	var th := UI.hbox(12)
	top.add_child(th)
	var ttl := UI.label(UI.ic("crosshairs") + "  " + str(meta.get("label", "Battle")).to_upper(), 17, UI.ACCENT)
	ttl.add_theme_font_override("font", UI.spaced("cond", 2))
	th.add_child(ttl)
	var theme_label: String = GameData.db().arenas["themes"].get(sim.arena.theme, {}).get("label", "")
	var sub := UI.label("%s  %s   %s  %s   %s  %s   %s  vs %s" % [UI.ic("globe"), meta.get("system", ""), UI.ic("map"), theme_label, UI.ic("eye"), Campaign.conditions_label(sim.conditions), UI.ic("flag"), meta.get("enemy", "")], 13, UI.DIM)
	th.add_child(sub)
	th.add_child(UI.spacer())
	play_btn = _btn("▶ Play", _toggle_play, "Space")
	th.add_child(play_btn)
	for s in [1.0, 2.0, 4.0]:
		var b := _btn("%dx" % int(s), func():
			speed = s
			playing = true)
		speed_btns.append(b)
		th.add_child(b)
	live_lbl = UI.label("PAUSED", 14, UI.WARN, true)
	live_lbl.add_theme_font_override("font", UI.spaced("cond_semi", 2))
	live_lbl.custom_minimum_size.x = 64
	th.add_child(live_lbl)
	time_lbl = UI.label("0:00", 18, UI.TEXT, true)
	time_lbl.add_theme_font_override("font", UI.font("cond_semi"))
	th.add_child(time_lbl)
	# objectives line
	var op := PanelContainer.new()
	var osb := UI.box(Color(0.03, 0.04, 0.052, 0.86), 4, UI.LINE, 1)
	osb.border_width_left = 3
	osb.border_color = UI.ACCENT
	osb.content_margin_left = 12
	osb.content_margin_right = 12
	osb.content_margin_top = 6
	osb.content_margin_bottom = 6
	op.add_theme_stylebox_override("panel", osb)
	op.set_anchors_preset(Control.PRESET_TOP_LEFT)
	op.position = Vector2(10, 52)
	add_child(op)
	var ov := UI.vbox(1)
	op.add_child(ov)
	var oh := UI.label(UI.ic("flag") + "  OBJECTIVE", 11, UI.ACCENT)
	oh.add_theme_font_override("font", UI.spaced("cond_semi", 2))
	ov.add_child(oh)
	obj_lbl = UI.label(str(meta.get("desc", "")), 13, UI.TEXT)
	obj_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	obj_lbl.custom_minimum_size.x = 520
	ov.add_child(obj_lbl)
	# right: the minimap, selection info and orders
	var rp := PanelContainer.new()
	var rsb := UI.box(Color(0.035, 0.045, 0.058, 0.93), 5, UI.LINE, 1)
	rsb.content_margin_left = 8
	rsb.content_margin_right = 8
	rsb.content_margin_top = 8
	rsb.content_margin_bottom = 8
	rsb.shadow_size = 12
	rsb.shadow_color = Color(0, 0, 0, 0.4)
	rp.add_theme_stylebox_override("panel", rsb)
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.anchor_top = 0.0
	rp.anchor_bottom = 1.0
	rp.offset_left = -322
	rp.offset_right = -10
	rp.offset_top = 52
	rp.offset_bottom = -154
	add_child(rp)
	var rv := UI.vbox(6)
	rp.add_child(rv)
	minimap = Minimap.new()
	rv.add_child(minimap)
	info_box = UI.vbox(3)
	info_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(info_box)
	rv.add_child(UI.header("Orders", "bolt", 12))
	var g := GridContainer.new()
	g.columns = 3
	g.add_child(_btn("Hold", func(): _order("hold"), "H: stand and shoot"))
	g.add_child(_btn("Free", func(): _order("free"), "F: the warrior fights on their own"))
	g.add_child(_btn("Withdraw", func(): _order("withdraw"), "W: leave by your map edge"))
	g.add_child(_btn("Close", func(): _order("range", "close"), "Fight at close range"))
	g.add_child(_btn("Optimal", func(): _order("range", "optimal"), "Fight at the best range for the weapons"))
	g.add_child(_btn("Long", func(): _order("range", "long"), "Keep the enemy at long range"))
	g.add_child(_btn("Cool", func(): _order("heat", "cool"), "Fire carefully, stay cool"))
	g.add_child(_btn("Balanced", func(): _order("heat", "balanced")))
	g.add_child(_btn("Run hot", func(): _order("heat", "hot"), "Fire everything, accept the heat"))
	g.add_child(_btn("Jets on", func(): _order("jump", "on"), "Use jump jets and death from above"))
	g.add_child(_btn("Jets off", func(): _order("jump", "off")))
	g.add_child(_btn("Select all", _select_all, "A"))
	rv.add_child(g)
	var g2 := UI.hbox(6)
	g2.add_child(_btn("Withdraw all", func():
		_select_all()
		_order("withdraw")))
	g2.add_child(_btn("Let the AI finish", _hand_over, "Your units fight the rest of the battle on their own, going for the objective"))
	rv.add_child(g2)
	var sup: Dictionary = meta.get("support", {}).get("player", {})
	if int(sup.get("artillery", 0)) + int(sup.get("air_strike", 0)) > 0:
		rv.add_child(UI.header("Support", "crosshairs", 12))
		var g3 := UI.hbox(6)
		support_btns["artillery"] = _btn("Artillery", func(): _start_aim("artillery"), "T: a battery off the map shells the spot you click. Three shells, 20 seconds out, and they hit anything there, yours included")
		support_btns["air_strike"] = _btn("Air strike", func(): _start_aim("air_strike"), "Y: a fighter strafes a strip. Click the middle of it and drag along the run. 12 seconds out, and it fires on anything under it")
		for sk in support_btns:
			(support_btns[sk] as Button).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			g3.add_child(support_btns[sk])
		rv.add_child(g3)
		_update_support()
	hint_lbl = UI.label(UI.ic("info") + HINT, 11, UI.DIM)
	rv.add_child(hint_lbl)
	# bottom: unit cards and the log
	var bot := PanelContainer.new()
	var bsb := UI.bar_box(false)
	bsb.content_margin_top = 8
	bsb.content_margin_bottom = 8
	bsb.content_margin_left = 10
	bsb.content_margin_right = 10
	bot.add_theme_stylebox_override("panel", bsb)
	bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_top = -146
	add_child(bot)
	var bh := UI.hbox(8)
	bot.add_child(bh)
	var cs := ScrollContainer.new()
	cs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	cs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := UI.hbox(6)
	cs.add_child(row)
	bh.add_child(cs)
	for i in player_idx:
		row.add_child(_card(i))
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.custom_minimum_size = Vector2(430, 120)
	log_box.add_theme_font_size_override("normal_font_size", 12)
	var lp := PanelContainer.new()
	var lsb := UI.box(Color(0.02, 0.025, 0.032, 0.8), 4, UI.LINE, 1)
	lsb.content_margin_left = 8
	lsb.content_margin_right = 8
	lsb.content_margin_top = 4
	lsb.content_margin_bottom = 4
	lp.add_theme_stylebox_override("panel", lsb)
	lp.add_child(log_box)
	bh.add_child(lp)
	slider = HSlider.new()
	slider.visible = false
	add_child(slider)
	done_btn = _btn("Done", _done)
	done_btn.visible = false
	add_child(done_btn)


func _card(i: int) -> Control:
	var m: CombatMech = sim.mechs[i]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _card_box(false))
	p.custom_minimum_size = Vector2(158, 112)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(v)
	var nm := UI.label("%s%s" % [("[%d] " % int(lance_of[i])) if lance_of.has(i) else "", m.name], 13, UI.TEXT, true)
	nm.clip_text = true
	v.add_child(nm)
	var dl := UI.label(m.design.display_name(), 11, UI.DIM)
	dl.clip_text = true
	v.add_child(dl)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 100
	bar.custom_minimum_size = Vector2(130, 10)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(bar)
	var st := UI.label("", 12, UI.GOOD)
	v.add_child(st)
	var cl := UI.label("", 11, UI.ACCENT)
	v.add_child(cl)
	for n in [nm, dl, st, cl]:
		(n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if not ev.shift_pressed:
				selected.clear()
			selected[i] = true
			if ev.double_click:
				cam.position = sprites[i].position
			accept_event())
	cards.append({"panel": p, "name": nm, "bar": bar, "status": st, "cmd": cl, "index": i})
	return p


func _card_box(on: bool, out := false) -> StyleBoxFlat:
	var sb := UI.box(Color(0.075, 0.09, 0.11, 0.95) if not on else Color(0.1, 0.11, 0.1, 0.98), 4, UI.ACCENT if on else UI.LINE, 1)
	sb.border_width_left = 3
	sb.border_color = UI.ACCENT if on else (Color(0.35, 0.18, 0.16) if out else mc.color.lightened(0.1))
	if on:
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
	sb.content_margin_left = 9
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb


func _toggle_play() -> void:
	playing = not playing


func _select_all() -> void:
	selected.clear()
	for i in player_idx:
		if not (sim.mechs[i] as CombatMech).out:
			selected[i] = true


func _sel_list() -> Array:
	var out: Array = []
	for i in selected:
		if not (sim.mechs[i] as CombatMech).out:
			out.append(int(i))
	out.sort()
	return out


func _order(cmd: String, arg: Variant = null) -> void:
	var us := _sel_list()
	if us.is_empty() or sim.finished:
		return
	if sim.issue_command(us, cmd, arg):
		_spawn_events()


## Your units go for the objective on their own and the battle runs to the end.
func _hand_over() -> void:
	for i in player_idx:
		(sim.mechs[i] as CombatMech).controller = "ai"
	sim.support[0]["auto"] = true
	_start_aim("")
	MercCampaign.objective_orders(sim, str(meta.get("type", "")), meta.get("edges", ["W", "E"]))
	_skip_to_end()


# ------------------------------------------------------------------ off-board support

func _update_support() -> void:
	for k in support_btns:
		var b: Button = support_btns[k]
		var n := sim.support_left(0, str(k))
		b.text = "%s  ×%d" % ["Artillery" if k == "artillery" else "Air strike", n]
		b.disabled = n <= 0 or sim.finished
		b.modulate = Color(1.0, 0.85, 0.4) if _aim == k else Color.WHITE


func _start_aim(kind: String) -> void:
	_aim = "" if kind == _aim or (kind != "" and sim.support_left(0, kind) <= 0) else kind
	_aim_from = Vector2.INF
	_drag_from = Vector2.INF
	if hint_lbl != null:
		match _aim:
			"artillery":
				hint_lbl.text = UI.ic("crosshairs") + "  Click where the shells should fall. Esc: cancel"
			"air_strike":
				hint_lbl.text = UI.ic("crosshairs") + "  Click the target, drag along the run. Esc: cancel"
			_:
				hint_lbl.text = UI.ic("info") + HINT
		hint_lbl.add_theme_color_override("font_color", UI.DIM if _aim == "" else UI.WARN)
	_update_support()


## The run a fighter makes when the strike is clicked rather than dragged: along the front, not over your own lines.
func _default_run() -> float:
	return PI / 2.0 if sim.home_edge(0) in ["W", "E"] else 0.0


func _aim_click(mb: InputEventMouseButton) -> void:
	var wp := _world(mb.position)
	if _aim == "artillery":
		if mb.pressed:
			sim.issue_support(0, "artillery", wp / PX)
			_start_aim("")
			_spawn_events()
		return
	if mb.pressed:
		_aim_from = wp
	elif _aim_from != Vector2.INF:
		var d := wp - _aim_from
		sim.issue_support(0, "air_strike", _aim_from / PX, d.angle() if d.length() > 30.0 else _default_run())
		_start_aim("")
		_spawn_events()


func _draw_support(font: Font) -> void:
	var T: Dictionary = sim.tables["support"]
	var mine := Color(0.5, 0.82, 1.0)
	var theirs := Color(1.0, 0.3, 0.25)
	var drawn := {}
	for st in sim.strikes:
		var own := int(st["team"]) == 0
		var left := float(st["at"]) - sim.t
		if not own and left > 6.0:
			continue          # you hear the enemy's guns before you know where the shells will fall
		var key := "%s%s%s" % [st["kind"], st["pos"], st["team"]]
		if drawn.has(key):
			continue
		drawn[key] = true
		var col := mine if own else theirs
		var p: Vector2 = (st["pos"] as Vector2) * PX
		var pulse := 0.55 + 0.45 * sin(pt * 9.0)
		if str(st["kind"]) in ["artillery", "tube"]:
			_draw_blast(p, col, 0.5 + 0.3 * pulse)
		else:
			_draw_strip(p, float(st["ang"]), col, 0.5 + 0.3 * pulse)
		var txt := ("%s  %d s" % ["FIRE MISSION" if str(st["kind"]) in ["artillery", "tube"] else "AIR STRIKE", int(ceil(left))]) if own else "INCOMING!"
		var k := 1.0 / clampf(cam.zoom.x, 0.3, 1.2)       # readable at any zoom
		var top := float(T["artillery"]["radius_m"]) * PX if str(st["kind"]) in ["artillery", "tube"] else float(T["air_strike"]["width_m"]) * PX
		fx_node.draw_string_outline(font, p + Vector2(-110.0 * k, -top - 8.0 * k), txt, HORIZONTAL_ALIGNMENT_CENTER, 220.0 * k, int(15.0 * k), int(4.0 * k), Color(0, 0, 0, 0.7))
		fx_node.draw_string(font, p + Vector2(-110.0 * k, -top - 8.0 * k), txt, HORIZONTAL_ALIGNMENT_CENTER, 220.0 * k, int(15.0 * k), col)
	if _aim == "":
		return
	var mp := _world(_mouse)
	var gold := Color(1.0, 0.85, 0.4)
	if _aim == "artillery":
		_draw_blast(mp, gold, 0.9)
	elif _aim_from == Vector2.INF:
		_draw_strip(mp, _default_run(), gold, 0.9)
	else:
		var d := mp - _aim_from
		_draw_strip(_aim_from, d.angle() if d.length() > 30.0 else _default_run(), gold, 0.9)


func _draw_blast(p: Vector2, col: Color, a: float) -> void:
	var S: Dictionary = sim.tables["support"]["artillery"]
	var r := float(S["radius_m"]) * PX
	fx_node.draw_circle(p, r, Color(col.r, col.g, col.b, 0.08 * a))
	fx_node.draw_arc(p, r, 0, TAU, 48, Color(col.r, col.g, col.b, a), 2.0)
	fx_node.draw_arc(p, CombatSim.HEX * 0.5 * PX, 0, TAU, 24, Color(col.r, col.g, col.b, a), 1.5)
	fx_node.draw_arc(p, r + float(S["scatter_m"]) * PX, 0, TAU, 64, Color(col.r, col.g, col.b, 0.3 * a), 1.0)
	fx_node.draw_line(p - Vector2(12, 0), p + Vector2(12, 0), Color(col.r, col.g, col.b, a), 1.5)
	fx_node.draw_line(p - Vector2(0, 12), p + Vector2(0, 12), Color(col.r, col.g, col.b, a), 1.5)


func _draw_strip(p: Vector2, ang: float, col: Color, a: float) -> void:
	var S: Dictionary = sim.tables["support"]["air_strike"]
	var dir := Vector2.from_angle(ang)
	var half := dir * float(S["length_m"]) * 0.5 * PX
	var side := dir.orthogonal() * float(S["width_m"]) * 0.5 * PX
	var pts := PackedVector2Array([p - half - side, p + half - side, p + half + side, p - half + side])
	fx_node.draw_colored_polygon(pts, Color(col.r, col.g, col.b, 0.1 * a))
	pts.append(pts[0])
	fx_node.draw_polyline(pts, Color(col.r, col.g, col.b, a), 2.0)
	# which way the fighter flies
	var tip := p + half + dir * 26.0
	fx_node.draw_line(p - half - dir * 40.0, tip, Color(col.r, col.g, col.b, 0.6 * a), 1.5)
	fx_node.draw_colored_polygon(PackedVector2Array([tip, tip - dir * 18.0 + dir.orthogonal() * 9.0, tip - dir * 18.0 - dir.orthogonal() * 9.0]), Color(col.r, col.g, col.b, a))


# ------------------------------------------------------------------ input

func _world(screen: Vector2) -> Vector2:
	return cam.position + (screen - size / 2.0) / cam.zoom.x


func _gui_input(event: InputEvent) -> void:
	if results != null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		_mouse = mb.position
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.12)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.12)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_pan = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and _aim != "":
			_aim_click(mb)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and _aim != "":
			if mb.pressed:
				_start_aim("")
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = mb.position
				_drag_to = mb.position
			else:
				if _drag_from != Vector2.INF:
					_finish_select(mb.shift_pressed)
				_drag_from = Vector2.INF
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_right_click(mb.position)
		accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_mouse = mm.position
		if _pan:
			cam.position -= mm.relative / cam.zoom.x
		elif _drag_from != Vector2.INF:
			_drag_to = mm.position
		accept_event()


func _zoom_at(p: Vector2, f: float) -> void:
	var before := _world(p)
	var z := clampf(cam.zoom.x * f, 0.15, 2.2)
	cam.zoom = Vector2(z, z)
	cam.position += before - _world(p)


func _unhandled_input(event: InputEvent) -> void:
	if results != null:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		var pan_v := {KEY_A: Vector2.LEFT, KEY_LEFT: Vector2.LEFT, KEY_D: Vector2.RIGHT, KEY_RIGHT: Vector2.RIGHT,
			KEY_UP: Vector2.UP, KEY_DOWN: Vector2.DOWN, KEY_S: Vector2.DOWN}
		if pan_v.has(k.keycode) and not k.ctrl_pressed:
			if k.pressed:
				_keys_pan += pan_v[k.keycode]
			else:
				_keys_pan -= pan_v[k.keycode]
			_keys_pan = _keys_pan.clamp(Vector2(-1, -1), Vector2(1, 1))
			return
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_SPACE:
				_toggle_play()
			KEY_H:
				_order("hold")
			KEY_F:
				_order("free")
			KEY_W:
				_order("withdraw")
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
				var n := int(k.keycode - KEY_0)
				if not k.shift_pressed:
					selected.clear()
				for i in lance_of:
					if int(lance_of[i]) == n and not (sim.mechs[i] as CombatMech).out:
						selected[i] = true
			KEY_T:
				if support_btns.has("artillery"):
					_start_aim("artillery")
			KEY_Y:
				if support_btns.has("air_strike"):
					_start_aim("air_strike")
			KEY_ESCAPE:
				if _aim != "":
					_start_aim("")
				else:
					selected.clear()
		if k.keycode == KEY_A and k.ctrl_pressed:
			_select_all()


func _finish_select(add: bool) -> void:
	var r := Rect2(_drag_from, Vector2.ZERO).expand(_drag_to)
	if not add:
		selected.clear()
	if r.size.length() < 8.0:
		var best := -1
		var bd := 36.0
		for i in player_idx:
			var m: CombatMech = sim.mechs[i]
			if m.out:
				continue
			var sp := (sprites[i] as Sprite2D).position
			var d := (size / 2.0 + (sp - cam.position) * cam.zoom.x).distance_to(_drag_from)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			if add and selected.has(best):
				selected.erase(best)
			else:
				selected[best] = true
		return
	for i in player_idx:
		var m2: CombatMech = sim.mechs[i]
		if m2.out:
			continue
		var s2 := size / 2.0 + ((sprites[i] as Sprite2D).position - cam.position) * cam.zoom.x
		if r.has_point(s2):
			selected[i] = true


func _right_click(p: Vector2) -> void:
	if _sel_list().is_empty():
		return
	var wp := _world(p)
	# an enemy under the cursor?
	var best := -1
	var bd := 34.0 / cam.zoom.x
	for k in sim.mechs.size():
		var m: CombatMech = sim.mechs[k]
		if m.team == 0 or m.out or not m.spotted:
			continue
		var d := (sprites[k] as Sprite2D).position.distance_to(wp)
		if d < bd:
			bd = d
			best = k
	if best >= 0:
		_order("attack", best)
		fx.append({"type": "text", "t": sim.t, "pos": sprites[best].position + Vector2(0, -50), "text": "ATTACK", "col": UI.BAD})
		return
	var meters := wp / PX
	var ci := sim.arena.cell_index(meters)
	if sim.arena.terrain[ci] == Arena.T.BUILDING and int(sim.arena.bld_cf[ci]) < 99999:
		_order("shell", ci)
		fx.append({"type": "text", "t": sim.t, "pos": wp + Vector2(0, -30), "text": "FIRE ON THE BUILDING", "col": UI.WARN})
		return
	_order("move", meters)
	fx.append({"type": "dust", "t": sim.t, "pos": wp})


# ------------------------------------------------------------------ playback

func _process(delta: float) -> void:
	if results != null:
		return
	if _keys_pan != Vector2.ZERO:
		cam.position += _keys_pan * 900.0 * delta / cam.zoom.x
	_clamp_camera()
	if playing and not sim.finished:
		var want := sim.t + delta * speed
		var steps := 0
		while sim.t < want and not sim.finished and steps < 400:
			sim.step()
			steps += 1
		_sync_frames()
	pt = sim.t
	_spawn_events()
	_update_scene()
	under.pt = pt
	over.pt = pt
	arena_view.set_time(pt)
	under.queue_redraw()
	over.queue_redraw()
	fx_node.queue_redraw()
	glow.queue_redraw()
	lights.queue_redraw()
	_apply_shake(delta if playing else 0.0)
	play_btn.text = "⏸ Pause" if playing else "▶ Play"
	live_lbl.text = ("● %dx" % int(speed)) if playing else "PAUSED"
	live_lbl.add_theme_color_override("font_color", UI.BAD if playing else UI.WARN)
	_info_t -= delta
	if _info_t <= 0.0:
		_info_t = 0.25
		_update_cards()
		_update_info()
	if sim.finished and not applied:
		_finish()


func _update_sprites(f0: PackedFloat32Array, f1: PackedFloat32Array, a: float) -> void:
	super._update_sprites(f0, f1, a)
	for k in sim.mechs.size():
		var m: CombatMech = sim.mechs[k]
		var sp: Sprite2D = sprites[k]
		var sh: Sprite2D = shadows[k]
		var flags: int = sp.get_meta("flags", 0)
		var hidden := bool(flags & 32768) or bool(flags & 16384)
		if m.team != 0 and not (flags & 8192) and not (flags & 8):
			hidden = true
		if m.team != 0 and (flags & 8192):
			last_seen[k] = sp.position
		sp.visible = not hidden
		sh.visible = not hidden
		if m.is_infantry:
			sp.scale = Vector2(0.46, 0.46)
			sh.visible = false
		elif m.is_vehicle:
			sp.scale = Vector2(0.55, 0.55)
			sh.scale = sp.scale
			if flags & 4096 and not (flags & 4):
				# a VTOL in flight: lifted off its shadow
				sh.position = sp.position + Vector2(26, 34)
				sp.position -= Vector2(0, 14)
			var o := k * CombatSim.STRIDE
			if m.internal.has("TU"):
				sp.set_meta("turret", lerp_angle(f0[o + 3], f1[o + 3], a))


func _update_panels(_f0: PackedFloat32Array, _f1: PackedFloat32Array, _a: float) -> void:
	pass


func _update_cards() -> void:
	var cmds := {"move": "Moving", "attack": "Attacking", "hold": "Holding", "withdraw": "Withdrawing", "attack_cell": "Shelling",
		"guard": "Guarding", "recon": "Scouting", "free": ""}
	for cd in cards:
		var i: int = cd["index"]
		var m: CombatMech = sim.mechs[i]
		var frac := (m.armor_fraction() * 0.6 + (1.0 - m.internal_lost_fraction()) * 0.4) * 100.0
		(cd["bar"] as ProgressBar).value = frac
		(cd["bar"] as ProgressBar).add_theme_stylebox_override("fill", UI.box(UI.frac_color(frac / 100.0), 2))
		var st := "Fighting"
		var col := UI.GOOD
		if m.destroyed:
			st = "DESTROYED"
			col = UI.BAD
		elif m.withdrew:
			st = "Withdrew"
			col = UI.DIM
		elif m.ejected:
			st = "Ejected"
			col = UI.BAD
		elif m.out:
			st = m.out_reason.capitalize()
			col = UI.BAD
		elif m.is_vehicle and m.immobile:
			st = "Immobile"
			col = UI.WARN
		elif m.gait == CombatMech.Gait.PRONE:
			st = "Down"
			col = UI.WARN
		elif m.shutdown:
			st = "Shutdown"
			col = UI.WARN
		elif not m.is_vehicle and m.heat >= 10.0:
			st = "Hot (%d)" % int(m.heat)
			col = UI.WARN
		(cd["status"] as Label).text = st
		(cd["status"] as Label).add_theme_color_override("font_color", col)
		var c2: Dictionary = sim.ai.state[i].get("cmd", {})
		(cd["cmd"] as Label).text = cmds.get(str(c2.get("type", "free")), "") if not m.out else ""
		var p: PanelContainer = cd["panel"]
		var on := selected.has(i)
		if not p.has_meta("on") or bool(p.get_meta("on")) != on or m.out != p.get_meta("out", false):
			p.set_meta("on", on)
			p.set_meta("out", m.out)
			p.add_theme_stylebox_override("panel", _card_box(on, m.out))


func _update_info() -> void:
	var us := _sel_list()
	var want := int(us[0]) if not us.is_empty() else -1
	if want != info_index:
		info_index = want
		UI.clear(info_box)
		info_lbls = {}
		info_doll = null
		if want < 0:
			info_box.add_child(UI.label("Nothing selected", 14, UI.DIM))
			info_box.add_child(UI.label("Click your units, drag a box, or press 1-4 for a lance.", 12, UI.DIM))
			return
		var m: CombatMech = sim.mechs[want]
		info_box.add_child(UI.label(m.name, 16, UI.TEXT, true))
		info_box.add_child(UI.label("%s  ·  G%d/%s%d" % [m.design.display_name(), m.gunnery, "D" if m.is_vehicle else "P", m.piloting], 12, UI.DIM))
		if m.is_infantry:
			var sd = SquadDoll.new(1.0)
			sd.set_design(m.design as VehicleDesign, {})
			info_doll = sd
		elif m.is_vehicle:
			var vd = VehicleDoll.new(0.95)
			vd.set_design(m.design as VehicleDesign, {})
			info_doll = vd
		else:
			var pd = PaperDoll.new(1.0)
			pd.set_design(m.design, {})
			info_doll = pd
		info_box.add_child(info_doll)
		for key in ["state", "heat", "weapons"]:
			var l := UI.label("", 12, UI.TEXT)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info_box.add_child(l)
			info_lbls[key] = l
		if us.size() > 1:
			info_box.add_child(UI.label("+ %d more selected" % (us.size() - 1), 12, UI.ACCENT))
	if want < 0:
		return
	var m2: CombatMech = sim.mechs[want]
	info_doll.call("set_live", m2.armor, m2.internal)
	var parts: Array = []
	parts.append("%d/%d MP" % [m2.walk_mp(), m2.run_mp()])
	if m2.is_infantry:
		parts.append("%d of %d %s left" % [m2.troopers_alive(), m2.troopers_max, "suits" if m2.battle_armor else "troopers"])
		if m2.anti_mech:
			parts.append("swarms legs")
	elif m2.is_vehicle:
		if m2.immobile or m2.engine_dead:
			parts.append("IMMOBILE")
		if m2.crew_stunned(sim.t):
			parts.append("crew stunned")
		if m2.turret_locked:
			parts.append("turret locked")
	else:
		if m2.pilot_hits > 0:
			parts.append("pilot hits %d" % m2.pilot_hits)
		if m2.gait == CombatMech.Gait.PRONE:
			parts.append("prone")
	(info_lbls["state"] as Label).text = "  ·  ".join(parts)
	(info_lbls["heat"] as Label).text = "" if m2.is_vehicle else "Heat %d  (%s orders)" % [int(m2.heat), str(m2.orders.get("heat", "balanced"))]
	var wl: Array = []
	for wi in m2.weapons:
		var mt: Dictionary = m2.mounts[wi]
		var it: Dictionary = mt["item"]
		var tag := ""
		if mt["destroyed"] or m2.loc_destroyed.get(mt["loc"], false):
			tag = " ✗"
		else:
			var bi := sim.find_ammo(m2, mt)
			if bi == -1:
				tag = " (empty)"
			elif bi >= 0:
				tag = " (%d)" % int(m2.mounts[bi]["shots"])
		wl.append("%s%s" % [it.get("name", ""), tag])
	(info_lbls["weapons"] as Label).text = ", ".join(wl)


# ------------------------------------------------------------------ drawing

func _fx_for(e: Dictionary) -> void:
	super._fx_for(e)
	if str(e.get("k", "")) == "support_call":
		_update_support()
		if int(e["team"]) == 0:
			_text(float(e["t"]), Vector2(float(e["pos"][0]), float(e["pos"][1])) * PX + Vector2(0, -20), "FIRE MISSION" if str(e["kind"]) == "artillery" else "AIR STRIKE", Color(0.5, 0.82, 1.0))
	if str(e.get("k", "")) == "shot_bld":
		var t := float(e["t"])
		var dst := sim.arena.center_of_index(int(e["cell"])) * PX
		if not e["hit"]:
			dst += Vector2(randf_range(-30, 30), randf_range(-30, 30))
		fx.append({"type": "shot", "wt": e.get("wt", ""), "w": e.get("w", ""), "t": t, "src": _pos_at(int(e["m"]), t), "dst": dst, "hit": e["hit"]})


func _draw_unit_marks(font: Font) -> void:
	var A := sim.arena
	_draw_support(font)
	# exit edges: your own in green, the breakthrough edge in gold
	var szp := A.size_m() * PX
	for e in sim.exit_edges(0):
		var col := Color(0.4, 0.9, 0.5, 0.18) if str(e) == sim.home_edge(0) else Color(1.0, 0.8, 0.3, 0.25)
		var band := 22.0 * PX
		match str(e):
			"W":
				fx_node.draw_rect(Rect2(0, 0, band, szp.y), col)
			"E":
				fx_node.draw_rect(Rect2(szp.x - band, 0, band, szp.y), col)
			"N":
				fx_node.draw_rect(Rect2(0, 0, szp.x, band), col)
			"S":
				fx_node.draw_rect(Rect2(0, szp.y - band, szp.x, band), col)
	var ob := A.objectives
	for key in ["defend_cells", "attack_cells"]:
		var cc := Color(0.4, 0.7, 1.0) if key == "defend_cells" else Color(1.0, 0.4, 0.3)
		for ci in ob.get(key, []):
			var cp := A.center_of_index(int(ci)) * PX
			var r := Rect2(cp - Vector2(Arena.CELL, Arena.CELL) * PX / 2.0, Vector2(Arena.CELL, Arena.CELL) * PX)
			if A.terrain[int(ci)] == Arena.T.BUILDING:
				fx_node.draw_rect(r, Color(cc.r, cc.g, cc.b, 0.85), false, 2.0)
			else:
				fx_node.draw_line(r.position, r.end, Color(cc.r, cc.g, cc.b, 0.5), 2.0)
	var pts: Array = ob.get("recon_points", [])
	for k in pts.size():
		var done := k < sim.recon_done.size() and bool(sim.recon_done[k])
		var rp: Vector2 = (pts[k] as Vector2) * PX
		var rc := Color(0.4, 0.95, 0.5) if done else Color(1.0, 0.85, 0.3)
		fx_node.draw_arc(rp, float(ob.get("recon_radius_m", 130.0)) * PX, 0, TAU, 48, Color(rc.r, rc.g, rc.b, 0.6), 2.0)
		fx_node.draw_string(font, rp + Vector2(-30, 6), "RECON %d%s" % [k + 1, " ✓" if done else ""], HORIZONTAL_ALIGNMENT_CENTER, 60, 16, rc)
	# units
	for k in sim.mechs.size():
		var m: CombatMech = sim.mechs[k]
		var sp: Sprite2D = sprites[k]
		var flags: int = sp.get_meta("flags", 0)
		if not sp.visible:
			if m.team != 0 and last_seen.has(k) and not m.out:
				var lp: Vector2 = last_seen[k]
				fx_node.draw_arc(lp, 26.0, 0, TAU, 24, Color(1.0, 0.4, 0.35, 0.35), 2.0)
				fx_node.draw_string(font, lp + Vector2(-10, 7), "?", HORIZONTAL_ALIGNMENT_CENTER, 20, 18, Color(1.0, 0.5, 0.45, 0.5))
			continue
		var col: Color = sp.get_meta("color")
		var rad := 27.0 if not m.is_vehicle else (18.0 if m.is_infantry else 23.0)
		if flags & 4:
			fx_node.draw_arc(sp.position, rad, 0, TAU, 32, Color(0.4, 0.4, 0.4, 0.4), 1.5, true)
		else:
			fx_node.draw_circle(sp.position, rad, Color(col.r, col.g, col.b, 0.1))
			fx_node.draw_arc(sp.position, rad, 0, TAU, 40, Color(col.r, col.g, col.b, 0.85), 2.0, true)
		if selected.has(k):
			# a turning dashed bracket around the selection
			var spin := pt * 1.2 + k
			for q in 4:
				var a0 := spin + q * PI / 2.0
				fx_node.draw_arc(sp.position, rad + 6.0, a0, a0 + 0.9, 10, Color(0.55, 1.0, 0.65, 0.95), 2.5, true)
		if m.is_vehicle and sp.has_meta("turret") and not (flags & 4):
			var ta := float(sp.get_meta("turret")) + sp.rotation - PI / 2.0
			fx_node.draw_line(sp.position, sp.position + Vector2.from_angle(ta) * 26.0, Color(0.1, 0.1, 0.1, 0.9), 4.0)
		if flags & 512 and not (flags & 4):
			fx_node.draw_arc(sp.position, 180.0 * PX, 0, TAU, 64, Color(0.4, 0.7, 1.0, 0.15), 2.0)
		if m.team == 0 and m.controller == "player" and not m.out:
			var c2: Dictionary = sim.ai.state[k].get("cmd", {})
			var ct := str(c2.get("type", "free"))
			if ct == "move" or ct == "hold":
				var gp: Vector2 = (c2.get("pos", m.pos) as Vector2) * PX
				if gp.distance_to(sp.position) > 20.0:
					fx_node.draw_dashed_line(sp.position, gp, Color(0.5, 1.0, 0.6, 0.6 if selected.has(k) else 0.3), 2.0, 10.0)
				fx_node.draw_circle(gp, 4.0, Color(0.5, 1.0, 0.6, 0.6))
			elif ct == "withdraw":
				fx_node.draw_dashed_line(sp.position, A.edge_point(m.pos, str(c2.get("edge", "W")), 4.0) * PX, Color(1.0, 0.85, 0.3, 0.4), 2.0, 10.0)
			elif ct == "attack":
				var ti := int(c2.get("target", -1))
				if ti >= 0 and not sim.mechs[ti].out:
					fx_node.draw_line(sp.position, sprites[ti].position, Color(1.0, 0.35, 0.3, 0.45 if selected.has(k) else 0.2), 2.0)
		var label := m.name
		if lance_of.has(k):
			label = "%d %s" % [int(lance_of[k]), m.name]
		if not (flags & 4):
			Vfx.health_bar(fx_node, sp.position + Vector2(0, rad + 6), float(sp.get_meta("arm", 1.0)), float(sp.get_meta("str", 1.0)), col, 36.0)
		fx_node.draw_string(font, sp.position + Vector2(-69, rad + 27), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color(0, 0, 0, 0.7))
		fx_node.draw_string(font, sp.position + Vector2(-70, rad + 26), label, HORIZONTAL_ALIGNMENT_CENTER, 140, 13, Color(1, 1, 1, 0.9))
	if _drag_from != Vector2.INF and _drag_from.distance_to(_drag_to) > 8.0:
		var a := _world(_drag_from)
		var b := _world(_drag_to)
		var r2 := Rect2(a, Vector2.ZERO).expand(b)
		fx_node.draw_rect(r2, Color(0.5, 1.0, 0.6, 0.12))
		fx_node.draw_rect(r2, Color(0.5, 1.0, 0.6, 0.7), false, 1.5)


# ------------------------------------------------------------------ the end

func _finish() -> void:
	applied = true
	playing = false
	var res := sim.result
	summary_m = mc.resolve_battle(meta, res)
	load("res://ui/merc/ops_tab.gd").last_summary = summary_m
	Game.save_game("merc_autosave")
	results = PanelContainer.new()
	var out := str(summary_m.get("outcome", "draw"))
	var oc := UI.GOOD if out == "victory" else (UI.BAD if out == "defeat" else UI.WARN)
	var rsb := UI.box(Color(0.035, 0.045, 0.058, 0.97), 6, UI.LINE_HI, 1)
	rsb.border_width_top = 3
	rsb.border_color = oc
	rsb.shadow_size = 30
	rsb.shadow_color = Color(0, 0, 0, 0.6)
	rsb.content_margin_left = 26
	rsb.content_margin_right = 26
	rsb.content_margin_top = 18
	rsb.content_margin_bottom = 20
	results.add_theme_stylebox_override("panel", rsb)
	results.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(results)
	var v := UI.vbox(5)
	results.add_child(v)
	var t := UI.label(out.to_upper(), 44, oc)
	t.add_theme_font_override("font", UI.spaced("cond", 8))
	t.add_theme_color_override("font_shadow_color", Color(oc.r, oc.g, oc.b, 0.35))
	t.add_theme_constant_override("shadow_outline_size", 10)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var hw := UI.label("%s after %d:%02d" % [str(res["how"]).capitalize(), int(sim.t) / 60, int(sim.t) % 60], 14, UI.DIM)
	hw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hw)
	v.add_child(UI.header("Report", "list", 12))
	for line in summary_m.get("units", []):
		v.add_child(UI.label(str(line), 13))
	for line in summary_m.get("people", []):
		v.add_child(UI.label(str(line), 13, UI.DIM))
	for line in summary_m.get("money", []):
		v.add_child(UI.label(str(line), 13, UI.GOOD))
	if not mc.salvage.is_empty():
		v.add_child(UI.label("Salvage is waiting on the Battles tab.", 14, UI.ACCENT))
	var b := UI.primary(_btn("Continue  " + UI.ic("arrow_right"), _done))
	b.custom_minimum_size.y = 38
	v.add_child(UI.spacer(false))
	v.add_child(b)
	UI.fade_in(results, 0.3)
	results.custom_minimum_size = Vector2(560, 0)
	results.position = (get_viewport_rect().size - Vector2(560, 380)) / 2.0
	(func():
		if is_instance_valid(results):
			var rs := results.get_combined_minimum_size()
			results.position = ((get_viewport_rect().size - Vector2(330, 150)) - rs) / 2.0 + Vector2(0, 40)).call_deferred()


func _done() -> void:
	if not sim.finished:
		return
	if not applied:
		_finish()
		return
	Game.show_merc_hub("ops")
