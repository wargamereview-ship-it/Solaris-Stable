extends MarginContainer
## MechWarriors: roster table and a detail card with assignment, default orders and contract.

var hub
var c: Campaign
var tree: Tree
var detail: VBoxContainer
static var sel := -1


func build() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	var root := UI.vbox(8)
	add_child(root)
	var p := c.player()
	root.add_child(UI.title("MechWarriors (%d)" % p.warriors.size()))
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	tree = UI.tree([["Name", 3], ["G/P", -50], ["Age", -45], ["'Mech", 2], ["Status", 2], ["Fame", -55], ["Record", -70], ["Rating", -65], ["Salary/wk", -90], ["Contract", -75]])
	split.add_child(tree)
	tree.item_selected.connect(func():
		sel = int(tree.get_selected().get_metadata(0))
		_show())
	var first: TreeItem = null
	for wid in p.warriors:
		var w: Warrior = c.warriors[wid]
		var it := tree.create_item()
		it.set_text(0, w.full_name())
		it.set_text(1, w.skill_str())
		it.set_custom_color(1, UI.skill_color(int((w.gunnery + w.piloting) / 2.0)))
		it.set_text(2, str(w.age(c.year)))
		it.set_text(3, c.mechs[w.mech_uid].design.display_name() if w.mech_uid >= 0 and c.mechs.has(w.mech_uid) else "—")
		it.set_text(4, w.status_str())
		it.set_custom_color(4, UI.GOOD if w.available() else UI.WARN)
		it.set_text(5, "%.0f" % w.fame)
		it.set_text(6, w.record_str())
		it.set_text(7, "%.0f" % w.elo)
		it.set_text(8, UI.short_money(w.salary))
		it.set_text(9, "%d wk" % w.contract_weeks)
		it.set_metadata(0, wid)
		if first == null or wid == sel:
			first = it
	detail = UI.vbox(8)
	detail.custom_minimum_size.x = 470
	split.add_child(UI.scroll(detail))
	if first:
		first.select(0)
	else:
		detail.add_child(UI.label("No MechWarriors. Hire some on the Market.", 14, UI.DIM))


func _show() -> void:
	UI.clear(detail)
	var w: Warrior = c.warriors.get(sel)
	if w == null:
		return
	var h := UI.hbox(12)
	h.add_child(Views.portrait(w, 128))
	var v := UI.vbox(3)
	v.add_child(UI.label(w.full_name(), 20, UI.TEXT, true))
	v.add_child(UI.label("%s, age %d  ·  %s" % [w.culture, w.age(c.year), w.status_str()], 13, UI.DIM))
	var sk := UI.hbox(14)
	sk.add_child(_skill("GUNNERY", w.gunnery))
	sk.add_child(_skill("PILOTING", w.piloting))
	v.add_child(sk)
	v.add_child(UI.label("Record %s  ·  %d kills  ·  rating %.0f  ·  fame %.0f" % [w.record_str(), w.kills, w.elo, w.fame], 13))
	v.add_child(UI.label("XP %d / %d to next improvement" % [w.xp, int(c.rules["xp_to_improve"])], 12, UI.DIM))
	for t in w.titles:
		v.add_child(UI.label("★ " + str(t), 13, UI.ACCENT))
	h.add_child(v)
	detail.add_child(h)
	var mh := UI.hbox(10)
	mh.add_child(UI.label("Morale", 13))
	mh.add_child(Views.bar(w.morale / 100.0, UI.GOOD if w.morale > 50 else UI.WARN, 120))
	mh.add_child(UI.label("Fatigue", 13))
	mh.add_child(Views.bar(w.fatigue / 100.0, UI.BAD if w.fatigue > 60 else UI.WARN, 120))
	detail.add_child(mh)
	var tv := UI.vbox(2)
	for t in w.traits:
		tv.add_child(UI.rich("[b]%s[/b] — %s" % [str(t).replace("_", " ").capitalize(), CombatMech.TRAITS.get(t, "")]))
	if w.traits.is_empty():
		tv.add_child(UI.label("No special traits.", 13, UI.DIM))
	detail.add_child(UI.panel(tv))
	# assignment
	detail.add_child(UI.label("ASSIGNED 'MECH", 12, UI.DIM, true))
	var mo := OptionButton.new()
	mo.add_item("— none —", -1)
	var p := c.player()
	var sel_i := 0
	var n := 1
	for uid in p.mechs:
		var om: OwnedMech = c.mechs[uid]
		var pilot := ""
		for wid in p.warriors:
			if c.warriors[wid].mech_uid == uid and wid != w.id:
				pilot = " (%s's)" % c.warriors[wid].short_name()
		mo.add_item("%s — %s%s" % [om.label(), om.status, pilot], uid)
		if uid == w.mech_uid:
			sel_i = n
		n += 1
	mo.select(sel_i)
	mo.item_selected.connect(func(i):
		var uid2 := mo.get_item_id(i)
		if uid2 < 0:
			w.mech_uid = -1
		else:
			c.assign(w.id, uid2)
		hub.refresh())
	detail.add_child(mo)
	# default orders used for title and championship bookings and as the starting point when booking
	detail.add_child(UI.label("CONTRACT", 12, UI.DIM, true))
	detail.add_child(UI.label("%s per week, %d%% of purses, %d weeks left. Fair salary now: %s." % [UI.money(w.salary), int(w.purse_share * 100), w.contract_weeks, UI.money(w.fair_salary(c.rules))], 13))
	var bh := UI.hbox(8)
	bh.add_child(UI.button("Extend 52 weeks", func():
		var e := c.extend_contract(w.id, 52)
		if e != "":
			UI.popup(hub, "Contract", e)
		hub.refresh()))
	bh.add_child(UI.button("Release", func():
		UI.confirm(hub, "Release", "Release %s? Severance is up to 8 weeks' salary." % w.full_name(), func():
			var e2 := c.release(w.id)
			if e2 != "":
				UI.popup(hub, "Release", e2)
			hub.refresh())))
	detail.add_child(bh)
	detail.add_child(UI.label("RECENT FIGHTS", 12, UI.DIM, true))
	var hv := UI.vbox(1)
	for i in range(w.history.size() - 1, maxi(-1, w.history.size() - 11), -1):
		var e3: Dictionary = w.history[i]
		var vs: Warrior = c.warriors.get(int(e3["vs"]))
		var col := UI.GOOD if e3["res"] == "W" else (UI.BAD if e3["res"] == "L" else UI.DIM)
		if str(e3.get("kind", "")) == "contract":
			hv.add_child(UI.label("%d wk %d  %s on contract on %s (%s)" % [int(e3["y"]), int(e3["w"]), e3["res"], e3["arena"], e3["how"]], 12, col))
			continue
		hv.add_child(UI.label("%d wk %d  %s vs %s at %s (%s)" % [int(e3["y"]), int(e3["w"]), e3["res"], vs.short_name() if vs else "?", e3["arena"], e3["how"]], 12, col))
	if w.history.is_empty():
		hv.add_child(UI.label("No fights yet.", 12, UI.DIM))
	detail.add_child(hv)


func _skill(name: String, v: int) -> Control:
	var b := UI.vbox(0)
	b.add_child(UI.label(name, 10, UI.DIM))
	b.add_child(UI.label(str(v), 26, UI.skill_color(v), true))
	return b
