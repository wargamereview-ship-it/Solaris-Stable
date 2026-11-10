extends MarginContainer
## Mercenary work: House agents and brokers on Solaris hire a stable's 'Mechs for short jobs off-world.
## Pick the fighters, send them, and they come back some weeks later as the battle left them.

var hub
var c: Campaign
var detail: VBoxContainer
static var sel := -1
static var picked: Dictionary = {}   # warrior id -> true


func build() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	var root := UI.hbox(14)
	add_child(root)
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 640
	root.add_child(left)
	detail = UI.vbox(8)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.scroll(detail))
	left.add_child(UI.title("Mercenary work"))
	left.add_child(_wrap("Between arena seasons a stable's 'Mechs are still 'Mechs. House agents and mercenary brokers on Solaris pay well for a few of them on a short job off-world. The fighters miss the fight card while they are gone, and the battle is fought without you.", 13, UI.DIM))
	if not c.deployment.is_empty():
		_deployment_box(left)
	if not c.last_deployment.is_empty():
		_last_box(left)
	if not c.deployment.is_empty():
		detail.add_child(_wrap("Your fighters are off-world. New offers come once they are back.", 14, UI.DIM))
		return
	var tree := UI.tree([["Job", 3], ["Employer", 3], ["World", 2], ["Against", 3], ["Weeks", -55], ["'Mechs", -60], ["Risk", -70]])
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tree)
	var first: TreeItem = null
	for j in c.merc_jobs:
		var it := tree.create_item()
		it.set_text(0, str(j["label"]))
		it.set_text(1, str(j["employer_name"]))
		it.set_text(2, str(j["world"]))
		it.set_text(3, str(j["enemy_name"]).capitalize() if str(j["enemy"]) == "PIR" else str(j["enemy_name"]))
		it.set_text(4, str(int(j["weeks"])))
		it.set_text(5, "up to %d" % int(j["slots"]))
		var risk := _risk(j)
		it.set_text(6, str(risk[0]))
		it.set_custom_color(6, risk[1])
		it.set_metadata(0, int(j["id"]))
		if first == null or int(j["id"]) == sel:
			first = it
	tree.item_selected.connect(func():
		var id := int(tree.get_selected().get_metadata(0))
		if id != sel:
			picked = {}
		sel = id
		_show())
	if first != null:
		first.select(0)
	else:
		detail.add_child(_wrap("Nobody is hiring this week. Offers change every week.", 14, UI.DIM))


func _risk(j: Dictionary) -> Array:
	var d := float(j["danger"]) * (1.15 if int(j["skill"][0]) <= 3 else 1.0)
	if d < 0.8:
		return ["Low", UI.GOOD]
	if d < 1.0:
		return ["Fair", UI.WARN]
	return ["High", UI.BAD]


func _deployment_box(parent: Control) -> void:
	var d := c.deployment
	var j: Dictionary = d["job"]
	var v := _section(parent, "Off-world now: %s on %s" % [j["label"], j["world"]])
	var names: Array = []
	for e in d["entries"]:
		var w: Warrior = c.warriors.get(int(e["warrior"]))
		var om: OwnedMech = c.mechs.get(int(e["mech"]))
		if w != null and om != null:
			names.append("%s (%s)" % [w.short_name(), om.design.display_name()])
	v.add_child(_wrap(", ".join(names), 14, UI.TEXT))
	var wl := int(d["weeks_left"])
	v.add_child(UI.label("For the %s against %s  ·  back in %d week%s" % [j["employer_name"], j["enemy_name"], wl, "" if wl == 1 else "s"], 13, UI.DIM))
	v.add_child(UI.label("%s paid in advance, %s on return, %s more for a victory" % [UI.money(int(d["paid"])), UI.money(int(d["fee"]) - int(d["paid"])), UI.money(int(d["bonus"]))], 13, UI.GOOD))


func _last_box(parent: Control) -> void:
	var s := c.last_deployment
	var v := _section(parent, "Last job: %s on %s" % [str(s.get("outcome", "")), s.get("world", "")])
	v.add_child(UI.label("%s for the %s against %s  ·  week %d, %d" % [s.get("label", ""), s.get("employer", ""), s.get("enemy", ""), int(s.get("w", 0)), int(s.get("y", 0))], 13, UI.DIM))
	for line in s.get("lines", []):
		var bad := str(line).find("killed") >= 0 or str(line).find("lost") >= 0 or str(line).find("wreck") >= 0
		v.add_child(_wrap(str(line), 13, UI.BAD if bad else UI.TEXT))
	v.add_child(UI.label("Paid in all: %s" % UI.money(int(s.get("pay", 0))), 13, UI.GOOD))


