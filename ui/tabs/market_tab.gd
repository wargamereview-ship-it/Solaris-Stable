extends MarginContainer
## The Solaris market: used 'Mechs, free-agent MechWarriors and parts in stock this week.

var hub
var c: Campaign
var detail: VBoxContainer
static var page := 0


func build() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	var root := UI.vbox(8)
	add_child(root)
	var head := UI.hbox(10)
	head.add_child(UI.title("Market — %s" % c.date_str()))
	head.add_child(UI.spacer())
	for i in 3:
		var nm: String = ["'Mechs for sale", "MechWarriors", "Parts in stock"][i]
		var b := UI.button(nm, func():
			page = i
			hub.refresh())
		if i == page:
			b.add_theme_color_override("font_color", UI.ACCENT)
		head.add_child(b)
	root.add_child(head)
	if c.price_mult() > 1.01:
		root.add_child(UI.label("Wartime prices: everything costs %d%% more." % int((c.price_mult() - 1.0) * 100), 13, UI.WARN))
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	detail = UI.vbox(8)
	detail.custom_minimum_size.x = 600
	match page:
		0:
			_mechs(split)
		1:
			_agents(split)
		2:
			_parts(split)
	split.add_child(UI.scroll(detail))


func _mechs(split: Control) -> void:
	var t := UI.tree([["'Mech", 3], ["Class", -90], ["Condition", -85], ["BV", -60], ["Price", -110]])
	split.add_child(t)
	for o in c.market["mechs"]:
		var it := t.create_item()
		var d: Dictionary = GameData.db().design_by_id[o["design"]]
		var tag := ""
		if o["kind"] == "relic":
			tag = " [Star League relic]"
		elif o["kind"] == "clan":
			tag = " [Clan salvage]"
		it.set_text(0, d["id"] + tag)
		it.set_text(1, "%s %dt" % [GameData.db().weight_class(int(d["tons"])).capitalize(), int(d["tons"])])
		it.set_text(2, "%d%%" % int(float(o["quality"]) * 100))
		it.set_text(3, str(int(d.get("bv", 0))))
		it.set_text(4, UI.short_money(int(o["price"])))
		it.set_metadata(0, int(o["offer"]))
		if o["kind"] != "used":
			it.set_custom_color(0, UI.ACCENT)
	t.item_selected.connect(func(): _show_mech(int(t.get_selected().get_metadata(0))))
	if c.market["mechs"].is_empty():
		detail.add_child(UI.label("Nothing for sale this week.", 14, UI.DIM))
	else:
		t.get_root().get_first_child().select(0)


func _show_mech(offer: int) -> void:
	UI.clear(detail)
	for o in c.market["mechs"]:
		if int(o["offer"]) != offer:
			continue
		var md := MechDesign.from_stock(o["design"])
		detail.add_child(UI.panel(Views.sheet(md, o["condition"], Game.tint_material(Color(0.6, 0.6, 0.58)), c.year)))
		if o["kind"] == "relic":
			detail.add_child(UI.label("A Star League-era machine with lostech that can't be replaced in %d. Damage to those parts is permanent." % c.year, 13, UI.ACCENT))
		elif o["kind"] == "clan":
			detail.add_child(UI.label("Clan salvage. Clan parts can't be bought on the Inner Sphere market.", 13, UI.ACCENT))
		detail.add_child(UI.button("Buy for %s" % UI.money(int(o["price"])), func():
			var e := c.buy_mech(offer)
			if e != "":
				UI.popup(hub, "Market", e)
			hub.refresh()))
		return


