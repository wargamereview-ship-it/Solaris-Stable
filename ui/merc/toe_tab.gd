extends "res://ui/merc/merc_tab.gd"
## TO&E: lances, their roles on contract, which units are in them and who crews each unit.


func build() -> void:
	setup_margins()
	var root := UI.vbox(10)
	add_child(root)
	var head := UI.hbox(10)
	head.add_child(UI.title("Lances and crews"))
	head.add_child(UI.spacer())
	head.add_child(UI.button("New lance", func(): act(func():
		c.new_lance("Lance %d" % (c.lances.size() + 1))
		return "")))
	root.add_child(head)
	root.add_child(wrap_label("On a contract each lance with a role may be called to fight every week: Fight and Scout lances see the most action, Defend lances hold bases, Training gives green crews XP, Reserve never deploys.", 13, UI.DIM))
	var body := UI.vbox(10)
	root.add_child(UI.scroll(body))
	var roles: Dictionary = c.rules["operations"]["roles"]
	var role_keys: Array = roles.keys()
	for l in c.lances:
		var v := UI.vbox(4)
		var p := UI.panel(v)
		body.add_child(p)
		var h := UI.hbox(10)
		var ne := LineEdit.new()
		ne.text = str(l["name"])
		ne.custom_minimum_size.x = 220
		ne.text_submitted.connect(func(t): act(func():
			l["name"] = t.strip_edges() if t.strip_edges() != "" else l["name"]
			return ""))
		h.add_child(ne)
		h.add_child(UI.label("Role", 13, UI.DIM))
		var labels: Array = []
		for k in role_keys:
			labels.append(str(roles[k]["label"]))
		var ro := UI.option(labels, role_keys.find(str(l["role"])))
		ro.item_selected.connect(func(i): act(func():
			c.set_role(int(l["id"]), str(role_keys[i]))
			return ""))
		h.add_child(ro)
		h.add_child(UI.label("BV %d" % c.lance_bv(int(l["id"])), 13, UI.DIM))
		h.add_child(UI.spacer())
		h.add_child(UI.button("Disband", func(): act(func():
			c.delete_lance(int(l["id"]))
			return "")))
		v.add_child(h)
		if (l["units"] as Array).is_empty():
			v.add_child(UI.label("No units. Add some from the unassigned list below.", 13, UI.DIM))
		for uid in l["units"]:
			v.add_child(_unit_row(c.units[int(uid)]))
	var loose := UI.vbox(4)
	body.add_child(UI.panel(loose))
	loose.add_child(UI.label("UNASSIGNED UNITS", 13, UI.ACCENT, true))
	var any := false
	for id in c.units:
		var u: MercUnit = c.units[id]
		if u.lance < 0 and not u.wreck():
			loose.add_child(_unit_row(u))
			any = true
	if not any:
		loose.add_child(UI.label("None.", 13, UI.DIM))


func _unit_row(u: MercUnit) -> Control:
	var h := UI.hbox(10)
	h.add_child(Views.sprite(u.design.sprite, Game.tint_material(c.color, c.camo), 46))
	var nm := UI.label(u.label(), 14, UI.TEXT, true)
	nm.custom_minimum_size.x = 260
	h.add_child(nm)
	h.add_child(UI.label("%s, %dt" % [u.kind_label(), u.tons()], 12, UI.DIM))
	var st := MercUI.unit_status(c, u)
	var sl := UI.label(str(st[0]), 12, st[1])
	sl.custom_minimum_size.x = 110
	h.add_child(sl)
	# crew picker: the current crew plus everyone free with the right role
	var want := "vehicle_crew" if u.is_vehicle() else "mechwarrior"
	var opts: Array = ["(no crew)"]
	var ids: Array = [-1]
	var cur := 0
	for p in c.roster():
		var pp: MercPerson = p
		if pp.role != want:
			continue
		if pp.unit_id >= 0 and pp.unit_id != u.id:
			continue
		opts.append("%s  %s%s" % [pp.short_name(), pp.skill_str(), "" if pp.available() else " (%s)" % pp.status])
		ids.append(pp.id)
		if pp.unit_id == u.id:
			cur = ids.size() - 1
	var co := UI.option(opts, cur)
	co.custom_minimum_size.x = 240
	co.item_selected.connect(func(i): act(func():
		var pid := int(ids[i])
		if pid < 0:
			for x in u.crew.duplicate():
				c.unassign(int(x))
			return ""
		return c.assign(pid, u.id)))
	h.add_child(co)
	var lopts: Array = ["(no lance)"]
	var lids: Array = [-1]
	var lcur := 0
	for l in c.lances:
		lopts.append(str(l["name"]))
		lids.append(int(l["id"]))
		if int(l["id"]) == u.lance:
			lcur = lids.size() - 1
	var lo := UI.option(lopts, lcur)
	lo.item_selected.connect(func(i): act(func(): return c.set_lance(u.id, int(lids[i]))))
	h.add_child(lo)
	return h
