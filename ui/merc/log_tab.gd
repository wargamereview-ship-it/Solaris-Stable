extends "res://ui/merc/merc_tab.gd"
## The company log, newest first.


func build() -> void:
	setup_margins()
	var root := UI.vbox(8)
	add_child(root)
	root.add_child(UI.title("Company log"))
	var tree := UI.tree([["Date", -130], ["", -90], ["Event", 6]])
	tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tree)
	var cols := {"battle": UI.ACCENT, "contract": UI.GOOD, "personnel": UI.BLUE, "money": UI.WARN, "salvage": UI.GOOD, "hangar": UI.TEXT, "parts": UI.DIM, "travel": UI.DIM, "news": UI.WARN}
	for i in range(c.log.size() - 1, -1, -1):
		var e: Dictionary = c.log[i]
		var it := tree.create_item()
		it.set_text(0, MercCampaign.date_label(int(e["day"])))
		it.set_text(1, str(e["kind"]))
		it.set_text(2, str(e["text"]))
		it.set_custom_color(2, cols.get(str(e["kind"]), UI.TEXT))
