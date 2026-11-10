extends Control
## Screen-space weather: rain streaks, snowfall, drifting fog.

var weather := "clear"
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(delta: float) -> void:
	_t += delta
	if weather != "clear":
		queue_redraw()


func _draw() -> void:
	var s := size
	match weather:
		"rain":
			for k in 220:
				var x := fposmod(k * 97.31 + _t * 140.0, s.x + 40.0) - 20.0
				var y := fposmod(k * 53.7 + _t * 900.0, s.y + 40.0) - 20.0
				draw_line(Vector2(x, y), Vector2(x - 4.0, y + 16.0), Color(0.7, 0.78, 0.9, 0.35), 1.2)
		"snow":
			for k in 260:
				var x2 := fposmod(k * 77.7 + sin(_t + k) * 18.0 + _t * 20.0, s.x)
				var y2 := fposmod(k * 41.3 + _t * 60.0 * (0.6 + float(k % 5) * 0.1), s.y)
				draw_circle(Vector2(x2, y2), 1.6 + float(k % 3) * 0.6, Color(1, 1, 1, 0.7))
		"fog":
			draw_rect(Rect2(Vector2.ZERO, s), Color(0.8, 0.82, 0.85, 0.16))
			for k in 10:
				var c := Vector2(fposmod(k * 233.0 + _t * 12.0, s.x + 400.0) - 200.0, fmod(k * 157.0, s.y))
				draw_circle(c, 220.0, Color(0.85, 0.87, 0.9, 0.07))
		"wind":
			for k in 40:
				var x3 := fposmod(k * 131.0 + _t * 520.0, s.x + 200.0) - 100.0
				var y3 := fmod(k * 71.0, s.y)
				draw_line(Vector2(x3, y3), Vector2(x3 + 60.0, y3 + 2.0), Color(0.85, 0.85, 0.8, 0.12), 1.0)
