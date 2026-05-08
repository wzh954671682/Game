extends Node

## Spatial authority for the 1080x2160 portrait layout.
##
## Layout values can come from two sources:
##   1. Scene-driven (BattleUI.tscn) — visual editing, no code changes needed
##   2. Hardcoded LAYOUT_* constants — fallback defaults
##
## Layout:
##   Viewport Top
##     │  Grid (centered in remaining space above wall)
##     │
##   Wall Boundary  ←  wall_top (from scene or computed)
##     │  Wall Body
##   Wall Bottom    ←  wall_top + wall_h
##     │  gap
##   Card Tray Top
##     │  Card Tray
##   Viewport Bottom

const REF_WIDTH: int = 1080
const REF_HEIGHT: int = 2160
const GRID_COLS: int = 5
const GRID_ROWS: int = 5
const REF_CELL_SIZE: float = 190.0

# --- Fallback layout constants (used when no scene layout is applied) ---
const LAYOUT_CARD_TRAY_HEIGHT: float = 220.0
const LAYOUT_CARD_TRAY_BOTTOM_MARGIN: float = 20.0
const LAYOUT_WALL_HEIGHT: float = 46.0
const LAYOUT_WALL_TO_TRAY_GAP: float = 30.0


var _cell_size: float = 0.0
var _grid_center: Vector2 = Vector2.ZERO

# GridAnchor override (dynamic, set by BattleTest from BattleUI.tscn GridAnchor node)
var _grid_anchor_pos: Vector2 = Vector2.ZERO
var _has_grid_anchor: bool = false

# Scene-driven layout overrides
var _has_scene_layout: bool = false
var _scene_wall_top: float = 0.0
var _scene_wall_height: float = 0.0
var _scene_tray_top: float = 0.0
var _scene_tray_height: float = 0.0


func _ready() -> void:
	_refresh_layout()
	get_tree().root.size_changed.connect(_refresh_layout)


# ============================================================
# Scene layout injection (called by BattleTest after loading BattleUI.tscn)
# ============================================================

func set_grid_anchor_pos(pos: Vector2) -> void:
	_grid_anchor_pos = pos
	_has_grid_anchor = true
	_refresh_layout()
	print("[GridManager] GridAnchor 位置已注入: %s" % pos)


func apply_scene_layout(wall_rect: Rect2, tray_rect: Rect2) -> void:
	_scene_wall_top = wall_rect.position.y
	_scene_wall_height = wall_rect.size.y
	_scene_tray_top = tray_rect.position.y
	_scene_tray_height = tray_rect.size.y
	_has_scene_layout = true
	_refresh_layout()
	print("[GridManager] 场景布局已注入: wall_top=%.0f wall_h=%.0f tray_top=%.0f tray_h=%.0f" % [
		_scene_wall_top, _scene_wall_height, _scene_tray_top, _scene_tray_height,
	])


# ============================================================
# Grid coordinate conversion
# ============================================================

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


func _clamp_grid(pos: Vector2i) -> Vector2i:
	return Vector2i(clampi(pos.x, 0, GRID_COLS - 1), clampi(pos.y, 0, GRID_ROWS - 1))


# ============================================================
# Layout queries
# ============================================================

func get_grid_center() -> Vector2:
	return _grid_center


func get_card_tray_top() -> float:
	if _has_scene_layout:
		return _scene_tray_top
	return float(REF_HEIGHT) - LAYOUT_CARD_TRAY_HEIGHT - LAYOUT_CARD_TRAY_BOTTOM_MARGIN


func get_card_tray_height() -> float:
	if _has_scene_layout:
		return _scene_tray_height
	return LAYOUT_CARD_TRAY_HEIGHT


func get_wall_boundary() -> float:
	if _has_scene_layout:
		return _scene_wall_top
	return get_card_tray_top() - LAYOUT_WALL_TO_TRAY_GAP - LAYOUT_WALL_HEIGHT


func get_wall_height() -> float:
	if _has_scene_layout:
		return _scene_wall_height
	return LAYOUT_WALL_HEIGHT


func get_wall_bottom() -> float:
	return get_wall_boundary() + get_wall_height()


# ============================================================
# Internal
# ============================================================

func _refresh_layout() -> void:
	if _has_grid_anchor:
		_grid_center = _grid_anchor_pos
	else:
		var grid_top: float = 0.0
		var grid_bottom: float = get_wall_boundary()
		_grid_center = Vector2(REF_WIDTH / 2.0, (grid_top + grid_bottom) / 2.0)

	var viewport_rect: Rect2 = get_viewport().get_visible_rect()
	var vp_w: float = viewport_rect.size.x if viewport_rect.size.x > 0.0 else float(REF_WIDTH)
	var vp_h: float = viewport_rect.size.y if viewport_rect.size.y > 0.0 else float(REF_HEIGHT)

	var scale_x: float = vp_w / float(REF_WIDTH)
	var scale_y: float = vp_h / float(REF_HEIGHT)
	_cell_size = REF_CELL_SIZE * minf(scale_x, scale_y)
