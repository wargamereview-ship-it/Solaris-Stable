extends "res://ui/merc/merc_tab.gd"
## Star map: the Inner Sphere by owner, with a panel for the selected system and travel.

const MapView := preload("res://ui/merc/star_map_view.gd")
static var sel := -1
static var view_center := Vector2.INF
static var view_zoom := 1.25

var view
var info: VBoxContainer


func build() -> void:
	setup_margins()
	var root := UI.hbox(12)
	add_child(root)
	view = MapView.new()
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.setup(c)
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
	root.add_child(frame)
	info = UI.vbox(8)
	var sc := UI.scroll(info)
	sc.size_flags_horizontal = Control.SIZE_FILL
	sc.custom_minimum_size.x = 420
	root.add_child(sc)
	view.system_selected.connect(func(i):
		sel = i
		view_center = view.center
		view_zoom = view.zoom
		_show.call_deferred())
	if sel < 0:
		sel = int(c.contract["system"]) if not c.contract.is_empty() else c.location
	view.select(sel)


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
	var head := UI.hbox(14)
	var planet := TextureRect.new()
	planet.texture = load(sm.planet_image(i))
	planet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	planet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	planet.custom_minimum_size = Vector2(150, 150)
	head.add_child(planet)
	var hv := UI.vbox(4)
	hv.alignment = BoxContainer.ALIGNMENT_CENTER
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(UI.title(sm.name_of(i), 24))
	var fl := UI.label(sm.faction_name(owner), 15, col.lightened(0.25), true)
	fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hv.add_child(fl)
	var chips := HFlowContainer.new()
	chips.add_theme_constant_override("h_separation", 6)
	chips.add_theme_constant_override("v_separation", 6)
	var hall0 := sm.hall(i, yf)
	if hall0 != "":
		chips.add_child(UI.chip(UI.ic("star") + " " + hall0.to_lower().capitalize() + " hall", UI.ACCENT))
	if i == c.location and not c.in_transit():
		chips.add_child(UI.chip(UI.ic("rocket") + " You are here", UI.GOOD))
	if not c.contract.is_empty() and i == int(c.contract["system"]):
		chips.add_child(UI.chip(UI.ic("crosshairs") + " Contract", UI.BAD))
	if chips.get_child_count() > 0:
		hv.add_child(chips)
	head.add_child(hv)
	info.add_child(head)
	var v := section(info, "System")
	var hall := sm.hall(i, yf)
	if hall != "":
		kv(v, "Hiring hall", hall.to_lower().capitalize(), UI.ACCENT)
	kv(v, "Star", str(s.get("star", "?")))
	var pop := sm.population(i, yf)
	kv(v, "Population", ("%.2f billion" % (pop / 1.0e9)) if pop >= 1.0e9 else ("%.1f million" % (pop / 1.0e6)) if pop > 0 else "unknown")
	var so := sm.socio(i, yf)
	kv(v, "Tech / industry", "%s / %s  (%s)" % [so.substr(0, 1), so.substr(2, 1) if so.length() > 2 else "?", so])
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
	if str(pl.get("desc", "")) != "":
		info.add_child(wrap_label(str(pl["desc"]), 13, UI.DIM))
	var t := section(info, "Travel")
	if i == c.location and not c.in_transit():
		t.add_child(UI.label("The company is here.", 14, UI.GOOD))
	else:
		var tr := c.plan_trip(i)
		if not tr["ok"]:
			t.add_child(UI.label(str(tr["why"]), 14, UI.BAD))
		else:
			kv(t, "Route", "%d jumps, about %d days" % [int(tr["jumps"]), int(tr["days"])])
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
