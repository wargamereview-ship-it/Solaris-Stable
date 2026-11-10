extends Control
## The briefing room: every choice for a new game on one screen, for either mode.
##
## Three columns of settings (who you are, when and where; what you start with; what you are up
## against and the rules of the world) over a strip that sums up the game you are about to start.
## The rows of a column are data (MERC and STABLE below): [key, caption, kind, ...]. `v` holds the
## value of every key; a widget writes its key and the summary redraws. Starting hands `v` to
## Game.new_merc_custom or Game.new_game_custom as a setup (what you start with) and the campaign's
## settings (how the game plays), see MercCampaign.start_setup and Campaign.start_setup.

var mode := "merc"
var v: Dictionary = {}
var w: Dictionary = {}          # widgets by key
var cols: HBoxContainer
var summary: HBoxContainer
var note: Label
var probe: MercCampaign          # a blank campaign set to the chosen date, to ask what is going on then
var _halls: Array = []           # system ids behind the hiring hall list
var _syncing := false
var _color_touched := false

const CAP_W := 168
## Row kinds: "text"; "color"; "seed"; "int" lo hi step; "pct" lo hi step (shown as a percentage);
## "money" lo hi step; "check" text; "choice" labels values; "hall"; "sector"; "presets"; "info" (a
## line of text the screen fills in).
const MERC := [
	[["Company", "shield", [
		["name", "Name", "text"], ["color", "Paint", "color"], ["seed", "World seed", "seed"]]],
	["Date and place", "globe", [
		["year", "Year", "int", 3015, 3150, 1], ["month", "Month", "choice", MercCampaign.MONTHS, [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]],
		["hall", "Hiring hall", "hall"], ["i_place", "", "info"], ["i_wars", "", "info"], ["i_force", "", "info"], ["i_next", "", "info"]]]],
	[["Starting force", "crosshairs", [
		["preset", "Start from", "presets"],
		["mechs", "BattleMechs", "int", 0, 12, 1], ["mech_each", "Strength per 'Mech", "int", 500, 1800, 50],
		["mech_tons_max", "Heaviest 'Mech", "choice", ["35 tons (lights)", "55 tons (mediums)", "65 tons", "75 tons (heavies)", "100 tons (any)"], [35, 55, 65, 75, 100]],
		["vehicles", "Combat vehicles", "int", 0, 12, 1], ["vehicle_each", "Strength per vehicle", "int", 250, 1000, 50],
		["infantry", "Infantry units", "int", 0, 6, 1],
		["crew", "Crew experience", "choice", ["Green", "Regular", "Veteran", "Elite"], [-0.25, 0.0, 0.2, 0.35]],
		["worn", "", "check", "Second-hand gear: units start with armor missing"]]],
	["Staff and cash", "users", [
		["techs", "Techs", "int", 0, 12, 1], ["doctors", "Doctors", "int", 0, 4, 1], ["admins", "Admins", "int", 0, 4, 1],
		["cash", "C-bills", "money", 500000, 20000000, 500000], ["i_staff", "", "info"]]]],
	[["Opposition", "bomb", [
		["enemy_strength", "Enemy strength", "pct", 50, 130, 5],
		["enemy_skill", "Enemy skill", "choice", ["Greener than usual", "As the contract says", "Tougher than usual"], [-1, 0, 1]],
		["battle_tempo", "Battles per month", "pct", 50, 150, 10],
		["enemy_support", "", "check", "The enemy may call artillery and air strikes"],
		["enemy_infantry", "", "check", "The enemy fields infantry and battle armour"]]],
	["Economy", "money", [
		["pay", "Contract pay", "pct", 50, 200, 10], ["prices", "Prices", "pct", 50, 200, 10],
		["supply", "Finding parts", "choice", ["Much easier (-2)", "Easier (-1)", "Normal", "Harder (+1)", "Much harder (+2)"], [-2, -1, 0, 1, 2]],
		["repair_speed", "Tech work rate", "pct", 50, 200, 10], ["upkeep", "Upkeep costs", "pct", 50, 200, 10]]],
	["World and rules", "flag", [
		["news", "", "check", "Canon events and wars make the news"],
		["trade_effects", "", "check", "Events and wars change pay, prices and who hires"],
		["industrial", "", "check", "IndustrialMechs turn up on the markets"],
		["auto_withdraw", "", "check", "Crippled units of yours fall back on their own"],
		["lethality", "Deaths and injuries", "pct", 0, 150, 25]]]],
]
const STABLE := [
	[["Stable", "shield", [
		["name", "Name", "text"], ["sector", "Home sector", "sector"], ["color", "Paint", "color"], ["seed", "World seed", "seed"]]],
	["Season", "globe", [
		["year", "First season", "int", 3015, 3150, 1], ["i_place", "", "info"], ["i_next", "", "info"]]]],
	[["Starting stable", "crosshairs", [
		["cash", "C-bills", "money", 1000000, 20000000, 500000], ["warriors", "MechWarriors", "int", 1, 6, 1],
		["m_light", "Light 'Mechs", "int", 0, 4, 1], ["m_medium", "Medium 'Mechs", "int", 0, 4, 1],
		["m_heavy", "Heavy 'Mechs", "int", 0, 4, 1], ["m_assault", "Assault 'Mechs", "int", 0, 4, 1],
		["bays", "'Mech bays", "int", 2, 12, 1], ["techs", "Techs", "int", 1, 10, 1], ["fame", "Starting fame", "int", 0, 40, 5]]]],
	[["The league", "trophy", [
		["rivals", "Rival stables", "int", 6, 30, 1],
		["rival_skill", "Their warriors", "choice", ["Weaker than usual", "As usual", "Stronger than usual"], [-0.25, 0.0, 0.25]]]],
	["Economy", "money", [
		["purses", "Purses", "pct", 50, 200, 10], ["sponsors", "Sponsors and merchandise", "pct", 50, 200, 10],
		["prices", "Prices", "pct", 50, 200, 10], ["upkeep", "Upkeep costs", "pct", 50, 200, 10]]],
	["World and rules", "flag", [
		["timeline", "", "check", "Canon events make the news and move prices and purses"],
		["merc_work", "", "check", "Agents offer mercenary work off-world"],
		["injuries", "Time out injured", "pct", 25, 200, 25]]]],
]
const ERAS := [[3019, "Late Succession Wars"], [3049, "Succession Wars renaissance"], [3061, "Clan Invasion"], [3067, "FedCom Civil War"],
	[3080, "Jihad"], [3100, "Early Republic"], [3130, "Late Republic"], [3150, "Dark Age"], [9999, "ilClan"]]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UI.backdrop())
	probe = MercCampaign.new()
	_defaults()
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		m.add_theme_constant_override("margin_" + side, 22)
	m.add_theme_constant_override("margin_top", 14)
	m.add_theme_constant_override("margin_bottom", 14)
	add_child(m)
	var root := UI.vbox(10)
	m.add_child(root)
	var head := UI.hbox(10)
	head.add_child(UI.title("New mercenary company" if mode == "merc" else "New Solaris stable", 26))
	head.add_child(UI.spacer())
	for pair in [["merc", "Mercenary company", "globe"], ["stable", "Solaris stable", "trophy"]]:
		var b := UI.ibutton(str(pair[2]), str(pair[1]), func(): Game.show_setup(str(pair[0])))
		b.toggle_mode = true
		b.button_pressed = mode == str(pair[0])
		head.add_child(b)
	head.add_child(UI.ibutton("sign_out", "Back to the menu", Game.show_menu))
	root.add_child(head)
	cols = UI.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	for col in (MERC if mode == "merc" else STABLE):
		var box := UI.vbox(10)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var sc := UI.scroll(box)
		sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.size_flags_stretch_ratio = 1.0
		cols.add_child(sc)
		for sect in col:
			var sv := UI.vbox(7)
			sv.add_child(UI.header(str(sect[0]), str(sect[1])))
			for row in sect[2]:
				_add_row(sv, row)
			box.add_child(UI.panel(sv))
	var strip := UI.vbox(4)
	summary = UI.hbox(26)
	strip.add_child(summary)
	note = UI.label("", 13, UI.BAD)
	note.visible = false
	strip.add_child(note)
	var sp := UI.panel(strip)
	var sb := UI.card_box(true)
	sp.add_theme_stylebox_override("panel", sb)
	root.add_child(sp)
	_sync()
	_refresh()
	UI.fade_in(self)


