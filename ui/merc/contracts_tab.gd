extends "res://ui/merc/merc_tab.gd"
## Contracts: the current job, offers at this world (terms, negotiation, accept), and past contracts.

static var sel := -1

var detail: VBoxContainer
const CLAUSES := [["pay", "Base pay"], ["command", "Command rights"], ["salvage", "Salvage"], ["support", "Straight support"],
	["blc", "Battle loss compensation"], ["transport", "Transport"], ["advance", "Advance"], ["signing", "Signing bonus"]]


func build() -> void:
	setup_margins()
	var root := UI.hbox(14)
	add_child(root)
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 640
	root.add_child(left)
	detail = UI.vbox(8)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.scroll(detail))
	if not c.contract.is_empty():
		_current(left)
	var hall := c.hall_level()
	left.add_child(UI.title("Offers at %s (%d)" % [c.sm.name_of(c.location), c.contract_offers.size()], 18))
	if c.in_transit():
		left.add_child(wrap_label("You're in transit. New offers come up where you land.", 14, UI.DIM))
	elif hall == "":
		left.add_child(wrap_label("No hiring hall here: few employers look for mercenaries on this world. Galatea, Outreach and the other hall worlds have far more.", 13, UI.DIM))
	var tree := UI.tree([["Employer", 3], ["Mission", 3], ["Enemy", 3], ["World", 2], ["Months", -60], ["Total", -110], ["Jumps", -60]])
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tree)
	var first: TreeItem = null
	for o in c.contract_offers:
		var it := tree.create_item()
		var v := c.contract_value(o)
		it.set_text(0, str(o["employer_name"]))
		it.set_text(1, str(o["mission_label"]))
		it.set_text(2, str(o["enemy_name"]))
		it.set_text(3, str(o["system_name"]))
		it.set_text(4, str(o["months"]))
		it.set_text(5, UI.short_money(int(v["total"])))
		it.set_text(6, str(o["jumps"]))
		it.set_metadata(0, int(o["offer"]))
		if first == null or int(o["offer"]) == sel:
			first = it
	tree.item_selected.connect(func():
		sel = int(tree.get_selected().get_metadata(0))
		_show())
	if not c.history.is_empty():
		var hv := section(left, "Past contracts")
		for h in c.history:
			hv.add_child(UI.label("%s for %s on %s: %s (score %d)" % [h["mission_label"], h["employer_name"], h["system_name"], str(h["result"]).to_upper(), int(h["score"])], 13, UI.GOOD if h["result"] == "success" else (UI.BAD if h["result"] == "failure" else UI.DIM)))
	if first != null:
		first.select(0)
	else:
		detail.add_child(UI.label("No offers here right now. They refresh at the start of each month.", 14, UI.DIM))


func _current(parent: Control) -> void:
	var k := c.contract
	var v := section(parent, "Current contract: %s for %s" % [k["mission_label"], k["employer_name"]])
	var t: Dictionary = k["terms"]
	kv(v, "World", "%s  ·  enemy %s" % [k["system_name"], k["enemy_name"]])
	kv(v, "Terms", "%s command, %d%% salvage%s, %d%% support, %d%% battle loss comp., %d%% transport" % [t["command"], int(t["salvage"]), " (exchange)" if t.get("exchange", false) else "", int(t["support"]), int(t["blc"]), int(t["transport"])])
	match str(k["status"]):
		"signed":
			kv(v, "Status", "Signed: be on %s by %s" % [k["system_name"], MercCampaign.date_label(int(k["deadline_arrive"]))], UI.WARN)
			if not c.in_transit() and c.location != int(k["system"]):
				var tr := c.plan_trip(int(k["system"]))
				v.add_child(UI.button("Travel to %s (%d jumps, %d days, %s)" % [k["system_name"], int(tr.get("jumps", 0)), int(tr.get("days", 0)), UI.money(int(tr.get("cost", 0)))], func(): act(func(): return c.start_travel(int(k["system"])))))
		"active":
			kv(v, "Status", "%d days left  ·  score %d" % [int(k["end_day"]) - c.day, int(k["score"])], UI.GOOD)


