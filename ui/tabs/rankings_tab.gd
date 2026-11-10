extends MarginContainer
## Rankings by weight class, stable standings and the Grand Championship bracket.

var hub
var c: Campaign
static var cls := "open"


func build() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	var root := UI.vbox(8)
	add_child(root)
	var head := UI.hbox(8)
	head.add_child(UI.title("Rankings"))
	head.add_child(UI.spacer())
	for k in ["open", "light", "medium", "heavy", "assault", "stables"]:
		var b := UI.button(k.capitalize(), func():
			cls = k
			hub.refresh())
		if k == cls:
			b.add_theme_color_override("font_color", UI.ACCENT)
		head.add_child(b)
	root.add_child(head)
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	if cls == "stables":
		var t := UI.tree([["#", -40], ["Stable", 3], ["Sector", 2], ["Fame", -60], ["Record", -90], ["Warriors", -70], ["'Mechs", -60]])
		var r := c.stable_rankings()
		for i in r.size():
			var s: Stable = c.stables[r[i]]
			var it := t.create_item()
			it.set_text(0, str(i + 1))
			it.set_text(1, s.name)
			it.set_text(2, s.sector)
			it.set_text(3, "%.0f" % s.fame)
			it.set_text(4, "%d-%d-%d" % [s.wins, s.losses, s.draws])
			it.set_text(5, str(s.warriors.size()))
			it.set_text(6, str(s.mechs.size()))
			if s.is_player:
				for col in 7:
					it.set_custom_color(col, UI.ACCENT)
		split.add_child(t)
	else:
		var t2 := UI.tree([["#", -40], ["MechWarrior", 3], ["Stable", 2], ["'Mech", 2], ["G/P", -50], ["Record", -80], ["Rating", -65], ["Fame", -55]])
		var ids := c.rankings(cls)
		var champ: int = c.champions.get(cls if cls != "open" else "grand", -1)
		for i in mini(ids.size(), 40):
			var w: Warrior = c.warriors[ids[i]]
			var it2 := t2.create_item()
			it2.set_text(0, str(i + 1))
			it2.set_text(1, ("★ " if w.id == champ else "") + w.full_name())
			it2.set_text(2, c.stables[w.stable_id].name)
			it2.set_text(3, c.mechs[w.mech_uid].design.display_name() if c.mechs.has(w.mech_uid) else "—")
			it2.set_text(4, w.skill_str())
			it2.set_text(5, w.record_str())
			it2.set_text(6, "%.0f" % w.elo)
			it2.set_text(7, "%.0f" % w.fame)
			if w.stable_id == c.player_id:
				for col in 8:
					it2.set_custom_color(col, UI.ACCENT)
		split.add_child(t2)
	var side := UI.vbox(6)
	side.custom_minimum_size.x = 380
	side.add_child(UI.title("Grand Championship", 16))
	var ch: Dictionary = c.championship
	if ch.get("active", false):
		var rnd: Array = ["Quarterfinals", "Semifinals", "Final"]
		side.add_child(UI.label("%s (week %d)" % [rnd[mini(int(ch["round"]), 2)], c.week], 14, UI.WARN))
		for m in ch["matches"]:
			var a: Warrior = c.warriors[int(m["a"])]
			var b: Warrior = c.warriors[int(m["b"])]
			var txt := "%s  vs  %s" % [a.short_name(), b.short_name()]
			if m["done"]:
				txt += "   → " + c.warriors[int(m["winner"])].short_name()
			side.add_child(UI.label(txt, 14, UI.ACCENT if a.stable_id == c.player_id or b.stable_id == c.player_id else UI.TEXT))
	else:
		var g: int = c.champions.get("grand", -1)
		if g >= 0 and c.warriors.has(g):
			side.add_child(UI.label("Reigning Grand Champion: %s" % c.warriors[g].full_name(), 14, UI.ACCENT))
		side.add_child(UI.label("In week %d the top eight rated warriors meet in a three-week knockout. Fighting in it is worth huge purses and fame." % int(c.rules["championship_weeks"][0]), 13, UI.DIM))
		side.get_child(side.get_child_count() - 1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(UI.title("Title fights", 16))
	var tf := UI.label("Every %d weeks each weight-class champion defends against the top-rated contender in that class." % int(c.rules["title_fight_every_weeks"]), 13, UI.DIM)
	tf.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(tf)
	split.add_child(side)
