extends "res://ui/merc/merc_tab.gd"
## Parts and supply: the warehouse, the shopping list (procurement rolls), deliveries on the way.


func build() -> void:
	setup_margins()
	var root := UI.hbox(14)
	add_child(root)
	var left := UI.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.scroll(left))
	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.scroll(right))
	var y := c.year()
	var wh := section(left, "Warehouse")
	if c.warehouse.is_empty():
		wh.add_child(UI.label("Empty. Parts come from purchases, salvage and stripped wrecks.", 13, UI.DIM))
	var keys: Array = c.warehouse.keys()
	keys.sort()
	for k in keys:
		var info := MercRepair.part_info(str(k), y)
		var h := UI.hbox(8)
		var l := UI.label("%s" % info["name"], 13)
		l.custom_minimum_size.x = 300
		h.add_child(l)
		h.add_child(UI.label("x%s%s" % [str(c.warehouse[k]), " t" if info["tons"] else ""], 13, UI.ACCENT))
		h.add_child(UI.spacer())
		var kk := str(k)
		h.add_child(UI.button("Sell 1", func(): act(func():
			c.sell_part(kk, 1.0)
			return "")))
		wh.add_child(h)
	var need := section(left, "Needed for repairs")
	var wanted := {}
	for q in c.repair_queue():
		var t: Dictionary = q["task"]
		var part := str(t["part"])
		if part == "" or c.has_part(part, float(t["qty"])):
			continue
		wanted[part] = float(wanted.get(part, 0.0)) + float(t["qty"])
	if wanted.is_empty():
		need.add_child(UI.label("Nothing missing.", 13, UI.GOOD))
	for part2 in wanted:
		var info2 := MercRepair.part_info(str(part2), y)
		var tn := c.procurement_tn(str(part2))
		need.add_child(UI.label("%s x%s  ·  availability %s, needs %d+" % [info2["name"], str(snappedf(float(wanted[part2]), 0.01)), info2["avail"], int(tn["tn"])], 13, UI.WARN if tn["possible"] else UI.BAD))
	if not wanted.is_empty():
		need.add_child(UI.button("Search for all of these", func(): act(func():
			for p3 in wanted:
				c._want(str(p3), float(wanted[p3]))
			return "")))
	var buy := section(left, "Order supplies")
	if absf(c.price_mult() - 1.0) > 0.01 or c.supply_mod() != 0:
		var why: Array = []
		if absf(c.price_mult() - 1.0) > 0.01:
			why.append("prices %+d%%" % int(round((c.price_mult() - 1.0) * 100.0)))
		if c.supply_mod() != 0:
			why.append("every search %+d" % c.supply_mod())
		buy.add_child(UI.label("The times: %s." % ", ".join(why), 13, UI.WARN))
	var std := ["armor:standard", "armor:ferro"]
	var ammo := {}
	for u in c.combat_units():
		var rep := (u as MercUnit).analysis()
		for mt in rep.get("mounts", []):
			var it: Dictionary = mt["item"] if mt.has("item") and mt["item"] is Dictionary else c.db.item(mt["id"])
			if it.get("kind", "") == "ammo":
				ammo["ammo:" + str(mt["id"])] = true
	for k2 in std + ammo.keys():
		var info3 := c.part_info(str(k2))
		var h2 := UI.hbox(8)
		var l2 := UI.label(str(info3["name"]), 13)
		l2.custom_minimum_size.x = 300
		h2.add_child(l2)
		h2.add_child(UI.label("%s/%s  ·  %s" % [UI.short_money(int(info3["price"])), "ton" if info3["tons"] else "each", info3["avail"]], 12, UI.DIM))
		h2.add_child(UI.spacer())
		var key := str(k2)
		for n in [1, 4]:
			h2.add_child(UI.button("+%d" % n, func(): act(func(): return c.order_part(key, float(n)))))
		buy.add_child(h2)
	var sh := section(right, "Shopping list (%d)" % c.shopping.size())
	sh.add_child(wrap_label("Each item is searched for once a week: 2d6 against your logistics admin's skill, the availability rating and the world. Found parts are paid for and arrive in a few days.", 12, UI.DIM))
	for i in c.shopping.size():
		var s: Dictionary = c.shopping[i]
		var info4 := MercRepair.part_info(str(s["key"]), y)
		var tn2 := c.procurement_tn(str(s["key"]))
		var h3 := UI.hbox(8)
		var l3 := UI.label("%s x%s%s" % [info4["name"], str(s["qty"]), "  (refit)" if s.get("refit", false) else ""], 13)
		l3.custom_minimum_size.x = 280
		h3.add_child(l3)
		var mods: Array = []
		for m in tn2["mods"]:
			mods.append("%s %+d" % [m[0], int(m[1])])
		var tl := UI.label("needs %d+ · next roll %s" % [int(tn2["tn"]), MercCampaign.date_label(int(s["next"]))] if tn2["possible"] else "not for sale", 12, UI.DIM if tn2["possible"] else UI.BAD)
		tl.tooltip_text = ", ".join(mods)
		tl.mouse_filter = Control.MOUSE_FILTER_PASS
		h3.add_child(tl)
		h3.add_child(UI.spacer())
		var idx := i
		if s.get("refit", false):
			var rl := UI.label("cancel the refit in the Hangar", 12, UI.DIM)
			h3.add_child(rl)
		else:
			h3.add_child(UI.button("Cancel", func(): act(func():
				c.cancel_shopping(idx)
				return "")))
		sh.add_child(h3)
	var od := section(right, "On the way (%d)" % c.orders.size())
	for o in c.orders:
		var info5 := MercRepair.part_info(str(o["key"]), y)
		od.add_child(UI.label("%s x%s  ·  %d days%s" % [info5["name"], str(o["qty"]), int(o["days"]), "  (refit)" if o.get("refit", false) else ""], 13))