func _show() -> void:
	UI.clear(detail)
	var j := c.merc_job(sel)
	if j.is_empty():
		return
	var info := _section(detail, "%s on %s" % [j["label"], j["world"]])
	info.add_child(_wrap(str(j["desc"]), 14, UI.TEXT))
	_kv(info, "Employer", str(j["employer_name"]))
	_kv(info, "Opposition", "%s, %s crews, about %d%% of your strength" % [j["enemy_name"], "veteran" if int(j["skill"][0]) <= 3 else "regular", int(float(j["danger"]) * 100)])
	_kv(info, "Away for", "%d weeks: no arena fights, no repairs or refits on those 'Mechs" % int(j["weeks"]))
	_kv(info, "Rate", "%s C-bills per point of Battle Value a week" % str(int(j["rate"])), UI.ACCENT)
	var mine := _section(detail, "Who goes (up to %d)" % int(j["slots"]))
	var ok := c.job_candidates(j)
	for wid in picked.keys():
		if not (int(wid) in ok):
			picked.erase(wid)
	if ok.is_empty():
		mine.add_child(_wrap("Nobody can go: a MechWarrior needs to be fit, have a ready 'Mech, no bout booked this week and more than %d weeks left on their contract." % int(j["weeks"]), 14, UI.WARN))
		return
	for wid in ok:
		var w: Warrior = c.warriors[wid]
		var om := c.warrior_mech(w)
		var cb := CheckBox.new()
		cb.text = "%s  [%s]   %s, %dt, BV %d%s" % [w.full_name(), w.skill_str(), om.design.display_name(), om.design.tons, Campaign._bv(om),
			"  ·  %d%% damaged" % int(om.damage_fraction() * 100) if om.is_damaged() else ""]
		cb.button_pressed = picked.has(wid)
		cb.disabled = not picked.has(wid) and picked.size() >= int(j["slots"])
		cb.toggled.connect(func(on):
			if on:
				picked[wid] = true
			else:
				picked.erase(wid)
			_show.call_deferred())
		mine.add_child(cb)
	var pay := c.job_pay(j, picked.keys())
	var tot := _section(detail, "The contract")
	if picked.is_empty():
		tot.add_child(_wrap("Tick the MechWarriors to send. The fee follows the Battle Value of their 'Mechs.", 14, UI.DIM))
		return
	_kv(tot, "Force", "%d 'Mech%s, Battle Value %d" % [picked.size(), "" if picked.size() == 1 else "s", int(pay["bv"])])
	_kv(tot, "Fee", "%s: %s now, %s when they come home" % [UI.money(int(pay["fee"])), UI.money(int(pay["advance"])), UI.money(int(pay["fee"]) - int(pay["advance"]))], UI.GOOD)
	_kv(tot, "If they win", "%s on top" % UI.money(int(pay["bonus"])), UI.GOOD)
	_kv(tot, "If they lose", "Half the rest is docked, and a 'Mech that goes down on a lost field stays there", UI.WARN)
	var jid := int(j["id"])
	tot.add_child(UI.primary(UI.ibutton("rocket", "Sign and ship out", func():
		var e := c.hire_out(jid, picked.keys())
		if e != "":
			UI.popup(hub, "Mercenary work", e)
		else:
			picked = {}
			Game.save_game("autosave")
		hub.refresh())))


func _section(parent: Control, title: String) -> VBoxContainer:
	var v := UI.vbox(7)
	parent.add_child(UI.panel(v))
	v.add_child(UI.header(title))
	return v


func _kv(parent: Control, k: String, v: String, col := UI.TEXT) -> void:
	var h := UI.hbox(8)
	var kl := UI.label(k.to_upper(), 12, UI.DIM)
	kl.add_theme_font_override("font", UI.spaced("cond_semi", 1))
	kl.custom_minimum_size.x = 130
	h.add_child(kl)
	var vl := _wrap(v, 14, col)
	h.add_child(vl)
	parent.add_child(h)


func _wrap(text: String, size := 13, col := UI.DIM) -> Label:
	var l := UI.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l
