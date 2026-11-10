extends "res://ui/merc/merc_tab.gd"
## Finances: cash, the monthly bill, recent transactions and the bank.


func build() -> void:
	setup_margins()
	var root := UI.hbox(14)
	add_child(root)
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 520
	root.add_child(left)
	var right := UI.vbox(10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	left.add_child(UI.title("Cash %s" % UI.money(c.cash)))
	var mc := section(left, "Every month")
	var costs := c.monthly_costs()
	var tot := 0
	for k in costs:
		kv(mc, k, UI.money(int(costs[k])), UI.BAD)
		tot += int(costs[k])
	kv(mc, "Total", UI.money(tot), UI.BAD)
	if c.contract_active():
		kv(mc, "Contract pay", UI.money(int(c.contract["monthly_pay"])), UI.GOOD)
		var sup := int(c.contract["terms"]["support"])
		if sup > 0:
			kv(mc, "Employer support", "%d%% of salaries and maintenance" % sup, UI.GOOD)
	kv(mc, "Transport", "%s per jump for the whole company" % UI.money(c.transport_cost_per_jump()))
	var bank := section(left, "The bank")
	var r := c.rating()
	if c.loan.is_empty():
		var mx := int(c.rules["bank"]["max_by_rating"].get(r["letter"], 2000000))
		var rate := float(c.rules["bank"]["rate_by_rating"].get(r["letter"], 0.2))
		bank.add_child(wrap_label("At your %s rating the bank lends up to %s at %d%% a year." % [r["letter"], UI.money(mx), int(rate * 100)], 13, UI.DIM))
		var h := UI.hbox(8)
		var amt := SpinBox.new()
		amt.min_value = 100000
		amt.max_value = mx
		amt.step = 100000
		amt.value = mini(mx, 1000000)
		amt.custom_minimum_size.x = 160
		h.add_child(amt)
		var months: Array = c.rules["bank"]["terms_months"]
		var labels: Array = []
		for m in months:
			labels.append("%d months" % int(m))
		var mo := UI.option(labels, 1)
		h.add_child(mo)
		h.add_child(UI.button("Take the loan", func():
			var a := int(amt.value)
			var mm := int(months[mo.selected])
			act(func(): return c.take_loan(a, mm))))
		bank.add_child(h)
	else:
		kv(bank, "Loan", "%s at %d%%: %s a month, %d months left" % [UI.money(int(c.loan["principal"])), int(float(c.loan["rate"]) * 100), UI.money(int(c.loan["monthly"])), int(c.loan["months_left"])])
	bank.add_child(wrap_label("If your debts pass %s the banks close the company." % UI.money(int(c.rules["bank"]["fold_debt"])), 12, UI.DIM))
	right.add_child(UI.title("Transactions", 16))
	var tree := UI.tree([["Date", -120], ["What", 4], ["Amount", -120]])
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(tree)
	var n := 0
	for i in range(c.ledger.size() - 1, -1, -1):
		var e: Dictionary = c.ledger[i]
		var it := tree.create_item()
		it.set_text(0, MercCampaign.date_label(int(e["day"])))
		it.set_text(1, str(e["text"]))
		it.set_text(2, UI.money(int(e["amount"])))
		it.set_custom_color(2, UI.GOOD if int(e["amount"]) >= 0 else UI.BAD)
		n += 1
		if n > 200:
			break
