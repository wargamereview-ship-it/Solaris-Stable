extends Control
## Watches a fight live: the sim runs as you watch, so you can make corner calls to your warriors.
## Top-down arena, MegaMek sprites in stable colors, weapon effects, the live battlefield (fire, smoke,
## collapses, hazards, night and weather), armor diagrams, heat, and a log of every roll.
## You can scrub back through what has happened; calls only go out at the live edge.

const ArenaView := preload("res://ui/fight/arena_view.gd")
const ArenaFx := preload("res://ui/fight/arena_fx.gd")
const Weather := preload("res://ui/fight/weather_overlay.gd")
const PaperDoll := preload("res://ui/widgets/paper_doll.gd")
const PX := 2.4
const LASER := Color(1.0, 0.25, 0.2)
const PULSE := Color(1.0, 0.85, 0.3)
const PPC := Color(0.55, 0.8, 1.0)

var sim: CombatSim
var bout: Dictionary
var c: Campaign
var arena_mc: MercCampaign   # set for a mercenary company's duel on Solaris VII
var duration := 0.0
var pt := 0.0
var speed := 1.0
var playing := true
var ev_i := 0
var frame_t := PackedFloat32Array()

var world: Node2D
var cam: Camera2D
var fx_node: Node2D
var under: Node2D
var over: Node2D
var lights: Node2D
var glow: Node2D
var shake := 0.0
var arena_view: Node2D
var sprites: Array = []
var shadows: Array = []
var fx: Array = []
var follow := true
var applied := false
var summary: Dictionary = {}
var night := 0.0
var compact := false

# HUD
var log_box: RichTextLabel
var time_lbl: Label
var slider: HSlider
var done_btn: Button
var live_lbl: Label
var dolls: Array = []
var heat_bars: Array = []
var heat_lbls: Array = []
var status_lbls: Array = []
var pilot_lbls: Array = []
var call_boxes: Array = []   # per mech: {"box", "label", "focus"}
var banner: PanelContainer
var _scrubbing := false


func setup(s: CombatSim, b: Dictionary) -> void:
	sim = s
	bout = b
	c = Game.campaign
	arena_mc = Game.merc if b.get("merc_arena", false) else null
	_sync_frames()
	compact = sim.mechs.size() > 2
	match str(sim.conditions.get("light", "day")):
		"night":
			night = 0.55 if sim.conditions.get("floodlights", false) else 1.0
		"dusk":
			night = 0.35


func _sync_frames() -> void:
	for k in range(frame_t.size(), sim.frames.size()):
		frame_t.append(sim.frames[k][9])
	duration = sim.t


func _ready() -> void:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(svc)
	var sv := SubViewport.new()
	sv.handle_input_locally = false
	svc.add_child(sv)
	world = Node2D.new()
	sv.add_child(world)
	var av = ArenaView.new()
	av.setup(sim.arena)
	av.set_night(night)
	world.add_child(av)
	arena_view = av
	under = ArenaFx.new()
	under.arena = sim.arena
	under.layer = "under"
	under.night = night
	world.add_child(under)
	for m in sim.mechs:
		var sh := Sprite2D.new()
		sh.texture = Game.mech_texture(m.design.sprite)
		sh.modulate = Color(0, 0, 0, 0.35)
		sh.scale = Vector2(0.62, 0.62)
		world.add_child(sh)
		shadows.append(sh)
	for m in sim.mechs:
		var sp := Sprite2D.new()
		sp.texture = Game.mech_texture(m.design.sprite)
		sp.scale = Vector2(0.62, 0.62)
		var sid := _stable_of(m.index)
		var fallback := Color.from_hsv(float(m.team) / maxf(1.0, sim.team_count), 0.6, 0.85)
		if arena_mc != null:   # a mercenary company's duel: its own colors against the house fighter's
			var oc: Array = bout["opp"]["color"]
			fallback = arena_mc.color if m.team == 0 else Color.from_hsv(float(oc[0]), float(oc[1]), float(oc[2]))
		sp.material = Game.stable_material(sid) if sid >= 0 else (Game.tint_material(fallback, arena_mc.camo) if arena_mc != null and m.team == 0 else Game.tint_material(fallback))
		sp.set_meta("color", c.stables[sid].color if sid >= 0 and c != null else fallback)
		sp.modulate = Color(1, 1, 1).darkened(night * 0.25)
		world.add_child(sp)
		sprites.append(sp)
	over = ArenaFx.new()
	over.arena = sim.arena
	over.layer = "over"
	world.add_child(over)
	fx_node = Node2D.new()
	fx_node.draw.connect(_draw_fx)
	world.add_child(fx_node)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow = Node2D.new()
	glow.material = add
	glow.draw.connect(_draw_glow)
	world.add_child(glow)
	lights = Node2D.new()
	lights.material = add
	lights.draw.connect(_draw_lights)
	world.add_child(lights)
	cam = Camera2D.new()
	world.add_child(cam)
	cam.make_current()
	var wo = Weather.new()
	wo.weather = str(sim.conditions.get("weather", "clear"))
	add_child(wo)
	_build_hud()
	_fit_camera(true)


## The stable a sim 'Mech belongs to, from the bout's entries in sim order.
func _stable_of(index: int) -> int:
	if c == null:
		return -1
	var entries: Array = []
	if bout.has("sides"):
		for side in bout["sides"]:
			for e in side:
				entries.append(e)
	elif bout.has("a"):
		entries = [bout["a"], bout["b"]]
	if index < entries.size() and int(entries[index]["warrior"]) >= 0:
		return c.warriors[int(entries[index]["warrior"])].stable_id
	return -1


func _warrior_of(index: int) -> Warrior:
	if c == null:
		return null
	var entries: Array = []
	if bout.has("sides"):
		for side in bout["sides"]:
			for e in side:
				entries.append(e)
	elif bout.has("a"):
		entries = [bout["a"], bout["b"]]
	if index < entries.size() and int(entries[index]["warrior"]) >= 0:
		return c.warriors.get(int(entries[index]["warrior"]))
	return null


func _player_mech(index: int) -> bool:
	return bout.has("orders") and sim.mechs[index].team == 0


# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.035, 0.04, 0.88), 0))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	var th := UI.hbox(16)
	top.add_child(th)
	var kind: String = str(bout.get("kind", "regular"))
	var fmt: String = str(bout.get("format", "duel"))
	var ktxt: String = {"title": "TITLE FIGHT", "championship": "GRAND CHAMPIONSHIP", "grudge": "GRUDGE MATCH — TO THE DEATH", "open": "OPEN CLASS"}.get(kind, str(bout.get("class", "")).to_upper() + " DUEL")
	if fmt != "duel":
		ktxt = {"tag": "TAG TEAM", "lance": "LANCE BATTLE", "melee": "FREE-FOR-ALL"}.get(fmt, fmt.to_upper())
	th.add_child(UI.label(ktxt, 18, UI.ACCENT, true))
	var theme_label: String = GameData.db().arenas["themes"].get(sim.arena.theme, {}).get("label", "")
	th.add_child(UI.label("%s  ·  %s arena  ·  %s  ·  purse %s" % [bout.get("arena_name", "Arena"), theme_label, Campaign.conditions_label(sim.conditions), UI.short_money(int(bout.get("purse", 0)))], 15, UI.DIM))
	th.add_child(UI.spacer())
	live_lbl = UI.label("● LIVE", 15, UI.BAD, true)
	th.add_child(live_lbl)
	time_lbl = UI.label("0:00", 18, UI.TEXT, true)
	th.add_child(time_lbl)
	var cols := [UI.vbox(6), UI.vbox(6)]
	for k in 2:
		var holder := ScrollContainer.new()
		holder.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		holder.custom_minimum_size = Vector2(250 if compact else 230, 0)
		holder.set_anchors_preset(Control.PRESET_TOP_LEFT if k == 0 else Control.PRESET_TOP_RIGHT)
		holder.position = Vector2(8, 52) if k == 0 else Vector2(-8 - (250 if compact else 230), 52)
		holder.size = Vector2(250 if compact else 230, get_viewport_rect().size.y - 52 - 220)
		if k == 1:
			holder.anchor_left = 1.0
			holder.anchor_right = 1.0
			holder.offset_left = -8 - (250 if compact else 230)
			holder.offset_right = -8
		holder.anchor_bottom = 1.0
		holder.offset_top = 52
		holder.offset_bottom = -220
		holder.mouse_filter = Control.MOUSE_FILTER_PASS
		holder.add_child(cols[k])
		add_child(holder)
	for i in sim.mechs.size():
		var col: VBoxContainer = cols[0] if sim.mechs[i].team == 0 else cols[1]
		col.add_child(_side_panel(i))
	var bot := PanelContainer.new()
	bot.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.035, 0.04, 0.9), 0))
	bot.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bot.offset_top = -214
	add_child(bot)
	var bv := UI.vbox(6)
	bot.add_child(bv)
	var ctrl := UI.hbox(8)
	ctrl.add_child(UI.button("⏯ Pause", func(): playing = not playing))
	for s in [1.0, 2.0, 4.0, 8.0]:
		ctrl.add_child(UI.button("%dx" % int(s), func():
			speed = s
			playing = true))
	slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = maxf(0.1, duration)
	slider.step = 0.1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 24
	slider.value_changed.connect(func(v):
		if _scrubbing:
			_seek(v))
	slider.drag_started.connect(func(): _scrubbing = true)
	slider.drag_ended.connect(func(_c):
		_scrubbing = false
		_seek(slider.value))
	ctrl.add_child(slider)
	var fb := UI.button("Camera: follow", func(): pass)
	fb.pressed.connect(func():
		follow = not follow
		fb.text = "Camera: follow" if follow else "Camera: whole arena"
		if not follow:
			_fit_camera(true))
	ctrl.add_child(fb)
	ctrl.add_child(UI.button("Skip to end", _skip_to_end))
	done_btn = UI.button("Done ▶", _done)
	done_btn.disabled = true
	ctrl.add_child(done_btn)
	bv.add_child(ctrl)
	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.custom_minimum_size.y = 150
	log_box.add_theme_font_size_override("normal_font_size", 13)
	log_box.add_theme_font_size_override("bold_font_size", 13)
	bv.add_child(log_box)


func _side_panel(i: int) -> Control:
	var m: CombatMech = sim.mechs[i]
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.035, 0.04, 0.86), 4, sprites[i].get_meta("color"), 2))
	var v := UI.vbox(3)
	p.add_child(v)
	var h := UI.hbox(8)
	var w := _warrior_of(i)
	if w != null:
		h.add_child(Views.portrait(w, 36 if compact else 52))
	var nv := UI.vbox(0)
	nv.add_child(UI.label(m.name, 14 if compact else 16, UI.TEXT, true))
	nv.add_child(UI.label(m.design.display_name(), 12, UI.DIM))
	if not compact:
		nv.add_child(UI.label("G%d / P%d  %s" % [m.gunnery, m.piloting, ", ".join(m.traits).replace("_", " ")], 12, UI.DIM))
	h.add_child(nv)
	v.add_child(h)
	var pd = PaperDoll.new(0.5 if compact else 0.82)
	pd.set_design(m.design, {})
	pd.show_numbers = not compact
	var dh := UI.hbox(6)
	dh.add_child(pd)
	var side := UI.vbox(2)
	dh.add_child(side)
	v.add_child(dh)
	dolls.append(pd)
	var hh := UI.hbox(6)
	hh.add_child(UI.label("HEAT", 11, UI.DIM))
	var hb := ProgressBar.new()
	hb.min_value = 0
	hb.max_value = 30
	hb.show_percentage = false
	hb.custom_minimum_size = Vector2(90 if compact else 120, 12)
	hh.add_child(hb)
	heat_bars.append(hb)
	var hl := UI.label("0", 13)
	hh.add_child(hl)
	heat_lbls.append(hl)
	(side if compact else v).add_child(hh)
	var pl := UI.label("", 11, UI.DIM)
	(side if compact else v).add_child(pl)
	pilot_lbls.append(pl)
	var sl := UI.label("", 13, UI.WARN, true)
	(side if compact else v).add_child(sl)
	status_lbls.append(sl)
	# corner calls for your own warriors
	if _player_mech(i):
		var cb := UI.vbox(2)
		var cl := UI.label("", 11, UI.ACCENT)
		cb.add_child(cl)
		var g := GridContainer.new()
		g.columns = 3
		for call in ["press", "back_off", "flank", "cool", "yield"]:
			var label: String = {"press": "Press", "back_off": "Back off", "flank": "Flank", "cool": "Cool down", "yield": "Yield"}[call]
			var btn := UI.button(label, _call.bind(i, call, -1), CombatSim.CALLS[call])
			btn.add_theme_font_size_override("font_size", 12)
			g.add_child(btn)
		cb.add_child(g)
		var focus: OptionButton = null
		if sim.enemies(m).size() > 1:
			focus = OptionButton.new()
			focus.add_item("Focus fire on...", -1)
			for o in sim.mechs:
				if o.team != m.team:
					focus.add_item(o.name, o.index)
			focus.item_selected.connect(func(k):
				var ti := focus.get_item_id(k)
				if ti >= 0:
					_call(i, "focus", ti)
				focus.select(0))
			cb.add_child(focus)
		v.add_child(cb)
		call_boxes.append({"box": cb, "label": cl, "focus": focus, "index": i})
	return p


