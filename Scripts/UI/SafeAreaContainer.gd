extends MarginContainer

## Wraps UI content and automatically applies screen safe-area margins.
## Prevents content from being obscured by notches, camera cutouts,
## or gesture bars on modern mobile devices.

func _ready() -> void:
	var safe_area: Rect2 = DisplayServer.get_display_safe_area()
	if not safe_area.has_area():
		return

	var screen_size: Vector2i = DisplayServer.window_get_size()
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var scale_x: float = viewport_size.x / float(screen_size.x)
	var scale_y: float = viewport_size.y / float(screen_size.y)

	add_theme_constant_override(&"margin_left",   int(safe_area.position.x * scale_x))
	add_theme_constant_override(&"margin_top",    int(safe_area.position.y * scale_y))
	add_theme_constant_override(&"margin_right",  int((screen_size.x - safe_area.end.x) * scale_x))
	add_theme_constant_override(&"margin_bottom", int((screen_size.y - safe_area.end.y) * scale_y))