func _agents(split: Control) -> void:
	var t := UI.tree([["Name", 3], ["G/P", -50], ["Age", -45], ["Traits", 3], ["Asking/wk", -95]])
	split.add_child(t)
	for wid in c.market["agents"]:
		var w: Warrior = c.warriors[int(wid)]
		var it := t.create_item()
		it.set_text(0, w.full_name())
		it.set_text(1, w.skill_str())
		it.set_custom_color(1, UI.skill_color(int((w.gunnery + w.piloting) / 2.0)))
		it.set_text(2, str(w.age(c.year)))
		var tr: Array = []
		for x in w.traits:
			tr.append(str(x).replace("_", " "))
		it.set_text(3, ", ".join(tr))
		it.set_text(4, UI.short_money(w.salary))
		it.set_metadata(0, w.id)
	t.item_selected.connect(func(): _show_agent(int(t.get_selected().get_metadata(0))))
	if c.market["agents"].is_empty():
		detail.add_child(UI.label("No free agents looking for work this week.", 14, UI.DIM))
	else:
		t.get_root().get_first_child().select(0)


func _show_agent(wid: int) -> void:
	UI.clear(detail)
	var w: Warrior = c.warriors[wid]
	var h := UI.hbox(12)
	h.add_child(Views.portrait(w, 120))
	var v := UI.vbox(3)
	v.add_child(UI.label(w.full_name(), 20, UI.TEXT, true))
	v.add_child(UI.label("%s, age %d" % [w.culture, w.age(c.year)], 13, UI.DIM))
	v.add_child(UI.label("Gunnery %d  ·  Piloting %d  ·  record %s  ·  fame %.0f" % [w.gunnery, w.piloting, w.record_str(), w.fame], 14))
	for t in w.traits:
		v.add_child(UI.rich("[b]%s[/b] — %s" % [str(t).replace("_", " ").capitalize(), CombatMech.TRAITS.get(t, "")]))
	h.add_child(v)
	detail.add_child(h)
	var g := GridContainer.new()
	g.columns = 2
	g.add_child(UI.label("Weekly salary"))
	var sal := SpinBox.new()
	sal.min_value = 500
	sal.max_value = 50000
	sal.step = 100
	sal.value = w.salary
	g.add_child(sal)
	g.add_child(UI.label("Contract"))
	var wk := UI.option(["26 weeks", "52 weeks", "104 weeks"], 1)
	g.add_child(wk)
	detail.add_child(g)
	detail.add_child(UI.label("Signing bonus: 4 weeks' salary. Offers well under the asking price get turned down.", 12, UI.DIM))
	detail.add_child(UI.button("Offer contract", func():
		var e := c.hire(wid, int(sal.value), [26, 52, 104][wk.selected])
		if e != "":
			UI.popup(hub, "Contract", e)
		hub.refresh()))


func _parts(split: Control) -> void:
	var t := UI.tree([["Part", 3], ["Type", -80], ["Tons", -55], ["Crits", -55], ["Rarity", -60], ["Stock", -55], ["Price", -100]])
	split.add_child(t)
	var ids: Array = c.market["parts"].keys()
	ids.sort_custom(func(a, b): return str(GameData.db().item(a).get("name", "")) < str(GameData.db().item(b).get("name", "")))
	for id in ids:
		var it_d := GameData.db().item(id)
		if it_d.get("kind", "") == "ammo":
			continue
		var stock: Dictionary = c.market["parts"][id]
		var it := t.create_item()
		it.set_text(0, it_d.get("name", id))
		it.set_text(1, it_d.get("wtype", it_d.get("misc", it_d.get("kind", ""))))
		it.set_text(2, str(it_d.get("tons", "var")))
		it.set_text(3, str(it_d.get("crits", "var")))
		it.set_text(4, stock["rarity"])
		it.set_text(5, "∞" if int(stock["qty"]) >= 99 else str(int(stock["qty"])))
		it.set_text(6, UI.short_money(int(stock["price"])))
	detail.add_child(UI.label("Parts are bought automatically when you commit a refit in the 'Mech bay designer. What's rare this week may be gone next week, and lostech isn't sold at all until it's rediscovered.", 13, UI.DIM))
	detail.get_child(0).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
