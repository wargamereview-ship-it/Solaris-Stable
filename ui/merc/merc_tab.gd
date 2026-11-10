extends MarginContainer
## Base for the merc hub tabs: margins, a title, and a few layout helpers.

var hub
var c: MercCampaign


func setup_margins() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)


func section(parent: Control, title: String, icon := "") -> VBoxContainer:
	var v := UI.vbox(7)
	var p := UI.panel(v)
	parent.add_child(p)
	v.add_child(UI.header(title, icon))
	return v


func kv(parent: Control, k: String, v: String, col := UI.TEXT) -> void:
	var h := UI.hbox(8)
	var kl := UI.label(k.to_upper(), 12, UI.DIM)
	kl.add_theme_font_override("font", UI.spaced("cond_semi", 1))
	kl.custom_minimum_size.x = 150
	h.add_child(kl)
	var vl := UI.label(v, 14, col)
	vl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vl)
	parent.add_child(h)


func wrap_label(text: String, size := 13, col := UI.DIM) -> Label:
	var l := UI.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


## Runs an action, then rebuilds the tab after the click is done (never inside the button's signal).
func act(fn: Callable) -> void:
	var msg: Variant = fn.call()
	if msg is String and msg != "":
		hub.flash(msg)
	Game.save_game("merc_autosave")
	hub.refresh.call_deferred()
