extends "res://ui/merc/merc_tab.gd"
## Command center: where the company is, the contract, battles waiting, the state of the force.


func build() -> void:
	setup_margins()
	var root := UI.hbox(14)
	add_child(root)
	var left := UI.vbox(10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.scroll(left))
	var right := UI.vbox(10)
	right.custom_minimum_size.x = 440
	root.add_child(right)
	var sm := c.sm
	var yf := c.year_f()
	var where := section(left, "Situation")
	if c.in_transit():
		var tp := c.travel_position()
		kv(where, "Location", "In transit to %s, %d days left (%s)" % [sm.name_of(int(c.travel["dest"])), int(c.travel["days_left"]), str(tp.get("phase", ""))])
	else:
		var owner := sm.owner(c.location, yf)
		kv(where, "Location", "%s (%s)" % [sm.name_of(c.location), sm.faction_name(owner)])
		var hall := c.hall_level()
		kv(where, "Hiring hall", hall.to_lower().capitalize() if hall != "" else "None here: few contracts and a thin market", UI.TEXT if hall != "" else UI.DIM)
	kv(where, "Date", c.date_str())
	var con := section(left, "Contract")
	if c.contract.is_empty():
		con.add_child(wrap_label("No contract. Look at the Contracts tab: hiring halls have the most offers.", 14, UI.DIM))
		con.add_child(UI.button("Find a contract", func(): hub.show_tab("contracts")))
	else:
		var k := c.contract
		kv(con, "Employer", "%s  ·  %s" % [k["employer_name"], k["mission_label"]])
		kv(con, "Enemy", "%s (%s troops)" % [k["enemy_name"], str(k.get("enemy_skill", "regular"))])
		kv(con, "World", str(k["system_name"]))
		match str(k["status"]):
			"signed":
				var there := c.location == int(k["system"]) and not c.in_transit()
				kv(con, "Status", "Signed. Get to %s by %s." % [k["system_name"], MercCampaign.date_label(int(k["deadline_arrive"]))], UI.WARN)
				if not there and not c.in_transit():
					con.add_child(UI.button("Travel to %s" % k["system_name"], func(): act(func(): return c.start_travel(int(k["system"])))))
			"active":
				kv(con, "Status", "Under way until %s (%d days left)" % [MercCampaign.date_label(int(k["end_day"])), int(k["end_day"]) - c.day], UI.GOOD)
				kv(con, "Score", "%d  ·  enemy morale %s" % [int(k["score"]), ["Routed", "Very low", "Low", "Normal", "High", "Very high", "Overwhelming"][clampi(int(k["morale"]), 0, 6)]])
				kv(con, "Pay", "%s a month" % UI.money(int(k["monthly_pay"])))
	var bat := section(left, "Battles waiting")
	var pend := c.pending_scenarios()
	if pend.is_empty():
		bat.add_child(UI.label("None.", 14, UI.DIM))
	for s in pend:
		var h := UI.hbox(8)
		h.add_child(UI.label("%s  ·  %s  ·  by %s" % [s["label"], c.lance(int(s["lance"])).get("name", "?"), MercCampaign.date_label(int(s["deadline"]))], 14))
		h.add_child(UI.spacer())
		h.add_child(UI.button("Briefing", func():
			load("res://ui/merc/ops_tab.gd").sel = int(s["id"])
			hub.show_tab("ops")))
		bat.add_child(h)
	if not c.salvage.is_empty():
		bat.add_child(UI.button("Claim salvage from the last battle", func(): hub.show_tab("ops")))
	var force := section(left, "The company")
	var ready := 0
	var dmg := 0
	var wrecks := 0
	for u in c.combat_units():
		var uu: MercUnit = u
		if uu.damaged():
			dmg += 1
		elif c.deployable(uu):
			ready += 1
	for id in c.units:
		if (c.units[id] as MercUnit).wreck():
			wrecks += 1
	kv(force, "Units", "%d ready, %d damaged, %d wrecks" % [ready, dmg, wrecks])
	var roles := {}
	var injured := 0
	for p in c.roster():
		var pp: MercPerson = p
		roles[pp.role] = int(roles.get(pp.role, 0)) + 1
		if pp.status == "injured":
			injured += 1
	kv(force, "People", "%d MechWarriors, %d vehicle crews, %d techs, %d doctors, %d admins, %d AsTechs, %d medics%s" % [int(roles.get("mechwarrior", 0)), int(roles.get("vehicle_crew", 0)), int(roles.get("tech", 0)), int(roles.get("doctor", 0)), int(roles.get("admin", 0)), c.astechs, c.medics, ("  (%d injured)" % injured) if injured > 0 else ""])
	kv(force, "Tech time", "%d minutes a day, %d repair jobs open" % [c.tech_minutes(), c.repair_queue().size()])
	kv(force, "Parts", "%d wanted, %d on the way" % [c.shopping.size(), c.orders.size()])
	var costs := c.monthly_costs()
	var tot := 0
	for kk in costs:
		tot += int(costs[kk])
	kv(force, "Monthly costs", UI.money(tot))
	var r := c.rating()
	var parts: Array = []
	for kk in r["parts"]:
		parts.append("%s %+d" % [kk, int(r["parts"][kk])])
	kv(force, "Rating", "%s (%d): %s" % [r["letter"], int(r["score"]), ", ".join(parts)])
	var isn := section(right, "The Inner Sphere", "news")
	var heads := 0
	for i in range(c.news.size() - 1, -1, -1):
		var nw: Dictionary = c.news[i]
		if str(nw["kind"]) == "front":
			continue
		isn.add_child(wrap_label("%s  %s" % [MercCampaign.date_label(int(nw["day"])), nw["title"]], 13, UI.WARN if int(nw["day"]) >= c.day - 30 else UI.DIM))
		heads += 1
		if heads >= 3:
			break
	for s in c.timeline_summary():
		if str(s["text"]) != "":
			isn.add_child(wrap_label("%s: %s" % [s["title"], s["text"]], 12, UI.TEXT))
	var hiring := c.hiring_outlook()
	if not (hiring["more"] as Array).is_empty():
		isn.add_child(wrap_label("Hiring more: %s" % ", ".join(hiring["more"]), 12, UI.GOOD))
	if not (hiring["less"] as Array).is_empty():
		isn.add_child(wrap_label("Hiring less: %s" % ", ".join(hiring["less"]), 12, UI.BAD))
	if heads == 0 and c.timeline_summary().is_empty():
		isn.add_child(wrap_label("Quiet. List prices, usual pay.", 13))
	isn.add_child(UI.button("All the news", func(): hub.show_tab("news")))
	var lg := section(right, "Recent events")
	var box := UI.vbox(2)
	var n := 0
	for i in range(c.log.size() - 1, -1, -1):
		var e: Dictionary = c.log[i]
		box.add_child(wrap_label("%s  %s" % [MercCampaign.date_label(int(e["day"])), e["text"]], 13, UI.TEXT if int(e["day"]) >= c.day - 7 else UI.DIM))
		n += 1
		if n >= 26:
			break
	var sc := UI.scroll(box)
	sc.custom_minimum_size.y = 400
	lg.add_child(sc)
