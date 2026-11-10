class_name UI
extends RefCounted
## Small UI toolkit: the theme, colors, fonts, icons and widget builders so screens stay short.
## Look: dark industrial military HUD. Fira Sans for text, Fira Sans Condensed for headings,
## Font Awesome 4 icons as a fallback font (any label can show UI.ic("wrench")), amber accents.

const BG := Color(0.043, 0.055, 0.07)
const PANEL := Color(0.075, 0.093, 0.115, 0.96)
const PANEL2 := Color(0.105, 0.13, 0.16)
const LINE := Color(0.19, 0.23, 0.28)
const LINE_HI := Color(0.3, 0.36, 0.43)
const TEXT := Color(0.87, 0.9, 0.93)
const DIM := Color(0.55, 0.6, 0.66)
const ACCENT := Color(0.96, 0.64, 0.2)
const ACCENT_DIM := Color(0.62, 0.4, 0.12)
const GOOD := Color(0.42, 0.85, 0.5)
const BAD := Color(0.95, 0.38, 0.32)
const WARN := Color(0.96, 0.8, 0.3)
const BLUE := Color(0.38, 0.68, 0.98)

const ICONS := {
	"home": 0xf015, "building": 0xf1ad, "trophy": 0xf091, "user": 0xf007, "users": 0xf0c0, "wrench": 0xf0ad,
	"cart": 0xf07a, "chart": 0xf080, "money": 0xf0d6, "news": 0xf1ea, "list": 0xf03a, "globe": 0xf0ac,
	"file": 0xf15c, "sitemap": 0xf0e8, "cubes": 0xf1b3, "crosshairs": 0xf05b, "bolt": 0xf0e7, "flag": 0xf024,
	"star": 0xf005, "save": 0xf0c7, "power": 0xf011, "play": 0xf04b, "pause": 0xf04c, "forward": 0xf04e,
	"step": 0xf051, "check": 0xf00c, "times": 0xf00d, "warning": 0xf071, "info": 0xf05a, "shield": 0xf132,
	"plane": 0xf072, "rocket": 0xf135, "clock": 0xf017, "calendar": 0xf073, "map": 0xf279, "cog": 0xf013,
	"bars": 0xf0c9, "eye": 0xf06e, "fire": 0xf06d, "medkit": 0xf0fa, "truck": 0xf0d1, "gavel": 0xf0e3,
	"handshake": 0xf2b5, "line_chart": 0xf201, "archive": 0xf187, "bomb": 0xf1e2, "dot": 0xf111,
	"arrow_right": 0xf061, "arrow_left": 0xf060, "folder": 0xf07c, "plus": 0xf067, "refresh": 0xf021,
	"microchip": 0xf2db, "retweet": 0xf079, "sign_out": 0xf08b, "life_ring": 0xf1cd, "anchor": 0xf13d,
}

static var _fonts: Dictionary = {}


## Fonts by role: "regular", "medium", "semibold", "bold", "cond" (condensed bold, headings),
## "cond_semi", "mono". All fall back to Font Awesome for icon glyphs.
static func font(kind := "regular") -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var files := {"regular": "FiraSans-Regular", "medium": "FiraSans-Medium", "semibold": "FiraSans-SemiBold",
		"bold": "FiraSans-Bold", "cond": "FiraSansCondensed-Bold", "cond_semi": "FiraSansCondensed-SemiBold",
		"cond_med": "FiraSansCondensed-Medium", "mono": "Hack-Regular", "icons": "FontAwesome"}
	var f: FontFile = load("res://assets/fonts/%s.ttf" % files.get(kind, "FiraSans-Regular"))
	if f == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Fira Sans", "Noto Sans", "DejaVu Sans"])
		_fonts[kind] = sf
		return sf
	if kind != "icons":
		var fa := font("icons")
		f.fallbacks = [fa]
	_fonts[kind] = f
	return f


## A heading font with letter spacing.
static func spaced(kind := "cond", spacing := 1) -> Font:
	var key := "%s_sp%d" % [kind, spacing]
	if _fonts.has(key):
		return _fonts[key]
	var fv := FontVariation.new()
	fv.base_font = font(kind)
	fv.spacing_glyph = spacing
	_fonts[key] = fv
	return fv


