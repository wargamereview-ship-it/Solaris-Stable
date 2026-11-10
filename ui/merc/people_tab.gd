extends "res://ui/merc/merc_tab.gd"
## Personnel: everyone in the company by role, skills, injuries, pay; spend XP, assign, dismiss.

static var sel := -1
static var show_gone := false

var tree: Tree
var detail: VBoxContainer


func build() -> void:
	setup_margins()
	var root := UI.vbox(8)
	add_child(root)
	var head := UI.hbox(10)
	head.add_child(UI.title("Personnel (%d people, %d heads with crews and pools)" % [c.roster().size(), c.headcount()]))
	head.add_child(UI.spacer())
	var cb := CheckBox.new()
	cb.text = "Show the dead, missing and departed"
	cb.button_pressed = show_gone
	cb.toggled.connect(func(on):
		show_gone = on
		hub.refresh())
	head.add_child(cb)
	root.add_child(head)
	root.add_child(UI.label("AsTechs: %d (techs want %d)   ·   Medics: %d   ·   Monthly payroll %s" % [c.astechs, c.active("tech").size() * int(c.rules["repair"]["astechs_per_tech"]), c.medics, UI.money(c.monthly_salaries())], 13, UI.DIM))
	var split := UI.hbox(14)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	tree = UI.tree([["Name", 3], ["Role", 2], ["Skills", 2], ["Level", -80], ["Unit", 3], ["Status", 2], ["XP", -45], ["Kills", -50], ["Salary", -80]])
	split.add_child(tree)
	var first: TreeItem = null
	var order := ["mechwarrior", "vehicle_crew", "tech", "doctor", "admin"]
	var ps := c.roster(show_gone)
	ps.sort_custom(func(a, b):
		var pa: MercPerson = a
		var pb: MercPerson = b
		if order.find(pa.role) != order.find(pb.role):
			return order.find(pa.role) < order.find(pb.role)
		return pa.last < pb.last)
	for p in ps:
		var pp: MercPerson = p
		var it := tree.create_item()
		it.set_text(0, pp.full_name())
		it.set_text(1, pp.role_label() + (" +%d" % pp.crew if pp.role == "vehicle_crew" and pp.crew > 0 else ""))
		it.set_text(2, pp.skill_str())
		it.set_text(3, pp.experience(c.rules).capitalize())
		var u: MercUnit = c.units.get(pp.unit_id)
		it.set_text(4, u.label() if u != null else "—")
		var st := MercUI.person_status(pp)
		it.set_text(5, str(st[0]))
		it.set_custom_color(5, st[1])
		it.set_text(6, str(pp.xp))
		it.set_text(7, str(pp.kills))
		it.set_text(8, UI.short_money(pp.salary(c.rules)))
		it.set_metadata(0, pp.id)
		if first == null or pp.id == sel:
			first = it
	tree.item_selected.connect(func():
		sel = int(tree.get_selected().get_metadata(0))
		_show())
	detail = UI.vbox(8)
	detail.custom_minimum_size.x = 430
	split.add_child(UI.scroll(detail))
	if first != null:
		first.select(0)


func _show() -> void:
	UI.clear(detail)
	var p: MercPerson = c.people.get(sel)
	if p == null:
		return
	var h := UI.hbox(12)
	h.add_child(MercUI.portrait(p, 90))
	var v := UI.vbox(2)
	v.add_child(UI.label(p.full_name(), 18, UI.TEXT, true))
	v.add_child(UI.label("%s  ·  %s  ·  age %d" % [p.role_label(), p.experience(c.rules).capitalize(), p.age], 13, UI.DIM))
	var st := MercUI.person_status(p)
	v.add_child(UI.label(str(st[0]) + ("  (%s)" % p.injury if p.injury != "" else ""), 14, st[1]))
	v.add_child(UI.label("Joined %s  ·  %d battles, %d kills" % [p.joined, p.battles, p.kills], 13, UI.DIM))
	v.add_child(UI.label("Salary %s a month" % UI.money(p.salary(c.rules)), 13))
	h.add_child(v)
	detail.add_child(h)
	if not p.traits.is_empty():
		var tr: Array = []
		for t in p.traits:
			tr.append("%s: %s" % [str(t).replace("_", " "), CombatMech.TRAITS.get(t, "")])
		detail.add_child(wrap_label("\n".join(tr), 13, UI.TEXT))
	var sk := section(detail, "Skills (lower is better)  ·  %d XP to spend" % p.xp)
	var skills: Array = []
	match p.role:
		"mechwarrior":
			skills = [["gunnery", "Gunnery"], ["piloting", "Piloting"]]
		"vehicle_crew":
			skills = [["gunnery", "Gunnery"], ["piloting", "Driving"]]
		"tech":
			skills = [["tech", "Tech"]]
		"doctor":
			skills = [["medical", "Medicine"]]
		"admin":
			skills = [["admin", "Administration (logistics)"], ["negotiation", "Negotiation"]]
	for s in skills:
		var row := UI.hbox(10)
		var l := UI.label("%s  %d" % [s[1], int(p.get(s[0]))], 15)
		l.custom_minimum_size.x = 240
		row.add_child(l)
		var cost := c.xp_cost(p, str(s[0]))
		var key: String = s[0]
		var b := UI.button("Improve (%d XP)" % cost if cost > 0 else "At the limit", func(): act(func(): return c.improve(p.id, key)))
		b.disabled = cost <= 0 or p.xp < cost or not p.alive()
		row.add_child(b)
		sk.add_child(row)
	if p.role == "vehicle_crew":
		sk.add_child(UI.label("Crew: the commander plus %d crewmen" % p.crew, 13, UI.DIM))
	if p.alive():
		var bh := UI.hbox(10)
		if p.unit_id >= 0:
			bh.add_child(UI.button("Unassign from unit", func(): act(func():
				c.unassign(p.id)
				return "")))
		bh.add_child(UI.button("Dismiss", func():
			UI.confirm(self, "Dismiss %s?" % p.full_name(), "They leave the company for good.", func(): act(func(): return c.dismiss(p.id)))))
		detail.add_child(bh)
