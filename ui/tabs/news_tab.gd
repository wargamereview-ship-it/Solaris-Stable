extends MarginContainer
## The Solaris scream-sheets: everything that happened, newest first.

var hub
var c: Campaign
static var only_mine := false


func build() -> void:
	add_theme_constant_override("margin_left", 14)
	add_theme_constant_override("margin_right", 14)
	add_theme_constant_override("margin_top", 10)
	add_theme_constant_override("margin_bottom", 10)
	var root := UI.vbox(8)
	add_child(root)
	var head := UI.hbox(8)
	head.add_child(UI.title("News"))
	head.add_child(UI.spacer())
	var cb := CheckBox.new()
	cb.text = "Only my stable"
	cb.button_pressed = only_mine
	cb.toggled.connect(func(on):
		only_mine = on
		hub.refresh())
	head.add_child(cb)
	root.add_child(head)
	var v := UI.vbox(8)
	for i in range(c.news.size() - 1, -1, -1):
		var n: Dictionary = c.news[i]
		if only_mine and not n["mine"]:
			continue
		var col := UI.ACCENT if n["mine"] else (UI.WARN if n["kind"] in ["event", "championship", "title"] else UI.BLUE)
		v.add_child(UI.rich("[color=#%s][b]%s[/b][/color]   [color=#8a8f98]week %d, %d[/color]\n%s" % [col.to_html(false), n["title"], int(n["w"]), int(n["y"]), n["text"]]))
	root.add_child(UI.scroll(v))