func _call(i: int, call: String, arg: int) -> void:
	if not _at_live_edge() or sim.finished:
		return
	if sim.issue_call(i, call, arg):
		_spawn_events()
		fx.append({"type": "text", "t": sim.t, "pos": sprites[i].position + Vector2(0, -70), "text": "\"%s!\"" % CombatSim.CALLS[call], "col": UI.ACCENT})


func _at_live_edge() -> bool:
	return pt >= sim.t - 0.11


# ------------------------------------------------------------------ playback

func _process(delta: float) -> void:
	if playing:
		var want := pt + delta * speed
		if want > sim.t and not sim.finished:
			var steps := 0
			while sim.t < want and not sim.finished and steps < 600:
				sim.step()
				steps += 1
			_sync_frames()
		pt = minf(want, sim.t)
	slider.max_value = maxf(0.1, sim.t)
	slider.set_value_no_signal(pt)
	_spawn_events()
	_update_scene()
	if sim.finished and pt >= duration - 0.001 and not applied:
		_finish()
	if follow:
		_fit_camera(false, delta)
	under.pt = pt
	over.pt = pt
	arena_view.set_time(pt)
	under.queue_redraw()
	over.queue_redraw()
	fx_node.queue_redraw()
	glow.queue_redraw()
	lights.queue_redraw()
	_apply_shake(delta if playing else 0.0)
	var live := _at_live_edge() and not sim.finished
	live_lbl.text = "● LIVE" if live else ("REPLAY" if not sim.finished else "FINAL")
	live_lbl.add_theme_color_override("font_color", UI.BAD if live else UI.DIM)
	for cbx in call_boxes:
		var m: CombatMech = sim.mechs[cbx["index"]]
		var can := live and not m.out and m.calls_left > 0
		cbx["label"].text = "Corner calls left: %d%s" % [m.calls_left, "" if live or sim.finished else "  (go live to call)"]
		for b in (cbx["box"] as Node).get_child(1).get_children():
			b.disabled = not can
		if cbx["focus"] != null:
			cbx["focus"].disabled = not can


func _skip_to_end() -> void:
	while not sim.finished:
		sim.step()
	_sync_frames()
	_seek(duration)


func _seek(v: float) -> void:
	var back := v < pt
	pt = clampf(v, 0.0, sim.t)
	if back:
		ev_i = 0
		fx.clear()
		log_box.clear()
	# fast-forward the log without spawning old effects
	while ev_i < sim.events.size() and float(sim.events[ev_i]["t"]) < pt - 0.6:
		_log(sim.events[ev_i])
		ev_i += 1
	slider.set_value_no_signal(pt)


func _frame_index(t: float) -> int:
	var i := frame_t.bsearch(t)
	return clampi(i - 1, 0, sim.frames.size() - 1)


func _update_scene() -> void:
	var i := _frame_index(pt)
	var j := mini(i + 1, sim.frames.size() - 1)
	var f0: PackedFloat32Array = sim.frames[i]
	var f1: PackedFloat32Array = sim.frames[j]
	var span := maxf(0.0001, frame_t[j] - frame_t[i])
	var a := clampf((pt - frame_t[i]) / span, 0.0, 1.0)
	time_lbl.text = "%d:%02d / %d:%02d" % [int(pt) / 60, int(pt) % 60, int(sim.time_limit()) / 60, int(sim.time_limit()) % 60]
	_update_sprites(f0, f1, a)
	_update_panels(f0, f1, a)


func _update_sprites(f0: PackedFloat32Array, f1: PackedFloat32Array, a: float) -> void:
	for k in sim.mechs.size():
		var o := k * CombatSim.STRIDE
		var pos := Vector2(lerpf(f0[o], f1[o], a), lerpf(f0[o + 1], f1[o + 1], a)) * PX
		var fac := lerp_angle(f0[o + 2], f1[o + 2], a)
		var jz := lerpf(f0[o + 6], f1[o + 6], a)
		var flags := int(f1[o + 7]) if a > 0.5 else int(f0[o + 7])
		var sp: Sprite2D = sprites[k]
		var sh: Sprite2D = shadows[k]
		sp.position = pos - Vector2(0, jz * 26.0)
		sp.rotation = fac + PI / 2.0
		var sc := 0.62 * (1.0 + jz * 0.35)
		sp.scale = Vector2(sc, sc)
		sh.position = pos + Vector2(6 + jz * 30.0, 8 + jz * 30.0)
		sh.rotation = sp.rotation
		sp.set_meta("flags", flags)
		var m: CombatMech = sim.mechs[k]
		var mat := sp.material as ShaderMaterial
		var arm_now := 0.0
		var arm_max := 0.0
		var in_now := 0.0
		var in_max := 0.0
		if m.is_vehicle:
			for q in m.snap_locs.size():
				var lk: String = m.snap_locs[q]
				arm_now += f0[o + 10 + q]
				arm_max += float(m.max_armor.get(lk, 0))
				in_now += maxf(0.0, f0[o + 21 + q])
				in_max += float(m.max_internal.get(lk, 0))
		else:
			for q in CombatSim.ARMOR_KEYS.size():
				arm_now += f0[o + 10 + q]
				arm_max += float(m.max_armor.get(CombatSim.ARMOR_KEYS[q], 0))
			for q in MechDesign.LOCS.size():
				in_now += maxf(0.0, f0[o + 21 + q])
				in_max += float(m.max_internal.get(MechDesign.LOCS[q], 0))
		sp.set_meta("arm", arm_now / maxf(1.0, arm_max))
		sp.set_meta("str", in_now / maxf(1.0, in_max))
		sp.set_meta("dmg", 1.0 - in_now / maxf(1.0, in_max))
		sp.set_meta("heat", lerpf(f0[o + 5], f1[o + 5], a))
		if flags & 8:
			if sp.get_meta("wreck", false) == false:
				sp.texture = Game.wreck_texture(m.design.wreck)
				sh.texture = sp.texture
				sp.set_meta("wreck", true)
			mat.set_shader_parameter("darken", 0.35)
		else:
			if sp.get_meta("wreck", false):
				sp.texture = Game.mech_texture(m.design.sprite)
				sh.texture = sp.texture
				sp.set_meta("wreck", false)
			var dark := 0.0
			if flags & 1:
				dark = 0.25
				sp.rotation += 0.5
			if flags & 2:
				dark = 0.45
			mat.set_shader_parameter("darken", dark)


