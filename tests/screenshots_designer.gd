extends SceneTree
## godot --path . -s tests/screenshots_designer.gd -- <out_dir>
## The mech lab: a refit of a stable 'Mech with an item picked, and a new build.

var out := "user://shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func shot(name: String, frames := 10) -> void:
	for k in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	root.size = Vector2i(1600, 960)
	var game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await shot("80_menu", 4)
	game.new_game("Iron Gauntlet Stables", "Silesia", Color(0.2, 0.4, 0.8), 3015)
	var c: Campaign = game.campaign
	var d = load("res://ui/designer/designer.gd").new()
	d.setup(c, c.player().mechs[1], null)
	game.show_screen(d)
	await shot("81_designer_refit", 12)
	d.sel_item = "medium_laser"
	d._rebuild()
	await shot("82_designer_pick", 8)
	var d2 = load("res://ui/designer/designer.gd").new()
	d2.setup(c, -1, MechDesign.blank(55, 5))
	game.show_screen(d2)
	await shot("83_designer_new", 12)
	quit()
