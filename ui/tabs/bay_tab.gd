extends MarginContainer
## 'Mech bay: the stable's 'Mechs, repairs, refits, facilities and spare parts.

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
	var head := UI.hbox(14)
	head.add_child(UI.title("'Mech bay  (%d / %d bays)" % [p.mechs.size(), p.bays]))
	head.add_child(UI.spacer())
	head.add_child(UI.button("Design a new 'Mech", _new_design, "Build a 'Mech from scratch under the construction rules"))
	root.add_child(head)
	var fac := UI.hbox(10)
	fac.add_child(_facility("Bays %d" % p.bays, "+1 bay (%s)" % UI.short_money(int(c.rules["bay_cost"])), "bay"))
	fac.add_child(_facility("Techs %d (%d h/wk)" % [p.techs, p.techs * int(c.rules["tech_hours_week"])], "Hire tech (%s/wk)" % UI.short_money(int(c.rules["tech_salary_week"])), "tech"))
	fac.add_child(_facility("Medical bay %d" % p.medic, "Upgrade", "medic"))
	fac.add_child(_facility("Simulator pods %d" % p.sim_pods, "Add pod (%s)" % UI.short_money(int(c.rules["sim_pod_cost"])), "sim"))
	root.add_child(UI.panel(fac))
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var left := UI.vbox(6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(left)
	tree = UI.tree([["'Mech", 3], ["Class", -80], ["Status", 2], ["Damage", -70], ["Pilot", 2], ["Fights", -60], ["Value", -95]])
	left.add_child(tree)
	tree.item_selected.connect(func():
		sel = int(tree.get_selected().get_metadata(0))
		_show())
	var first: TreeItem = null
	for uid in p.mechs:
		var om: OwnedMech = c.mechs[uid]
		var it := tree.create_item()
		it.set_text(0, om.label())
		it.set_text(1, "%s %dt" % [om.design.weight_class().capitalize(), om.design.tons])
		var st := om.status
		if om.status in ["repair", "refit"]:
			st += " (%.0f h left)" % om.work_hours
		it.set_text(2, st)
		it.set_custom_color(2, UI.GOOD if om.status == "ready" else (UI.BAD if om.status == "wrecked" else UI.WARN))
		it.set_text(3, "%d%%" % int(om.damage_fraction() * 100) if om.is_damaged() else "—")
		var pilot := "—"
		for wid in p.warriors:
			if c.warriors[wid].mech_uid == uid:
				pilot = c.warriors[wid].short_name()
		it.set_text(4, pilot)
		it.set_text(5, "%d (%d k)" % [om.fights, om.kills])
		it.set_text(6, UI.short_money(om.value()))
		it.set_metadata(0, uid)
		if first == null or uid == sel:
			first = it
	# spare parts
	left.add_child(UI.label("SPARE PARTS", 12, UI.DIM, true))
	var inv := UI.vbox(1)
	for id in p.inventory:
		var ih := UI.hbox(6)
		ih.add_child(UI.label("%dx %s" % [int(p.inventory[id]), GameData.db().item(id).get("name", id)], 13))
		ih.add_child(UI.button("Sell one", func():
			c.sell_part(id)
			hub.refresh()))
		inv.add_child(ih)
	if p.inventory.is_empty():
		inv.add_child(UI.label("None. Parts removed in refits end up here and can go back into other 'Mechs.", 12, UI.DIM))
	left.add_child(inv)
	detail = UI.vbox(8)
	detail.custom_minimum_size.x = 600
	split.add_child(UI.scroll(detail))
	if first:
		first.select(0)


func _facility(text: String, btn: String, kind: String) -> Control:
	var h := UI.hbox(6)
	h.add_child(UI.label(text, 14))
	h.add_child(UI.button(btn, func():
		var e := c.buy_upgrade(kind)
		if e != "":
			UI.popup(hub, "Facilities", e)
		hub.refresh()))
	return h


func _show() -> void:
	UI.clear(detail)
	var om: OwnedMech = c.mechs.get(sel)
	if om == null:
		return
	detail.add_child(UI.panel(Views.sheet(om.design, om.condition, Game.stable_material(c.player_id), c.year)))
	var name_h := UI.hbox(6)
	name_h.add_child(UI.label("Nickname", 13))
	var le := LineEdit.new()
	le.text = om.nickname
	le.placeholder_text = "e.g. Legend-Killer"
	le.custom_minimum_size.x = 220
	le.text_submitted.connect(func(t):
		om.nickname = t.strip_edges()
		hub.refresh())
	name_h.add_child(le)
	detail.add_child(name_h)
	var bh := UI.hbox(8)
	if om.status == "wrecked":
		var est := om.repair_estimate(c.year, c.rules)
		bh.add_child(UI.button("Rebuild (%s, %.0f h)" % [UI.short_money(int(est["cost"] * c.price_mult()) + int(est["hours"] * float(c.rules["labor_cost_hour"]))), float(est["hours"])], func():
			_do(c.start_repair(om.uid))))
		bh.add_child(UI.button("Scrap for %s" % UI.short_money(int(om.value() * float(c.rules["market"]["sell_fraction"]))), func():
			_do(c.sell_mech(om.uid))))
	elif om.status == "ready":
		if om.is_damaged():
			var est2 := om.repair_estimate(c.year, c.rules)
			var cost2 := int(est2["cost"] * c.price_mult()) + int(est2["hours"] * float(c.rules["labor_cost_hour"]))
			bh.add_child(UI.button("Repair (%s, %.0f h)" % [UI.short_money(cost2), float(est2["hours"])], func():
				_do(c.start_repair(om.uid))))
		bh.add_child(UI.button("Refit in the designer", func(): _open_designer(om.uid)))
		bh.add_child(UI.button("Sell (%s)" % UI.short_money(int(om.value() * float(c.rules["market"]["sell_fraction"]))), func():
			UI.confirm(hub, "Sell", "Sell the %s?" % om.label(), func(): _do(c.sell_mech(om.uid)))))
	elif om.status == "away":
		bh.add_child(UI.label("Off-world on a contract%s. It comes back as the battle leaves it." % (
			", %d week%s to go" % [int(c.deployment["weeks_left"]), "" if int(c.deployment["weeks_left"]) == 1 else "s"] if not c.deployment.is_empty() else ""), 13, UI.WARN))
	else:
		bh.add_child(UI.label("In the bay: %s, %.0f hours of work left. Your techs put in %d hours a week." % [om.status, om.work_hours, c.player().techs * int(c.rules["tech_hours_week"])], 13, UI.WARN))
	detail.add_child(bh)
	if om.is_damaged() and om.status == "ready":
		var est3 := om.repair_estimate(c.year, c.rules)
		var lv := UI.vbox(1)
		for l in est3["lines"]:
			lv.add_child(Views.mono_label("%-36s %12s  %5.1f h" % [l[0], UI.money(int(l[1])), float(l[2])]))
		for m in est3["missing"]:
			lv.add_child(UI.label("Can't source a replacement %s in %d: it stays destroyed." % [m, c.year], 12, UI.BAD))
		detail.add_child(UI.panel(lv))
	detail.add_child(UI.label("%d fights, %d kills, fame %.0f. Bought for %s." % [om.fights, om.kills, om.fame, UI.money(om.paid)], 12, UI.DIM))


func _do(err: String) -> void:
	if err != "":
		UI.popup(hub, "'Mech bay", err)
	hub.refresh()


func _open_designer(uid: int) -> void:
	var d = load("res://ui/designer/designer.gd").new()
	d.setup(c, uid, null)
	Game.show_screen(d)


func _new_design() -> void:
	var p := c.player()
	if p.mechs.size() >= p.bays:
		UI.popup(hub, "'Mech bay", "You need a free bay to build a new 'Mech.")
		return
	var d = load("res://ui/designer/designer.gd").new()
	d.setup(c, -1, MechDesign.blank(50, 4))
	Game.show_screen(d)
