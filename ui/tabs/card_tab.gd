extends MarginContainer
## Fight card: bout offers (duels, tag teams, lance battles, free-for-alls), booking with orders, ammo and
## wagers, and fight night (watch live with corner calls, or simulate).

var hub
var c: Campaign
var offers_tree: Tree
var detail: VBoxContainer
var sel_offer := -1
var orders := {"range": 1, "heat": 1, "position": 0, "retreat": 2, "focus": 0}
var wager_spin: SpinBox
var msg: Label
var rows: Array = []   # per entry slot: {"w": OptionButton, "m": OptionButton, "ammo": {family: OptionButton}, "box": Container}
var tons_label: Label

const RANGE := ["close", "optimal", "long"]
const HEAT := ["cool", "balanced", "hot"]
const POS := ["cover", "flank", "brawl"]
const FOCUS := ["focus", "spread", "protect"]
const RETREAT := [0.35, 0.45, 0.55, 0.7, 0.9]
const RETREAT_L := ["Early (35%)", "Cautious (45%)", "Normal (55%)", "Stubborn (70%)", "Never (90%)"]
const HAZARD_L := {"flame_jets": "flame jets", "steam_vents": "steam vents", "shock_pylons": "shock pylons"}


func build() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	var root := UI.vbox(8)
	add_child(root)
	root.add_child(UI.title("Fight card — %s" % c.date_str()))
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := UI.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	left.add_child(UI.label("OFFERS", 12, UI.DIM, true))
	offers_tree = UI.tree([["Bout", -130], ["Opponent", 3], ["Their 'Mechs", 2], ["Rating", -62], ["Arena", 2], ["Purse", -90]])
	offers_tree.custom_minimum_size.y = 260
	offers_tree.item_selected.connect(func():
		sel_offer = int(offers_tree.get_selected().get_metadata(0))
		_show_offer())
	left.add_child(offers_tree)
	for o in c.offers:
		var it := offers_tree.create_item()
		var opp: Warrior = c.warriors[int(o["b"]["warrior"])]
		it.set_text(0, _bout_label(o))
		if o.has("sides"):
			var names: Array = []
			var mech_names: Array = []
			var elo := 0.0
			var n := 0
			for side in o["sides"].slice(1):
				for e in side:
					var w: Warrior = c.warriors[int(e["warrior"])]
					names.append(w.short_name())
					mech_names.append(c.mechs[int(e["mech"])].design.chassis)
					elo += w.elo
					n += 1
			it.set_text(1, ", ".join(names) + ("" if o["format"] == "melee" else "  (%s)" % c.stables[opp.stable_id].name))
			it.set_text(2, ", ".join(mech_names))
			it.set_text(3, "%.0f" % (elo / maxf(1.0, n)))
		else:
			it.set_text(1, "%s (%s)" % [opp.full_name(), c.stables[opp.stable_id].name])
			it.set_text(2, c.mechs[int(o["b"]["mech"])].design.display_name())
			it.set_text(3, "%.0f" % opp.elo)
		it.set_text(4, "%s (%s)" % [o["arena_name"], GameData.db().arenas["themes"][o["theme"]]["label"]])
		it.set_text(5, UI.short_money(int(o["purse"])))
		it.set_metadata(0, int(o["id"]))
		if o["kind"] in ["title", "championship"]:
			for col in 6:
				it.set_custom_color(col, UI.ACCENT)
		elif o.has("sides"):
			it.set_custom_color(0, UI.BLUE)
		if o["kind"] == "grudge":
			it.set_custom_color(0, UI.BAD)
	if c.offers.is_empty():
		left.add_child(UI.label("No more offers this week.", 13, UI.DIM))
	left.add_child(UI.label("YOUR BOUTS — FIGHT NIGHT", 12, UI.DIM, true))
	var booked := UI.vbox(4)
	for i in c.bookings.size():
		booked.add_child(_booking_row(i))
	if c.bookings.is_empty():
		booked.add_child(UI.label("Nothing booked.", 13, UI.DIM))
	left.add_child(UI.panel(booked))
	left.add_child(UI.label("ELSEWHERE ON THE CARD", 12, UI.DIM, true))
	var ai := UI.vbox(1)
	for b in c.ai_card:
		ai.add_child(UI.label("%s: %s at %s" % [_bout_label(b), _matchup(b), b["arena_name"]], 12, UI.DIM))
	left.add_child(UI.scroll(ai))
	var right := UI.vbox(8)
	right.custom_minimum_size.x = 580
	split.add_child(UI.scroll(right))
	detail = right
	if not c.offers.is_empty():
		sel_offer = int(c.offers[0]["id"])
		offers_tree.get_root().get_first_child().select(0)
	else:
		detail.add_child(UI.label("Pick an offer to book a bout.", 14, UI.DIM))


