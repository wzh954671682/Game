extends Node

## Converts between 5x5 logical grid coordinates (Vector2i, 0..4) and screen
## pixel positions (Vector2). The grid is centered on the safe-area viewport
## at the reference resolution 1080x2160 (9:18).

const REF_WIDTH: int = 1080
const REF_HEIGHT: int = 2160
const GRID_COLS: int = 5
const GRID_ROWS: int = 5
const REF_CELL_SIZE: float = 190.0


var _cell_size: float = 0.0
var _grid_center: Vector2 = Vector2.ZERO


func _ready() -> void:
	_refresh_layout()
	get_tree().root.size_changed.connect(_refresh_layout)


func get_screen_pos(logic_pos: Vector2i) -> Vector2:
	var clamped := _clamp_grid(logic_pos)
	return Vector2(
		_grid_center.x + (clamped.x - 2) * _cell_size,
		_grid_center.y + (clamped.y - 2) * _cell_size
	)


func get_logic_pos(screen_pos: Vector2) -> Vector2i:
	var col: int = roundi((screen_pos.x - _grid_center.x) / _cell_size + 2.0)
	var row: int = roundi((screen_pos.y - _grid_center.y) / _cell_size + 2.0)
	return _clamp_grid(Vector2i(col, row))


func _refresh_layout() -> void:
	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var safe_area: Rect2 = DisplayServer.get_display_safe_area()

	var usable: Rect2 = safe_area if safe_area.has_area() else viewport_rect
	_grid_center = usable.position + usable.size * 0.5

	var scale_x: float = usable.size.x / float(REF_WIDTH)
	var scale_y: float = usable.size.y / float(REF_HEIGHT)
	var scale_factor: float = minf(scale_x, scale_y)
	_cell_size = REF_CELL_SIZE * scale_factor


func _clamp_grid(pos: Vector2i) -> Vector2i:
	return Vector2i(clampi(pos.x, 0, GRID_COLS - 1), clampi(pos.y, 0, GRID_ROWS - 1))
