extends MarginContainer

## Wraps UI content and automatically applies screen safe-area margins.
## Prevents content from being obscured by notches, camera cutouts,
## or gesture bars on modern mobile devices.

func _ready() -> void:
	# [防爆装甲 1]：仅在真实的移动设备（安卓/iOS）上启用安全区计算
	if not OS.has_feature("android") and not OS.has_feature("iOS"):
		return

	var safe_area: Rect2 = DisplayServer.get_display_safe_area()
	if not safe_area.has_area():
		return

	var screen_size: Vector2i = DisplayServer.window_get_size()

	# [防爆装甲 2]：越界保护。如果安全区尺寸大于当前窗口，说明获取到了电脑显示器坐标，直接放弃
	if safe_area.size.x > screen_size.x or safe_area.size.y > screen_size.y:
		return

	var viewport_size: Vector2 = get_viewport().get_visible_rect().size

	var scale_x: float = viewport_size.x / float(screen_size.x)
	var scale_y: float = viewport_size.y / float(screen_size.y)

	# 计算边缘，并加上 [防爆装甲 3]：强制限制最小值不能小于 0
	var m_left: int = max(0, int(safe_area.position.x * scale_x))
	var m_top: int = max(0, int(safe_area.position.y * scale_y))
	var m_right: int = max(0, int((screen_size.x - safe_area.end.x) * scale_x))
	var m_bottom: int = max(0, int((screen_size.y - safe_area.end.y) * scale_y))

	add_theme_constant_override(&"margin_left", m_left)
	add_theme_constant_override(&"margin_top", m_top)
	add_theme_constant_override(&"margin_right", m_right)
	add_theme_constant_override(&"margin_bottom", m_bottom)
