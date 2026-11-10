extends "res://ui/merc/merc_tab.gd"
## Hangar: every unit, its damage, the repair jobs it needs and the parts they use. Sell or strip wrecks.
## A 'Mech can be sent to the mech lab for a refit; the refit on order, its parts and progress show here.

static var sel := -1

var tree: Tree
var detail: VBoxContainer


func build() -> void:
	setup_margins()
	var root := UI.vbox(8)
	add_child(root)
	var head := UI.hbox(10)
	head.add_child(UI.title("Hangar (%d units)" % c.units.size()))
	head.add_child(UI.spacer())
	head.add_child(UI.label("Repair mode", 13, UI.DIM))
	var modes: Dictionary = c.rules["repair"]["modes"]
	var mk: Array = modes.keys()
	var labels: Array = []
	for k in mk:
		labels.append(str(modes[k]["label"]))
	var mo := UI.option(labels, mk.find(c.repair_mode))
	mo.item_selected.connect(func(i): act(func():
		c.repair_mode = str(mk[i])
		return ""))
	head.add_child(mo)
	root.add_child(head)
	var techs := c.active("tech")
	var best := 12
	for t in techs:
		best = mini(best, (t as MercPerson).tech)
	root.add_child(UI.label("%d techs (best skill %s), %d AsTechs: %d tech minutes a day. Jobs on units with a battle coming are done first." % [techs.size(), str(best) if not techs.is_empty() else "-", c.astechs, c.tech_minutes()], 13, UI.DIM))
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	tree = UI.tree([["Unit", 4], ["Type", -80], ["Tons", -50], ["Status", 2], ["Crew", 2], ["Lance", 2], ["Jobs", -50], ["BV", -55], ["Value", -90]])
	split.add_child(tree)
	var first: TreeItem = null
	var ids: Array = c.units.keys()
	ids.sort()
	for id in ids:
		var u: MercUnit = c.units[id]
		var it := tree.create_item()
		it.set_text(0, u.label())
		it.set_text(1, u.kind_label())
		it.set_text(2, str(u.tons()))
		var st := MercUI.unit_status(c, u)
		it.set_text(3, str(st[0]))
		it.set_custom_color(3, st[1])
		var p := c.crew_of(u)
		it.set_text(4, p.short_name() if p != null else "—")
		it.set_text(5, str(c.lance(u.lance).get("name", "—")))
		it.set_text(6, str(MercRepair.tasks(u).size()))
		it.set_text(7, str(u.bv()))
		it.set_text(8, UI.short_money(u.value()))
		it.set_metadata(0, int(id))
		if first == null or int(id) == sel:
			first = it
	tree.item_selected.connect(func():
		sel = int(tree.get_selected().get_metadata(0))
		_show())
	detail = UI.vbox(8)
	detail.custom_minimum_size.x = 560
	split.add_child(UI.scroll(detail))
	if first != null:
		first.select(0)
	else:
		detail.add_child(UI.label("The hangar is empty. Buy units on the Market or take salvage.", 14, UI.DIM))


func _show() -> void:
	UI.clear(detail)
	var u: MercUnit = c.units.get(sel)
	if u == null:
		return
	detail.add_child(MercUI.sheet(u.design, u.condition, Game.tint_material(c.color, c.camo), c.year()))
	var st := MercUI.unit_status(c, u)
	detail.add_child(UI.label("%s  ·  %d battles, %d kills  ·  joined %s (%s)" % [str(st[0]).replace(" (refit)", ""), u.battles, u.kills, u.acquired, u.origin], 13, st[1]))
	if u.wreck():
		detail.add_child(wrap_label("This unit is a wreck: its center torso or a vehicle location is gone. Strip it for parts (intact weapons, ammo and some armor go to the warehouse) or sell the scrap.", 14, UI.WARN))
		var bh0 := UI.hbox(10)
		bh0.add_child(UI.button("Strip for parts", func(): act(func(): return c.strip_unit(u.id))))
		bh0.add_child(UI.button("Sell the scrap (%s)" % UI.money(int(u.value() * float(c.rules["markets"]["sell_fraction"]))), func(): act(func(): return c.sell_unit(u.id))))
		detail.add_child(bh0)
		return
	var tasks := MercRepair.tasks(u)
	var jobs := section(detail, "Repair jobs (%d)" % tasks.size())
	if tasks.is_empty():
		jobs.add_child(UI.label("Nothing to repair.", 14, UI.GOOD))
	var mode: Dictionary = c.rules["repair"]["modes"][c.repair_mode]
	var missing := 0
	for t in tasks:
		var h := UI.hbox(8)
		var l := UI.label(str(t["label"]), 13)
		l.custom_minimum_size.x = 280
		h.add_child(l)
		var done := float(u.progress.get(t["key"], 0.0))
		h.add_child(UI.label("%d/%d min" % [int(done), int(float(t["minutes"]) * float(mode["time"]))], 12, UI.DIM))
		if int(t["tn"]) > -50:
			h.add_child(UI.label("TN %+d" % int(t["tn"]), 12, UI.DIM))
		var part := str(t["part"])
		if part != "":
			var info := MercRepair.part_info(part, c.year())
			var have := c.has_part(part, float(t["qty"]))
			var txt := "%s x%s" % [info["name"], str(t["qty"])]
			var col := UI.GOOD if have else UI.WARN
			if not have:
				missing += 1
				var queued := false
				for s in c.shopping:
					if str(s["key"]) == part:
						queued = true
				for o in c.orders:
					if str(o["key"]) == part:
						queued = true
						txt += " (on the way)"
				if queued and txt.find("on the way") < 0:
					txt += " (searching)"
				if str(info["avail"]) == "X":
					txt += " (not for sale)"
					col = UI.BAD
			h.add_child(UI.label(txt, 12, col))
		if str(t["requires"]) != "":
			h.add_child(UI.label("after the location", 12, UI.DIM))
		jobs.add_child(h)
	if missing > 0:
		jobs.add_child(UI.button("Search for the missing parts", func(): act(func():
			for t2 in MercRepair.tasks(u):
				if not c.has_part(str(t2["part"]), float(t2["qty"])):
					c._want(str(t2["part"]), float(t2["qty"]))
			return "Your logistics admin starts looking (rolls weekly).")))
	_refit_section(u)
	var bh := UI.hbox(10)
	var ne := LineEdit.new()
	ne.placeholder_text = "Nickname"
	ne.text = u.nickname
	ne.custom_minimum_size.x = 160
	ne.text_submitted.connect(func(t): act(func():
		u.nickname = t.strip_edges()
		return ""))
	bh.add_child(ne)
	if u.design.is_infantry():
		pass   # infantry are what they are: replacements, not refits
	elif u.refit.is_empty() and u.is_vehicle():
		bh.add_child(UI.ibutton("wrench", "Refit in the workshop", func(): _open_lab(u.id),
			"Change weapons, ammunition, equipment and armor; the hull, engine and turret stay as built. Anything made in %d can go on: parts the warehouse lacks are put on the shopping list." % c.year()))
	elif u.refit.is_empty():
		bh.add_child(UI.ibutton("wrench", "Refit in the mech lab", func(): _open_lab(u.id),
			"Change weapons, equipment, armor, engine and more. Anything made in %d can go on: parts the warehouse lacks are put on the shopping list." % c.year()))
	bh.add_child(UI.button("Sell (%s)" % UI.money(int(u.value() * float(c.rules["markets"]["sell_fraction"]))), func():
		UI.confirm(self, "Sell the %s?" % u.label(), "A dealer will take it for half its value.", func(): act(func(): return c.sell_unit(u.id)))))
	detail.add_child(bh)