func _update_panels(f0: PackedFloat32Array, f1: PackedFloat32Array, a: float) -> void:
	for k in sim.mechs.size():
		var o := k * CombatSim.STRIDE
		var jz := lerpf(f0[o + 6], f1[o + 6], a)
		var flags := int(f1[o + 7]) if a > 0.5 else int(f0[o + 7])
		var m: CombatMech = sim.mechs[k]
		var arm := {}
		for q in CombatSim.ARMOR_KEYS.size():
			arm[CombatSim.ARMOR_KEYS[q]] = int(f0[o + 10 + q])
		var inn := {}
		for q in MechDesign.LOCS.size():
			inn[MechDesign.LOCS[q]] = int(f0[o + 21 + q])
		dolls[k].set_live(arm, inn)
		var heat := lerpf(f0[o + 5], f1[o + 5], a)
		heat_bars[k].value = heat
		var hcol := UI.GOOD
		if heat >= 14:
			hcol = UI.BAD
		elif heat >= 8:
			hcol = UI.WARN
		heat_bars[k].add_theme_stylebox_override("fill", UI.box(hcol, 2))
		heat_lbls[k].text = "%d" % int(heat)
		pilot_lbls[k].text = "Pilot: %s" % ("●".repeat(int(f0[o + 8])) + "○".repeat(6 - int(f0[o + 8])))
		var st := ""
		if flags & 8:
			st = "DESTROYED"
		elif flags & 16:
			st = "YIELDED" if not m.ejected else "EJECTED"
		elif flags & 32:
			st = "UNCONSCIOUS"
		elif flags & 4:
			st = "OUT"
		elif flags & 2:
			st = "SHUTDOWN"
		elif flags & 1:
			st = "PRONE"
		elif jz > 0.01:
			st = "JUMPING"
		elif flags & 64:
			st = "MASC SPRINT"
		elif flags & 128:
			st = "HOLDING A CLUB"
		status_lbls[k].text = st


func _pos_at(k: int, t: float) -> Vector2:
	var i := _frame_index(t)
	var f: PackedFloat32Array = sim.frames[i]
	var o := k * CombatSim.STRIDE
	return Vector2(f[o], f[o + 1]) * PX


func _spawn_events() -> void:
	while ev_i < sim.events.size() and float(sim.events[ev_i]["t"]) <= pt:
		var e: Dictionary = sim.events[ev_i]
		_log(e)
		if float(e["t"]) > pt - 1.0:
			_fx_for(e)
		ev_i += 1


func _log(e: Dictionary) -> void:
	var line := sim.describe(e)
	if line == "":
		return
	var col := "#c8ccd2"
	match e.get("k", ""):
		"shot":
			col = "#e6e6e6" if e["hit"] else "#8a8f98"
		"dmg":
			col = "#d8b45a"
		"crit", "tac", "blown_off", "loc_destroyed", "ap":
			col = "#f09a3e"
		"ammo_explosion", "explode", "destroyed", "unconscious", "masc_fail":
			col = "#ff5a4a"
		"fall", "shutdown", "psr", "stand_fail":
			col = "#9fc0ff"
		"charge", "dfa", "push", "club_pickup", "collapse":
			col = "#ffb347"
		"fire", "hazard", "inferno", "shell", "strafe":
			col = "#ff8040"
		"support_call":
			col = "#7fd0ff" if int(e["team"]) == 0 else "#ff5a4a"
		"call":
			col = "#f2a33a"
		"end", "yield", "eject":
			col = "#ffd75a"
	log_box.append_text("[color=#6c727c]%5.1f[/color]  [color=%s]%s[/color]\n" % [float(e["t"]), col, line])


func _text(t: float, pos: Vector2, txt: String, col: Color) -> void:
	fx.append({"type": "text", "t": t, "pos": pos, "text": txt, "col": col})


