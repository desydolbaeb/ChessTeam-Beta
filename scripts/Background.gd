extends Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()

func _draw() -> void:
	var r: Rect2 = Rect2(Vector2.ZERO, size)
	# Warm beige base
	draw_rect(r, Color("f3e6d4"))
	# Soft gradient bands
	draw_rect(Rect2(0.0, 0.0, size.x, size.y * 0.48), Color("efe0c8"))
	draw_rect(Rect2(0.0, size.y * 0.48, size.x, size.y * 0.52), Color("e8d5b5"))
	# Subtle warm radial glow
	var center: Vector2 = Vector2(size.x * 0.5, size.y * 0.38)
	var max_radius: float = maxf(size.x, size.y) * 0.75
	for i in range(14, 0, -1):
		var t: float = float(i) / 14.0
		var radius: float = max_radius * t
		var alpha: float = 0.012 + (1.0 - t) * 0.028
		draw_circle(center, radius, Color(0.78, 0.62, 0.38, alpha))
	# Soft top accent line
	draw_line(Vector2(0, 2), Vector2(size.x, 2), Color("c4a574"), 2.0)