# ------------------------------------------------------------------ values

func _defaults() -> void:
	v = {"seed": randi() % 100000}
	if mode == "merc":
		v["name"] = "Gray Death Irregulars"
		v["color"] = Color(0.55, 0.5, 0.3)
		for k in MercCampaign.SETTING_DEFAULTS:
			v[k] = MercCampaign.SETTING_DEFAULTS[k]
		v["enemy_strength"] = float(GameData.db().merc()["rules"]["difficulty"]["Regular"])
		_preset("combined")
		v["hall"] = "Galatea"
	else:
		v["name"] = "Iron Gauntlet Stables"
		var sec: Dictionary = GameData.db().arenas["sectors"][0]
		v["sector"] = str(sec["id"])
		v["color"] = Color(float(sec["color"][0]), float(sec["color"][1]), float(sec["color"][2]))
		for k in Campaign.SETTING_DEFAULTS:
			v[k] = Campaign.SETTING_DEFAULTS[k]
		var st := Campaign.start_setup()
		for k in ["year", "cash", "fame", "bays", "techs", "warriors", "rivals", "rival_skill"]:
			v[k] = st[k]
		for cls in ["light", "medium", "heavy", "assault"]:
			v["m_" + cls] = (st["mechs"] as Array).count(cls)


## One of the starting packages of data/merc_rules.json, as the values of the force and staff rows.
func _preset(package: String) -> void:
	var st := MercCampaign.start_setup(package)
	for k in ["mechs", "vehicles", "infantry", "mech_tons_max", "crew", "worn", "techs", "doctors", "admins", "cash"]:
		v[k] = st[k]
	if not v.has("year"):
		v["year"] = st["year"]
		v["month"] = 1
	v["mech_each"] = int(round(float(st["mech_bv"]) / maxf(1.0, float(st["mechs"])) / 50.0)) * 50
	v["vehicle_each"] = int(round(float(st["vehicle_bv"]) / maxf(1.0, float(st["vehicles"])) / 50.0)) * 50 if int(st["vehicles"]) > 0 else 550
	v["preset"] = package


