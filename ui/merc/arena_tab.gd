extends "res://ui/merc/merc_tab.gd"
## Solaris VII: while the company is on the Game World and not serving a contract, the promoters offer
## duels. Pick a 'Mech and its MechWarrior, give the corner orders, then watch the fight or take the result.

static var sel := -1
static var entrant := -1
static var orders := {"range": 1, "heat": 1, "position": 0, "retreat": 2}
static var last_summary: Dictionary = {}

const RANGE := ["close", "optimal", "long"]
const HEAT := ["cool", "balanced", "hot"]
const POS := ["cover", "flank", "brawl"]
const RETREAT := [0.35, 0.45, 0.55, 0.7, 0.9]
const RETREAT_L := ["Early (35%)", "Cautious (45%)", "Normal (55%)", "Stubborn (70%)", "Never (90%)"]

var detail: VBoxContainer


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
	left.add_child(UI.title("Solaris VII: the arenas", 18))
	if not last_summary.is_empty():
		_summary_box(left)
	if not c.arena_open():
		_closed(left)
		_record(left)
		return
	var tree := UI.tree([["Class", -80], ["Arena", 3], ["Opponent", 3], ["'Mech", 3], ["Skill", -60], ["Purse", -90]])
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tree)
	var first: TreeItem = null
	for o in c.arena_offers:
		var od: Dictionary = o["opp"]
		var it := tree.create_item()
		it.set_text(0, str(o["class"]).capitalize())
		it.set_text(1, str(o["arena_name"]))
		it.set_text(2, str(od["name"]))
		it.set_text(3, MercCampaign.db_design(str(od["design"])).display_name())
		it.set_text(4, "%d/%d" % [int(od["gunnery"]), int(od["piloting"])])
		it.set_custom_color(4, UI.skill_color(int(od["gunnery"])))
		it.set_text(5, UI.short_money(int(o["purse"])))
		if c.arena_entrants(o).is_empty():
			for col in 6:
				it.set_custom_color(col, UI.DIM)
		it.set_metadata(0, int(o["id"]))
		if first == null or int(o["id"]) == sel:
			first = it
	tree.item_selected.connect(func():
		sel = int(tree.get_selected().get_metadata(0))
		_show())
	left.add_child(wrap_label("The promoters post a new card every Monday. A walk-on company fights for a share of the purse only: %d%% to the winner. Damage is yours to repair, and a duel ends when a 'Mech is out or its MechWarrior yields." % int(float(c.rules["solaris"]["winner_share"]) * 100), 13, UI.DIM))
	_record(left)
	if first != null:
		first.select(0)
	else:
		detail.add_child(wrap_label("No bouts left on this week's card. The next one goes up on Monday.", 14, UI.DIM))


## Why there is nothing to fight, and how to change that.
func _closed(parent: Control) -> void:
	var v := section(parent, "The arenas are closed to you")
	if c.contract_active():
		v.add_child(wrap_label("The company is under contract%s. The promoters only book mercenaries who are free: come back between contracts." % (" on " + str(c.contract.get("system_name", "")) if c.contract.has("system_name") else ""), 14, UI.WARN))
		return
	if c.in_transit():
		var to := int(c.travel["dest"])
		v.add_child(wrap_label("In transit to %s, %d days out.%s" % [c.sm.name_of(to), int(c.travel["days_left"]), " The fight card goes up when you land." if to == c.solaris() else ""], 14, UI.DIM))
		return
	v.add_child(wrap_label("The Game World's arenas book any MechWarrior who turns up with a 'Mech. Between contracts a company can fight duels there for prize money: no employer, no salvage, just the purse and the repair bill.", 14, UI.DIM))
	var tr := c.plan_trip(c.solaris())
	if not tr.get("ok", false):
		v.add_child(UI.label("No jump route to Solaris from here.", 13, UI.BAD))
		return
	kv(v, "From here", "%d jumps, about %d days, %s" % [int(tr["jumps"]), int(tr["days"]), UI.money(int(tr["cost"]))])
	v.add_child(UI.primary(UI.ibutton("rocket", "Travel to Solaris VII", func(): act(func(): return c.start_travel(c.solaris())))))


func _record(parent: Control) -> void:
	var fights := int(c.stats.get("arena_fights", 0))
	if fights == 0:
		return
	var v := section(parent, "Arena record")
	var wins := int(c.stats.get("arena_wins", 0))
	v.add_child(UI.label("%d fight%s, %d won" % [fights, "" if fights == 1 else "s", wins], 14))
	var n := 0
	for i in range(c.log.size() - 1, -1, -1):
		if str(c.log[i]["kind"]) != "arena":
			continue
		v.add_child(wrap_label("%s  %s" % [MercCampaign.date_label(int(c.log[i]["day"])), c.log[i]["text"]], 12, UI.DIM))
		n += 1
		if n >= 5:
			break


func _summary_box(parent: Control) -> void:
	var s := last_summary
	var head := "DRAW" if s.get("draw", false) else ("VICTORY" if s.get("won", false) else "DEFEAT")
	var v := section(parent, "Last bout: %s at %s" % [head, s.get("arena", "")])
	v.add_child(UI.label("Against %s  ·  %s" % [s.get("opponent", ""), str(s.get("how", "")).capitalize()], 13, UI.DIM))
	for line in s.get("lines", []):
		v.add_child(wrap_label(str(line), 13, UI.BAD if str(line).find("KILLED") >= 0 or str(line).find("wreck") >= 0 else UI.TEXT))
	v.add_child(UI.label("Purse: %s" % UI.money(int(s.get("purse", 0))), 13, UI.GOOD))
	v.add_child(UI.button("Dismiss", func():
		last_summary = {}
		hub.refresh()))