func _fx_for(e: Dictionary) -> void:
	var k: String = e.get("k", "")
	var t := float(e["t"])
	match k:
		"shot":
			var src := _pos_at(int(e["m"]), t)
			var dst := _pos_at(int(e["tg"]), t)
			if not e["hit"]:
				var perp := (dst - src).orthogonal().normalized()
				var jitter := (float(hash(str(t) + str(e["w"])) % 100) / 100.0 - 0.5) * 2.0
				dst += perp * (40.0 + 30.0 * absf(jitter)) * signf(jitter if jitter != 0 else 1.0) + (dst - src).normalized() * 30.0
			fx.append({"type": "shot", "wt": e.get("wt", ""), "w": e.get("w", ""), "t": t, "src": src, "dst": dst, "hit": e["hit"]})
			var wt0 := str(e.get("wt", ""))
			var dir0 := (dst - src).normalized()
			Vfx.muzzle(fx, t, src, dir0, wt0)
			if e["hit"]:
				var travel := 0.05 if wt0 in ["laser", "pulse", "ppc", "flamer"] else (0.9 if wt0 in ["lrm", "elrm", "xlrm", "streak_lrm", "mml", "atm"] else (0.55 if wt0 in CombatSim.MISSILE_TYPES else 0.3))
				Vfx.impact(fx, t + travel, dst, dir0, int(e["tg"]) * 13 + ev_i, wt0 in ["laser", "pulse", "ppc"])
		"dmg":
			if int(e["tg"]) >= 0:
				var p := _pos_at(int(e["tg"]), t)
				_text(t + 0.25, p + Vector2(randf_range(-20, 20), -30), "-%d %s" % [int(e["dmg"]), e["loc"]], Color(1.0, 0.85, 0.35))
				fx.append({"type": "spark", "t": t + 0.2, "pos": p + Vector2(randf_range(-12, 12), randf_range(-12, 12))})
		"crit":
			_text(t + 0.3, _pos_at(int(e["tg"]), t) + Vector2(0, -55), "CRIT: %s" % e["what"], Color(1.0, 0.55, 0.2))
		"ammo_explosion", "explode":
			Vfx.explosion(fx, t + 0.25, _pos_at(int(e["tg"]), t), 70.0, int(e["tg"]) + 101)
			_shake(0.6, _pos_at(int(e["tg"]), t))
		"destroyed":
			var wp := _pos_at(int(e["tg"]), t)
			Vfx.explosion(fx, t + 0.2, wp, 110.0, int(e["tg"]) + 7)
			Vfx.wreck_fire(fx, t + 0.4, wp)
			arena_view.add_scorch(t + 0.2, wp / PX)
			_shake(1.0, wp)
		"fall":
			Vfx.dust(fx, t, _pos_at(int(e["tg"]), t), 46.0, int(e["tg"]))
			_text(t, _pos_at(int(e["tg"]), t) + Vector2(0, -45), "FALLS", Color(0.6, 0.75, 1.0))
		"physical":
			if e["hit"]:
				var lbl := "CLUB!" if str(e["w"]) == "club" else str(e["w"]).to_upper() + "!"
				_text(t, _pos_at(int(e["tg"]), t) + Vector2(0, -60), lbl, Color(1, 1, 1))
				Vfx.dust(fx, t, _pos_at(int(e["tg"]), t), 34.0, int(e["tg"]) + 3)
				Vfx.impact(fx, t, _pos_at(int(e["tg"]), t), Vector2.UP, int(e["m"]))
		"charge":
			_text(t, _pos_at(int(e["m"]), t) + Vector2(0, -64), "CHARGE!", Color(1.0, 0.7, 0.3))
			if e["hit"]:
				Vfx.dust(fx, t, _pos_at(int(e["tg"]), t), 60.0, int(e["tg"]) + 11)
				_shake(0.45, _pos_at(int(e["tg"]), t))
		"dfa":
			_text(t, _pos_at(int(e["tg"]), t) + Vector2(0, -70), "DEATH FROM ABOVE!" if e["hit"] else "MISSED!", Color(1.0, 0.45, 0.25))
			Vfx.dust(fx, t, _pos_at(int(e["tg"]), t), 80.0, int(e["tg"]) + 17)
			_shake(0.7, _pos_at(int(e["tg"]), t))
		"push":
			if e["hit"]:
				_text(t, _pos_at(int(e["tg"]), t) + Vector2(0, -60), "SHOVED!", Color(1, 1, 1))
		"club_pickup":
			_text(t, _pos_at(int(e["m"]), t) + Vector2(0, -64), "rips up a %s!" % e["club"], Color(0.85, 0.9, 0.6))
		"narc":
			_text(t, _pos_at(int(e["tg"]), t) + Vector2(0, -54), "NARC'D", Color(1.0, 0.35, 0.35))
		"inferno":
			fx.append({"type": "boom", "t": t + 0.5, "pos": _pos_at(int(e["tg"]), t), "r": 38.0, "col": Color(1.0, 0.45, 0.1)})
			_text(t + 0.5, _pos_at(int(e["tg"]), t) + Vector2(0, -50), "+%d HEAT" % int(e["heat"]), Color(1.0, 0.5, 0.2))
		"masc_fail":
			_text(t, _pos_at(int(e["tg"]), t) + Vector2(0, -60), "MASC FAILURE", Color(1.0, 0.35, 0.3))
		"collapse":
			var cp := sim.arena.center_of_index(int(e["cell"])) * PX
			Vfx.collapse(fx, t, cp, int(e["cell"]))
			_shake(0.5, cp)
		"hazard":
			if str(e["type"]) == "shock_pylons" and e.has("tg"):
				var hz: Dictionary = sim.arena.hazards[int(e["h"])]
				fx.append({"type": "arc", "t": t, "src": (hz["pos"] as Vector2) * PX, "dst": _pos_at(int(e["tg"]), t)})
		"jump":
			fx.append({"type": "jet", "t": t, "m": int(e["m"])})
		"shell":
			var sp := Vector2(float(e["pos"][0]), float(e["pos"][1]))
			Vfx.explosion(fx, t, sp * PX, 150.0, int(sp.x * 7.0 + sp.y))
			Vfx.dust(fx, t + 0.1, sp * PX, 90.0, int(sp.x + sp.y * 3.0))
			arena_view.add_scorch(t, sp)
			_shake(0.9, sp * PX)
		"strafe":
			var a := Vector2(float(e["from"][0]), float(e["from"][1])) * PX
			var b := Vector2(float(e["to"][0]), float(e["to"][1])) * PX
			var sdir := (b - a).normalized()
			# the fighter crosses the strip in about a second and a half, its fire walking ahead of it
			fx.append({"type": "plane", "t": t - 0.6, "from": a - sdir * 900.0, "to": b + sdir * 900.0, "dur": 2.6})
			var sn := int(a.distance_to(b) / 26.0)
			for si in sn:
				var q := a.lerp(b, si / float(maxi(1, sn - 1))) + sdir.orthogonal() * (float((si * 37) % 21) - 10.0)
				var tt := t + 0.75 * si / float(maxi(1, sn))
				Vfx.impact(fx, tt, q, sdir, si * 5 + 3, si % 2 == 0)
				if si % 3 == 1:
					fx.append({"type": "boom", "t": tt, "pos": q, "r": 20.0})
			_shake(0.5, (a + b) / 2.0)
		"shutdown":
			_text(t, _pos_at(int(e["tg"]), t) + Vector2(0, -45), "SHUTDOWN", Color(1.0, 0.4, 0.3))