func _bout_label(o: Dictionary) -> String:
	var kind: String = o["kind"]
	var cls: String = str(o["class"]).capitalize()
	match o.get("format", "duel"):
		"tag":
			return "Tag team · %s" % cls
		"lance":
			return "Lance · %d t cap" % int(o.get("cap", 0))
		"melee":
			return "Free-for-all (%d)" % (o["sides"] as Array).size()
	if kind == "title":
		return "TITLE " + cls
	if kind == "championship":
		return "GRAND CHAMP."
	if kind == "grudge":
		return "Grudge " + cls
	return cls


func _matchup(b: Dictionary) -> String:
	if not b.has("sides"):
		var a: Warrior = c.warriors[int(b["a"]["warrior"])]
		var bb: Warrior = c.warriors[int(b["b"]["warrior"])]
		return "%s (%s) vs %s (%s)" % [a.short_name(), c.mechs[int(b["a"]["mech"])].design.display_name(), bb.short_name(), c.mechs[int(b["b"]["mech"])].design.display_name()]
	var parts: Array = []
	for side in b["sides"]:
		var names: Array = []
		for e in side:
			if int(e["warrior"]) >= 0:
				names.append(c.warriors[int(e["warrior"])].short_name())
			else:
				names.append("you")
		parts.append(" & ".join(names))
	return " vs ".join(parts)


func _offer() -> Dictionary:
	for o in c.offers:
		if int(o["id"]) == sel_offer:
			return o
	return {}


func _show_offer() -> void:
	UI.clear(detail)
	rows = []
	var o := _offer()
	if o.is_empty():
		return
	var th: Dictionary = GameData.db().arenas["themes"][o["theme"]]
	detail.add_child(UI.title("Scouting report", 17))
	var hz: Array = []
	for h in th.get("hazards", []):
		hz.append(HAZARD_L.get(h["type"], h["type"]))
	var info := "%s, %s arena  ·  %s" % [o["arena_name"], th["label"], Campaign.conditions_label(o.get("conditions", {}))]
	if not hz.is_empty():
		info += "  ·  hazards: " + ", ".join(hz)
	info += "  ·  " + ("TO THE DEATH" if o.get("to_death", false) else "yielding allowed")
	var il := UI.label(info, 13, UI.WARN if o.get("to_death", false) or not hz.is_empty() else UI.TEXT)
	il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(il)
	if o.has("sides"):
		for side in o["sides"].slice(1):
			for e in side:
				detail.add_child(_opponent_card(int(e["warrior"]), int(e["mech"]), false))
		_team_entry(o)
	else:
		detail.add_child(_opponent_card(int(o["b"]["warrior"]), int(o["b"]["mech"]), true))
		_duel_entry(o)