func _show() -> void:
	UI.clear(detail)
	var o := c.arena_offer(sel)
	if o.is_empty():
		return
	var od: Dictionary = o["opp"]
	var col: Array = od["color"]
	var opp_col := Color.from_hsv(float(col[0]), float(col[1]), float(col[2]))
	var purses := c.arena_purses(o)
	var info := section(detail, "%s duel at %s" % [str(o["class"]).capitalize(), o["arena_name"]])
	var theme_label := str(c.db.arenas["themes"].get(o["theme"], {}).get("label", o["theme"]))
	kv(info, "Arena", "%s%s  ·  %s" % [theme_label, ", " + str(o["sector"]) if str(o["sector"]) != "" else "", Campaign.conditions_label(o["conditions"])])
	kv(info, "Purse", "%s to the winner, %s to the loser" % [UI.money(purses[0]), UI.money(purses[1])], UI.ACCENT)
	kv(info, "Opponent", "%s of the %s  ·  gunnery %d, piloting %d  ·  a %s" % [od["name"], od["stable"], int(od["gunnery"]), int(od["piloting"]), MercCampaign.ARENA_STYLES[int(od["style"])][0]])
	detail.add_child(UI.panel(MercUI.sheet(MercCampaign.db_design(str(od["design"])), {}, Game.tint_material(opp_col), c.year())))
	var mine := section(detail, "Your corner")
	var ids := c.arena_entrants(o)
	if ids.is_empty():
		mine.add_child(wrap_label("No %s 'Mech of yours is fit to fight with a MechWarrior aboard." % o["class"], 14, UI.WARN))
		return
	if not (entrant in ids):
		entrant = int(ids[0])
	var labels: Array = []
	for uid in ids:
		var u: MercUnit = c.units[uid]
		var p := c.crew_of(u)
		labels.append("%s  ·  %s (%d/%d)%s" % [u.label(), p.short_name(), p.gunnery, p.piloting, "  ·  %d%% damaged" % int(u.damage_fraction() * 100) if u.damaged() else ""])
	var pick := UI.option(labels, ids.find(entrant))
	pick.item_selected.connect(func(i):
		entrant = int(ids[i])
		_show.call_deferred())
	mine.add_child(pick)
	var eu: MercUnit = c.units[entrant]
	mine.add_child(MercUI.sheet(eu.design, eu.condition, Game.tint_material(c.color, c.camo), c.year()))
	if eu.damaged():
		var worn := _yield_score(eu)
		if worn >= float(RETREAT[orders["retreat"]]):
			mine.add_child(wrap_label("This 'Mech is already hurt badly enough that %s would yield at the opening bell with these orders. Repair it first, or order a later yield." % c.crew_of(eu).short_name(), 13, UI.BAD))
		else:
			mine.add_child(wrap_label("This 'Mech goes in as it stands, damage and all.", 13, UI.WARN))
	if not eu.refit.is_empty():
		mine.add_child(wrap_label("It has a refit on order; the techs wait until the fight is over.", 13, UI.DIM))
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 10)
	g.add_theme_constant_override("v_separation", 6)
	g.add_child(UI.label("Range"))
	g.add_child(_order_opt("range", ["Close in", "Best for loadout", "Long range"]))
	g.add_child(UI.label("Heat"))
	g.add_child(_order_opt("heat", ["Run cool", "Balanced", "Run hot"]))
	g.add_child(UI.label("Positioning"))
	g.add_child(_order_opt("position", ["Use cover", "Flank for rear shots", "Stand and brawl"]))
	g.add_child(UI.label("Yield when"))
	g.add_child(_order_opt("retreat", RETREAT_L))
	mine.add_child(g)
	var bh := UI.hbox(10)
	bh.add_child(UI.primary(UI.ibutton("eye", "Watch the fight", func(): Game.watch_merc_bout(int(o["id"]), entrant, orders_dict()),
		"The duel runs live. You get three corner calls to change the orders.")))
	bh.add_child(UI.ibutton("forward", "Take the result", func():
		var oid := int(o["id"])
		var uid := entrant
		act(func():
			last_summary = c.arena_auto(oid, uid, orders_dict())
			return "")))
	mine.add_child(bh)


func _order_opt(key: String, items: Array) -> OptionButton:
	var ob := UI.option(items, int(orders[key]))
	ob.item_selected.connect(func(i):
		orders[key] = i
		if key == "retreat":
			_show.call_deferred())
	return ob


## How close a damaged 'Mech already is to the point where its MechWarrior yields (the duel AI's own measure).
func _yield_score(u: MercUnit) -> float:
	var ipts: Dictionary = Construction.internal_points(u.design.tons)
	var ci: Dictionary = u.condition.get("internal", {})
	var ca: Dictionary = u.condition.get("armor", {})
	var lost := 0.0
	var tot := 0.0
	var legs := 0
	for loc in ipts:
		var mx := float(ipts[loc])
		tot += mx
		lost += mx - float(ci.get(loc, mx))
		if loc in ["LL", "RL"] and float(ci.get(loc, mx)) <= 0.0:
			legs += 1
	var ct := float(ipts.get("CT", 1))
	var score := lost / maxf(1.0, tot) + (1.0 - float(ci.get("CT", ct)) / ct) * 0.7
	if not ca.is_empty() and float(ca.get("CT", 99)) + float(ca.get("CTR", 99)) <= 4.0:
		score += 0.15
	if legs > 0:
		score += 0.3
	return score


static func orders_dict() -> Dictionary:
	return {"range": RANGE[orders["range"]], "heat": HEAT[orders["heat"]], "position": POS[orders["position"]],
		"retreat": RETREAT[orders["retreat"]], "focus": "focus"}