func _show() -> void:
	UI.clear(detail)
	var o: Dictionary = {}
	for x in c.contract_offers:
		if int(x["offer"]) == sel:
			o = x
	if o.is_empty():
		return
	var mi: Dictionary = c.rules["missions"][o["mission"]]
	detail.add_child(UI.title("%s: %s" % [o["employer_name"], o["mission_label"]], 19))
	var info := section(detail, "The job")
	kv(info, "World", "%s (%s)" % [o["system_name"], c.sm.faction_name(c.sm.owner(int(o["system"]), c.year_f()))])
	kv(info, "Enemy", "%s, %s troops" % [o["enemy_name"], o["enemy_skill"]])
	if o.get("wartime", false):
		kv(info, "Wartime", "Employer and enemy are at war: the pay is %d%% over the usual." % int(round((float(c.rules["timeline"]["war_pay"]) - 1.0) * 100.0)), UI.WARN)
	kv(info, "Length", "%d months  ·  battle tempo x%.1f" % [int(o["months"]), float(mi["tempo"])])
	kv(info, "Lances needed", str(o["lances"]))
	kv(info, "Travel", "%d jumps, about %d days, %s in transport" % [int(o["jumps"]), int(o["travel_days"]), UI.money(int(o["travel_cost"]))])
	kv(info, "Offer expires", MercCampaign.date_label(int(o["expires"])))
	var v := c.contract_value(o)
	var terms := section(detail, "Terms")
	var t: Dictionary = o["terms"]
	var neg: Dictionary = o["negotiated"]
	for cl in CLAUSES:
		var h := UI.hbox(8)
		var kl := UI.label(cl[1], 13, UI.DIM)
		kl.custom_minimum_size.x = 190
		h.add_child(kl)
		var val := ""
		match str(cl[0]):
			"pay":
				val = "%s a month" % UI.money(int(v["monthly"]))
			"command":
				val = str(t["command"])
			"salvage":
				val = "%d%%%s" % [int(t["salvage"]), " (exchanged for cash)" if t.get("exchange", false) else ""]
			"advance":
				val = "%d%% (%s)" % [int(t["advance"]), UI.money(int(v["advance"]))]
			"signing":
				val = "%d%% (%s)" % [int(t["signing"]), UI.money(int(v["signing"]))]
			_:
				val = "%d%%" % int(t[cl[0]])
		var vl := UI.label(val, 14)
		vl.custom_minimum_size.x = 230
		h.add_child(vl)
		var odds := "%d%% chance (your best admin's negotiation)" % int(round(c.negotiation_chance() * 100))
		if neg.has(cl[0]):
			h.add_child(UI.label("agreed" if neg[cl[0]] else "refused", 12, UI.GOOD if neg[cl[0]] else UI.BAD))
		elif cl[0] == "command":
			h.add_child(UI.button("More say", func(): act(func(): return c.negotiate(int(o["offer"]), "command", "independence")), "Toward Independent: you may decline battles and fewer come up, but no allies. " + odds))
			h.add_child(UI.button("More allies", func(): act(func(): return c.negotiate(int(o["offer"]), "command", "support")), "Toward Integrated: allied troops fight beside you, and more battles come up. " + odds))
		else:
			var k: String = cl[0]
			h.add_child(UI.button("Negotiate", func(): act(func(): return c.negotiate(int(o["offer"]), k)), "Improve this clause one step; nothing else changes. One try. " + odds))
		terms.add_child(h)
	terms.add_child(UI.label("Total value %s over %d months" % [UI.money(int(v["total"])), int(o["months"])], 15, UI.ACCENT, true))
	terms.add_child(wrap_label("Negotiating a clause only ever improves it, and you get one try at each (%d%% odds with your best admin). Offers that start with generous salvage, support or transport already pay a little less. Command rights: Integrated and House bring allied troops and more battles; Liaison and Independent let you turn battles down." % int(round(c.negotiation_chance() * 100)), 12, UI.DIM))
	var busy := not c.contract.is_empty()
	var b := UI.button("  Accept the contract  ", func(): act(func():
		var e := c.accept_contract(int(o["offer"]))
		if e == "" and not c.in_transit() and c.location != int(c.contract["system"]):
			return "Signed. Use the Star Map or the Command tab to travel to %s." % c.contract["system_name"]
		return e))
	b.disabled = busy
	detail.add_child(b)
	if busy:
		detail.add_child(UI.label("Finish your current contract first.", 13, UI.WARN))