func _opponent_card(wid: int, uid: int, full: bool) -> Control:
	var opp: Warrior = c.warriors[wid]
	var om: OwnedMech = c.mechs[uid]
	var v := UI.vbox(4)
	var h := UI.hbox(10)
	h.add_child(Views.portrait(opp, 80 if full else 44))
	var info := UI.vbox(1)
	info.add_child(UI.label(opp.full_name(), 16 if full else 14, UI.TEXT, true))
	info.add_child(UI.label("%s  ·  Gunnery %d  Piloting %d  ·  %s  ·  rating %.0f" % [c.stables[opp.stable_id].name, opp.gunnery, opp.piloting, opp.record_str(), opp.elo], 12, UI.DIM))
	var tr: Array = []
	for t in opp.traits:
		tr.append(str(t).replace("_", " "))
	info.add_child(UI.label("Traits: " + (", ".join(tr) if not tr.is_empty() else "none known"), 12))
	if not full:
		var r := Construction.analyze(om.design)
		var wl: Array = []
		for mt in r.get("weapons", []):
			wl.append(GameData.db().item(mt["id"]).get("name", ""))
		var ml := UI.label("%s (%d t, BV %d): %s" % [om.design.display_name(), om.design.tons, int(r.get("bv", 0)), ", ".join(wl).left(90)], 12, UI.BLUE)
		ml.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ml.custom_minimum_size.x = 440
		info.add_child(ml)
	h.add_child(info)
	v.add_child(h)
	if full:
		v.add_child(UI.panel(Views.sheet(om.design, om.condition, Game.stable_material(opp.stable_id), c.year)))
	return v if full else UI.panel(v)


func _order_grid(team: bool) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	g.add_child(UI.label("Range"))
	g.add_child(_order_opt("range", ["Close in", "Best for loadout", "Long range"]))
	g.add_child(UI.label("Heat"))
	g.add_child(_order_opt("heat", ["Run cool", "Balanced", "Run hot"]))
	g.add_child(UI.label("Positioning"))
	g.add_child(_order_opt("position", ["Use cover", "Flank for rear shots", "Stand and brawl"]))
	if team:
		g.add_child(UI.label("Targeting"))
		g.add_child(_order_opt("focus", ["Focus fire", "Spread out", "Protect teammates"]))
	g.add_child(UI.label("Yield when"))
	g.add_child(_order_opt("retreat", RETREAT_L))
	return g


func _orders_dict() -> Dictionary:
	return {"range": RANGE[orders["range"]], "heat": HEAT[orders["heat"]], "position": POS[orders["position"]],
		"retreat": RETREAT[orders["retreat"]], "focus": FOCUS[orders["focus"]]}


func _entry_row(o: Dictionary, slot: int, default_wid: int) -> void:
	var box := UI.vbox(3)
	var h := UI.hbox(6)
	var wopt := OptionButton.new()
	wopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var p := c.player()
	var sel := 0
	var n := 0
	for wid in p.warriors:
		var w: Warrior = c.warriors[wid]
		if o.has("player_wid") and int(o["player_wid"]) != wid:
			continue
		wopt.add_item("%s [%s] — %s" % [w.short_name(), w.skill_str(), w.status_str()], wid)
		if wid == default_wid:
			sel = n
		n += 1
	if n > 0:
		wopt.select(sel)
	var mopt := OptionButton.new()
	mopt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(wopt)
	h.add_child(mopt)
	box.add_child(h)
	var ammo_box := UI.hbox(6)
	box.add_child(ammo_box)
	var row := {"w": wopt, "m": mopt, "ammo": {}, "ammo_box": ammo_box}
	rows.append(row)
	wopt.item_selected.connect(func(_i):
		_fill_mechs(o, row)
		_update_tons(o))
	mopt.item_selected.connect(func(_i):
		_fill_ammo(row)
		_update_tons(o))
	_fill_mechs(o, row)
	detail.add_child(box)


func _duel_entry(o: Dictionary) -> void:
	detail.add_child(UI.title("Your entry", 17))
	var first := -1
	for wid in c.player().warriors:
		var w: Warrior = c.warriors[wid]
		if w.available() and w.mech_uid >= 0 and (o["class"] == "open" or c.mech_class(w.mech_uid) == o["class"]) and not c._booked(wid):
			first = wid
			break
	_entry_row(o, 0, first)
	detail.add_child(_order_grid(false))
	_wager_and_book(o)


