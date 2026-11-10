extends "res://ui/merc/merc_tab.gd"
## Star map: the Inner Sphere by owner, with a floating search/navigation bar and a rich system inspector.

const MapView := preload("res://ui/merc/star_map_view.gd")
static var sel := -1
static var view_center := Vector2.INF
static var view_zoom := 1.25
static var show_lanes := true
static var show_grid := true

var view
var info: VBoxContainer
var search_edit: LineEdit
var search_panel: PanelContainer
var search_box: VBoxContainer
var _matches: Array = []


func build() -> void:
	setup_margins()
	var root := UI.hbox(12)
	add_child(root)

	view = MapView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.setup(c)
	view.show_lanes = show_lanes
	view.show_grid = show_grid

	var frame := PanelContainer.new()
	var fsb := UI.box(Color(0, 0, 0, 0), 5, UI.LINE_HI, 1)
	fsb.content_margin_left = 1
	fsb.content_margin_right = 1
	fsb.content_margin_top = 1
	fsb.content_margin_bottom = 1
	frame.add_theme_stylebox_override("panel", fsb)
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if view_center != Vector2.INF:
		view.center = view_center
		view.zoom = view_zoom
	frame.add_child(view)

	# Floating top map toolbar + live search dropdown
	var overlay := MarginContainer.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_theme_constant_override("margin_left", 10)
	overlay.add_theme_constant_override("margin_right", 10)
	overlay.add_theme_constant_override("margin_top", 10)
	overlay.add_theme_constant_override("margin_bottom", 10)
	frame.add_child(overlay)

	var over_col := UI.vbox(4)
	over_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(over_col)

	var tbar := PanelContainer.new()
	tbar.add_theme_stylebox_override("panel", UI.box(Color(0.04, 0.055, 0.075, 0.92), 4, UI.LINE, 1))
	tbar.size_flags_horizontal = Control.SIZE_FILL
	over_col.add_child(tbar)

	var th := UI.hbox(8)
	tbar.add_child(th)
	th.add_child(UI.label(UI.ic("globe"), 14, UI.ACCENT))

	search_edit = LineEdit.new()
	search_edit.placeholder_text = "Find system (Solaris, Outreach, Tharkad)..."
	search_edit.clear_button_enabled = true
	search_edit.custom_minimum_size = Vector2(250, 28)
	search_edit.add_theme_font_size_override("font_size", 13)
	search_edit.text_changed.connect(_on_search_changed)
	search_edit.text_submitted.connect(_on_search_submitted)
	th.add_child(search_edit)

	var btn_here := _nav_btn(UI.ic("rocket") + " Here", func():
		if c.location >= 0:
			view.focus_system(c.location, 1.8)
			_sync_view())
	th.add_child(btn_here)

	if not c.contract.is_empty():
		var btn_con := _nav_btn(UI.ic("crosshairs") + " Contract", func():
			view.focus_system(int(c.contract["system"]), 1.8)
			_sync_view())
		th.add_child(btn_con)

	var btn_hall := _nav_btn(UI.ic("star") + " Nearest Hall", func():
		var hi := _nearest_hall()
		if hi >= 0:
			view.focus_system(hi, 1.8)
			_sync_view())
	th.add_child(btn_hall)

	var btn_sphere := _nav_btn("Overview", func():
		view.center = Vector2.ZERO
		view.zoom = 0.65
		_sync_view())
	th.add_child(btn_sphere)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	th.add_child(spacer)

	var lanes_btn := Button.new()
	lanes_btn.toggle_mode = true
	lanes_btn.button_pressed = show_lanes
	lanes_btn.text = "Jump Lanes"
	lanes_btn.add_theme_font_size_override("font_size", 12)
	lanes_btn.toggled.connect(func(on: bool):
		show_lanes = on
		view.show_lanes = on)
	th.add_child(lanes_btn)

	var grid_btn := Button.new()
	grid_btn.toggle_mode = true
	grid_btn.button_pressed = show_grid
	grid_btn.text = "Grid"
	grid_btn.add_theme_font_size_override("font_size", 12)
	grid_btn.toggled.connect(func(on: bool):
		show_grid = on
		view.show_grid = on)
	th.add_child(grid_btn)

	search_panel = PanelContainer.new()
	search_panel.add_theme_stylebox_override("panel", UI.box(Color(0.035, 0.05, 0.07, 0.96), 4, UI.ACCENT_DIM, 1))
	search_panel.custom_minimum_size.x = 320
	search_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	search_panel.visible = false
	search_box = UI.vbox(2)
	search_panel.add_child(search_box)
	over_col.add_child(search_panel)

	root.add_child(frame)

	info = UI.vbox(8)
	var sc := UI.scroll(info)
	sc.size_flags_horizontal = Control.SIZE_FILL
	sc.custom_minimum_size.x = 420
	root.add_child(sc)

	view.system_selected.connect(func(i):
		sel = i
		_sync_view()
		_show.call_deferred())
	if sel < 0:
		sel = int(c.contract["system"]) if not c.contract.is_empty() else c.location
	view.select(sel)


