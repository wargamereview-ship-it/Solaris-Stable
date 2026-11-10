extends SceneTree
## godot --headless --path . -s tests/test_merc_refit.gd
## A 'Mech or vehicle refit in the mercenary game: the quote, the order, the parts search on the shopping list,
## delivery, the techs' work, the swap of the design, cancelling, and a save/load round trip.

var fails := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("FAIL: ", what)


func _swap(d: MechDesign, from: String, to: String) -> bool:
	for loc in MechDesign.LOCS:
		var row: Array = d.slots[loc]
		for i in row.size():
			if row[i] == from:
				row[i] = to
				return true
	return false


func _init() -> void:
	var db := GameData.db()
	var c := MercCampaign.new_game("Refit Co", Color(0.7, 0.3, 0.2), 3025, "Galatea", "combined", 777)
	var u: MercUnit = null
	var u2: MercUnit = null
	for id in c.units:
		var x: MercUnit = c.units[id]
		if x.is_vehicle():
			continue
		var has_ml := false
		for m in Construction.mounts_of(x.design):
			if m["id"] == "medium_laser":
				has_ml = true
		if has_ml and u == null:
			u = x
		elif has_ml and u2 == null:
			u2 = x
	check(u != null and u2 != null, "two 'Mechs with a medium laser")
	print("unit: ", u.label(), "  parts: ", c.design_parts(u.design))
	# same design: nothing to do
	var same := u.design.copy()
	var q0 := c.refit_quote(u.id, same)
	check(float(q0["minutes"]) == 0.0 and (q0["need"] as Dictionary).is_empty(), "unchanged design needs nothing")
	check(c.commit_refit(u.id, same) == "Nothing to change", "unchanged design is refused")
	# medium laser -> small laser, +8 armor on the CT
	var nd := u.design.copy()
	check(_swap(nd, "medium_laser", "small_laser"), "swap")
	c.warehouse.erase("item:small_laser")
	var q := c.refit_quote(u.id, nd)
	check((q["errors"] as Array).is_empty(), "quote has no errors")
	check(int(q["need"].get("item:small_laser", 0)) == 1, "needs a small laser")
	check(int(q["freed"].get("item:medium_laser", 0)) == 1, "frees a medium laser")
	check(int(q["buy"].get("item:small_laser", 0)) == 1 and int(q["cost"]) == 11250, "buys one small laser for 11,250")
	var rep := Construction.analyze(nd, c.year())
	check(rep["valid"], "new design is legal: " + str(rep["errors"]))
	var cash0 := c.cash
	check(c.commit_refit(u.id, nd) == "", "commit")
	check(c.cash == cash0, "nothing charged at commit")
	var found := false
	for s in c.shopping:
		if s["key"] == "item:small_laser" and s.get("refit", false) and float(s["qty"]) == 1.0:
			found = true
	check(found, "shopping list has the small laser, flagged refit")
	check(c.deployable(u) and not u.refitting(), "still deployable while waiting for parts")
	check(c.commit_refit(u.id, nd).find("already") >= 0, "second refit refused")
	# save / load
	var js := JSON.stringify(c.to_dict())
	var c2 := MercCampaign.from_dict(JSON.parse_string(js))
	var ub: MercUnit = c2.units[u.id]
	check(not ub.refit.is_empty() and int(ub.refit["need"]["item:small_laser"]) == 1, "refit survives save and load")
	# a second refit that wants the same part: one shopping entry for two
	var nd2 := u2.design.copy()
	_swap(nd2, "medium_laser", "small_laser")
	check(c.commit_refit(u2.id, nd2) == "", "second unit commit")
	var n := 0
	var qty := 0.0
	for s in c.shopping:
		if s["key"] == "item:small_laser":
			n += 1
			qty += float(s["qty"])
	check(n == 1 and qty == 2.0, "one shopping entry for two small lasers (%d entries, %s)" % [n, str(qty)])
	check(c.cancel_refit(u2.id) == "", "cancel")
	qty = 0.0
	for s in c.shopping:
		if s["key"] == "item:small_laser":
			qty += float(s["qty"])
	check(qty == 1.0 and u2.refit.is_empty(), "cancel shrinks the shopping entry back to one")
	# run the days
	var ml0 := float(c.warehouse.get("item:medium_laser", 0.0))
	var saw_order := false
	var saw_refitting := false
	var done_day := -1
	var done_event := false
	for dday in 200:
		var ev := c.advance_day()
		for o in c.orders:
			if o["key"] == "item:small_laser" and o.get("refit", false):
				saw_order = true
		if u.refitting():
			saw_refitting = true
			if c.deployable(u):
				check(false, "refitting unit must not be deployable")
		for e in ev:
			if str(e.get("text", "")).find("refit complete") >= 0:
				done_event = true
		if u.refit.is_empty():
			done_day = dday
			break
	print("refit done after %d days; cash %d -> %d" % [done_day, cash0, c.cash])
	check(done_day >= 0, "refit finishes")
	check(saw_order, "a refit order was on the way")
	check(done_event, "completion event")
	var has_sl := false
	var mls := 0
	for m in Construction.mounts_of(u.design):
		if m["id"] == "small_laser":
			has_sl = true
	check(has_sl, "the 'Mech now carries the small laser")
	check(float(c.warehouse.get("item:medium_laser", 0.0)) == ml0 + 1.0, "the medium laser went to the warehouse")
	check(float(c.warehouse.get("item:small_laser", 0.0)) == 0.0, "the small laser left the warehouse")
	var left := false
	for s in c.shopping:
		if s.get("refit", false):
			left = true
	check(not left, "no refit entries left on the shopping list")
	check(c.deployable(u) or c.crew_of(u) == null or u.damaged(), "deployable again")
	# parts already in the warehouse: nothing to buy, set aside at once, back on cancel
	var nd3 := u2.design.copy()
	_swap(nd3, "medium_laser", "small_laser")
	c.warehouse["item:small_laser"] = 2.0
	var q3 := c.refit_quote(u2.id, nd3)
	check((q3["buy"] as Dictionary).is_empty() and int(q3["cost"]) == 0, "warehouse part: nothing to buy")
	check(c.commit_refit(u2.id, nd3) == "", "commit with the part in store")
	check(float(c.warehouse.get("item:small_laser", 0.0)) == 1.0 and c.refit_missing(u2).is_empty(), "part set aside")
	c.cancel_refit(u2.id)
	check(float(c.warehouse.get("item:small_laser", 0.0)) == 2.0, "part back after cancel")
	# something nobody makes in 3025
	var nd4 := u2.design.copy()
	_swap(nd4, "medium_laser", "er_medium_laser")
	var q4 := c.refit_quote(u2.id, nd4)
	print("3058 part in 3025: ", q4["errors"])
	check(not (q4["errors"] as Array).is_empty(), "ER medium laser can't be ordered in 3025")
	check(c.commit_refit(u2.id, nd4) != "", "and the commit is refused")
	# armor: 8 points less on the center torso, nothing to buy
	var nd5 := u2.design.copy()
	nd5.armor["CT"] = int(nd5.armor["CT"]) - 8
	var q5 := c.refit_quote(u2.id, nd5)
	print("armor -8: need ", q5["need"], " freed ", q5["freed"], " min ", q5["minutes"])
	check((q5["need"] as Dictionary).is_empty() and float(q5["minutes"]) == 40.0, "taking 8 points off is 40 minutes and no parts")
	_vehicles(c)
	print("REFIT TEST DONE, fails: ", fails)
	quit()


