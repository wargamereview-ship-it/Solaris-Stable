extends "res://ui/merc/merc_tab.gd"
## Battles: salvage to claim, battles waiting (briefing, deployment, command or auto-resolve), the record.

static var sel := -1
static var last_summary: Dictionary = {}
static var deploy: Dictionary = {}   # scenario id -> {uid: bool}

var detail: VBoxContainer


func build() -> void:
	setup_margins()
	var root := UI.hbox(14)
	add_child(root)
	var left := UI.vbox(10)
	left.custom_minimum_size.x = 420
	root.add_child(left)
	detail = UI.vbox(8)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(UI.scroll(detail))
	if not last_summary.is_empty():
		_summary_box(left)
	var pend := c.pending_scenarios()
	var lst := section(left, "Battles waiting (%d)" % pend.size())
	if pend.is_empty():
		var why := "No battles right now."
		if not c.contract_active():
			why += " Battles come up each week while you're on a contract."
		lst.add_child(wrap_label(why, 14, UI.DIM))
	for s in pend:
		var b := UI.button("%s  ·  %s  ·  by %s" % [s["label"], c.lance(int(s["lance"])).get("name", "?"), MercCampaign.date_label(int(s["deadline"]))], _pick.bind(int(s["id"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if int(s["id"]) == sel:
			b.add_theme_color_override("font_color", UI.ACCENT)
		lst.add_child(b)
	var past := section(left, "Battle record")
	var n := 0
	for i in range(c.scenarios.size() - 1, -1, -1):
		var s2: Dictionary = c.scenarios[i]
		if str(s2["status"]) == "pending":
			continue
		var col := UI.GOOD if s2["status"] == "victory" else (UI.BAD if s2["status"] in ["defeat", "missed"] else UI.DIM)
		past.add_child(UI.label("%s  %s: %s" % [MercCampaign.date_label(int(s2.get("resolved", s2["deadline"]))), s2["label"], str(s2["status"]).to_upper()], 13, col))
		n += 1
		if n > 14:
			break
	if n == 0:
		past.add_child(UI.label("No battles fought on this contract yet.", 13, UI.DIM))
	if not c.salvage.is_empty():
		_salvage_panel()
		return
	var found := false
	for s3 in pend:
		if int(s3["id"]) == sel:
			found = true
	if not found and not pend.is_empty():
		sel = int(pend[0]["id"])
	if not pend.is_empty():
		_briefing()


func _pick(sid: int) -> void:
	sel = sid
	hub.refresh()


func _summary_box(parent: Control) -> void:
	var s := last_summary
	var v := section(parent, "Last battle: " + str(s.get("outcome", "")).to_upper())
	v.add_child(UI.label("%s  ·  %s" % [str(s.get("how", "")).capitalize(), "you hold the field" if s.get("held", false) else "you lost the field"], 13, UI.DIM))
	for line in s.get("units", []):
		v.add_child(wrap_label(str(line), 13, UI.TEXT))
	for line in s.get("people", []):
		v.add_child(wrap_label(str(line), 13, UI.BAD if str(line).find("KILLED") >= 0 or str(line).find("missing") >= 0 else UI.DIM))
	for line in s.get("money", []):
		v.add_child(UI.label(str(line), 13, UI.GOOD))
	if int(s.get("score", 0)) != 0:
		v.add_child(UI.label("Contract score %+d" % int(s["score"]), 13, UI.GOOD if int(s["score"]) > 0 else UI.BAD))
	v.add_child(UI.button("Dismiss", func():
		last_summary = {}
		hub.refresh()))


func _salvage_panel() -> void:
	UI.clear(detail)
	detail.add_child(UI.title("Salvage"))
	var tv := 0
	for s in c.salvage:
		tv += int(s["value"])
	var pct := int(c.contract.get("terms", {}).get("salvage", 0))
	var allowance := int(tv * pct / 100.0)
	detail.add_child(wrap_label("You hold the field. Your contract gives you %d%% of the salvage: up to %s of the %s on the field. The employer takes the rest. Wrecks can only be stripped for parts." % [pct, UI.money(allowance), UI.money(tv)], 14, UI.TEXT))
	var picks := {}
	for i in c.auto_salvage_picks():
		picks[int(i)] = true
	var used_lbl := UI.label("", 14, UI.ACCENT)
	var boxes: Array = []
	var update := func():
		var used := 0
		for k in boxes.size():
			if (boxes[k] as CheckBox).button_pressed:
				used += int(c.salvage[k]["value"])
		used_lbl.text = "Claimed %s of %s" % [UI.money(used), UI.money(allowance)]
		used_lbl.add_theme_color_override("font_color", UI.BAD if used > allowance else UI.ACCENT)
	for i in c.salvage.size():
		var s2: Dictionary = c.salvage[i]
		var h := UI.hbox(10)
		var cb := CheckBox.new()
		cb.button_pressed = picks.has(i)
		cb.toggled.connect(func(_on): update.call())
		boxes.append(cb)
		h.add_child(cb)
		var d := MercCampaign.db_design(str(s2["design"]))
		h.add_child(Views.sprite(d.sprite, Game.tint_material(Color(0.5, 0.5, 0.5)), 54))
		var v := UI.vbox(0)
		v.add_child(UI.label("%s%s" % [s2["name"], "  (WRECK)" if s2["wreck"] else ""], 15, UI.BAD if s2["wreck"] else UI.TEXT, true))
		var tmp := MercUnit.new()
		tmp.design = d
		tmp.condition = s2["condition"]
		v.add_child(UI.label("%d tons  ·  %d%% damaged  ·  worth %s" % [d.tons, int(tmp.damage_fraction() * 100), UI.money(int(s2["value"]))], 13, UI.DIM))
		h.add_child(v)
		detail.add_child(h)
	detail.add_child(used_lbl)
	update.call()
	var bh := UI.hbox(10)
	bh.add_child(UI.button("Claim selected", func():
		var chosen: Array = []
		for k in boxes.size():
			if (boxes[k] as CheckBox).button_pressed:
				chosen.append(k)
		act(func(): return c.claim_salvage(chosen))))
	bh.add_child(UI.button("Leave it all", func(): act(func(): return c.claim_salvage([]))))
	detail.add_child(bh)


func _briefing() -> void:
	UI.clear(detail)
	var s := c.scenario(sel)
	if s.is_empty():
		return
	var O: Dictionary = c.rules["operations"]
	detail.add_child(UI.title(str(s["label"])))
	detail.add_child(wrap_label(str(s["desc"]), 15, UI.TEXT))
	var info := section(detail, "Briefing")
	var th: Dictionary = c.db.arenas["themes"].get(str(s["biome"]), {})
	kv(info, "Where", "%s, %s" % [c.contract.get("system_name", ""), str(th.get("label", s["biome"])).to_lower()])
	kv(info, "Enemy", "%s, %s troops" % [c.contract.get("enemy_name", "?"), str(c.contract.get("enemy_skill", "regular"))])
	kv(info, "Deadline", "%s (%d days)" % [MercCampaign.date_label(int(s["deadline"])), int(s["deadline"]) - c.day], UI.WARN if int(s["deadline"]) - c.day <= 1 else UI.TEXT)
	kv(info, "Command rights", "%s: allied troops %s" % [c.contract.get("terms", {}).get("command", "?"), "likely" if float(O["ally_chance"].get(str(c.contract.get("terms", {}).get("command", "")), 0.0)) >= 0.4 else "unlikely"])
	kv(info, "Time limit", "%d minutes" % int(float(O["scenarios"][s["type"]]["time_limit"]) / 60.0))
	var sup: Dictionary = c.battle_support(s)["player"]
	var parts: Array = []
	if int(sup["artillery"]) > 0:
		parts.append("%d artillery fire mission%s" % [int(sup["artillery"]), "s" if int(sup["artillery"]) > 1 else ""])
	if int(sup["air_strike"]) > 0:
		parts.append("%d air strike%s" % [int(sup["air_strike"]), "s" if int(sup["air_strike"]) > 1 else ""])
	kv(info, "Support", ", ".join(parts) if not parts.is_empty() else "none: you fight with what you bring", UI.GOOD if not parts.is_empty() else UI.DIM)
	var ech := float(O["support"]["enemy_chance"].get(str(s["type"]), 0.0))
	var ekinds: Array = O["support"]["enemy_kinds"].get(StarMap.get_map().faction_kind(str(c.contract.get("enemy", "PIR"))), O["support"]["enemy_kinds"]["DEFAULT"])
	if ech > 0.0 and not ekinds.is_empty():
		kv(info, "Enemy support", "%s (%s)" % ["likely" if ech >= 0.45 else "possible", " and ".join(ekinds).replace("_", " ")], UI.WARN)
	var dep := section(detail, "Deploy")
	if not deploy.has(sel):
		var dd := {}
		for uid in c.default_deployment(s):
			dd[int(uid)] = true
		deploy[sel] = dd
	var chosen: Dictionary = deploy[sel]
	var total_bv := 0
	for u in c.combat_units():
		var uu: MercUnit = u
		var h := UI.hbox(8)
		var cb := CheckBox.new()
		var ok := c.deployable(uu) and not c._deployed_elsewhere(uu.id, sel)
		cb.button_pressed = chosen.get(uu.id, false) and ok
		cb.disabled = not ok
		cb.toggled.connect(func(on):
			chosen[uu.id] = on)
		h.add_child(cb)
		var st := MercUI.unit_status(c, uu)
		var p := c.crew_of(uu)
		var l := Views.mono_label("%-32s  %s" % [uu.label().left(32), p.short_name() + " " + p.skill_str() if p != null else "no crew"], 13)
		l.custom_minimum_size.x = 470
		h.add_child(l)
		h.add_child(UI.label(str(st[0]), 13, st[1]))
		h.add_child(UI.label("BV %d" % uu.bv(), 12, UI.DIM))
		h.add_child(UI.label(str(c.lance(uu.lance).get("name", "")), 12, UI.DIM))
		dep.add_child(h)
		if cb.button_pressed:
			total_bv += uu.bv()
	dep.add_child(UI.label("Selected force: about %d BV. The enemy will bring a force sized to what you deploy." % total_bv, 13, UI.DIM))
	var bh := UI.hbox(12)
	bh.add_child(UI.button("  Command the battle  ", func(): _launch(true), "Fight it yourself in real time: pause, select units, give orders"))
	bh.add_child(UI.button("Auto-resolve", func(): _launch(false), "The AI fights the battle for you, going for the objective"))
	if c.can_decline():
		var pen := int(c.rules["terms"]["decline_score"][str(c.contract["terms"]["command"])])
		var sid := sel
		bh.add_child(UI.button("Decline", func(): act(func(): return c.decline_battle(sid)), "Your %s command rights let you turn this down (contract score %+d)" % [c.contract["terms"]["command"], pen]))
	detail.add_child(bh)
	detail.add_child(wrap_label("Commanding: Space pauses. Click or drag to select your units, number keys pick a lance. Right-click the ground to move, an enemy to attack, a building to shell it. Units ordered off a map edge they may leave (your own, or the breakthrough edge) withdraw from the battle.", 13, UI.DIM))


func _uids() -> Array:
	var out: Array = []
	var chosen: Dictionary = deploy.get(sel, {})
	for uid in chosen:
		if chosen[uid] and c.units.has(int(uid)) and c.deployable(c.units[int(uid)]):
			out.append(int(uid))
	return out


func _launch(live: bool) -> void:
	var uids := _uids()
	if uids.is_empty():
		hub.flash("Pick at least one unit to deploy.")
		return
	var sid := sel
	deploy.erase(sid)
	if live:
		Game.watch_merc_battle.call_deferred(sid, uids)
		return
	last_summary = c.auto_resolve(sid, uids, false)
	Game.save_game("merc_autosave")
	hub.refresh.call_deferred()
