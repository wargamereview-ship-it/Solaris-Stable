extends Control
## Root scene: a full-window container the Game autoload swaps screens into.

func _ready() -> void:
	theme = Game.ui_theme
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(holder)
	Game.root_ui = holder
	Game.show_menu()