func _put(key: String, value: Variant) -> void:
	if _syncing:
		return
	v[key] = value
	if key in ["mechs", "vehicles", "infantry", "mech_each", "vehicle_each", "techs", "doctors", "admins", "cash", "crew", "worn", "mech_tons_max"]:
		v["preset"] = ""
	if key in ["year", "month"] and mode == "merc":
		_fill_halls()
	_refresh()


# ------------------------------------------------------------------ rows

func _add_row(parent: Control, row: Array) -> void:
	var key := str(row[0])
	var kind := str(row[2])
	if kind == "info":
		var il := UI.label("", 13, UI.DIM)
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		il.custom_minimum_size.x = 200
		w[key] = il
		parent.add_child(il)
		return
	if kind == "check":
		var cb := CheckBox.new()
		cb.text = str(row[3])
		cb.toggled.connect(func(on): _put(key, on))
		w[key] = cb
		parent.add_child(cb)
		return
	var h := UI.hbox(8)
	var cap := UI.label(str(row[1]), 14, UI.TEXT)
	cap.custom_minimum_size.x = CAP_W
	h.add_child(cap)
	parent.add_child(h)
	match kind:
		"text":
			var le := LineEdit.new()
			le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			le.text_changed.connect(func(t): _put(key, t))
			w[key] = le
			h.add_child(le)
		"color":
			var cp := ColorPickerButton.new()
			cp.custom_minimum_size = Vector2(120, 30)
			cp.color_changed.connect(func(c):
				_color_touched = true
				_put(key, c))
			w[key] = cp
			h.add_child(cp)
		"seed":
			var se := LineEdit.new()
			se.custom_minimum_size.x = 120
			se.text_changed.connect(func(t): _put(key, int(t) if t.is_valid_int() else 0))
			w[key] = se
			h.add_child(se)
			h.add_child(UI.button("Roll another", func():
				v["seed"] = randi() % 100000
				_sync()))
		"int":
			var sbx := SpinBox.new()
			sbx.min_value = float(row[3])
			sbx.max_value = float(row[4])
			sbx.step = float(row[5])
			sbx.custom_minimum_size.x = 110
			sbx.value_changed.connect(func(nv): _put(key, int(nv)))
			w[key] = sbx
			h.add_child(sbx)
			var hint := UI.label("", 12, UI.DIM)
			w[key + "_hint"] = hint
			h.add_child(hint)
		"pct", "money":
			var sl := HSlider.new()
			sl.min_value = float(row[3])
			sl.max_value = float(row[4])
			sl.step = float(row[5])
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var out := UI.label("", 14, UI.ACCENT)
			out.custom_minimum_size.x = 96
			out.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			sl.value_changed.connect(func(nv):
				out.text = ("%d%%" % int(nv)) if kind == "pct" else UI.short_money(int(nv))
				_put(key, nv / 100.0 if kind == "pct" else int(nv)))
			w[key] = sl
			w[key + "_out"] = out
			h.add_child(sl)
			h.add_child(out)
		"choice":
			var ob := UI.option(row[3], 0)
			ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ob.set_meta("values", row[4])
			ob.item_selected.connect(func(i): _put(key, (row[4] as Array)[i]))
			w[key] = ob
			h.add_child(ob)
		"hall":
			var hb := OptionButton.new()
			hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.item_selected.connect(func(i): _put(key, str(_halls[i])))
			w[key] = hb
			h.add_child(hb)
		"sector":
			var names: Array = []
			for s in GameData.db().arenas["sectors"]:
				names.append("%s%s" % [s["id"], (" (" + str(s["house"]) + ")") if str(s["house"]) != "" else " (neutral)"])
			var so := UI.option(names, 0)
			so.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			so.item_selected.connect(func(i):
				var sec: Dictionary = GameData.db().arenas["sectors"][i]
				if not _color_touched:
					v["color"] = Color(float(sec["color"][0]), float(sec["color"][1]), float(sec["color"][2]))
					(w["color"] as ColorPickerButton).color = v["color"]
				_put(key, str(sec["id"])))
			w[key] = so
			h.add_child(so)
		"presets":
			var packs: Dictionary = GameData.db().merc()["rules"]["start"]["packages"]
			for pk in packs:
				var pb := UI.button(str(packs[pk]["label"]).replace("Mercenary ", "").capitalize(), func():
					_preset(str(pk))
					_sync()
					_refresh())
				pb.toggle_mode = true
				pb.tooltip_text = str(packs[pk]["desc"])
				w["preset_" + str(pk)] = pb
				h.add_child(pb)


