extends "res://ui/merc/merc_tab.gd"
## The Inner Sphere's news: the timeline's events, wars and worlds changing hands, newest first.
## On the right, where things stand today: the wars under way and what the times do to the trade.

static var filter := "all"

const KINDS := [["all", "Everything"], ["event", "Events"], ["war", "Wars"], ["front", "Front lines"]]


func build() -> void:
	setup_margins()
	var root := UI.hbox(14)
	add_child(root)
	var left := UI.vbox(8)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var head := UI.hbox(8)
	head.add_child(UI.title("News of the Inner Sphere"))
	head.add_child(UI.spacer())
	for k in KINDS:
		var b := UI.button(str(k[1]), func():
			filter = str(k[0])
			hub.refresh.call_deferred())
		b.toggle_mode = true
		b.button_pressed = filter == str(k[0])
		head.add_child(b)
	left.add_child(head)
	var v := UI.vbox(8)
	var shown := 0
	for i in range(c.news.size() - 1, -1, -1):
		var n: Dictionary = c.news[i]
		if filter != "all" and str(n["kind"]) != filter:
			continue
		var col := UI.BLUE
		match str(n["kind"]):
			"event":
				col = UI.ACCENT if n.get("major", false) else UI.WARN
			"war":
				col = UI.BAD
		v.add_child(UI.rich("[color=#%s][b]%s[/b][/color]   [color=#8a8f98]%s[/color]\n%s" % [col.to_html(false), n["title"], MercCampaign.date_label(int(n["day"])), n["text"]]))
		shown += 1
	if shown == 0:
		v.add_child(wrap_label("Nothing yet. News reaches the company as it happens: the timeline's events, wars breaking out and ending, and each month the worlds that changed hands.", 14))
	left.add_child(UI.scroll(v))

	var right := UI.vbox(10)
	right.custom_minimum_size.x = 470
	root.add_child(UI.scroll(right))
	right.get_parent().custom_minimum_size.x = 480
	var yf := c.year_f()
	var force := section(right, "In force today", "bolt")
	var sumry := c.timeline_summary()
	if sumry.is_empty():
		force.add_child(wrap_label("Nothing out of the ordinary: list prices, usual pay.", 13))
	for s in sumry:
		force.add_child(UI.label(str(s["title"]), 14, UI.WARN))
		force.add_child(wrap_label("%s%s" % [str(s["text"]) + "  ·  " if str(s["text"]) != "" else "", _left(int(s["left"]))], 13, UI.TEXT))
		if str(s["note"]) != "":
			force.add_child(wrap_label(str(s["note"]), 12))
	var hiring := c.hiring_outlook()
	if not (hiring["more"] as Array).is_empty():
		kv(force, "Hiring more", ", ".join(hiring["more"]), UI.GOOD)
	if not (hiring["less"] as Array).is_empty():
		kv(force, "Hiring less", ", ".join(hiring["less"]), UI.BAD)
	var wars := section(right, "Wars under way", "crosshairs")
	var list := c.sm.wars_at(yf)
	var n_shown := 0
	for w in list:
		var sides := c.war_sides(w, yf)
		if sides == "" or _clan_feud(w):
			continue
		wars.add_child(UI.label(str(w["name"]), 14, UI.BAD))
		wars.add_child(wrap_label(sides.left(1).to_upper() + sides.substr(1), 13, UI.TEXT))
		n_shown += 1
	if n_shown == 0:
		wars.add_child(wrap_label("No declared wars. Raids along the borders never stop.", 13))
	else:
		wars.add_child(wrap_label("A House at war hires more and pays %d%% over the usual against its enemy." % int(round((float(c.rules["timeline"]["war_pay"]) - 1.0) * 100.0)), 12))


## A Clan fighting itself in the homeworlds: not the Inner Sphere's news.
func _clan_feud(w: Dictionary) -> bool:
	for p in w["pairs"]:
		if str(p[0]) != str(p[1]) or c.sm.faction_kind(str(p[0])) != "CLAN":
			return false
	return true


func _left(days: int) -> String:
	if days > 730:
		return "%d more years" % int(round(days / 365.0))
	if days > 90:
		return "%d more months" % int(round(days / 30.4))
	return "%d more days" % days