func _team_entry(o: Dictionary) -> void:
	var need: int = (o["sides"][0] as Array).size()
	var rule := ""
	match o["format"]:
		"tag":
			rule = "Two %s 'Mechs fight side by side." % o["class"]
		"lance":
			rule = "Four 'Mechs, at most %d tons together." % int(o.get("cap", 0))
		"melee":
			rule = "Every 'Mech for itself. Last one standing takes half the purse; the rest is split by how long you last."
	detail.add_child(UI.title("Your %s" % ("entry" if need == 1 else "team"), 17))
	detail.add_child(UI.label(rule, 13, UI.DIM))
	var cands: Array = []
	for wid in c.player().warriors:
		var w: Warrior = c.warriors[wid]
		if w.available() and w.mech_uid >= 0 and not c._booked(wid) and (not (o["class"] in Campaign.CLASSES) or c.mech_class(w.mech_uid) == o["class"]):
			cands.append(wid)
	for k in need:
		_entry_row(o, k, cands[k] if k < cands.size() else -1)
	tons_label = UI.label("", 13, UI.WARN)
	detail.add_child(tons_label)
	_update_tons(o)
	detail.add_child(_order_grid(need > 1))
	_wager_and_book(o)


func _wager_and_book(o: Dictionary) -> void:
	var p := c.player()
	var wh := UI.hbox(6)
	wh.add_child(UI.label("Wager"))
	wager_spin = SpinBox.new()
	wager_spin.min_value = 0
	wager_spin.max_value = maxi(0, int(p.cash * float(c.rules["max_wager_fraction"])))
	wager_spin.step = 10000
	wager_spin.custom_minimum_size.x = 160
	wh.add_child(wager_spin)
	if not o.has("sides") and not rows.is_empty():
		var wo: OptionButton = rows[0]["w"]
		if wo.selected >= 0:
			var wid := wo.get_item_id(wo.selected)
			wh.add_child(UI.label("odds %.2f (win chance %.0f%%)" % [c.odds_for(wid, int(o["b"]["warrior"])), c.win_prob(wid, int(o["b"]["warrior"])) * 100.0], 13, UI.DIM))
	detail.add_child(wh)
	detail.add_child(UI.button("Book this bout", _book))
	# fresh every time: clearing the detail panel frees whatever label was here before
	msg = UI.label("", 14, UI.BAD)
	detail.add_child(msg)
	var pur := UI.label("Purse %s. The winning side's stable takes %d%%, minus warrior shares and the arena fee. You get %d corner calls per warrior when you watch." % [UI.money(int(o["purse"])), int(float(c.rules["purse_winner_share"]) * 100), int(GameData.db().tables.get("corner_calls_per_fight", 3))], 12, UI.DIM)
	pur.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_child(pur)


func _order_opt(key: String, labels: Array) -> OptionButton:
	var ob := UI.option(labels, orders[key])
	ob.item_selected.connect(func(i): orders[key] = i)
	return ob


func _fill_mechs(o: Dictionary, row: Dictionary) -> void:
	var m_opt: OptionButton = row["m"]
	var w_opt: OptionButton = row["w"]
	m_opt.clear()
	if w_opt.selected < 0:
		return
	var wid := w_opt.get_item_id(w_opt.selected)
	var w: Warrior = c.warriors[wid]
	var p := c.player()
	var sel := 0
	var n := 0
	for uid in p.mechs:
		var om: OwnedMech = c.mechs[uid]
		var ok: bool = not (o["class"] in Campaign.CLASSES) or c.mech_class(uid) == o["class"]
		var tag := "" if om.ready() else " [%s]" % om.status
		if not ok:
			tag += " [wrong class]"
		elif om.is_damaged():
			tag += " [damaged %d%%]" % int(om.damage_fraction() * 100)
		m_opt.add_item("%s, %dt%s" % [om.label(), om.design.tons, tag], uid)
		if uid == w.mech_uid and ok:
			sel = n
		n += 1
	if n > 0:
		m_opt.select(sel)
	_fill_ammo(row)


func _fill_ammo(row: Dictionary) -> void:
	var box: Container = row["ammo_box"]
	UI.clear(box)
	row["ammo"] = {}
	var m_opt: OptionButton = row["m"]
	if m_opt.selected < 0:
		return
	var om: OwnedMech = c.mechs.get(m_opt.get_item_id(m_opt.selected))
	if om == null:
		return
	var opts := c.munition_options(om)
	if opts.is_empty():
		return
	box.add_child(UI.label("Ammo:", 12, UI.DIM))
	var mun: Dictionary = GameData.db().tables["munitions"]
	for fam in opts:
		var keys: Array = opts[fam]
		var labels: Array = []
		for k in keys:
			labels.append("%s %s" % [str(fam).to_upper(), mun[k]["label"]])
		var ob := UI.option(labels, 0)
		box.add_child(ob)
		row["ammo"][fam] = [ob, keys]