## An icon glyph, for any label or button text: "%s  Hangar" % UI.ic("wrench").
static func ic(name: String) -> String:
	return char(int(ICONS.get(name, 0xf111)))


static func build_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font("regular")
	t.default_font_size = 15
	t.set_font("bold_font", "RichTextLabel", font("semibold"))
	t.set_font("mono_font", "RichTextLabel", font("mono"))
	t.set_font("font", "Button", font("medium"))
	t.set_font("font", "OptionButton", font("medium"))
	t.set_font("title_button_font", "Tree", font("cond_semi"))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, 4, LINE, 1))
	t.set_stylebox("panel", "Panel", box(PANEL, 4, LINE, 1))
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := _button_box(st)
		t.set_stylebox(st, "Button", sb)
		t.set_stylebox(st, "OptionButton", _button_box(st))
		t.set_stylebox(st, "CheckBox", _flat_box(st))
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	t.set_color("font_hover_pressed_color", "Button", Color(0.1, 0.08, 0.05))
	t.set_color("font_focus_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", DIM.darkened(0.35))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color.WHITE)
	t.set_color("font_pressed_color", "CheckBox", TEXT)
	t.set_color("font_color", "OptionButton", TEXT)
	t.set_color("font_hover_color", "OptionButton", Color.WHITE)
	t.set_constant("h_separation", "Button", 8)
	var le := box(Color(0.035, 0.045, 0.058), 3, LINE, 1)
	le.content_margin_left = 9
	le.content_margin_right = 9
	le.content_margin_top = 5
	le.content_margin_bottom = 5
	t.set_stylebox("normal", "LineEdit", le)
	var lef := le.duplicate()
	lef.border_color = ACCENT
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", ACCENT_DIM)
	t.set_color("font_placeholder_color", "LineEdit", DIM.darkened(0.2))
	# tables
	var tb := box(Color(0.035, 0.045, 0.058, 0.96), 4, LINE, 1)
	tb.content_margin_left = 4
	tb.content_margin_right = 4
	t.set_stylebox("panel", "Tree", tb)
	t.set_color("font_color", "Tree", TEXT)
	t.set_color("font_selected_color", "Tree", Color.WHITE)
	t.set_color("title_button_color", "Tree", ACCENT.lerp(TEXT, 0.35))
	var th := box(Color(0.09, 0.11, 0.135), 0, LINE, 0)
	th.border_width_bottom = 2
	th.border_color = LINE_HI
	th.content_margin_top = 6
	th.content_margin_bottom = 6
	t.set_stylebox("title_button_normal", "Tree", th)
	t.set_stylebox("title_button_hover", "Tree", th)
	t.set_stylebox("title_button_pressed", "Tree", th)
	var sel := box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16), 2, ACCENT_DIM, 1)
	t.set_stylebox("selected", "Tree", sel)
	var self_ := box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22), 2, ACCENT, 1)
	t.set_stylebox("selected_focus", "Tree", self_)
	t.set_stylebox("focus", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("cursor", "Tree", StyleBoxEmpty.new())
	t.set_stylebox("cursor_unfocused", "Tree", StyleBoxEmpty.new())
	t.set_constant("v_separation", "Tree", 7)
	t.set_constant("item_margin", "Tree", 6)
	t.set_color("guide_color", "Tree", Color(1, 1, 1, 0.035))
	t.set_constant("draw_guides", "Tree", 1)
	# menus, dialogs, tooltips
	var pm := box(Color(0.08, 0.1, 0.125, 0.98), 4, LINE_HI, 1)
	pm.shadow_size = 12
	pm.shadow_color = Color(0, 0, 0, 0.5)
	t.set_stylebox("panel", "PopupMenu", pm)
	t.set_stylebox("hover", "PopupMenu", box(Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.22), 2))
	t.set_color("font_hover_color", "PopupMenu", Color.WHITE)
	t.set_constant("v_separation", "PopupMenu", 8)
	var dlg := box(Color(0.07, 0.085, 0.105, 0.99), 5, ACCENT_DIM, 1)
	dlg.border_width_top = 3
	dlg.border_color = ACCENT
	dlg.shadow_size = 24
	dlg.shadow_color = Color(0, 0, 0, 0.6)
	dlg.content_margin_left = 16
	dlg.content_margin_right = 16
	dlg.content_margin_top = 14
	dlg.content_margin_bottom = 12
	t.set_stylebox("panel", "AcceptDialog", dlg)
	t.set_stylebox("embedded_border", "Window", dlg)
	t.set_stylebox("embedded_unfocused_border", "Window", dlg)
	t.set_font("title_font", "Window", font("cond"))
	t.set_font_size("title_font_size", "Window", 17)
	t.set_color("title_color", "Window", ACCENT)
	t.set_constant("title_height", "Window", 34)
	t.set_stylebox("tab_selected", "TabContainer", box(PANEL2, 0, ACCENT, 1))
	t.set_stylebox("tab_unselected", "TabContainer", box(PANEL, 0, LINE, 1))
	t.set_stylebox("panel", "TabContainer", box(PANEL, 0, LINE, 1))
	var tip := box(Color(0.04, 0.05, 0.065, 0.97), 3, ACCENT_DIM, 1)
	tip.content_margin_left = 10
	tip.content_margin_right = 10
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", TEXT)
	# progress bars and sliders
	t.set_stylebox("background", "ProgressBar", box(Color(0.03, 0.035, 0.045), 3, LINE, 1))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, 3))
	var sl := box(Color(0.03, 0.035, 0.045), 3, LINE, 1)
	sl.content_margin_top = 3
	sl.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", sl)
	t.set_stylebox("grabber_area", "HSlider", box(ACCENT_DIM, 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(ACCENT, 3))
	# thin scrollbars
	for sb_name in ["VScrollBar", "HScrollBar"]:
		var track := box(Color(0, 0, 0, 0.18), 4)
		track.content_margin_left = 3
		track.content_margin_right = 3
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		t.set_stylebox("scroll", sb_name, track)
		t.set_stylebox("scroll_focus", sb_name, track)
		t.set_stylebox("grabber", sb_name, box(Color(0.3, 0.35, 0.42, 0.8), 4))
		t.set_stylebox("grabber_highlight", sb_name, box(Color(0.45, 0.5, 0.58, 0.9), 4))
		t.set_stylebox("grabber_pressed", sb_name, box(ACCENT_DIM, 4))
	t.set_stylebox("separator", "HSeparator", box(LINE, 0))
	return t


static func _button_box(st: String) -> StyleBoxFlat:
	var c := Color(0.12, 0.148, 0.18)
	var border := LINE_HI
	match st:
		"hover":
			c = Color(0.16, 0.195, 0.235)
			border = ACCENT.lerp(LINE_HI, 0.45)
		"pressed":
			c = ACCENT.darkened(0.05)
			border = ACCENT.lightened(0.2)
		"disabled":
			c = Color(0.08, 0.095, 0.115)
			border = LINE
		"focus":
			return box(Color(0, 0, 0, 0), 3)
	var sb := box(c, 3, border, 1)
	sb.border_width_bottom = 2
	sb.border_color = border
	if st == "normal":
		sb.border_color = Color(0.22, 0.27, 0.32)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.anti_aliasing = true
	return sb


static func _flat_box(st: String) -> StyleBoxFlat:
	var sb := box(Color(1, 1, 1, 0.04) if st == "hover" else Color(0, 0, 0, 0), 3)
	sb.content_margin_left = 4
	sb.content_margin_right = 6
	return sb


static func box(c: Color, radius := 0, border := Color(0, 0, 0, 0), bw := 0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(radius)
	if bw > 0:
		sb.border_color = border
		sb.set_border_width_all(bw)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	sb.anti_aliasing = true
	return sb


## A raised card: panel color, a hairline border, a soft drop shadow and an accent rule on top.
static func card_box(accent := false) -> StyleBoxFlat:
	var sb := box(PANEL, 5, LINE, 1)
	sb.shadow_size = 10
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_offset = Vector2(0, 3)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	if accent:
		sb.border_width_top = 2
		sb.border_color = LINE
	return sb


static func label(text: String, size := 15, color := TEXT, bold := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font("semibold"))
	return l


static func title(text: String, size := 22) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_override("font", spaced("cond", 2))
	l.add_theme_font_size_override("font_size", size + 2)
	l.add_theme_color_override("font_color", ACCENT)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


## A section header: icon, spaced condensed caps, and a hairline running to the right edge.
static func header(text: String, icon := "", size := 13, col := ACCENT) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	var l := Label.new()
	l.text = ((ic(icon) + "   ") if icon != "" else "") + text.to_upper()
	l.add_theme_font_override("font", spaced("cond_semi", 2))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	h.add_child(l)
	var line := ColorRect.new()
	line.color = Color(col.r, col.g, col.b, 0.22)
	line.custom_minimum_size = Vector2(10, 1)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(line)
	return h


static func button(text: String, cb: Callable, tip := "") -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


## An icon button: glyph + text.
static func ibutton(icon: String, text: String, cb: Callable, tip := "") -> Button:
	return button(("%s   %s" % [ic(icon), text]) if text != "" else ic(icon), cb, tip)


## The call-to-action look: filled amber with dark text.
static func primary(b: Button) -> Button:
	for st in ["normal", "hover", "pressed", "disabled"]:
		var c := ACCENT.darkened(0.08)
		match st:
			"hover":
				c = ACCENT.lightened(0.08)
			"pressed":
				c = ACCENT.darkened(0.25)
			"disabled":
				c = Color(0.2, 0.17, 0.12)
		var sb := box(c, 3, ACCENT.lightened(0.25) if st == "hover" else ACCENT.darkened(0.35), 1)
		sb.border_width_bottom = 3
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
		b.add_theme_stylebox_override(st, sb)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, Color(0.09, 0.07, 0.04))
	b.add_theme_color_override("font_disabled_color", Color(0.45, 0.4, 0.32))
	b.add_theme_font_override("font", font("semibold"))
	return b


## A small colored tag: "VETERAN", "DAMAGED".
static func chip(text: String, col: Color, size := 11) -> Control:
	var p := PanelContainer.new()
	var sb := box(Color(col.r, col.g, col.b, 0.14), 3, Color(col.r, col.g, col.b, 0.55), 1)
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	var l := label(text.to_upper(), size, col)
	l.add_theme_font_override("font", spaced("cond_semi", 1))
	p.add_child(l)
	return p


## A key figure: small caps caption over a big value.
static func stat(caption: String, value: String, col := TEXT, icon := "") -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	var c := Label.new()
	c.text = ((ic(icon) + "  ") if icon != "" else "") + caption.to_upper()
	c.add_theme_font_override("font", spaced("cond_semi", 1))
	c.add_theme_font_size_override("font_size", 11)
	c.add_theme_color_override("font_color", DIM)
	v.add_child(c)
	var l := Label.new()
	l.text = value
	l.add_theme_font_override("font", font("cond_semi"))
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", col)
	v.add_child(l)
	return v


static func hbox(sep := 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


static func vbox(sep := 6) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func panel(child: Control = null, color := PANEL) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := card_box()
	sb.bg_color = color
	p.add_theme_stylebox_override("panel", sb)
	if child:
		p.add_child(child)
	return p


static func spacer(h := true) -> Control:
	var c := Control.new()
	if h:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return c


static func rich(bb := "") -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = bb
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


static func tree(columns: Array) -> Tree:
	var t := Tree.new()
	t.columns = columns.size()
	t.column_titles_visible = true
	t.hide_root = true
	t.select_mode = Tree.SELECT_ROW
	for i in columns.size():
		var c = columns[i]
		if c is Array:
			t.set_column_title(i, str(c[0]).to_upper())
			t.set_column_expand(i, c[1] > 0)
			if c[1] > 0:
				t.set_column_expand_ratio(i, int(c[1]))
			else:
				t.set_column_custom_minimum_width(i, -int(c[1]))
		else:
			t.set_column_title(i, str(c).to_upper())
		t.set_column_title_alignment(i, HORIZONTAL_ALIGNMENT_LEFT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	t.add_theme_font_size_override("title_button_font_size", 12)
	t.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	t.create_item()  # hidden root; rows hang off it
	_stripe.call_deferred(t)
	return t


## Zebra rows, once the tab has filled the table.
static func _stripe(t: Tree) -> void:
	if not is_instance_valid(t):
		return
	var root := t.get_root()
	if root == null:
		return
	var it := root.get_first_child()
	var k := 0
	while it != null:
		if k % 2 == 1:
			for c in t.columns:
				it.set_custom_bg_color(c, Color(1, 1, 1, 0.025))
		it = it.get_next()
		k += 1


static func option(items: Array, selected := 0) -> OptionButton:
	var o := OptionButton.new()
	for i in items.size():
		o.add_item(str(items[i]), i)
	o.select(clampi(selected, 0, items.size() - 1))
	o.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return o


static func scroll(child: Control) -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.add_child(child)
	return s


static func clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## Navigation rail button: icon + label, a lit bar on the left when active.
static func nav_button(icon: String, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = "%s    %s" % [ic(icon), text]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 42
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	b.add_theme_font_override("font", font("medium"))
	b.add_theme_font_size_override("font_size", 15)
	set_nav_active(b, false)
	return b


static func set_nav_active(b: Button, on: bool) -> void:
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var c := Color(0, 0, 0, 0)
		if on:
			c = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.11)
		elif st == "hover":
			c = Color(1, 1, 1, 0.045)
		var sb := box(c, 0)
		sb.content_margin_left = 18
		sb.content_margin_top = 8
		sb.content_margin_bottom = 8
		if on:
			sb.border_width_left = 3
			sb.border_color = ACCENT
		b.add_theme_stylebox_override(st, sb)
	var fc := ACCENT if on else Color(0.78, 0.82, 0.87)
	for k in ["font_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, fc)
	b.add_theme_color_override("font_hover_color", ACCENT.lightened(0.15) if on else Color.WHITE)


## Style for a top or bottom bar.
static func bar_box(top := true) -> StyleBoxFlat:
	var sb := box(Color(0.03, 0.04, 0.052, 0.94), 0)
	if top:
		sb.border_width_bottom = 1
	else:
		sb.border_width_top = 1
	sb.border_color = LINE
	sb.shadow_size = 14
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


## The animated backdrop behind the hub screens and menus.
static func backdrop() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := ShaderMaterial.new()
	m.shader = load("res://ui/backdrop.gdshader")
	r.material = m
	return r


## Fades a control in (screens and tabs).
static func fade_in(c: CanvasItem, dur := 0.18) -> void:
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func money(v: int) -> String:
	return Campaign.money(v)


static func short_money(v: int) -> String:
	var a := absi(v)
	var s := ""
	if a >= 1000000:
		s = "%.2fM" % (a / 1000000.0)
	elif a >= 1000:
		s = "%dk" % (a / 1000)
	else:
		s = str(a)
	return ("-" if v < 0 else "") + s + " C"


static func skill_color(v: int) -> Color:
	if v <= 2:
		return GOOD
	if v <= 3:
		return Color(0.65, 0.85, 0.45)
	if v <= 4:
		return TEXT
	if v <= 5:
		return WARN
	return BAD


static func frac_color(f: float) -> Color:
	if f >= 0.75:
		return Color(0.3, 0.74, 0.42)
	if f >= 0.45:
		return Color(0.88, 0.74, 0.26)
	if f > 0.0:
		return Color(0.9, 0.36, 0.24)
	return Color(0.2, 0.2, 0.22)


static func popup(parent: Node, title_text: String, body: String) -> AcceptDialog:
	var d := AcceptDialog.new()
	d.title = title_text
	d.dialog_text = body
	d.dialog_autowrap = true
	d.min_size = Vector2i(480, 0)
	parent.add_child(d)
	primary(d.get_ok_button())
	d.popup_centered()
	d.confirmed.connect(d.queue_free)
	d.canceled.connect(d.queue_free)
	return d


static func confirm(parent: Node, title_text: String, body: String, on_ok: Callable) -> ConfirmationDialog:
	var d := ConfirmationDialog.new()
	d.title = title_text
	d.dialog_text = body
	d.dialog_autowrap = true
	d.min_size = Vector2i(480, 0)
	parent.add_child(d)
	primary(d.get_ok_button())
	d.confirmed.connect(func():
		on_ok.call()
		d.queue_free())
	d.canceled.connect(d.queue_free)
	d.popup_centered()
	return d
