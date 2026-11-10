extends Control
## A heraldic crest for a stable or company: a shield in its paint color with a chevron and initials.

var color := Color(0.6, 0.5, 0.3)
var initials := "?"


func _init(col := Color(0.6, 0.5, 0.3), name := "", s := 44.0) -> void:
	color = col
	var parts := name.strip_edges().split(" ", false)
	initials = ""
	for p in parts:
		if p.length() > 0 and p[0] == p[0].to_upper() and initials.length() < 2 and not (p.to_lower() in ["the", "of"]):
			initials += p[0]
	if initials == "":
		initials = "?"
	custom_minimum_size = Vector2(s * 0.86, s)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var w := size.x
	var h := size.y
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h * 0.55), Vector2(w * 0.5, h), Vector2(0, h * 0.55)])
	var inner := PackedVector2Array()
	var c := Vector2(w / 2.0, h * 0.45)
	for p in pts:
		inner.append(c + (p - c) * 0.82)
	draw_colored_polygon(pts, color.darkened(0.55))
	var cols := PackedColorArray([color.lightened(0.15), color.lightened(0.15), color.darkened(0.15), color.darkened(0.35), color.darkened(0.15)])
	draw_polygon(inner, cols)
	var rim := pts.duplicate()
	rim.append(pts[0])
	draw_polyline(rim, UI.ACCENT.lerp(Color.WHITE, 0.2), 1.5, true)
	# chevron
	draw_polyline(PackedVector2Array([Vector2(w * 0.2, h * 0.62), Vector2(w * 0.5, h * 0.8), Vector2(w * 0.8, h * 0.62)]), Color(1, 1, 1, 0.55), 2.0, true)
	var f := UI.font("cond")
	var fs := int(h * 0.36)
	var ts := f.get_string_size(initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var tp := Vector2((w - ts.x) / 2.0, h * 0.5)
	draw_string(f, tp + Vector2(1, 2), initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.5))
	draw_string(f, tp, initials, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.95))