func _draw_fx() -> void:
	var keep: Array = []
	var font := get_theme_default_font()
	for f in fx:
		var age := pt - float(f["t"])
		if age < 0.0:
			keep.append(f)
			continue
		var alive := true
		match f["type"]:
			"pfx":
				alive = Vfx.draw_normal(fx_node, f, age)
			"shot":
				alive = _draw_shot(f, age)
			"text":
				alive = age < 1.6
				if alive:
					var a := clampf(1.6 - age, 0.0, 1.0)
					var col: Color = f["col"]
					col.a = a
					var p: Vector2 = f["pos"] + Vector2(0, -age * 22.0)
					fx_node.draw_string(font, p + Vector2(1, 1), f["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 15, Color(0, 0, 0, a))
					fx_node.draw_string(font, p, f["text"], HORIZONTAL_ALIGNMENT_CENTER, -1, 15, col)
			"spark":
				alive = age < 0.35
				if alive:
					fx_node.draw_circle(f["pos"], 6.0 + age * 40.0, Color(1.0, 0.9, 0.5, 0.9 - age * 2.5))
			"boom":
				alive = age < 1.4
				if alive:
					var rr: float = float(f["r"]) * clampf(age * 2.5, 0.2, 1.0)
					var bc: Color = f.get("col", Color(1.0, 0.55, 0.15))
					fx_node.draw_circle(f["pos"], rr, Color(bc.r, bc.g, bc.b, clampf(1.0 - age, 0.0, 1.0)))
					fx_node.draw_circle(f["pos"], rr * 0.55, Color(1.0, 0.95, 0.6, clampf(1.0 - age * 1.4, 0.0, 1.0)))
			"smoke":
				alive = not f.has("until") or pt < float(f["until"])
				for s in 5:
					var off := Vector2(sin(age * 0.7 + s * 1.3) * 12.0 + s * 6.0, -fmod(age * 18.0 + s * 20.0, 100.0))
					fx_node.draw_circle(f["pos"] + off, 14.0 + s * 2.0, Color(0.15, 0.15, 0.15, 0.35))
			"dust":
				alive = age < 1.0
				if alive:
					var big := 2.0 if f.get("big", false) else 1.0
					fx_node.draw_arc(f["pos"], (20.0 + age * 60.0) * big, 0, TAU, 32, Color(0.75, 0.68, 0.5, 0.7 - age * 0.7), 6.0 * big)
			"plane":
				alive = age < float(f["dur"])
				if alive:
					var ptex: Texture2D = Game.mech_texture("defaults/asf.png")
					var pa: Vector2 = f["from"]
					var pb: Vector2 = f["to"]
					var pp := pa.lerp(pb, age / float(f["dur"]))
					var prot := (pb - pa).angle() + PI / 2.0
					var psz := ptex.get_size() * 1.9
					fx_node.draw_set_transform(pp + Vector2(46, 60), prot, Vector2.ONE)
					fx_node.draw_texture_rect(ptex, Rect2(-psz * 0.4, psz * 0.8), false, Color(0, 0, 0, 0.3))
					fx_node.draw_set_transform(pp, prot, Vector2.ONE)
					fx_node.draw_texture_rect(ptex, Rect2(-psz / 2.0, psz), false, Color(0.82, 0.85, 0.9))
					fx_node.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			"jet":
				alive = age < 1.8
				if alive:
					var mp: Vector2 = sprites[int(f["m"])].position
					for s in 4:
						fx_node.draw_circle(mp + Vector2(randf_range(-10, 10), randf_range(10, 30)), randf_range(3, 7), Color(1.0, 0.7, 0.3, 0.7))
			"arc":
				alive = age < 0.5
				if alive:
					var pts := PackedVector2Array()
					var src: Vector2 = f["src"]
					var dst: Vector2 = f["dst"]
					var perp := (dst - src).orthogonal().normalized()
					for s in 9:
						var q := src.lerp(dst, s / 8.0)
						if s > 0 and s < 8:
							q += perp * randf_range(-12, 12)
						pts.append(q)
					fx_node.draw_polyline(pts, Color(0.6, 0.85, 1.0, 0.4), 9.0)
					fx_node.draw_polyline(pts, Color(0.95, 0.98, 1.0, 1.0 - age * 2.0), 2.5)
		if alive:
			keep.append(f)
	fx = keep
	for k in sprites.size():
		var sp: Sprite2D = sprites[k]
		if sp.visible and not (int(sp.get_meta("flags", 0)) & 4):
			Vfx.unit_effects(fx_node, null, sp.position, float(sp.get_meta("dmg", 0.0)), 0.0, pt, k)
	_draw_unit_marks(font)


## The additive pass: fireballs, flashes, sparks, muzzle flashes, beam glow, jets, heat shimmer.
func _draw_glow() -> void:
	for f in fx:
		var age := pt - float(f["t"])
		if age < 0.0:
			continue
		match f["type"]:
			"pfx":
				Vfx.draw_glow(glow, f, age)
			"shot":
				var wt: String = f["wt"]
				if wt in ["laser", "pulse", "ppc"] and age < 0.35:
					var a := 1.0 - age / 0.35
					var col := Color(1.0, 0.3, 0.25) if wt == "laser" else (Color(1.0, 0.8, 0.3) if wt == "pulse" else Color(0.5, 0.75, 1.0))
					glow.draw_line(f["src"], f["dst"], Color(col.r, col.g, col.b, 0.18 * a), 16.0)
					glow.draw_line(f["src"], f["dst"], Color(col.r, col.g, col.b, 0.35 * a), 6.0)
					if f["hit"]:
						glow.draw_circle(f["dst"], 22.0 * a, Color(col.r, col.g, col.b, 0.4 * a))
			"jet":
				if age < 1.8 and int(f["m"]) < sprites.size():
					var mp: Vector2 = sprites[int(f["m"])].position
					for s in 3:
						glow.draw_circle(mp + Vector2(-8 + s * 8, 22 + sin(age * 30.0 + s) * 4.0), 7.0, Color(1.0, 0.55, 0.2, 0.45 * (1.0 - age / 1.8)))
	for k in sprites.size():
		var sp: Sprite2D = sprites[k]
		if sp.visible and not (int(sp.get_meta("flags", 0)) & 4):
			var hv := float(sp.get_meta("heat", 0.0))
			if hv >= 11.0:
				Vfx.unit_effects(fx_node, glow, sp.position, 0.0, hv, pt, k)


func _shake(amount: float, at: Vector2) -> void:
	if cam == null:
		return
	var d := cam.position.distance_to(at) * cam.zoom.x
	var vs := get_viewport_rect().size
	if d > vs.length() * 0.7:
		return
	shake = maxf(shake, amount * clampf(1.2 - d / vs.length(), 0.3, 1.0))


func _apply_shake(delta: float) -> void:
	if shake <= 0.0:
		cam.offset = Vector2.ZERO
		return
	cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * shake * 10.0 / maxf(0.2, cam.zoom.x)
	shake = move_toward(shake, 0.0, delta * 2.4)


## Rings, names, ECM bubbles, MASC trails, Narc pods (the command view draws its own).
func _draw_unit_marks(font: Font) -> void:
	for k in sim.mechs.size():
		var sp: Sprite2D = sprites[k]
		var col: Color = sp.get_meta("color")
		var flags: int = sp.get_meta("flags", 0)
		if not (flags & 4):
			fx_node.draw_circle(sp.position, 27.0, Color(col.r, col.g, col.b, 0.1))
		fx_node.draw_arc(sp.position, 27.0, 0, TAU, 40, Color(col.r, col.g, col.b, 0.8 if not (flags & 4) else 0.3), 2.0, true)
		if flags & 512 and not (flags & 4):
			fx_node.draw_arc(sp.position, 180.0 * PX, 0, TAU, 64, Color(0.4, 0.7, 1.0, 0.18), 2.0)
		if flags & 64:
			var back := Vector2.from_angle(sp.rotation + PI / 2.0) * 30.0
			for s in 3:
				fx_node.draw_line(sp.position + back + Vector2(-8 + s * 8, 0), sp.position + back * 2.2 + Vector2(-8 + s * 8, 0), Color(0.5, 0.75, 1.0, 0.6), 2.0)
		if flags & 256 and int(pt * 3.0) % 2 == 0:
			fx_node.draw_circle(sp.position + Vector2(14, -14), 4.0, Color(1.0, 0.2, 0.2))
		if flags & 128:
			fx_node.draw_line(sp.position + Vector2(18, 0), sp.position + Vector2(30, -22), Color(0.55, 0.42, 0.25), 5.0)
		var m: CombatMech = sim.mechs[k]
		if not (flags & 4):
			Vfx.health_bar(fx_node, sp.position + Vector2(0, 38), float(sp.get_meta("arm", 1.0)), float(sp.get_meta("str", 1.0)), col)
		fx_node.draw_string(font, sp.position + Vector2(-59, 61), m.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(0, 0, 0, 0.7))
		fx_node.draw_string(font, sp.position + Vector2(-60, 60), m.name, HORIZONTAL_ALIGNMENT_CENTER, 120, 14, Color(1, 1, 1, 0.92))


## Additive glow: fires, flame jets, searchlights at night.
func _draw_lights() -> void:
	for i in sim.arena.fire_start:
		if sim.arena.burning(i, pt):
			var c2 := sim.arena.center_of_index(i) * PX
			lights.draw_circle(c2, 34.0, Color(0.55, 0.22, 0.03, 0.35 * (0.5 + night)))
	for hz in sim.arena.hazards:
		if hz["type"] == "flame_jets" and sim.arena.hazard_active(hz, pt):
			lights.draw_circle((hz["pos"] as Vector2) * PX, 60.0, Color(0.6, 0.25, 0.04, 0.4))
	if night <= 0.0:
		return
	for k in sim.mechs.size():
		var m: CombatMech = sim.mechs[k]
		var sp: Sprite2D = sprites[k]
		var flags: int = sp.get_meta("flags", 0)
		if flags & 4:
			continue
		if m.searchlight or sim.conditions.get("floodlights", false):
			var dir := Vector2.from_angle(sp.rotation - PI / 2.0)
			var poly := PackedVector2Array([sp.position, sp.position + dir.rotated(0.32) * 300.0 * (0.5 if not m.searchlight else 1.0), sp.position + dir.rotated(-0.32) * 300.0 * (0.5 if not m.searchlight else 1.0)])
			lights.draw_colored_polygon(poly, Color(0.25, 0.25, 0.18, 0.25 * night))
		lights.draw_circle(sp.position, 40.0, Color(0.12, 0.1, 0.08, 0.3 * night))


func _draw_shot(f: Dictionary, age: float) -> bool:
	var wt: String = f["wt"]
	var src: Vector2 = f["src"]
	var dst: Vector2 = f["dst"]
	var name: String = str(f["w"]).to_lower()
	match wt:
		"laser", "pulse":
			if age > 0.35:
				return false
			var col := PULSE if wt == "pulse" else LASER
			var width := 3.0
			if name.find("large") >= 0:
				width = 5.0
			elif name.find("small") >= 0:
				width = 2.0
			var a := 1.0 - age / 0.35
			fx_node.draw_line(src, dst, Color(col.r, col.g, col.b, 0.25 * a), width * 3.0)
			if wt == "pulse":
				var n := 7
				for s in n:
					var p0 := src.lerp(dst, float(s) / n)
					var p1 := src.lerp(dst, (s + 0.55) / n)
					fx_node.draw_line(p0, p1, Color(col.r, col.g, col.b, a), width)
			else:
				fx_node.draw_line(src, dst, Color(1, 1, 1, a), width * 0.45)
				fx_node.draw_line(src, dst, Color(col.r, col.g, col.b, a), width)
			return true
		"ppc":
			if age > 0.45:
				return false
			var a2 := 1.0 - age / 0.45
			var pts := PackedVector2Array()
			var n2 := 12
			var perp := (dst - src).orthogonal().normalized()
			for s in n2 + 1:
				var p := src.lerp(dst, float(s) / n2)
				if s > 0 and s < n2:
					p += perp * sin(s * 2.7 + f["t"] * 13.0) * 9.0
				pts.append(p)
			fx_node.draw_polyline(pts, Color(PPC.r, PPC.g, PPC.b, 0.3 * a2), 14.0)
			fx_node.draw_polyline(pts, Color(0.9, 0.95, 1.0, a2), 4.0)
			return true
		"flamer":
			if age > 0.6:
				return false
			for s in 8:
				var p2 := src.lerp(dst, clampf(age / 0.4 + s * 0.06, 0.0, 1.0))
				fx_node.draw_circle(p2, 6.0 + s, Color(1.0, 0.5 + s * 0.04, 0.1, 0.6 * (1.0 - age / 0.6)))
			return true
		"narc", "inarc":
			if age > 0.5:
				return false
			fx_node.draw_circle(src.lerp(dst, age / 0.5), 4.0, Color(1.0, 0.3, 0.3))
			return true
		"lrm", "srm", "mrm", "atm", "mml", "streak_srm", "streak_lrm", "elrm", "xlrm", "rl", "tbolt":
			var dur := 0.9 if wt in ["lrm", "elrm", "xlrm", "streak_lrm", "mml", "atm"] else 0.55
			if age > dur + 0.3:
				return false
			var n3 := 6
			var arc := (dst - src).orthogonal().normalized() * minf(80.0, src.distance_to(dst) * 0.12)
			var inferno := name.find("inferno") >= 0
			for s in n3:
				var tt := clampf((age - s * 0.04) / dur, 0.0, 1.0)
				if tt <= 0.0 or tt >= 1.0:
					continue
				var off := (s - n3 / 2.0) * 4.0
				var p3 := src.lerp(dst, tt) + arc * sin(tt * PI) * (0.6 + s * 0.08) + (dst - src).orthogonal().normalized() * off
				var trail := src.lerp(dst, maxf(0.0, tt - 0.08)) + arc * sin(maxf(0.0, tt - 0.08) * PI) * (0.6 + s * 0.08)
				fx_node.draw_line(trail, p3, Color(0.85, 0.85, 0.85, 0.45), 3.0)
				fx_node.draw_circle(p3, 3.0, Color(1.0, 0.5, 0.15) if inferno else Color(1.0, 0.85, 0.5))
			if age > dur and f["hit"]:
				fx_node.draw_circle(dst, 18.0 * (1.0 - (age - dur) / 0.3), Color(1.0, 0.6, 0.2, 0.8))
			return true
		_:
			# ballistic: autocannon, gauss, machine guns, LB-X
			var dur2 := 0.22 if wt in ["gauss", "lgauss", "hgauss"] else 0.35
			if age > dur2 + 0.15:
				return false
			var shots := 5 if wt in ["mg", "lmg", "hmg", "rac"] else (2 if wt == "uac" else 1)
			if wt == "lbx" and name.find("cluster") >= 0:
				shots = 6
			for s in shots:
				var tt2 := clampf((age - s * 0.05) / dur2, 0.0, 1.0)
				if tt2 <= 0.0 or tt2 >= 1.0:
					continue
				var spread := Vector2.ZERO
				if wt == "lbx" and shots > 1:
					spread = (dst - src).orthogonal().normalized() * (s - shots / 2.0) * 5.0 * tt2
				var p4 := src.lerp(dst, tt2) + spread
				var dir := (dst - src).normalized()
				var col2 := Color(0.85, 0.9, 1.0) if wt.find("gauss") >= 0 else Color(1.0, 0.8, 0.35)
				var big := 1.0
				if name.find("20") >= 0:
					big = 2.0
				elif name.find("10") >= 0:
					big = 1.5
				fx_node.draw_line(p4 - dir * 18.0 * big, p4, col2, 3.0 * big)
			if age > dur2 and f["hit"]:
				fx_node.draw_circle(dst, 12.0, Color(1.0, 0.7, 0.3, 0.7))
			return true


func _fit_camera(instant: bool, delta := 0.0) -> void:
	var vs := get_viewport_rect().size
	var avail := vs - Vector2(560, 300)
	var target_pos: Vector2
	var target_zoom: float
	if follow and not sprites.is_empty():
		var r := Rect2()
		var first := true
		for k in sprites.size():
			var flags: int = sprites[k].get_meta("flags", 0)
			if flags & 4 and sprites.size() > 2:
				continue
			if first:
				r = Rect2(sprites[k].position, Vector2.ZERO)
				first = false
			else:
				r = r.expand(sprites[k].position)
		if first:
			r = Rect2(sprites[0].position, Vector2.ZERO)
		r = r.grow(260.0)
		target_pos = r.get_center() + Vector2(0, 60)
		target_zoom = clampf(minf(avail.x / r.size.x, avail.y / r.size.y), 0.3, 1.6)
	else:
		var size := sim.arena.size_m() * PX
		target_pos = size / 2.0 + Vector2(0, 80)
		target_zoom = clampf(minf(avail.x / size.x, avail.y / size.y), 0.2, 2.0)
	if instant:
		cam.position = target_pos
		cam.zoom = Vector2(target_zoom, target_zoom)
	else:
		var k2 := clampf(delta * 2.0, 0.0, 1.0)
		cam.position = cam.position.lerp(target_pos, k2)
		var z := lerpf(cam.zoom.x, target_zoom, k2)
		cam.zoom = Vector2(z, z)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			follow = false
			cam.zoom *= 1.1
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			follow = false
			cam.zoom /= 1.1
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT or event.button_mask & MOUSE_BUTTON_MASK_MIDDLE):
		follow = false
		cam.position -= event.relative / cam.zoom.x
	elif event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		playing = not playing


# ------------------------------------------------------------------ end

func _finish() -> void:
	applied = true
	done_btn.disabled = false
	if c != null and bout.has("warrior_id"):
		summary = Game.finish_watched(bout, sim)
	var merc_sum := {}
	if arena_mc != null:
		merc_sum = arena_mc.resolve_arena(bout, sim.result)
		load("res://ui/merc/arena_tab.gd").last_summary = merc_sum
	var win: int = sim.result["winner"]
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.035, 0.04, 0.94), 6, UI.ACCENT, 2))
	banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	banner.position.y = 70
	add_child(banner)
	var v := UI.vbox(4)
	banner.add_child(v)
	var mine := win == 0
	var head := "DRAW" if win < 0 else ("VICTORY" if mine else "DEFEAT")
	if str(bout.get("format", "")) == "melee" and win != 0:
		var placement: Array = sim.result["placement"]
		for pi in placement.size():
			if sim.mechs[placement[pi]].team == 0:
				head = "FINISHED %s OF %d" % [["1ST", "2ND", "3RD", "4TH", "5TH", "6TH", "7TH", "8TH"][mini(pi, 7)], placement.size()]
	var t := UI.label(head, 32, UI.GOOD if mine else (UI.DIM if win < 0 else UI.BAD), true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(UI.label("%s after %d:%02d" % [str(sim.result["how"]).capitalize(), int(duration) / 60, int(duration) % 60], 15))
	for m in sim.result["mechs"]:
		v.add_child(UI.label("%s: dealt %d, took %d, %d/%d shots hit%s" % [m["name"], int(m["dmg_dealt"]), int(m["dmg_taken"]), int(m["hits"]), int(m["shots"]),
			(", " + str(m["reason"])) if str(m["reason"]) != "" else ""], 13, UI.DIM))
	if not summary.is_empty():
		v.add_child(UI.label("Purse to your stable: %s" % UI.money(int(summary.get("purse_a", 0))), 15, UI.ACCENT))
		if summary.has("wager"):
			v.add_child(UI.label("Wager: %s" % UI.money(int(summary["wager"])), 14, UI.GOOD if int(summary["wager"]) >= 0 else UI.BAD))
	if not merc_sum.is_empty():
		v.add_child(UI.label("Purse to the company: %s" % UI.money(int(merc_sum.get("purse", 0))), 15, UI.ACCENT))
		for line in merc_sum.get("lines", []):
			v.add_child(UI.label(str(line), 13, UI.DIM))
	banner.position.x = (get_viewport_rect().size.x - 520) / 2.0
	banner.custom_minimum_size.x = 520


func _done() -> void:
	if not sim.finished:
		_skip_to_end()
	if not applied:
		_finish()
	if arena_mc != null:
		Game.save_game("merc_autosave")
		Game.show_merc_hub("arena")
		return
	Game.save_game("autosave")
	Game.show_hub("card")
