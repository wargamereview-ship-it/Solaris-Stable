extends MarginContainer
## The office: what needs attention this week.

var hub
var c: Campaign


func build() -> void:
	add_theme_constant_override("margin_left", 16)
	add_theme_constant_override("margin_right", 16)
	add_theme_constant_override("margin_top", 12)
	add_theme_constant_override("margin_bottom", 12)
	var cols := UI.hbox(16)
	add_child(cols)
	var left := UI.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(left)
	var right := UI.vbox(10)
	right.custom_minimum_size.x = 440
	cols.add_child(right)
	var p := c.player()

	left.add_child(UI.title("%s — this week" % c.date_str()))
	var todo := UI.vbox(4)
	var damaged := 0
	var wrecked := 0
	for uid in p.mechs:
		var om: OwnedMech = c.mechs[uid]
		if om.status == "wrecked":
			wrecked += 1
		elif om.status == "ready" and om.is_damaged():
			damaged += 1
	var idle: Array = []
	for wid in p.warriors:
		var w: Warrior = c.warriors[wid]
		if w.available() and w.mech_uid >= 0 and c.mechs.has(w.mech_uid) and c.mechs[w.mech_uid].ready():
			var booked := false
			for b in c.bookings:
				if wid in Campaign.bout_warriors(b):
					booked = true
			if not booked:
				idle.append(w.short_name())
	if not idle.is_empty():
		todo.add_child(_item("Ready to fight but not booked: %s." % ", ".join(idle), UI.WARN, "card"))
	if damaged > 0:
		todo.add_child(_item("%d damaged 'Mech%s waiting for repairs." % [damaged, "" if damaged == 1 else "s"], UI.WARN, "bay"))
	if wrecked > 0:
		todo.add_child(_item("%d wrecked 'Mech%s in the bay: rebuild or scrap." % [wrecked, "" if wrecked == 1 else "s"], UI.BAD, "bay"))
	for o in c.offers:
		if o["kind"] in ["title", "championship"]:
			todo.add_child(_item("%s bout offered for %s!" % [("Title" if o["kind"] == "title" else "Grand Championship"), c.warriors[int(o["player_wid"])].short_name()], UI.ACCENT, "card"))
	var no_mech: Array = []
	for wid in p.warriors:
		if c.warriors[wid].mech_uid < 0:
			no_mech.append(c.warriors[wid].short_name())
	if not no_mech.is_empty():
		todo.add_child(_item("No 'Mech assigned: %s." % ", ".join(no_mech), UI.WARN, "roster"))
	for wid in p.warriors:
		var w2: Warrior = c.warriors[wid]
		if w2.contract_weeks <= 4:
			todo.add_child(_item("%s's contract ends in %d week%s." % [w2.short_name(), w2.contract_weeks, "" if w2.contract_weeks == 1 else "s"], UI.WARN, "roster"))
	if p.cash < 300000:
		todo.add_child(_item("Cash is low. Bankrupt stables lose everything.", UI.BAD, "finances"))
	if todo.get_child_count() == 0:
		todo.add_child(UI.label("Everything's in order. Book bouts, then advance the week.", 14, UI.DIM))
	left.add_child(UI.panel(todo))

	left.add_child(UI.title("Your bouts", 16))
	var bv := UI.vbox(3)
	if c.bookings.is_empty():
		bv.add_child(UI.label("Nothing booked yet. Open the Fight Card to pick opponents.", 14, UI.DIM))
	for b in c.bookings:
		var txt := "%s: %s at %s, purse %s" % [Campaign.FORMAT_LABEL.get(b.get("format", "duel"), "Duel"), _matchup(b), b["arena_name"], UI.short_money(int(b["purse"]))]
		if b["resolved"]:
			var res: Dictionary = b["result"]
			txt += "  —  " + ("WON" if int(res["winner"]) == 0 else ("DRAW" if int(res["winner"]) < 0 else "LOST"))
		bv.add_child(UI.label(txt, 14))
	left.add_child(UI.panel(bv))

	left.add_child(UI.title("Last results", 16))
	var lr := UI.vbox(2)
	var shown := 0
	for i in range(c.results.size() - 1, -1, -1):
		var r: Dictionary = c.results[i]
		if not r["player"]:
			continue
		var a: Warrior = c.warriors[int(r["a"])]
		var bb: Warrior = c.warriors[int(r["b"])]
		var mine_a := a.stable_id == c.player_id
		var won := (int(r["winner"]) == 0) == mine_a and int(r["winner"]) >= 0
		var col := UI.GOOD if won else (UI.DIM if int(r["winner"]) < 0 else UI.BAD)
		var desc := "%s (%s) vs %s (%s)" % [a.short_name(), r["ma"], bb.short_name(), r["mb"]]
		if r.has("teams"):
			var parts: Array = []
			for team in r["teams"]:
				var names: Array = []
				for wid in team:
					names.append(c.warriors[int(wid)].short_name())
				parts.append(" & ".join(names))
			desc = "%s: %s" % [Campaign.FORMAT_LABEL.get(r.get("format", ""), ""), " vs ".join(parts)]
		lr.add_child(UI.label("Wk %d  %s  %s, %s" % [int(r["w"]), "W" if won else ("D" if int(r["winner"]) < 0 else "L"), desc, r["how"]], 13, col))
		shown += 1
		if shown >= 8:
			break
	if shown == 0:
		lr.add_child(UI.label("No fights yet.", 13, UI.DIM))
	left.add_child(UI.panel(lr))

	right.add_child(UI.title("Champions", 16))
	var ch := UI.vbox(2)
	for cls in ["light", "medium", "heavy", "assault", "grand"]:
		var wid2: int = c.champions.get(cls, -1)
		var nm := "vacant"
		if wid2 >= 0 and c.warriors.has(wid2):
			var w3: Warrior = c.warriors[wid2]
			nm = "%s (%s)" % [w3.full_name(), c.stables[w3.stable_id].name if w3.stable_id >= 0 else "free agent"]
		ch.add_child(UI.label("%-8s %s" % [("Grand" if cls == "grand" else cls.capitalize()), nm], 13, UI.ACCENT if wid2 >= 0 and c.warriors.has(wid2) and c.warriors[wid2].stable_id == c.player_id else UI.TEXT))
	if c.championship.get("active", false):
		ch.add_child(UI.label("Grand Championship round %d of 3 is on." % (int(c.championship["round"]) + 1), 13, UI.WARN))
	elif c.week < int(c.rules["championship_weeks"][0]):
		ch.add_child(UI.label("Grand Championship: top 8 by rating in week %d." % int(c.rules["championship_weeks"][0]), 12, UI.DIM))
	right.add_child(UI.panel(ch))
	right.add_child(UI.title("Headlines", 16))
	var nv := UI.vbox(4)
	var k := 0
	for i in range(c.news.size() - 1, -1, -1):
		var n: Dictionary = c.news[i]
		var l := UI.rich("[color=#%s][b]%s[/b][/color]  [color=#8a8f98]wk %d %d[/color]\n%s" % [(UI.ACCENT if n["mine"] else UI.BLUE).to_html(false), n["title"], int(n["w"]), int(n["y"]), n["text"]])
		nv.add_child(l)
		k += 1
		if k >= 7:
			break
	right.add_child(UI.panel(nv))
	for e in c.effects_in_force():
		var how_long := "%d more weeks" % int(e["weeks"]) if int(e["weeks"]) < 520 else "for good"
		var fl := UI.label("%s%s  (%s)" % [str(e["src"]) + ": " if str(e["src"]) != "" else "", e["text"], how_long], 12, UI.WARN)
		fl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		right.add_child(fl)


func _matchup(b: Dictionary) -> String:
	if not b.has("sides"):
		return "%s (%s) vs %s (%s)" % [c.warriors[int(b["a"]["warrior"])].short_name(), c.mechs[int(b["a"]["mech"])].design.display_name(),
			c.warriors[int(b["b"]["warrior"])].short_name(), c.mechs[int(b["b"]["mech"])].design.display_name()]
	var parts: Array = []
	for side in b["sides"]:
		var names: Array = []
		for e in side:
			names.append(c.warriors[int(e["warrior"])].short_name() if int(e["warrior"]) >= 0 else "?")
		parts.append(" & ".join(names))
	return " vs ".join(parts)


func _item(text: String, col: Color, tab: String) -> Control:
	var h := UI.hbox(8)
	var dot := ColorRect.new()
	dot.color = col
	dot.custom_minimum_size = Vector2(8, 8)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(dot)
	var l := UI.label(text, 14)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	h.add_child(UI.button("Go", func(): hub.show_tab(tab)))
	return h
