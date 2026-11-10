extends "res://ui/merc/merc_tab.gd"
## Market: 'Mechs and vehicles for sale on this world, and people looking for work.

static var sel := -1
static var page := 0

var detail: VBoxContainer


func build() -> void:
	setup_margins()
	var root := UI.vbox(8)
	add_child(root)
	var head := UI.hbox(10)
	head.add_child(UI.title("Market at %s" % c.sm.name_of(c.location)))
	head.add_child(UI.spacer())
	head.add_child(UI.button("Units for sale (%d)" % c.market_units.size(), func():
		page = 0
		hub.refresh()))
	head.add_child(UI.button("Hiring (%d)" % c.market_people.size(), func():
		page = 1
		hub.refresh()))
	root.add_child(head)
	root.add_child(UI.label("Offers refresh at the start of each month. Hiring halls have far more on offer.  Cash: %s" % UI.money(c.cash), 13, UI.DIM))
	if c.in_transit():
		root.add_child(UI.label("You're in transit: the market opens when you land.", 14, UI.WARN))
		return
	if absf(c.price_mult() - 1.0) > 0.01:
		root.add_child(UI.label("%s: everything costs %d%% %s." % [_price_cause(), absi(int(round((c.price_mult() - 1.0) * 100.0))), "more" if c.price_mult() > 1.0 else "less"], 13, UI.WARN))
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	detail = UI.vbox(8)
	detail.custom_minimum_size.x = 540
	if page == 0:
		var tree := UI.tree([["Unit", 4], ["Type", -80], ["Tons", -50], ["BV", -55], ["Condition", -90], ["Seller", 2], ["Price", -100]])
		split.add_child(tree)
		var first: TreeItem = null
		for o in c.market_units:
			var d := MercCampaign.db_design(str(o["design"]))
			var tmp := MercUnit.new()
			tmp.design = d
			tmp.condition = o["condition"]
			var it := tree.create_item()
			it.set_text(0, d.display_name())
			it.set_text(1, tmp.kind_label())
			it.set_text(2, str(d.tons))
			it.set_text(3, str(tmp.bv()))
			it.set_text(4, "new" if tmp.condition.is_empty() else "%d%% worn" % int(tmp.damage_fraction() * 100))
			it.set_text(5, str(o["seller"]))
			it.set_text(6, UI.short_money(int(o["price"])))
			it.set_metadata(0, int(o["offer"]))
			if first == null or int(o["offer"]) == sel:
				first = it
		tree.item_selected.connect(func():
			sel = int(tree.get_selected().get_metadata(0))
			_show_unit())
		split.add_child(UI.scroll(detail))
		if first != null:
			first.select(0)
	else:
		var tree2 := UI.tree([["Name", 3], ["Role", 2], ["Skills", 2], ["Level", -80], ["Hiring bonus", -110]])
		split.add_child(tree2)
		for o in c.market_people:
			var it2 := tree2.create_item()
			if o.has("pool"):
				it2.set_text(0, "%d %ss" % [int(o["count"]), str(o["pool"]).capitalize()])
				it2.set_text(1, "Pool")
				it2.set_text(4, UI.short_money(int(o["count"]) * int(c.rules["salaries"][str(o["pool"])])))
			else:
				var p := MercPerson.from_dict(o["person"])
				it2.set_text(0, p.full_name())
				it2.set_text(1, p.role_label())
				it2.set_text(2, p.skill_str())
				it2.set_text(3, p.experience(c.rules).capitalize())
				it2.set_text(4, UI.short_money(p.salary(c.rules) * int(c.rules["hire_fee_months"])))
			it2.set_metadata(0, int(o["offer"]))
		tree2.item_selected.connect(func():
			sel = int(tree2.get_selected().get_metadata(0))
			_show_person())
		split.add_child(UI.scroll(detail))


func _show_unit() -> void:
	UI.clear(detail)
	for o in c.market_units:
		if int(o["offer"]) != sel:
			continue
		var d := MercCampaign.db_design(str(o["design"]))
		detail.add_child(MercUI.sheet(d, o["condition"], Game.tint_material(c.color, c.camo), c.year()))
		detail.add_child(UI.label("Sold by %s for %s" % [o["seller"], UI.money(int(o["price"]))], 15, UI.ACCENT))
		var b := UI.button("Buy", func(): act(func(): return c.buy_unit(int(o["offer"]))))
		b.disabled = c.cash < int(o["price"])
		detail.add_child(b)
		return


func _show_person() -> void:
	UI.clear(detail)
	for o in c.market_people:
		if int(o["offer"]) != sel:
			continue
		if o.has("pool"):
			detail.add_child(UI.label("%d %ss looking for work" % [int(o["count"]), str(o["pool"])], 16, UI.TEXT, true))
			detail.add_child(wrap_label("AsTechs assist your techs (six per tech for full speed); medics help your doctors. Both are paid as a pool.", 13, UI.DIM))
		else:
			var p := MercPerson.from_dict(o["person"])
			var h := UI.hbox(12)
			h.add_child(MercUI.portrait(p, 80))
			var v := UI.vbox(2)
			v.add_child(UI.label(p.full_name(), 17, UI.TEXT, true))
			v.add_child(UI.label("%s  ·  %s  ·  %s" % [p.role_label(), p.skill_str(), p.experience(c.rules)], 13, UI.DIM))
			v.add_child(UI.label("Salary %s a month" % UI.money(p.salary(c.rules)), 13))
			h.add_child(v)
			detail.add_child(h)
		detail.add_child(UI.button("Hire", func(): act(func(): return c.hire(int(o["offer"])))))
		return


## The timeline entries behind today's prices, by name.
func _price_cause() -> String:
	var names: Array = []
	for a in c.timeline_active():
		if absf(float(a["fx"].get("price", 1.0)) - 1.0) > 0.005:
			names.append(str(a["title"]))
	return ", ".join(names) if not names.is_empty() else "The times"