func _nav_btn(label: String, fn: Callable) -> Button:
	var b := Button.new()
	b.text = label
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(fn)
	return b


func _sync_view() -> void:
	view_center = view.center
	view_zoom = view.zoom


func _nearest_hall() -> int:
	var sm := c.sm
	var yf := c.year_f()
	var origin := sm.pos(c.location) if c.location >= 0 else Vector2.ZERO
	var best := -1
	var best_d := INF
	for i in sm.systems.size():
		if sm.hall(i, yf) == "":
			continue
		var d := origin.distance_to(sm.pos(i))
		if d < best_d:
			best_d = d
			best = i
	return best


func _on_search_changed(txt: String) -> void:
	UI.clear(search_box)
	_matches.clear()
	var q := txt.strip_edges().to_lower()
	if q.length() == 0:
		search_panel.visible = false
		return
	var sm := c.sm
	var yf := c.year_f()
	var starts: Array = []
	var contains: Array = []
	for i in sm.systems.size():
		var nm := sm.name_of(i).to_lower()
		if nm.begins_with(q):
			starts.append(i)
		elif nm.find(q) >= 0:
			contains.append(i)
		if starts.size() >= 8:
			break
	for idx in starts:
		_matches.append(idx)
	for idx in contains:
		if _matches.size() >= 8:
			break
		_matches.append(idx)
	if _matches.is_empty():
		search_box.add_child(UI.label("No matching star system", 12, UI.DIM))
		search_panel.visible = true
		return
	for idx in _matches:
		var o := sm.owner(idx, yf)
		var hall := sm.hall(idx, yf)
		var tag := ("  ★ " + hall.to_lower().capitalize()) if hall != "" else ""
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s  ·  %s%s" % [sm.name_of(idx), sm.faction_name(o), tag]
		b.add_theme_font_size_override("font_size", 12)
		var target_idx: int = idx
		b.pressed.connect(func():
			search_edit.text = ""
			search_panel.visible = false
			view.focus_system(target_idx, 2.2)
			_sync_view())
		search_box.add_child(b)
	search_panel.visible = true


func _on_search_submitted(_txt: String) -> void:
	if not _matches.is_empty():
		var target_idx: int = _matches[0]
		search_edit.text = ""
		search_panel.visible = false
		view.focus_system(target_idx, 2.2)
		_sync_view()


func _planet_glow_color(img_path: String) -> Color:
	if img_path.find("terran") >= 0 or img_path.find("ocean") >= 0:
		return Color(0.32, 0.68, 1.0)
	if img_path.find("jungle") >= 0:
		return Color(0.28, 0.82, 0.52)
	if img_path.find("desert") >= 0 or img_path.find("arid") >= 0:
		return Color(0.95, 0.66, 0.32)
	if img_path.find("ice") >= 0:
		return Color(0.58, 0.88, 1.0)
	if img_path.find("volcanic") >= 0:
		return Color(1.0, 0.42, 0.24)
	if img_path.find("toxic") >= 0 or img_path.find("tainted") >= 0:
		return Color(0.72, 0.85, 0.28)
	return Color(0.62, 0.68, 0.76)