## Puts `v` on the widgets (after a preset, a new seed, or at the start).
func _sync() -> void:
	_syncing = true
	if mode == "merc":
		_fill_halls()
	for col in (MERC if mode == "merc" else STABLE):
		for sect in col:
			for row in sect[2]:
				var key := str(row[0])
				if not w.has(key) or not v.has(key):
					continue
				match str(row[2]):
					"text", "seed":
						(w[key] as LineEdit).text = str(v[key])
					"color":
						(w[key] as ColorPickerButton).color = v[key]
					"int":
						(w[key] as SpinBox).value = float(v[key])
					"pct":
						(w[key] as HSlider).value = round(float(v[key]) * 100.0)
						(w[key + "_out"] as Label).text = "%d%%" % int(round(float(v[key]) * 100.0))
					"money":
						(w[key] as HSlider).value = float(v[key])
						(w[key + "_out"] as Label).text = UI.short_money(int(v[key]))
					"check":
						(w[key] as CheckBox).button_pressed = bool(v[key])
					"choice":
						var vals: Array = row[4]
						for i in vals.size():
							if is_equal_approx(float(vals[i]), float(v[key])):
								(w[key] as OptionButton).select(i)
					"sector":
						var secs: Array = GameData.db().arenas["sectors"]
						for i in secs.size():
							if str(secs[i]["id"]) == str(v[key]):
								(w[key] as OptionButton).select(i)
	_syncing = false


