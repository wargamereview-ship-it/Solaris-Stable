extends SceneTree
## godot --path . -s tests/screenshots_ui.gd -- <out_dir> [which]
## Quick look at the menus and hub screens of both modes (for visual polish work).

var out := "user://shots"
var game


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func shot(name: String, frames := 4) -> void:
	for k in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	root.size = Vector2i(1600, 960)
	game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await shot("50_menu", 30)
	game.new_game("Iron Gauntlet Stables", "Silesia", Color(0.2, 0.4, 0.8), 3015)
	await shot("51_office", 12)
	var hub = game.root_ui.get_child(0)
	for t in [["card", "52_card"], ["roster", "53_roster"], ["bay", "54_bay"]]:
		hub.show_tab(t[0])
		await shot(t[1], 10)
	game.new_merc_game("Kell's Raiders", Color(0.45, 0.42, 0.3), 3025, "Galatea", "combined", 909)
	await shot("55_merc_command", 12)
	hub = game.root_ui.get_child(0)
	for t in [["contracts", "56_contracts"], ["map", "57_map"], ["hangar", "58_hangar"], ["people", "59_people"], ["toe", "60_toe"]]:
		hub.show_tab(t[0])
		await shot(t[1], 10)
	quit()
