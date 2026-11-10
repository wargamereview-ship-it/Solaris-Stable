extends Control
## Title screen: new game, continue, quit.



const AttractView := preload("res://ui/fight/attract_view.gd")

var backdrop: Control
var caption: Label
var forms: VBoxContainer
var _attract_seed := 0


func _ready() -> void:
	backdrop = Control.new()
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	_attract_seed = randi() % 100000
	_new_attract()
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://ui/menu_overlay.gdshader")
	shade.material = sm
	add_child(shade)
	# left column: title and menu
	var left := MarginContainer.new()
	left.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	left.offset_right = 560
	left.add_theme_constant_override("margin_left", 84)
	left.add_theme_constant_override("margin_top", 110)
	left.add_theme_constant_override("margin_bottom", 40)
	add_child(left)
	var col := UI.vbox(6)
	left.add_child(col)
	var kicker := UI.label("%s   BATTLETECH  ·  3015 – 3152" % UI.ic("shield"), 14, UI.ACCENT)
	kicker.add_theme_font_override("font", UI.spaced("cond_semi", 4))
	col.add_child(kicker)
	var t := Label.new()
	t.text = "SOLARIS\nSTABLE"
	t.add_theme_font_override("font", UI.spaced("cond", 6))
	t.add_theme_font_size_override("font_size", 86)
	t.add_theme_constant_override("line_spacing", -22)
	t.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	t.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	t.add_theme_constant_override("shadow_offset_x", 0)
	t.add_theme_constant_override("shadow_offset_y", 4)
	t.add_theme_constant_override("shadow_outline_size", 10)
	col.add_child(t)
	var bar := ColorRect.new()
	bar.color = UI.ACCENT
	bar.custom_minimum_size = Vector2(120, 4)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(bar)
	var st := UI.label("Run a BattleMech stable on Solaris VII,\nor a mercenary company across the Inner Sphere.", 17, Color(0.78, 0.8, 0.84))
	col.add_child(st)
	col.add_child(UI.spacer(false))
	var items := UI.vbox(2)
	col.add_child(items)
	var saves := Game.list_saves()
	if not saves.is_empty():
		var cont := _menu_item("play", "Continue", func(): Game.load_game(saves[0]["path"]))
		cont.tooltip_text = str(saves[0]["slot"])
		items.add_child(cont)
	items.add_child(_menu_item("trophy", "New Solaris stable", _show_form))
	items.add_child(_menu_item("globe", "New mercenary company", _show_merc_form))
	if not saves.is_empty():
		items.add_child(_menu_item("folder", "Load a game", _show_loads))
	items.add_child(_menu_item("power", "Quit", func(): get_tree().quit()))
	col.add_child(UI.spacer(false))
	var credit := UI.label("Personal-use fan project. 'Mech sprites, portraits and unit data: MegaMek Data (CC BY-NC-SA 4.0).\nBattleTech is a trademark of The Topps Company. Fonts: Fira Sans, Hack, Font Awesome.", 11, Color(0.5, 0.54, 0.6))
	col.add_child(credit)
	# right: the forms
	var right := MarginContainer.new()
	right.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_left = -640
	right.add_theme_constant_override("margin_right", 70)
	right.add_theme_constant_override("margin_top", 90)
	right.add_theme_constant_override("margin_bottom", 90)
	add_child(right)
	forms = UI.vbox(12)
	forms.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(forms)
	caption = UI.label("", 12, Color(0.75, 0.78, 0.82, 0.8))
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	caption.position = Vector2(-560, -40)
	caption.size = Vector2(530, 24)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(caption)
	_update_caption()


func _menu_item(icon: String, text: String, cb: Callable) -> Button:
	var b := UI.nav_button(icon, text, cb)
	b.add_theme_font_size_override("font_size", 21)
	b.add_theme_font_override("font", UI.font("semibold"))
	b.custom_minimum_size = Vector2(380, 52)
	return b


func _new_attract() -> void:
	_attract_seed += 1
	var sim := AttractView.random_battle(_attract_seed)
	var av = AttractView.new()
	av.setup(sim, {})
	av.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	av.battle_over.connect(func(): _swap_attract.call_deferred())
	UI.clear(backdrop)
	backdrop.add_child(av)
	UI.fade_in(av, 1.2)
	_update_caption.call_deferred()


func _swap_attract() -> void:
	_new_attract()


func _update_caption() -> void:
	if caption == null or backdrop.get_child_count() == 0:
		return
	var av = backdrop.get_child(0)
	caption.text = "%s  LIVE  ·  %s" % [UI.ic("dot"), av.caption]


## The setup screen (ui/screens/setup.gd) has every choice for a new game, for either mode.
func _show_form() -> void:
	Game.show_setup("stable")


func _show_merc_form() -> void:
	Game.show_setup("merc")


func _show_loads() -> void:
	var d := AcceptDialog.new()
	d.title = "Load a saved game"
	var v := UI.vbox(6)
	for s in Game.list_saves():
		var path: String = s["path"]
		var when := Time.get_datetime_string_from_unix_time(int(s["time"]), true)
		v.add_child(UI.button("%s   (%s)" % [s["slot"], when], func():
			d.queue_free()
			Game.load_game(path)))
	d.add_child(v)
	add_child(d)
	d.popup_centered(Vector2i(420, 300))