## The hiring halls open on the chosen date, best first.
func _fill_halls() -> void:
	if not w.has("hall"):
		return
	var sm := StarMap.get_map()
	var yf := _year_f()
	var rank := {"GREAT": 0, "STANDARD": 1, "MINOR": 2, "QUESTIONABLE": 3}
	var found: Array = []
	for i in sm.systems.size():
		if not (sm.systems[i].get("halls", []) as Array).is_empty() and sm.hall(i, yf) != "":
			found.append([int(rank.get(sm.hall(i, yf), 4)), sm.name_of(i), str(sm.systems[i]["id"]), sm.hall(i, yf)])
	found.sort_custom(func(a, b): return a[0] < b[0] if a[0] != b[0] else str(a[1]) < str(b[1]))
	var ob: OptionButton = w["hall"]
	var was := _syncing
	_syncing = true
	ob.clear()
	_halls = []
	for f in found:
		_halls.append(f[2])
		ob.add_item("%s (%s)" % [f[1], str(f[3]).to_lower()])
	if _halls.is_empty():
		_halls.append("Galatea")
		ob.add_item("Galatea")
	if not (str(v.get("hall", "")) in _halls):
		v["hall"] = _halls[0]
	ob.select(_halls.find(str(v["hall"])))
	_syncing = was


func _year_f() -> float:
	return float(v["year"]) + (float(v.get("month", 1)) - 1.0) / 12.0 + 0.01


# ------------------------------------------------------------------ what the choices add up to

func _era(y: int) -> String:
	for e in ERAS:
		if y <= int(e[0]):
			return str(e[1])
	return ""


## The next big entry of the timeline after the start date, for this mode.
func _next_event() -> String:
	var skip := "merc" if mode == "stable" else "stable"
	var from := "%04d-%02d-01" % [int(v["year"]), int(v.get("month", 1))]
	for e in GameData.db().events:
		if str(e.get("only", "")) != skip and e.get("major", false) and str(e["date"]) > from:
			return "%s, %s %d" % [e["title"], MercCampaign.MONTHS[int(e["month"]) - 1], int(e["year"])]
	return ""


func _refresh() -> void:
	if summary == null:
		return
	if mode == "merc":
		_refresh_merc()
	else:
		_refresh_stable()


func _stat(caption: String, value: String, col := UI.TEXT) -> void:
	summary.add_child(UI.stat(caption, value, col))


func _start_button(text: String) -> void:
	summary.add_child(UI.spacer())
	var go := UI.primary(UI.ibutton("play", text, _start))
	go.custom_minimum_size = Vector2(230, 44)
	w["start"] = go
	summary.add_child(go)


