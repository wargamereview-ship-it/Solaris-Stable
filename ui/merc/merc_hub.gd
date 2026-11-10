extends Control
## The company office: top bar (date, location, C-bills, rating), navigation, the current tab, and the
## time controls (advance a day, or run to the next event).

const TABS := [
	["command", "Command", "res://ui/merc/command_tab.gd", "crosshairs"],
	["ops", "Battles", "res://ui/merc/ops_tab.gd", "bomb"],
	["contracts", "Contracts", "res://ui/merc/contracts_tab.gd", "handshake"],
	["arena", "Solaris Arenas", "res://ui/merc/arena_tab.gd", "trophy"],
	["map", "Star Map", "res://ui/merc/map_tab.gd", "globe"],
	["toe", "Lances (TO&E)", "res://ui/merc/toe_tab.gd", "sitemap"],
	["people", "Personnel", "res://ui/merc/people_tab.gd", "users"],
	["hangar", "Hangar", "res://ui/merc/hangar_tab.gd", "wrench"],
	["logistics", "Parts & Supply", "res://ui/merc/logistics_tab.gd", "cubes"],
	["market", "Market", "res://ui/merc/market_tab.gd", "cart"],
	["money", "Finances", "res://ui/merc/money_tab.gd", "line_chart"],
	["news", "News", "res://ui/merc/news_tab.gd", "news"],
	["log", "Log", "res://ui/merc/log_tab.gd", "list"],
]
const Emblem := preload("res://ui/widgets/emblem.gd")

var c: MercCampaign
var top: HBoxContainer
var content: PanelContainer
var nav: VBoxContainer
var status: Label
var day_btn: Button
var run_btn: Button
var current := ""
var _pending_tab := ""


func _ready() -> void:
	c = Game.merc
	add_child(UI.backdrop())
	var root := UI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var topp := PanelContainer.new()
	topp.add_theme_stylebox_override("panel", UI.bar_box(true))
	top = UI.hbox(26)
	topp.add_child(top)
	root.add_child(topp)
	var mid := UI.hbox(0)
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var navp := PanelContainer.new()
	var nsb := UI.box(Color(0.025, 0.033, 0.043, 0.88), 0)
	nsb.border_width_right = 1
	nsb.border_color = UI.LINE
	nsb.content_margin_left = 0
	nsb.content_margin_right = 0
	nsb.content_margin_top = 14
	navp.add_theme_stylebox_override("panel", nsb)
	nav = UI.vbox(2)
	nav.custom_minimum_size.x = 210
	navp.add_child(nav)
	mid.add_child(navp)
	content = PanelContainer.new()
	content.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(content)
	var bot := PanelContainer.new()
	bot.add_theme_stylebox_override("panel", UI.bar_box(false))
	var bh := UI.hbox(10)
	status = UI.label("", 14, UI.DIM)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.clip_text = true
	bh.add_child(status)
	bh.add_child(UI.ibutton("save", "Save", func():
		Game.save_game("merc_autosave")
		Game.save_game("merc_%s_%d_%02d" % [c.name.to_snake_case().left(16), c.year(), c.month()])
		flash("Saved.")))
	bh.add_child(UI.ibutton("sign_out", "Main menu", func():
		Game.save_game("merc_autosave")
		Game.show_menu()))
	day_btn = UI.ibutton("step", "Next day", _advance_day, "Advance one day")
	bh.add_child(day_btn)
	run_btn = UI.primary(UI.ibutton("forward", "Advance to next event", _advance_event, "Run day by day until something needs you"))
	run_btn.add_theme_font_size_override("font_size", 16)
	bh.add_child(run_btn)
	bot.add_child(bh)
	root.add_child(bot)
	for t in TABS:
		var b := UI.nav_button(t[3], t[1], show_tab.bind(t[0]))
		b.set_meta("tab", t[0])
		b.set_meta("label", t[1])
		b.set_meta("icon", t[3])
		nav.add_child(b)
	nav.add_child(UI.spacer(false))
	var foot := UI.label("  %s  MERCENARY COMPANY" % UI.ic("shield"), 11, UI.DIM)
	foot.add_theme_font_override("font", UI.spaced("cond_semi", 2))
	nav.add_child(foot)
	show_tab(Game.merc_tab)


func refresh() -> void:
	show_tab(current)


