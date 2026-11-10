extends SceneTree
## godot --path . -s tests/screenshots_dolls.gd -- <out_dir>
## The armor dolls side by side: 'Mechs pristine, battered and broken, and each vehicle type.

const PaperDoll := preload("res://ui/widgets/paper_doll.gd")
const VehicleDoll := preload("res://ui/widgets/vehicle_doll.gd")

var out := "user://shots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	DirAccess.make_dir_recursive_absolute(out)
	_run.call_deferred()


func _battered(d: MechDesign, k: float, kill: Array) -> Dictionary:
	var a := {}
	var i := {}
	var mi: Dictionary = VehicleConstruction.internal_points(d) if d.is_vehicle() else Construction.internal_points(d.tons)
	var n := 0
	for loc in d.armor:
		n += 1
		a[loc] = int(float(d.armor[loc]) * fmod(k * (n * 0.37 + 0.2), 1.0))
	for loc in mi:
		i[loc] = int(mi[loc])
	for loc in kill:
		a[loc] = 0
		i[loc] = 0
	if not d.is_vehicle():
		a["LA"] = 0
		i["LA"] = maxi(1, int(mi["LA"]) / 2)
	return {"armor": a, "internal": i}


func _cell(parent: Control, title: String, doll: Control) -> void:
	var v := UI.vbox(6)
	var p := UI.panel(v)
	v.add_child(UI.header(title, "", 11))
	var cc := CenterContainer.new()
	cc.add_child(doll)
	v.add_child(cc)
	parent.add_child(p)


func _run() -> void:
	root.size = Vector2i(1600, 960)
	var bg := UI.backdrop()
	root.add_child(bg)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 18)
	m.theme = UI.build_theme()
	root.add_child(m)
	var g := GridContainer.new()
	g.columns = 5
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 12)
	m.add_child(g)
	var db := GameData.db()
	for id in ["Atlas AS7-D", "Hunchback HBK-4G", "Locust LCT-1V"]:
		var d := db.stock_design(id)
		if d == null:
			continue
		var pd = PaperDoll.new(1.0)
		pd.set_design(d, {} if id.begins_with("Atlas") else _battered(d, 0.83, ["RA"] if id.begins_with("Hunch") else ["RT", "RL"]))
		if id.begins_with("Atlas"):
			pd.highlight = "CT"
		_cell(g, d.display_name(), pd)
	var seen := {}
	for e in db.get_vehicle_library():
		var vd: VehicleDesign = db.stock_design(str(e["id"]))
		var key := vd.motion + ("_t" if vd.armor.has("TU") else "")
		if seen.has(key) or seen.size() >= 7:
			continue
		seen[key] = true
		var dl = VehicleDoll.new(1.25)
		dl.set_design(vd, _battered(vd, 0.61, ["LS"]) if seen.size() % 2 == 0 else {})
		_cell(g, "%s (%s)" % [vd.chassis.left(22), vd.motion_label()], dl)
	for k in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/70_dolls.png" % out)
	print("saved 70_dolls")
	quit()
