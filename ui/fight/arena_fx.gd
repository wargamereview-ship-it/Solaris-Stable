extends Node2D
## The live battlefield drawn over the static arena: rubble from collapsed buildings, burned ground,
## fires and smoke, the arena's hazards, and the night. Everything is drawn for the playback time `pt`,
## so scrubbing back shows the arena as it was.

const PX := 2.4

var arena: Arena
var layer := "under"   # "under" (rubble, ash, darkness) or "over" (flames, smoke, hazards)
var pt := 0.0
var night := 0.0       # 0 day ... 1 dark


func _draw() -> void:
	if arena == null:
		return
	var cell := Arena.CELL * PX
	if layer == "under":
		# ash and rubble are drawn by the terrain shader; here: debris on fresh rubble
		for i in arena.collapsed_at:
			if float(arena.collapsed_at[i]) <= pt:
				var r2 := Rect2(Vector2(i % arena.w, i / arena.w) * cell, Vector2(cell, cell))
				var h2 := absi(hash(i * 31))
				for k in 6:
					var p2 := r2.position + Vector2(float((h2 >> k) % 22) / 22.0, float((h2 >> (k + 9)) % 22) / 22.0) * cell
					var s := 3.0 + float((h2 >> (k + 3)) % 6)
					draw_rect(Rect2(p2 + Vector2(1.5, 2), Vector2(s, s * 0.7)), Color(0, 0, 0, 0.3))
					draw_rect(Rect2(p2, Vector2(s, s * 0.7)), Color(0.3, 0.29, 0.29) if k % 2 == 0 else Color(0.56, 0.51, 0.43))
		# hazard fixtures on the floor
		for hz in arena.hazards:
			var hp: Vector2 = (hz["pos"] as Vector2) * PX
			match hz["type"]:
				"flame_jets":
					draw_rect(Rect2(hp - Vector2(11, 11), Vector2(22, 22)), Color(0.2, 0.18, 0.16))
					for k in 4:
						draw_line(hp + Vector2(-9, -6 + k * 4), hp + Vector2(9, -6 + k * 4), Color(0.45, 0.35, 0.25), 2.0)
				"steam_vents":
					draw_circle(hp, 13.0, Color(0.22, 0.22, 0.24))
					draw_arc(hp, 13.0, 0, TAU, 24, Color(0.5, 0.5, 0.55), 2.0)
				"shock_pylons":
					draw_circle(hp, 9.0, Color(0.55, 0.6, 0.75))
					draw_arc(hp, 13.0, 0, TAU, 24, Color(0.6, 0.8, 1.0, 0.8), 2.0)
		return
	# over: fire, smoke and active hazards
	var tm := pt
	for i in arena.fire_start:
		var c := (arena.center_of_index(i)) * PX
		var burning := arena.burning(i, tm)
		var smoky := float(arena.fire_start[i]) <= tm and tm < float(arena.fire_end[i]) + 15.0
		if burning:
			var hh := absi(hash(i))
			for k in 5:
				var flick := sin(tm * (7.0 + k) + hh % 7) * 0.5 + 0.5
				var off := Vector2(float((hh >> k) % 17) - 8.0, float((hh >> (k + 4)) % 17) - 8.0)
				draw_circle(c + off, 6.0 + flick * 5.0, Color(1.0, 0.45 + flick * 0.3, 0.1, 0.85))
				draw_circle(c + off + Vector2(0, -3), 3.0 + flick * 2.0, Color(1.0, 0.9, 0.5, 0.9))
		if smoky:
			for k in 3:
				var drift := Vector2(arena.wind) * fmod(tm * 6.0 + k * 9.0, 30.0)
				var rise := Vector2(sin(tm * 0.6 + k) * 6.0, -fmod(tm * 10.0 + k * 13.0, 26.0))
				draw_circle(c + drift + rise, 14.0 + k * 3.0, Color(0.35, 0.35, 0.36, 0.33))
	for hz in arena.hazards:
		var hp: Vector2 = (hz["pos"] as Vector2) * PX
		var on := arena.hazard_active(hz, tm)
		match hz["type"]:
			"flame_jets":
				if on:
					for k in 7:
						var fl := sin(tm * 18.0 + k * 1.7) * 0.5 + 0.5
						draw_circle(hp + Vector2(sin(k * 2.1) * 6.0, -k * 6.0), 12.0 - k * 1.1 + fl * 3.0, Color(1.0, 0.35 + k * 0.08, 0.08, 0.9 - k * 0.08))
			"steam_vents":
				if arena.hazard_active(hz, tm, 5.0):
					var since := fposmod(tm + float(hz["phase"]), float(hz["period"]))
					var a := clampf(1.0 - maxf(0.0, since - float(hz["active"])) / 5.0, 0.0, 1.0)
					for k in 8:
						var ang := k * TAU / 8.0 + tm * 0.3
						draw_circle(hp + Vector2.from_angle(ang) * (16.0 + since * 5.0), 22.0, Color(0.92, 0.93, 0.95, 0.38 * a))
					draw_circle(hp, 26.0, Color(0.95, 0.95, 0.97, 0.45 * a))