func _build_top() -> void:
	UI.clear(top)
	var id := UI.hbox(12)
	id.add_child(Emblem.new(c.color, c.name, 46))
	var nv := UI.vbox(-2)
	var nm := UI.label(c.name.to_upper(), 22, UI.TEXT)
	nm.add_theme_font_override("font", UI.spaced("cond", 2))
	nv.add_child(nm)
	var where := "%s  %s" % [UI.ic("globe"), c.sm.name_of(c.location)]
	if c.in_transit():
		where = "%s  In transit to %s, %d days" % [UI.ic("rocket"), c.sm.name_of(int(c.travel["dest"])), int(c.travel["days_left"])]
	nv.add_child(UI.label(where, 13, UI.DIM))
	id.add_child(nv)
	top.add_child(id)
	top.add_child(UI.spacer())
	top.add_child(UI.stat("Date", c.date_str(), UI.TEXT, "calendar"))
	top.add_child(UI.stat("C-bills", UI.money(c.cash), UI.GOOD if c.cash >= 0 else UI.BAD, "money"))
	var r := c.rating()
	top.add_child(UI.stat("Rating", "%s  (%d)" % [r["letter"], int(r["score"])], UI.ACCENT, "star"))
	top.add_child(UI.stat("Units", "%d" % c.combat_units().size(), UI.TEXT, "shield"))
	var con := "None"
	if not c.contract.is_empty():
		con = "%s" % c.contract["mission_label"]
	top.add_child(UI.stat("Contract", con, UI.TEXT if not c.contract.is_empty() else UI.DIM, "handshake"))
	var pend := c.pending_scenarios().size()
	var txt := "%d battle%s waiting." % [pend, "" if pend == 1 else "s"] if pend > 0 else "No battles waiting."
	var q := c.repair_queue().size()
	if q > 0:
		txt += "  %d repair job%s." % [q, "" if q == 1 else "s"]
	if not c.salvage.is_empty():
		txt += "  Salvage to claim on the Battles tab."
	status.text = txt




func show_tab(id: String) -> void:
	current = id
	Game.merc_tab = id
	if _pending_tab == "":
		_build_tab.call_deferred()
	_pending_tab = id


func _build_tab() -> void:
	var id := _pending_tab
	_pending_tab = ""
	if id == "" or not is_inside_tree():
		return
	_build_top()
	for b in nav.get_children():
		if not b.has_meta("tab"):
			continue
		var on: bool = b.get_meta("tab") == id
		UI.set_nav_active(b, on)
		if b.get_meta("tab") == "ops":
			var n := c.pending_scenarios().size()
			b.text = "%s    Battles%s" % [UI.ic("bomb"), ("   %s %d" % [UI.ic("warning"), n]) if n > 0 else ""]
		if b.get_meta("tab") == "arena":
			var na := c.arena_offers.size() if c.arena_open() else 0
			b.text = "%s    Solaris Arenas%s" % [UI.ic("trophy"), ("   %d" % na) if na > 0 else ""]
	UI.clear(content)
	for t in TABS:
		if t[0] == id:
			var tab = load(t[2]).new()
			tab.hub = self
			tab.c = c
			content.add_child(tab)
			tab.build()
			UI.fade_in(tab, 0.16)
			return


func flash(msg: String) -> void:
	status.text = msg


func _advance_day() -> void:
	if c.game_over:
		return
	var ev := c.advance_day()
	Game.save_game("merc_autosave")
	_after(ev)


func _advance_event() -> void:
	if c.game_over:
		return
	if not c.salvage.is_empty():
		UI.popup(self, "Salvage waiting", "Claim (or leave) the salvage from your last battle on the Battles tab first.")
		return
	run_btn.disabled = true
	day_btn.disabled = true
	run_btn.text = "%s   Time passes..." % UI.ic("clock")
	await get_tree().process_frame
	var ev := c.advance_to_event(60)
	Game.save_game("merc_autosave")
	run_btn.disabled = false
	day_btn.disabled = false
	run_btn.text = "%s   Advance to next event" % UI.ic("forward")
	_after(ev)


func _after(ev: Array) -> void:
	if c.game_over:
		var d := UI.popup(self, "The company folds", "%s can't pay its debts. The banks take the 'Mechs; the people scatter to the hiring halls.\n\nContracts: %d won, %d failed. Battles: %d (%d victories)." % [c.name, int(c.stats["contracts_ok"]), int(c.stats["contracts_failed"]), int(c.stats["battles"]), int(c.stats["victories"])])
		d.confirmed.connect(Game.show_menu)
		d.canceled.connect(Game.show_menu)
		DirAccess.remove_absolute("%s/merc_autosave.json" % Game.SAVE_DIR)
		return
	var lines: Array = []
	var battle := false
	for e in ev:
		if e.get("stop", false) or str(e["kind"]) in ["repair"]:
			lines.append("• " + str(e["text"]))
		if str(e["kind"]) == "battle" and not str(e["text"]).begins_with("Missed"):
			battle = true
	if battle:
		show_tab("ops")
	else:
		refresh()
	if not lines.is_empty():
		UI.popup(self, c.date_str(), "\n".join(lines.slice(0, 14)))
