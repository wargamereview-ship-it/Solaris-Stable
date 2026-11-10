extends Control
## The stable office: top bar, navigation, the current tab, and the advance-week button.

const TABS := [
	["dashboard", "Office", "res://ui/tabs/dashboard_tab.gd", "building"],
	["card", "Fight Card", "res://ui/tabs/card_tab.gd", "trophy"],
	["jobs", "Mercenary Work", "res://ui/tabs/jobs_tab.gd", "rocket"],
	["roster", "MechWarriors", "res://ui/tabs/roster_tab.gd", "users"],
	["bay", "'Mech Bay", "res://ui/tabs/bay_tab.gd", "wrench"],
	["market", "Market", "res://ui/tabs/market_tab.gd", "cart"],
	["rankings", "Rankings", "res://ui/tabs/rankings_tab.gd", "chart"],
	["finances", "Finances", "res://ui/tabs/finance_tab.gd", "money"],
	["news", "News", "res://ui/tabs/news_tab.gd", "news"],
]
const Emblem := preload("res://ui/widgets/emblem.gd")

var c: Campaign
var top: HBoxContainer
var content: PanelContainer
var nav: VBoxContainer
var status: Label
var advance_btn: Button
var current := ""


func _ready() -> void:
	c = Game.campaign
	add_child(UI.backdrop())
	var root := UI.vbox(0)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var topp := PanelContainer.new()
	topp.add_theme_stylebox_override("panel", UI.bar_box(true))
	top = UI.hbox(22)
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
	nav.custom_minimum_size.x = 200
	navp.add_child(nav)
	mid.add_child(navp)
	content = PanelContainer.new()
	content.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(content)
	var bot := PanelContainer.new()
	bot.add_theme_stylebox_override("panel", UI.bar_box(false))
	var bh := UI.hbox(12)
	status = UI.label("", 14, UI.DIM)
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bh.add_child(status)
	bh.add_child(UI.ibutton("save", "Save", func():
		Game.save_game("autosave")
		Game.save_game("%s_%d_w%02d" % [c.player().name.to_snake_case().left(16), c.year, c.week])
		_flash("Saved.")))
	bh.add_child(UI.ibutton("sign_out", "Main menu", func():
		Game.save_game("autosave")
		Game.show_menu()))
	advance_btn = UI.primary(UI.ibutton("forward", "Advance week", _advance))
	advance_btn.add_theme_font_size_override("font_size", 16)
	bh.add_child(advance_btn)
	bot.add_child(bh)
	root.add_child(bot)
	for t in TABS:
		var b := UI.nav_button(t[3], t[1], show_tab.bind(t[0]))
		b.set_meta("tab", t[0])
		nav.add_child(b)
	nav.add_child(UI.spacer(false))
	var foot := UI.label("  %s  SOLARIS VII STABLE" % UI.ic("trophy"), 11, UI.DIM)
	foot.add_theme_font_override("font", UI.spaced("cond_semi", 2))
	nav.add_child(foot)
	show_tab(Game.last_tab)


func refresh() -> void:
	_build_top()
	show_tab(current)


func _build_top() -> void:
	UI.clear(top)
	var p := c.player()
	var id := UI.hbox(12)
	id.add_child(Emblem.new(p.color, p.name, 46))
	var nv := UI.vbox(-2)
	var nm := UI.label(p.name.to_upper(), 22, UI.TEXT)
	nm.add_theme_font_override("font", UI.spaced("cond", 2))
	nv.add_child(nm)
	nv.add_child(UI.label("%s  %s sector, Solaris City" % [UI.ic("building"), p.sector], 13, UI.DIM))
	id.add_child(nv)
	top.add_child(id)
	top.add_child(UI.spacer())
	top.add_child(UI.stat("Date", c.date_str(), UI.TEXT, "calendar"))
	top.add_child(UI.stat("C-bills", UI.money(p.cash), UI.GOOD if p.cash >= 0 else UI.BAD, "money"))
	top.add_child(UI.stat("Fame", "%.0f" % p.fame, UI.ACCENT, "star"))
	top.add_child(UI.stat("Record", "%d-%d-%d" % [p.wins, p.losses, p.draws], UI.TEXT, "trophy"))
	var rank := c.stable_rankings().find(p.id) + 1
	top.add_child(UI.stat("Stable rank", "#%d of %d" % [rank, c.stables.size()], UI.TEXT, "chart"))
	var unres := c.unresolved_bookings().size()
	status.text = "%d bout%s booked, %d still to fight.  %d offers on the table." % [c.bookings.size(), "" if c.bookings.size() == 1 else "s", unres, c.offers.size()]
	if c.week >= 49 and c.championship.get("active", false):
		status.text += "  The Grand Championship is underway."