func _build_planet_card(i: int, star_str: String) -> Control:
	var sm := c.sm
	var img_path := sm.planet_image(i)
	var glow := _planet_glow_color(img_path)

	var frame := PanelContainer.new()
	var sb := UI.box(Color(0.02, 0.028, 0.042), 6, Color(glow.r, glow.g, glow.b, 0.45), 1)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	frame.add_theme_stylebox_override("panel", sb)
	frame.custom_minimum_size = Vector2(154, 154)

	var box := Control.new()
	box.custom_minimum_size = Vector2(146, 146)
	box.clip_contents = true
	box.draw.connect(func():
		var cpos := box.size * 0.5
		for k in 14:
			var ang := float(k) * 2.39996 + float(i % 17)
			var rad := 18.0 + fmod(float(k * 19 + i * 7), 52.0)
			var sp := cpos + Vector2.from_angle(ang) * rad
			box.draw_circle(sp, 1.0, Color(0.85, 0.9, 1.0, 0.35))
		box.draw_circle(cpos, 64.0, Color(glow.r, glow.g, glow.b, 0.08))
		box.draw_circle(cpos, 54.0, Color(glow.r, glow.g, glow.b, 0.14))
		box.draw_arc(cpos, 56.0, 0, TAU, 48, Color(glow.r, glow.g, glow.b, 0.28), 1.2, true))
	frame.add_child(box)

	var planet := TextureRect.new()
	planet.texture = load(img_path)
	planet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	planet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	planet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.add_child(planet)

	var badge := PanelContainer.new()
	var bsb := UI.box(Color(0.03, 0.04, 0.06, 0.85), 3, UI.LINE, 1)
	bsb.content_margin_left = 5
	bsb.content_margin_right = 5
	bsb.content_margin_top = 1
	bsb.content_margin_bottom = 1
	badge.add_theme_stylebox_override("panel", bsb)
	badge.position = Vector2(4, 4)
	badge.add_child(Views.mono_label("★ " + star_str, 10, UI.ACCENT))
	box.add_child(badge)

	return frame


func _socio_color(grade: String) -> Color:
	match grade.to_upper():
		"A":
			return UI.GOOD
		"B":
			return UI.BLUE
		"C":
			return UI.TEXT
		"D":
			return UI.WARN
		"F", "X":
			return UI.BAD
	return UI.DIM


