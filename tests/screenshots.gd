extends SceneTree
## godot --path . -s tests/screenshots.gd -- <out_dir>
## Runs the real game in a window and saves screenshots of the main screens.

var out := "user://shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func shot(name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("saved ", name)


func _run() -> void:
	root.size = Vector2i(1600, 960)
	var game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await shot("01_menu")
	game.new_game("Iron Gauntlet Stables", "Silesia", Color(0.2, 0.4, 0.8), 3015)
	await shot("02_office")
	# the hub replaces the menu on a deferred call, so look it up after a frame
	var hub = game.root_ui.get_child(0)
	for t in [["card", "03_fight_card"], ["roster", "04_roster"], ["bay", "05_bay"], ["market", "06_market"], ["rankings", "07_rankings"]]:
		hub.show_tab(t[0])
		await shot(t[1])
	var c: Campaign = game.campaign
	var d = load("res://ui/designer/designer.gd").new()
	d.setup(c, c.player().mechs[1], null)
	game.show_screen(d)
	await shot("08_designer")
	# watch a fight
	var p := c.player()
	for wid in p.warriors:
		var w: Warrior = c.warriors[wid]
		var done := false
		for o in c.offers.duplicate():
			if c.book(o["id"], wid, w.mech_uid, {"range": "optimal", "position": "flank"}, 0) == "":
				done = true
				break
		if done:
			break
	game.watch_bout(c.bookings[0]["id"])
	for k in 3:
		await process_frame
	var fv = game.root_ui.get_child(0)
	var dur: float = fv.duration
	fv.follow = false
	fv._fit_camera(true)
	fv._seek(minf(4.0, dur * 0.2))
	fv.playing = true
	for k in 20:
		await process_frame
	await shot("09_fight_start")
	fv.follow = true
	fv._seek(dur * 0.55)
	for k in 40:
		await process_frame
	await shot("10_fight_mid")
	fv._seek(dur)
	for k in 10:
		await process_frame
	await shot("11_fight_end")
	quit()