func _row_ammo(row: Dictionary) -> Dictionary:
	var out := {}
	for fam in row["ammo"]:
		var pair: Array = row["ammo"][fam]
		var ob: OptionButton = pair[0]
		var key: String = pair[1][maxi(0, ob.selected)]
		if key != "standard":
			out[fam] = key
	return out


func _update_tons(o: Dictionary) -> void:
	if tons_label == null or not is_instance_valid(tons_label):
		return
	var tons := 0
	for row in rows:
		var mo: OptionButton = row["m"]
		if mo.selected >= 0:
			var om: OwnedMech = c.mechs.get(mo.get_item_id(mo.selected))
			if om:
				tons += om.design.tons
	var cap := int(o.get("cap", 0))
	tons_label.text = ("Team weight: %d t of %d t" % [tons, cap]) if cap > 0 else ("Team weight: %d t" % tons)
	tons_label.add_theme_color_override("font_color", UI.BAD if cap > 0 and tons > cap else UI.DIM)


func _book() -> void:
	var o := _offer()
	if o.is_empty():
		return
	var ord := _orders_dict()
	var entries: Array = []
	var ammo := {}
	for row in rows:
		var wo: OptionButton = row["w"]
		var mo: OptionButton = row["m"]
		if wo.selected < 0 or mo.selected < 0:
			msg.text = "Pick a MechWarrior and a 'Mech for every slot."
			return
		var wid := wo.get_item_id(wo.selected)
		entries.append([wid, mo.get_item_id(mo.selected)])
		ammo[str(wid)] = _row_ammo(row)
	var err := ""
	if o.has("sides"):
		err = c.book_team(sel_offer, entries, ord, ammo, int(wager_spin.value))
	else:
		ord["ammo"] = ammo.get(str(entries[0][0]), {})
		err = c.book(sel_offer, entries[0][0], entries[0][1], ord, int(wager_spin.value))
	if err != "":
		msg.text = err
		return
	hub.refresh()


func _booking_row(i: int) -> Control:
	var b: Dictionary = c.bookings[i]
	var h := UI.hbox(8)
	var txt := "%s — %s at %s, purse %s" % [_bout_label(b), _matchup(b), b["arena_name"], UI.short_money(int(b["purse"]))]
	var cond := Campaign.conditions_label(b.get("conditions", {}))
	if cond != "clear day":
		txt += " (%s)" % cond
	if int(b.get("wager", 0)) > 0:
		txt += ", wager %s @ %.2f" % [UI.short_money(int(b["wager"])), float(b["odds"])]
	var l := UI.label(txt, 13)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	h.add_child(l)
	if b["resolved"]:
		var res: Dictionary = b["result"]
		var won := int(res["winner"]) == 0
		h.add_child(UI.label(("WON" if won else ("DRAW" if int(res["winner"]) < 0 else "LOST")) + " (" + str(res["how"]) + ")", 14, UI.GOOD if won else UI.BAD, true))
	else:
		var id := int(b["id"])
		h.add_child(UI.button("Watch live", func(): Game.watch_bout(id), "Watch in real time and make corner calls"))
		h.add_child(UI.button("Simulate", func():
			var s: Dictionary = Game.simulate_bout(id)
			hub.refresh()
			if not s.is_empty():
				var won2 := int(s["winner"]) == 0
				UI.popup(hub, "Result", "%s — %s after %.0f seconds.\nPurse to you: %s" % ["Victory" if won2 else ("Draw" if int(s["winner"]) < 0 else "Defeat"), s["how"], float(s["duration"]), UI.money(int(s.get("purse_a", 0)))])))
		if b["kind"] in ["regular", "open", "grudge"]:
			h.add_child(UI.button("Cancel", func():
				c.cancel_booking(i)
				c.generate_offers()
				hub.refresh()))
	return h
