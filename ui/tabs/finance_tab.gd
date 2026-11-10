extends MarginContainer
## Weekly ledger for the last few months.

var hub
var c: Campaign


func build() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	var root := UI.vbox(8)
	add_child(root)
	var p := c.player()
	root.add_child(UI.title("Finances — %s on hand" % UI.money(p.cash)))
	var weeks: Array = p.ledger.slice(-10)
	var cats := {}
	for l in weeks:
		for k in l["lines"]:
			cats[k] = true
	for k in p.week_lines:
		cats[k] = true
	var cols: Array = [["Category", 3]]
	for l in weeks:
		cols.append(["Wk %d" % int(l["week"]), -90])
	cols.append(["This week", -95])
	var t := UI.tree(cols)
	var names: Array = cats.keys()
	names.sort()
	var totals := []
	totals.resize(weeks.size() + 1)
	totals.fill(0)
	for k in names:
		var it := t.create_item()
		it.set_text(0, k)
		for i in weeks.size():
			var v := int(weeks[i]["lines"].get(k, 0))
			totals[i] += v
			it.set_text(i + 1, UI.short_money(v) if v != 0 else "")
			it.set_custom_color(i + 1, UI.GOOD if v > 0 else UI.BAD)
		var cur := int(p.week_lines.get(k, 0))
		totals[weeks.size()] += cur
		it.set_text(weeks.size() + 1, UI.short_money(cur) if cur != 0 else "")
		it.set_custom_color(weeks.size() + 1, UI.GOOD if cur > 0 else UI.BAD)
	var tot := t.create_item()
	tot.set_text(0, "NET")
	for i in totals.size():
		tot.set_text(i + 1, UI.short_money(int(totals[i])))
		tot.set_custom_color(i + 1, UI.GOOD if int(totals[i]) >= 0 else UI.BAD)
	root.add_child(t)
	var sal := 0
	for wid in p.warriors:
		sal += c.warriors[wid].salary
	var fixed := sal + p.techs * int(c.rules["tech_salary_week"]) + p.bays * int(c.rules["bay_upkeep_week"])
	var info := UI.label("Fixed costs about %s a week (salaries %s, techs, bays, medical, simulators, 'Mech upkeep). Sponsors and merchandise grow with stable fame; purses are the main income." % [UI.money(fixed), UI.money(sal)], 13, UI.DIM)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(info)