func _show() -> void:
	UI.clear(info)
	var sm := c.sm
	var i := sel
	if i < 0:
		return
	var yf := c.year_f()
	var s: Dictionary = sm.sys(i)
	var owner := sm.owner(i, yf)
	var col := sm.faction_color(owner)
	var star_str := str(s.get("star", "?"))

	# Hero header card
	var hero := UI.vbox(8)
	info.add_child(UI.panel(hero))
	var head := UI.hbox(14)
	head.add_child(_build_planet_card(i, star_str))

	var hv := UI.vbox(5)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UI.title(sm.name_of(i), 24))
	var fl := UI.label(sm.faction_name(owner), 15, col.lightened(0.28), true)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(fl)

	# Check capital and border status
	var cap_name := str(sm.factions.get(owner, {}).get("capital", ""))
	var is_cap := (cap_name != "" and sm.index_of(cap_name) == i)
	var border_factions: Array = []
	for nb in s.get("nb", []):
		var nbi := int(nb[0])
		var nbo := sm.owner(nbi, yf)
		if nbo != owner and sm.is_real_faction(nbo) and nbo != "IND":
			if not (nbo in border_factions):
				border_factions.append(nbo)

	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	if i == c.location and not c.in_transit():
		chips.add_child(UI.chip(UI.ic("rocket") + " You are here", UI.GOOD))
	if not c.contract.is_empty() and i == int(c.contract["system"]):
		chips.add_child(UI.chip(UI.ic("crosshairs") + " Contract", UI.BAD))
	if is_cap:
		chips.add_child(UI.chip("◆ Faction Capital", Color(1.0, 0.86, 0.38)))
	var hall0 := sm.hall(i, yf)
	if hall0 != "":
		chips.add_child(UI.chip(UI.ic("star") + " " + hall0.to_lower().capitalize() + " hall", UI.ACCENT))
	if sm.industrial(i, yf):
		chips.add_child(UI.chip(UI.ic("cog") + " Industrial", UI.BLUE))
	if not border_factions.is_empty():
		chips.add_child(UI.chip(UI.ic("shield") + " Border world", UI.WARN))
	if chips.get_child_count() > 0:
		hv.add_child(chips)
	head.add_child(hv)
	hero.add_child(head)

	if str(s.get("planet", {}).get("desc", "")) != "":
		hero.add_child(HSeparator.new())
		hero.add_child(wrap_label(str(s["planet"]["desc"]), 12, UI.DIM))

	# System & Economy section
	var v := section(info, "System & Economy", "globe")
	var hall := sm.hall(i, yf)
	if hall != "":
		kv(v, "Hiring hall", hall.to_lower().capitalize(), UI.ACCENT)
	kv(v, "Star / transit", "%s  (%d days to jump point)" % [star_str, sm.transit_days(i)])
	var pop := sm.population(i, yf)
	kv(v, "Population", ("%.2f billion" % (pop / 1.0e9)) if pop >= 1.0e9 else ("%.1f million" % (pop / 1.0e6)) if pop > 0 else "unknown")

	var pl: Dictionary = s.get("planet", {})
	var parts: Array = []
	if pl.get("temp") != null:
		parts.append("%d °C" % int(pl["temp"]))
	if pl.get("water") != null:
		parts.append("%d%% water" % int(pl["water"]))
	if pl.get("gravity") != null:
		parts.append("%.2f g" % float(pl["gravity"]))
	if pl.get("atmo") != null:
		parts.append(str(pl["atmo"]).to_lower().replace("_", " "))
	kv(v, "Planet", ", ".join(parts) if not parts.is_empty() else "no survey")

	var bio: Dictionary = s.get("biomes", {})
	var bk: Array = bio.keys()
	bk.sort_custom(func(a, b): return float(bio[a]) > float(bio[b]))
	var names: Array = []
	for b in bk.slice(0, 4):
		names.append(str(c.db.arenas["themes"].get("bf_" + str(b), {}).get("label", b)).to_lower())
	kv(v, "Battlefields", ", ".join(names))

	# Visual USILR socio-industrial rating chips
	var so := sm.socio(i, yf)
	var codes := so.split("-")
	var labels_so := ["Tech", "Industry", "Raw", "Output", "Agri"]
	var so_row := HFlowContainer.new()
	so_row.add_theme_constant_override("h_separation", 6)
	so_row.add_theme_constant_override("v_separation", 4)
	for k in mini(codes.size(), labels_so.size()):
		var g := codes[k]
		so_row.add_child(UI.chip("%s: %s" % [labels_so[k], g], _socio_color(g)))
	v.add_child(so_row)

	# Politics & Frontier section
	if sm.is_real_faction(owner) and owner != "IND":
		var wars: Array = []
		for fk in sm.factions:
			if fk != owner and sm.faction_active(fk, yf) and sm.at_war(owner, fk, yf):
				var f_sys := sm.faction_systems(fk, yf)
				if not f_sys.is_empty():
					wars.append(sm.faction_name(fk))
		if not border_factions.is_empty() or not wars.is_empty():
			var pv := section(info, "Frontier & Conflicts", "flag")
			if not border_factions.is_empty():
				var bnames: Array = []
				for bf in border_factions:
					bnames.append(sm.faction_name(bf))
				kv(pv, "Borders (1 jump)", ", ".join(bnames), UI.WARN)
			if not wars.is_empty():
				kv(pv, "Active wars", ", ".join(wars.slice(0, 6)), UI.BAD)

	# Travel section
	var t := section(info, "Travel & Astrogation", "rocket")
	if i == c.location and not c.in_transit():
		t.add_child(UI.label("The company is currently stationed in this system.", 14, UI.GOOD))
	else:
		var tr := c.plan_trip(i)
		if not tr["ok"]:
			t.add_child(UI.label(str(tr["why"]), 14, UI.BAD))
		else:
			kv(t, "Route", "%d jump%s, about %d days" % [int(tr["jumps"]), "" if int(tr["jumps"]) == 1 else "s", int(tr["days"])])
			kv(t, "Transport", "%s (%s a jump)" % [UI.money(int(tr["cost"])), UI.money(c.transport_cost_per_jump())])
			var r: Array = tr["route"]
			var stops: Array = []
			for k in r:
				stops.append(sm.name_of(int(k)))
			t.add_child(wrap_label(" → ".join(stops), 12, UI.DIM))
			var b := UI.button("Travel here", func(): act(func(): return c.start_travel(i)))
			b.disabled = c.in_transit() or c.contract_active()
			t.add_child(b)
			if c.contract_active():
				t.add_child(UI.label("You can't leave while under contract.", 13, UI.WARN))