func _open_lab(uid: int) -> void:
	var vehicle: bool = c.units[uid].is_vehicle()
	var lab: Control = load("res://ui/designer/vehicle_lab.gd" if vehicle else "res://ui/designer/designer.gd").new()
	lab.setup_merc(c, uid)
	Game.show_screen(lab)


## The refit a 'Mech or vehicle has on order: what it becomes, the parts it waits for, how far the techs are.
func _refit_section(u: MercUnit) -> void:
	if u.refit.is_empty():
		return
	var nd := VehicleDesign.any_from_dict(u.refit["design"])
	var it := "vehicle" if u.is_vehicle() else "'Mech"
	var box := section(detail, "Refit on order" + ("" if nd.display_name() == u.design.display_name() else ": becomes the " + nd.display_name()))
	var need: Dictionary = u.refit.get("need", {})
	var miss := c.refit_missing(u)
	var mins := float(u.refit.get("minutes", 0.0))
	var left := mins - float(u.refit.get("done", 0.0))
	var days := c.refit_days(left)
	var eta := "no techs to do it" if days < 0 else "%d day%s of work left" % [days, "" if days == 1 else "s"]
	if u.refitting():
		box.add_child(UI.label("The techs are on it: %d%% done, %s. The %s can't fight until it is finished." % [int(c.refit_progress(u) * 100), eta, it], 13, UI.ACCENT))
	elif not miss.is_empty():
		box.add_child(wrap_label("Waiting for %d of %d kinds of parts. The %s fights as it is until the last one arrives; then the work takes %.0f tech hours (%s)." % [miss.size(), need.size(), it, mins / 60.0, eta], 13, UI.WARN))
	elif u.damaged():
		box.add_child(wrap_label("Every part is in. The techs repair the %s first, then start the refit (%.0f tech hours)." % [it, mins / 60.0], 13, UI.WARN))
	else:
		box.add_child(wrap_label("Every part is in. The techs start when they have time and the %s has no battle to fight (%.0f tech hours, %s)." % [it, mins / 60.0, eta], 13, UI.GOOD))
	for k in need:
		var info := MercRepair.part_info(str(k), c.year())
		var h := UI.hbox(8)
		var l := UI.label("%s x%s" % [info["name"], MercCampaign._qty_str(float(need[k]))], 13)
		l.custom_minimum_size.x = 280
		h.add_child(l)
		if not miss.has(k):
			h.add_child(UI.label("set aside", 12, UI.GOOD))
		else:
			var coming := 0.0
			for o in c.orders:
				if str(o["key"]) == str(k) and o.get("refit", false):
					coming += float(o["qty"])
			var txt := "%s missing" % MercCampaign._qty_str(float(miss[k]))
			if coming >= float(miss[k]) - 0.001:
				txt += " (on the way)"
			else:
				var tn := c.procurement_tn(str(k))
				txt += " (searching, %d+ each week)" % int(tn["tn"]) if tn["possible"] else " (not for sale)"
			h.add_child(UI.label(txt, 12, UI.WARN))
		box.add_child(h)
	var freed: Dictionary = u.refit.get("freed", {})
	if not freed.is_empty():
		var names: Array = []
		for k in freed:
			names.append("%s x%s" % [MercRepair.part_info(str(k), c.year())["name"], MercCampaign._qty_str(float(freed[k]))])
		box.add_child(wrap_label("Comes off and goes to the warehouse when it is done: " + ", ".join(names), 12, UI.DIM))
	box.add_child(UI.button("Cancel the refit", func():
		UI.confirm(self, "Cancel the refit of the %s?" % u.label(),
			"The parts set aside go back to the warehouse and the search for the rest stops." + (" The work already done is lost." if u.refitting() else ""),
			func(): act(func(): return c.cancel_refit(u.id)))))