func _refresh_merc() -> void:
	var sm := StarMap.get_map()
	var yf := _year_f()
	probe.day = MercCampaign.jdn(int(v["year"]), int(v["month"]), 1)
	probe.settings = {"trade_effects": v["trade_effects"]}
	probe._tl_day = -1
	sm.year_hint = yf
	var hi := sm.index_of(str(v["hall"]))
	var owner := sm.faction_name(sm.owner(hi, yf), yf) if hi >= 0 else "?"
	(w["i_place"] as Label).text = "%s. %s belongs to %s." % [_era(int(v["year"])), sm.name_of(hi) if hi >= 0 else str(v["hall"]), MercCampaign._the(owner)]
	var wars: Array = []
	for war in sm.wars_at(yf):
		var all_clan := true
		for p in war["pairs"]:
			if str(p[0]) != str(p[1]) or sm.faction_kind(str(p[0])) != "CLAN":
				all_clan = false
		if not all_clan:
			wars.append(str(war["name"]))
	(w["i_wars"] as Label).text = ("Wars under way: %s%s." % [", ".join(wars.slice(0, 3)), " and %d more" % (wars.size() - 3) if wars.size() > 3 else ""]) if not wars.is_empty() else "No declared wars on this date."
	var force: Array = []
	for s in probe.timeline_summary():
		force.append("%s (%s)" % [s["title"], s["text"]] if str(s["text"]) != "" else str(s["title"]))
	(w["i_force"] as Label).text = ("In force: %s." % "; ".join(force.slice(0, 2))) if not force.is_empty() else ("Nothing unusual in force." if v["trade_effects"] else "Events do not touch the trade in this game.")
	var nx := _next_event()
	(w["i_next"] as Label).text = ("Next on the timeline: %s." % nx) if nx != "" and v["news"] else ""
	(w["mech_each_hint"] as Label).text = "BV"
	(w["vehicle_each_hint"] as Label).text = "BV"
	(w["i_staff"] as Label).text = "%d AsTechs and %d medics come with them." % [int(v["techs"]) * 6, int(v["doctors"]) * 4]
	for pk in GameData.db().merc()["rules"]["start"]["packages"]:
		(w["preset_" + str(pk)] as Button).button_pressed = str(v.get("preset", "")) == str(pk)
	UI.clear(summary)
	_stat("Start", "%s %d, %s" % [MercCampaign.MONTHS[int(v["month"]) - 1], int(v["year"]), sm.name_of(hi) if hi >= 0 else "?"])
	var bv := int(v["mechs"]) * int(v["mech_each"]) + int(v["vehicles"]) * int(v["vehicle_each"]) + int(v["infantry"]) * 130
	var parts: Array = []
	for pair in [["mechs", "'Mech"], ["vehicles", "vehicle"], ["infantry", "infantry unit"]]:
		if int(v[pair[0]]) > 0:
			parts.append("%d %s%s" % [int(v[pair[0]]), pair[1], "" if int(v[pair[0]]) == 1 else "s"])
	_stat("Force", (", ".join(parts) if not parts.is_empty() else "nothing") + "  ·  about %d BV" % bv)
	_stat("People", "%d" % (int(v["mechs"]) + int(v["vehicles"]) + int(v["infantry"]) + int(v["techs"]) + int(v["doctors"]) + int(v["admins"])))
	_stat("Cash", UI.short_money(int(v["cash"])))
	_stat("Enemy", "%d%% of your strength" % int(round(float(v["enemy_strength"]) * 100.0)))
	var score := float(v["enemy_strength"]) / 0.8 * pow(float(v["prices"]), 0.5) * pow(float(v["upkeep"]), 0.3) / pow(float(v["pay"]), 0.7) / pow(float(v["repair_speed"]), 0.3)
	score *= 1.0 + 0.06 * float(v["enemy_skill"]) + 0.04 * float(v["supply"]) + 0.1 * (float(v["battle_tempo"]) - 1.0) - 0.25 * float(v["crew"])
	score *= 0.85 + 0.15 * minf(1.5, float(v["lethality"]))
	_challenge(score)
	_start_button("Found the company")


func _refresh_stable() -> void:
	var sm := StarMap.get_map()
	var y := int(v["year"])
	var sol := sm.index_of("Solaris")
	(w["i_place"] as Label).text = "%s. Solaris VII belongs to %s." % [_era(y), MercCampaign._the(sm.faction_name(sm.owner(sol, y + 0.01), y + 0.01)) if sol >= 0 else "?"]
	var nx := _next_event()
	(w["i_next"] as Label).text = ("Next on the timeline: %s." % nx) if nx != "" and v["timeline"] else ""
	var mechs := 0
	var classes: Array = []
	for cls in ["light", "medium", "heavy", "assault"]:
		mechs += int(v["m_" + cls])
		if int(v["m_" + cls]) > 0:
			classes.append("%d %s" % [int(v["m_" + cls]), cls])
	(w["bays_hint"] as Label).text = "needs %d" % mechs if mechs > int(v["bays"]) else ""
	UI.clear(summary)
	_stat("First season", "%d, %s sector" % [y, v["sector"]])
	_stat("'Mechs", ", ".join(classes) if not classes.is_empty() else "none")
	_stat("MechWarriors", "%d" % int(v["warriors"]))
	_stat("Cash", UI.short_money(int(v["cash"])))
	_stat("League", "%d rival stables" % int(v["rivals"]))
	var score := (1.0 + float(v["rival_skill"])) * pow(float(v["prices"]), 0.5) * pow(float(v["upkeep"]), 0.4) / pow(float(v["purses"]), 0.6) / pow(float(v["sponsors"]), 0.3)
	score *= pow(4000000.0 / maxf(500000.0, float(v["cash"])), 0.25) * (0.9 + 0.1 * float(v["injuries"]))
	_challenge(score)
	_start_button("Open the stable")


