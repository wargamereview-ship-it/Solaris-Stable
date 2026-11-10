extends SceneTree
## godot --headless --path . -s tests/plan_settlements.gd -- <out_dir>
## Draws generated maps as plans (streets, plazas, parks, buildings by type, outlines per building)
## and prints building counts by type. For checking settlement layouts without the renderer.

const KC := {0: Color(0.6, 0.6, 0.6), 1: Color(0.85, 0.45, 0.35), 2: Color(0.8, 0.55, 0.4), 3: Color(0.95, 0.8, 0.35),
	4: Color(0.75, 0.6, 0.85), 5: Color(0.5, 0.65, 0.9), 6: Color(0.35, 0.5, 1.0), 7: Color(0.6, 0.6, 0.65), 8: Color(0.45, 0.45, 0.5),
	9: Color(0.9, 0.9, 0.95), 10: Color(1.0, 1.0, 0.7), 11: Color(0.95, 0.95, 1.0), 12: Color(0.7, 0.3, 0.2), 13: Color(0.85, 0.85, 0.8),
	14: Color(0.3, 0.32, 0.3), 15: Color(0.55, 0.6, 0.5)}
const ZC := {0: Color(0.32, 0.42, 0.25), 1: Color(0.22, 0.22, 0.24), 2: Color(0.16, 0.16, 0.18), 3: Color(0.62, 0.6, 0.55),
	4: Color(0.3, 0.3, 0.34), 5: Color(0.42, 0.55, 0.3), 6: Color(0.2, 0.45, 0.2), 7: Color(0.45, 0.43, 0.4)}


func _init() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://plans"
	DirAccess.make_dir_recursive_absolute(out)
	var jobs := [["bf_urban", 11], ["bf_urban", 12], ["bf_plains", 21], ["bf_desert", 31], ["bf_badlands", 41], ["bf_coast", 51], ["bf_hills", 61]]
	for j in jobs:
		var a: Arena = BattlefieldGenerator.generate(j[0], j[1], {"scenario": "base_defense" if j[1] == 21 else "standup"})
		_plan(a, "%s/plan_%s_%d.png" % [out, j[0], j[1]])
	for j in [["urban", 7], ["factory", 8]]:
		var a2: Arena = ArenaGenerator.generate(j[0], j[1], 1)
		_plan(a2, "%s/plan_%s_%d.png" % [out, j[0], j[1]])
	quit()


func _plan(a: Arena, path: String) -> void:
	var s := 6
	var img := Image.create(a.w * s, a.h * s, false, Image.FORMAT_RGB8)
	var counts := {}
	for y in a.h:
		for x in a.w:
			var i := a.idx(x, y)
			var c: Color = ZC.get(int(a.zone[i]), ZC[0])
			match a.terrain[i]:
				Arena.T.WATER:
					c = Color(0.2, 0.35, 0.6)
				Arena.T.LIGHT_WOODS:
					c = Color(0.2, 0.42, 0.18) if a.zone[i] == 0 else Color(0.15, 0.5, 0.2)
				Arena.T.HEAVY_WOODS:
					c = Color(0.1, 0.28, 0.1)
				Arena.T.ROUGH:
					c = Color(0.45, 0.4, 0.3)
				Arena.T.PAVEMENT:
					if a.zone[i] == 0:
						c = Color(0.3, 0.3, 0.32)
				Arena.T.BUILDING:
					c = KC.get(int(a.bld_kind[i]), Color.WHITE).darkened(0.25 - clampf(a.bld_h[i] / 8.0, 0.0, 0.25))
			if a.terrain[i] != Arena.T.BUILDING and a.terrain[i] != Arena.T.WATER:
				c = c.lightened(a.height[i] * 0.05)
			img.fill_rect(Rect2i(x * s, y * s, s, s), c)
			if a.terrain[i] == Arena.T.BUILDING:
				var id := a.bld_id[i]
				if not counts.has(id):
					counts[id] = a.bld_kind[i]
				# outline where the building ends
				for o in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
					var nx: int = x + o.x
					var ny: int = y + o.y
					if not a.inside(nx, ny) or a.bld_id[a.idx(nx, ny)] != id:
						var r := Rect2i(x * s + (s - 1 if o.x > 0 else 0), y * s + (s - 1 if o.y > 0 else 0), 1 if o.x != 0 else s, 1 if o.y != 0 else s)
						img.fill_rect(r, Color(0.05, 0.05, 0.05))
	img.save_png(path)
	var by := {}
	for id in counts:
		var nm: String = Settlement.NAMES[int(counts[id])]
		by[nm] = int(by.get(nm, 0)) + 1
	print(path.get_file(), " ", a.w, "x", a.h, " buildings ", counts.size(), " ", by)
