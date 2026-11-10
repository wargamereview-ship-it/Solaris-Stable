class_name Views
extends RefCounted
## Builders for recurring panels: 'Mech record sheet, sprites, warrior cards.

const PaperDoll := preload("res://ui/widgets/paper_doll.gd")


static func sprite(d_sprite: String, mat: Material, size := 84) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = Game.mech_texture(d_sprite)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(size, size * 72.0 / 84.0)
	tr.material = mat
	return tr


static func portrait(w: Warrior, size := 96) -> Control:
	var tex := Game.portrait(w.portrait)
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.custom_minimum_size = Vector2(size, size * 1.25)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.03, 0.03, 0.035), 3, UI.LINE, 1))
	p.add_child(tr)
	return p


static func doll(d: MechDesign, condition := {}, s := 1.0) -> Control:
	var pd = PaperDoll.new(s)
	pd.set_design(d, condition)
	return pd


## A compact record sheet: sprite, armor diagram, movement, heat, weapons.
static func sheet(d: MechDesign, condition := {}, mat: Material = null, year := -1) -> Control:
	var db := GameData.db()
	var rep := Construction.analyze(d, year)
	var root := UI.vbox(6)
	var head := UI.hbox(10)
	head.add_child(sprite(d.sprite, mat if mat else Game.tint_material(Color(0.62, 0.62, 0.6)), 96))
	var hv := UI.vbox(2)
	hv.add_child(UI.label(d.display_name(), 19, UI.TEXT, true))
	var sub := "%d tons %s  ·  %s  ·  intro %d" % [d.tons, d.weight_class(), d.tech, d.year]
	if d.role != "":
		sub += "  ·  " + d.role
	hv.add_child(UI.label(sub, 13, UI.DIM))
	hv.add_child(UI.label("Walk %d  Run %d  Jump %d   ·   %d %s engine   ·   %d %s heat sinks" % [d.walk, d.run_mp(), d.jump, d.engine_rating,
		d.engine_type.replace("_", " "), d.hs_count, d.hs_type.replace("_", " ")], 13))
	var heat: Dictionary = rep.get("heat", {})
	hv.add_child(UI.label("Armor %d / %d (%s)   ·   Heat %d / %d   ·   BV %d   ·   %s" % [rep.get("armor_points", 0), rep.get("armor_max", 0),
		d.armor_type.replace("_", " "), heat.get("alpha", 0), heat.get("dissipation", 0), rep.get("bv", 0), UI.money(int(rep.get("cost", 0)))], 13))
	head.add_child(hv)
	root.add_child(head)
	var body := UI.hbox(12)
	body.add_child(doll(d, condition, 0.9))
	var wt := UI.vbox(1)
	var hdr := UI.label("WEAPONS & EQUIPMENT", 12, UI.ACCENT, true)
	wt.add_child(hdr)
	var hit := {}
	for hs in condition.get("hit_slots", []):
		hit["%s:%d" % [hs[0], int(hs[1])]] = true
	var lines := {}
	for mt in rep.get("mounts", []):
		var it := db.item(mt["id"])
		var kind: String = it.get("kind", "")
		var misc: String = it.get("misc", "")
		if misc in ["heat_sink", "double_heat_sink", "jump_jet"]:
			continue
		var broken := false
		for sl in mt["slots"]:
			if hit.has("%s:%d" % [sl[0], int(sl[1])]):
				broken = true
		var txt := ""
		if kind == "weapon":
			var dmg := str(it.get("dmg", 0))
			if int(it.get("rack", 0)) > 0 and it.get("wtype", "") in CombatSim.MISSILE_TYPES:
				dmg = "%d/msl" % int(it.get("dmg", 1))
			txt = "%-18s %-4s H%-2d D%-6s %d/%d/%d" % [it.get("name", "?"), mt["loc"] + ("R" if mt["rear"] else ""), int(it.get("heat", 0)), dmg,
				int(it.get("s", 0)), int(it.get("m", 0)), int(it.get("l", 0))]
			if int(it.get("min", 0)) > 0:
				txt += " min %d" % int(it.get("min", 0))
		elif kind == "ammo":
			txt = "%-18s %-4s %d shots" % [it.get("name", "?").replace(" Ammo", "").left(18), mt["loc"], int(it.get("shots", 0))]
		else:
			txt = "%-18s %-4s" % [str(it.get("name", "?")).left(18), mt["loc"]]
		var key := txt + str(broken)
		lines[key] = {"t": txt, "n": int(lines.get(key, {}).get("n", 0)) + 1, "broken": broken, "kind": kind}
	for k in lines:
		var e: Dictionary = lines[k]
		var t: String = e["t"]
		if int(e["n"]) > 1:
			t = "%dx %s" % [e["n"], t]
		var col := UI.TEXT if e["kind"] == "weapon" else UI.DIM
		if e["broken"]:
			col = UI.BAD
			t += "  DESTROYED"
		var l := UI.label(t, 12, col)
		l.add_theme_font_override("font", _mono())
		wt.add_child(l)
	if not d.quirks.is_empty():
		var q: Array = []
		for x in d.quirks:
			if not str(x).begins_with("ubiquitous"):
				q.append(str(x).replace("_", " "))
		if not q.is_empty():
			var ql := UI.label("Quirks: " + ", ".join(q), 12, UI.BLUE)
			ql.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ql.custom_minimum_size.x = 320
			wt.add_child(ql)
	body.add_child(wt)
	root.add_child(body)
	return root


static var _mono_font: Font


static func _mono() -> Font:
	return UI.font("mono")


static func _mono_old() -> Font:
	if _mono_font == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Noto Sans Mono", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		_mono_font = f
	return _mono_font


static func mono_label(text: String, size := 12, color := UI.TEXT) -> Label:
	var l := UI.label(text, size, color)
	l.add_theme_font_override("font", _mono())
	return l


static func bar(frac: float, color: Color, w := 120, h := 10) -> Control:
	var c := ColorRect.new()
	c.color = Color(0.05, 0.05, 0.06)
	c.custom_minimum_size = Vector2(w, h)
	var f := ColorRect.new()
	f.color = color
	f.size = Vector2(w * clampf(frac, 0.0, 1.0), h)
	c.add_child(f)
	return c


static func warrior_line(c: Campaign, w: Warrior) -> String:
	var s := "%s  [%s]  %s" % [w.full_name(), w.skill_str(), w.record_str()]
	if w.stable_id >= 0:
		s += "  ·  " + c.stables[w.stable_id].name
	return s