func _challenge(score: float) -> void:
	var label := "Forgiving"
	var col := UI.GOOD
	if score >= 1.6:
		label = "Brutal"
		col = UI.BAD
	elif score >= 1.2:
		label = "Hard"
		col = UI.WARN
	elif score >= 0.9:
		label = "Standard"
		col = UI.TEXT
	_stat("Challenge", label, col)


# ------------------------------------------------------------------ starting

func _fail(text: String) -> void:
	note.text = text
	note.visible = true


func _start() -> void:
	var nm := str(v["name"]).strip_edges()
	var seed_v := int(v["seed"]) if int(v["seed"]) != 0 else randi()
	if mode == "merc":
		if int(v["mechs"]) + int(v["vehicles"]) + int(v["infantry"]) == 0:
			_fail("A company needs at least one unit to start with.")
			return
		_fail("Raising the company...")
		note.add_theme_color_override("font_color", UI.ACCENT)
		await get_tree().process_frame
		await get_tree().process_frame
		Game.new_merc_custom(nm if nm != "" else "Unnamed Company", v["color"], merc_setup(), seed_v, merc_play())
	else:
		if (stable_setup()["mechs"] as Array).is_empty():
			_fail("A stable needs at least one 'Mech to start with.")
			return
		_fail("Generating the Game World...")
		note.add_theme_color_override("font_color", UI.ACCENT)
		await get_tree().process_frame
		await get_tree().process_frame
		Game.new_game_custom(nm if nm != "" else "Unnamed Stable", str(v["sector"]), v["color"], seed_v, stable_setup(), stable_play())


func merc_setup() -> Dictionary:
	return {"year": int(v["year"]), "month": int(v["month"]), "hall": str(v["hall"]), "mechs": int(v["mechs"]),
		"vehicles": int(v["vehicles"]), "infantry": int(v["infantry"]), "mech_bv": int(v["mechs"]) * int(v["mech_each"]),
		"vehicle_bv": int(v["vehicles"]) * int(v["vehicle_each"]), "infantry_bv": int(v["infantry"]) * 130,
		"mech_tons_max": int(v["mech_tons_max"]), "crew": float(v["crew"]), "worn": bool(v["worn"]),
		"techs": int(v["techs"]), "astechs": int(v["techs"]) * 6, "doctors": int(v["doctors"]),
		"medics": int(v["doctors"]) * 4, "admins": int(v["admins"]), "cash": int(v["cash"])}


func merc_play() -> Dictionary:
	var out := {}
	for k in MercCampaign.SETTING_DEFAULTS:
		if k != "difficulty":
			out[k] = v[k]
	out["enemy_skill"] = int(v["enemy_skill"])
	out["supply"] = int(v["supply"])
	return out


func stable_setup() -> Dictionary:
	var mechs: Array = []
	for cls in ["light", "medium", "heavy", "assault"]:
		for k in int(v["m_" + cls]):
			mechs.append(cls)
	return {"year": int(v["year"]), "cash": int(v["cash"]), "fame": float(v["fame"]), "bays": int(v["bays"]),
		"techs": int(v["techs"]), "warriors": int(v["warriors"]), "mechs": mechs, "rivals": int(v["rivals"]),
		"rival_skill": float(v["rival_skill"])}


func stable_play() -> Dictionary:
	var out := {}
	for k in Campaign.SETTING_DEFAULTS:
		out[k] = v[k]
	return out
