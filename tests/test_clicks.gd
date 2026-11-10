extends SceneTree
## godot --headless --path . -s tests/test_clicks.gd
## Sends real mouse clicks through the viewport: SpinBox arrows and slot buttons in the designer,
## the hub's navigation and the office "Go" buttons. These rebuild the UI from inside their own
## signals, which used to free the clicked control mid-click and crash Godot.

var game


func _init() -> void:
	_run.call_deferred()


func click_at(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await process_frame


## A real drag: press at `a`, move to `b` in steps (a drag starts after 10 pixels), release.
func drag_to(a: Vector2, b: Vector2) -> void:
	var path := [a]
	for k in range(1, 9):
		path.append(a.lerp(b, k / 8.0))
	path.append(b + Vector2(1, 0))
	path.append(b)
	for k in path.size():
		if k == 0 or k == path.size() - 1:
			var e := InputEventMouseButton.new()
			e.button_index = MOUSE_BUTTON_LEFT
			e.pressed = k == 0
			e.button_mask = MOUSE_BUTTON_MASK_LEFT if k == 0 else 0
			e.position = path[k]
			e.global_position = path[k]
			if k > 0:
				# let the lab relight the locations before the drop
				for f in 3:
					await process_frame
			root.push_input(e)
		if k > 0:
			var m := InputEventMouseMotion.new()
			m.position = path[k]
			m.global_position = path[k]
			m.relative = path[k] - path[k - 1]
			m.button_mask = MOUSE_BUTTON_MASK_LEFT
			if k < path.size() - 1:
				root.push_input(m)
		await process_frame
	for f in 4:
		await process_frame


func click(c: Control) -> void:
	if c == null or not c.is_inside_tree() or not c.is_visible_in_tree():
		return
	await click_at(c.get_global_rect().get_center())


func find_all(n: Node, cls: String, out: Array) -> Array:
	if n.is_class(cls):
		out.append(n)
	for ch in n.get_children():
		find_all(ch, cls, out)
	return out


func _run() -> void:
	root.size = Vector2i(1600, 960)
	game = root.get_node("Game")
	var main = load("res://ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	game.new_game("Click Test", "Cathay", Color(0.3, 0.7, 0.3), 99)
	for k in 3:
		await process_frame
	var hub = game.root_ui.get_child(0)
	# nav buttons, several rounds
	for round in 2:
		for b in hub.nav.get_children():
			await click(b)
			await process_frame
	print("nav clicks ok")
	# office "Go" buttons (they replace the tab that contains them)
	hub.show_tab("dashboard")
	await process_frame
	await process_frame
	var gos: Array = []
	for b in find_all(hub.content, "Button", []):
		if b.text == "Go":
			gos.append(b)
	if not gos.is_empty():
		await click(gos[0])
		await process_frame
	print("office Go clicks ok (%d buttons)" % gos.size())
	# list selections: click different rows several times on every tab with a list
	for tab in ["card", "roster", "bay", "market"]:
		hub.show_tab(tab)
		await process_frame
		await process_frame
		for k in 8:
			var trees: Array = find_all(hub.content, "Tree", []).filter(func(t): return is_instance_valid(t) and t.is_visible_in_tree())
			if trees.is_empty():
				break
			var t: Tree = trees[0]
			var rows: Array = []
			var it := t.get_root().get_first_child()
			while it:
				rows.append(it)
				it = it.get_next()
			if rows.is_empty():
				break
			var row: TreeItem = rows[k % rows.size()]
			var pos := t.get_global_rect().position + t.get_item_area_rect(row).get_center() - Vector2(0, t.get_scroll().y)
			rows.clear()
			await click_at(pos)
			await process_frame
		# also hit buttons inside the detail panel that rebuild the tab
		print("list clicks ok: ", tab)
	# designer: SpinBox arrows and dropdown changes
	var c: Campaign = game.campaign
	var d = load("res://ui/designer/designer.gd").new()
	d.setup(c, c.player().mechs[0], null)
	game.show_screen(d)
	for k in 3:
		await process_frame
	for round in 6:
		for k in 5:
			# look the controls up fresh after every click (the old lab rebuilt itself on each one)
			var spins: Array = find_all(d, "SpinBox", []).filter(func(s): return is_instance_valid(s) and s.editable)
			if k >= spins.size():
				break
			var r: Rect2 = spins[k].get_global_rect()
			spins.clear()
			# the up arrow sits at the right edge, upper half
			await click_at(Vector2(r.end.x - 6, r.position.y + r.size.y * 0.25))
			await process_frame
	print("designer spinbox clicks ok")
	var sig0: String = d._sig()
	for round in 3:
		# take a mounted part or an arm actuator off
		var slot_buttons: Array = []
		for b in find_all(d, "Button", []):
			var bt: String = b.text.to_lower()
			if bt.find("medium laser") >= 0 or bt.find("machine gun") >= 0 or bt == "lower arm":
				slot_buttons.append(b)
		if not slot_buttons.is_empty():
			await click(slot_buttons[0])
		await process_frame
		# pick a part in the list
		var trees: Array = find_all(d, "Tree", [])
		if not trees.is_empty():
			var t: Tree = trees[0]
			var first := t.get_root().get_first_child()
			if first:
				var rr := t.get_item_area_rect(first)
				await click_at(t.get_global_rect().position + rr.get_center() + Vector2(0, 30))
		await process_frame
		await process_frame
		# and mount it where the lab offers ("+  Name" marks where it would land)
		for b in find_all(d, "Button", []):
			if b.text.begins_with("+  ") and not b.disabled and b.is_visible_in_tree():
				await click(b)
				break
		await process_frame
		await process_frame
	print("designer slot/list clicks ok (picked: %s, changed: %s)" % [d.sel_item, d._sig() != sig0])
	for ob in find_all(d, "OptionButton", []):
		if ob.is_inside_tree() and ob.item_count > 1:
			ob.item_selected.emit(1)
			await process_frame
			break
	await process_frame
	await process_frame
	# undo all the way back, redo once, undo again
	var steps := 0
	while not d._undo.is_empty() and steps < 200:
		await click(d.w["undo"])
		await process_frame
		await process_frame
		steps += 1
	print("undo: %d steps, back at the start: %s" % [steps, d._sig() == d._base_sig])
	await click(d.w["redo"])
	await process_frame
	await process_frame
	print("redo changes the design again: ", d._sig() != d._base_sig)
	# drag and drop, from the design as it started: a mounted weapon to another location, a part out
	# of the list onto a location, and a mounted part back onto the list
	while not d._undo.is_empty():
		d._undo_step()
		await process_frame
		await process_frame
	d._pick("")
	for k in 3:
		await process_frame
	var ds: Dictionary = d.d.slots
	var src := ""
	var src_i := -1
	for loc in MechDesign.LOCS:
		for i in ds[loc].size():
			var sv: String = ds[loc][i]
			if src == "" and sv != "" and not MechDesign.is_fixed(sv) and GameData.db().item(MechDesign.base_id(sv)).get("kind", "") == "weapon" \
					and Construction.item_crits(d.d, MechDesign.base_id(sv), 0.0) == 1:
				src = loc
				src_i = i
	var dst := ""
	for loc in ["RA", "LA", "RT", "LT"]:
		if dst == "" and loc != src and ds[loc].rfind("") >= 0:
			dst = loc
	if src == "" or dst == "":
		print("drag and drop: skipped, no one-slot weapon to move")
	else:
		var slot_at := func(loc: String, i: int) -> Vector2:
			var box: Control = d.w["loc_" + loc]["slots"]
			return box.global_position + Vector2(box.size.x * 0.5, i * (d.ROW_H + 1) + d.ROW_H * 0.5)
		var part: String = ds[src][src_i]
		var dst_i: int = ds[dst].rfind("")
		await drag_to(slot_at.call(src, src_i), slot_at.call(dst, dst_i))
		var moved: bool = ds[dst][dst_i] == part and ds[src][src_i] == ""
		var tr: Tree = d.w["tree"]
		var one: TreeItem = tr.get_root().get_first_child()
		while one and Construction.item_crits(d.d, str(one.get_metadata(0)), 0.0) != 1:
			one = one.get_next()
		var free_i: int = ds[dst].find("")
		var listed := false
		if one and free_i >= 0:
			await drag_to(tr.get_global_rect().position + tr.get_item_area_rect(one).get_center(), slot_at.call(dst, free_i))
			listed = ds[dst][free_i] == str(one.get_metadata(0)) and d.sel_item == ""
		await drag_to(slot_at.call(dst, dst_i), tr.get_global_rect().get_center())
		print("drag and drop: moved %s, mounted from the list %s, taken off %s, nothing left in the air %s" % [
			moved, listed, ds[dst][dst_i] == "", d.drag.is_empty()])
	var back: Button = null
	for b in find_all(d, "Button", []):
		if b.text == "Back to the bay":
			back = b
	await click(back)
	for k in 3:
		await process_frame
	# a changed design asks before it is thrown away
	var asked := false
	for dlg in find_all(d, "ConfirmationDialog", []):
		asked = true
		dlg.get_ok_button().pressed.emit()
	for k in 3:
		await process_frame
	print("back to bay (asked first: %s): %s" % [asked, game.root_ui.get_child(0).get_script().resource_path])
	print("CLICK TEST DONE")
	quit()