## A vehicle refit: weapons in a facing or the turret, ammo in the body, the hull stays as built.
func _vehicles(c: MercCampaign) -> void:
	var db := GameData.db()
	var v: MercUnit = null
	var wi := -1
	for id in c.units:
		var x: MercUnit = c.units[id]
		if not x.is_vehicle() or not x.refit.is_empty():
			continue
		var eq: Array = (x.design as VehicleDesign).equipment
		for i in eq.size():
			if db.item(str(eq[i][0])).get("kind", "") == "weapon" and str(eq[i][0]) != "machine_gun":
				v = x
				wi = i
				break
		if v != null:
			break
	check(v != null, "a vehicle with a weapon")
	if v == null:
		return
	v.condition = {}
	var vd := v.design as VehicleDesign
	var old_id := str(vd.equipment[wi][0])
	var old_loc := str(vd.equipment[wi][1])
	print("vehicle: ", v.label(), "  ", vd.motion_label(), " ", vd.tons, " t  equipment: ", vd.equipment)
	print("parts: ", c.vehicle_parts(vd))
	var q0 := c.refit_quote(v.id, vd.copy())
	check(float(q0["minutes"]) == 0.0 and (q0["need"] as Dictionary).is_empty() and (q0["errors"] as Array).is_empty(),
		"unchanged vehicle needs nothing: " + str(q0["errors"]))
	check(c.commit_refit(v.id, vd.copy()) == "Nothing to change", "unchanged vehicle is refused")
	# the hull is not the refit's to change
	var h := vd.copy() as VehicleDesign
	h.walk += 1
	h.engine_rating = VehicleConstruction.engine_rating_for(h.motion, h.tons, h.walk)
	check(str(c.refit_quote(v.id, h)["errors"]).find("hull") >= 0, "a faster engine is refused")
	# ammo belongs in the body, weapons don't
	var a := vd.copy() as VehicleDesign
	a.equipment[wi] = [old_id, "BD"]
	check(str(c.refit_quote(v.id, a)["errors"]).find("go in the Body") >= 0, "a weapon in the body is refused")
	check(MercCampaign.vehicle_loc_takes(vd, "BD", db.item("ac_5_ammo")) and not MercCampaign.vehicle_loc_takes(vd, "FR", db.item("ac_5_ammo")),
		"ammo goes in the body only")
	check(not MercCampaign.vehicle_loc_takes(vd, "RO", db.item("medium_laser")), "nothing mounts on a rotor")
	# moving a weapon to another facing is work, not parts
	var mv := vd.copy() as VehicleDesign
	var other := "RR" if old_loc != "RR" else "FR"
	mv.equipment[wi] = [old_id, other]
	var qm := c.refit_quote(v.id, mv)
	print("move %s %s -> %s: min %s need %s errors %s" % [old_id, old_loc, other, qm["minutes"], qm["need"], qm["errors"]])
	check((qm["errors"] as Array).is_empty() and (qm["need"] as Dictionary).is_empty() and float(qm["minutes"]) > 0.0, "moving a weapon costs time and no parts")
	# swap the weapon for a machine gun and its ammo, and put the saved tons into armor
	var nd := vd.copy() as VehicleDesign
	nd.equipment[wi] = ["machine_gun", old_loc]
	nd.equipment.append(["machine_gun_ammo_half", "BD"])
	var rep := Construction.analyze(nd, c.year())
	var free := nd.tons - float(rep["tons_used"])
	var extra := mini(int(floor(free * VehicleConstruction.armor_ppt(nd))), VehicleConstruction.max_armor(nd) - nd.armor_total())
	extra = maxi(0, extra)
	nd.armor["FR"] = int(nd.armor["FR"]) + extra
	rep = Construction.analyze(nd, c.year())
	check(rep["valid"], "refitted vehicle is legal: " + str(rep["errors"]))
	c.warehouse.erase("item:machine_gun")
	var q := c.refit_quote(v.id, nd)
	print("swap %s -> MG, +%d armor: need %s freed %s buy %s cost %s min %s errors %s" % [old_id, extra, q["need"], q["freed"], q["buy"], q["cost"], q["minutes"], q["errors"]])
	check((q["errors"] as Array).is_empty(), "vehicle quote has no errors")
	check(int(q["need"].get("item:machine_gun", 0)) == 1 and int(q["freed"].get("item:" + old_id, 0)) == 1, "needs a machine gun, frees the old weapon")
	check(int(q["buy"].get("item:machine_gun", 0)) == 1, "the machine gun has to be bought")
	check(extra == 0 or float(q["need"].get("armor:" + nd.armor_type, 0.0)) > 0.0, "the extra armor is on the bill")
	var old0 := float(c.warehouse.get("item:" + old_id, 0.0))
	check(c.commit_refit(v.id, nd) == "", "vehicle commit")
	var c2 := MercCampaign.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	check(not (c2.units[v.id] as MercUnit).refit.is_empty(), "vehicle refit survives save and load")
	var done := -1
	for dday in 200:
		c.advance_day()
		if v.refit.is_empty():
			done = dday
			break
	print("vehicle refit done after %d days" % done)
	check(done >= 0, "vehicle refit finishes")
	check(v.design is VehicleDesign, "the unit still has a vehicle design")
	var has_mg := false
	var has_old := 0
	for e in (v.design as VehicleDesign).equipment:
		if str(e[0]) == "machine_gun" and str(e[1]) == old_loc:
			has_mg = true
	check(has_mg, "the vehicle now carries the machine gun")
	check(float(c.warehouse.get("item:" + old_id, 0.0)) == old0 + 1.0, "the old weapon went to the warehouse")
	check(int(v.design.armor["FR"]) == int(nd.armor["FR"]), "the armor is as ordered")