func _stat(k: String, v: String, col := UI.TEXT) -> Control:
	var b := UI.vbox(0)
	b.add_child(UI.label(k, 10, UI.DIM))
	b.add_child(UI.label(v, 16, col, true))
	return b


var _pending_tab := ""


## Tab rebuilds run after the current input event: rebuilding inside a control's own signal would
## free that control mid-click (the cause of the SpinBox/Tree crashes).
func show_tab(id: String) -> void:
	current = id
	Game.last_tab = id
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
		UI.set_nav_active(b, b.get_meta("tab") == id)
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


func _flash(msg: String) -> void:
	status.text = msg


func _advance() -> void:
	var unres := c.unresolved_bookings().size()
	if unres > 0:
		UI.confirm(self, "Fight night", "You have %d booked bout%s you haven't watched. They'll be simulated. Advance the week?" % [unres, "" if unres == 1 else "s"], _do_advance)
	else:
		_do_advance()


func _do_advance() -> void:
	advance_btn.disabled = true
	advance_btn.text = "%s   Simulating fight night..." % UI.ic("clock")
	await get_tree().process_frame
	await get_tree().process_frame
	var prev_y := c.year
	var prev_w := c.week
	var cash0 := c.player().cash
	c.advance_week()
	Game.save_game("autosave")
	advance_btn.disabled = false
	advance_btn.text = "%s   Advance week" % UI.ic("forward")
	refresh()
	if c.player().cash < -1000000:
		var d := UI.popup(self, "Bankrupt", "Your creditors seize %s. The Game World moves on without you.\n\nFinal record %d-%d-%d, fame %.0f." % [c.player().name, c.player().wins, c.player().losses, c.player().draws, c.player().fame])
		d.confirmed.connect(Game.show_menu)
		d.canceled.connect(Game.show_menu)
		DirAccess.remove_absolute("%s/autosave.json" % Game.SAVE_DIR)
		return
	_week_report(prev_y, prev_w, cash0)
	if c.player().cash < 0:
		_flash("You're in debt. Below -1,000,000 C-bills the creditors take the stable.")


func _week_report(y: int, w: int, cash0: int) -> void:
	var lines: Array = []
	for r in c.results:
		if int(r["y"]) == y and int(r["w"]) == w and r["player"]:
			var a: Warrior = c.warriors[int(r["a"])]
			var b: Warrior = c.warriors[int(r["b"])]
			var mine_a := a.stable_id == c.player_id
			var me := a if mine_a else b
			var won := (int(r["winner"]) == 0 and mine_a) or (int(r["winner"]) == 1 and not mine_a)
			var res := "WIN" if won else ("DRAW" if int(r["winner"]) < 0 else "LOSS")
			var fmt: String = r.get("format", "duel")
			if fmt != "duel":
				lines.append("%s  %s with %s (%s), %s" % [res, Campaign.FORMAT_LABEL.get(fmt, fmt), me.short_name(), r["arena"], r["how"]])
			else:
				lines.append("%s  %s vs %s (%s), %s" % [res, me.short_name(), (b if mine_a else a).short_name(), r["arena"], r["how"]])
	var p := c.player()
	var led: Dictionary = p.ledger[-1] if not p.ledger.is_empty() else {}
	var fin: Array = []
	for k in led.get("lines", {}):
		fin.append("%s %s" % [k, UI.money(int(led["lines"][k]))])
	var body := ""
	if lines.is_empty():
		body += "No bouts for your stable last week.\n"
	else:
		body += "\n".join(lines) + "\n"
	body += "\nWeekly cash change: %s\n" % UI.money(p.cash - cash0)
	var news_mine: Array = []
	for n in c.news:
		if int(n["y"]) == c.year and int(n["w"]) == c.week and (n["mine"] or n["kind"] in ["event", "title", "championship"]):
			news_mine.append("• %s: %s" % [n["title"], n["text"]])
	if not news_mine.is_empty():
		body += "\n" + "\n".join(news_mine)
	UI.popup(self, "%s report" % ("Week %d, %d" % [w, y]), body)
