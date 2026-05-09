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

# CardStartMarker override (from BattleUI.tscn)
var _card_start_pos: Vector2 = Vector2.ZERO
var _has_card_start: bool = false

# Per-tile visual system (Phase 13+)
const TILE_COUNT: int = 25
const MAP_CONFIG_PATH: String = "res://Data/battleMap_config.json"

var _tile_nodes: Array[Sprite2D] = []
var _map_bg: Sprite2D = null
var _battle_ui: CanvasLayer = null
var _tiles_ready: bool = false
var _current_map_id: int = 0


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


func set_card_start_pos(pos: Vector2) -> void:
	_card_start_pos = pos
	_has_card_start = true
	print("[GridManager] CardStartMarker 位置已注入: %s" % pos)


func get_card_start_pos() -> Vector2:
	if _has_card_start:
		return _card_start_pos
	# Fallback: 托盘左侧 + 半个卡宽
	var tray_max_w: float = minf(float(REF_WIDTH) - 30.0, 820.0)
	return Vector2(
		(float(REF_WIDTH) - tray_max_w) / 2.0 + 75.0,
		get_card_tray_top() + get_card_tray_height() / 2.0
	)


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
	if _tiles_ready:
		var tile: Sprite2D = get_tile_for_grid_pos(clamped)
		if tile != null and is_instance_valid(tile):
			return tile.global_position
	# Fallback: math-based (no tile nodes cached)
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
# Map loading — 关卡背景 + 地块纹理注入
# ============================================================

func setup_map(battle_ui: CanvasLayer, map_bg: Sprite2D) -> void:
	_battle_ui = battle_ui
	_map_bg = map_bg
	_cache_tile_nodes()
	if _tile_nodes.size() == TILE_COUNT:
		_tiles_ready = true
		print("[GridManager] setup_map: %d 个地块节点已缓存" % _tile_nodes.size())
	else:
		push_error("[GridManager] setup_map: 仅找到 %d/%d 个 Tile 节点 (GridAnchor 下)" % [_tile_nodes.size(), TILE_COUNT])


func load_battle_map(map_id: int) -> void:
	if map_id < 1 or map_id > 5:
		push_error("[GridManager] load_battle_map: 无效的 map_id=%d (仅支持 1-5)" % map_id)
		return

	_current_map_id = map_id
	var cfg: Dictionary = _load_map_config(map_id)
	if cfg.is_empty():
		push_error("[GridManager] load_battle_map: battleMap_config.json 中无关卡 %d" % map_id)
		return

	# 1. 背景
	var bg_path: String = cfg.get("bg", "")
	if not bg_path.is_empty():
		_apply_background(bg_path)

	# 2. 地块纹理
	var tile_dir: String = cfg.get("tile_dir", "")
	var tile_pat: String = cfg.get("tile_pattern", "gezi_{n}.png")
	if not tile_dir.is_empty():
		_apply_tile_textures(tile_dir, tile_pat)

	# 3. 重算地块世界位置 (基于当前 grid_center + cell_size)
	_position_all_tiles()

	print("[GridManager] load_battle_map(%d) 完成 — bg=%s  tile_dir=%s" % [map_id, bg_path, tile_dir])


func load_map_async(map_id: int) -> void:
	print("[GridManager] load_map_async(%d) — 异步加载接口预留, 当前回退到同步加载" % map_id)
	load_battle_map(map_id)


func get_tile_node(index: int) -> Sprite2D:
	if index >= 1 and index <= _tile_nodes.size():
		return _tile_nodes[index - 1]
	return null


func get_tile_for_grid_pos(grid_pos: Vector2i) -> Sprite2D:
	var index: int = grid_pos.y * GRID_COLS + grid_pos.x
	return get_tile_node(index + 1)


# ============================================================
# Internal — map loading helpers
# ============================================================

func _cache_tile_nodes() -> void:
	_tile_nodes.clear()
	if _battle_ui == null:
		return
	var grid_anchor: Control = _battle_ui.get_node_or_null("GridAnchor") as Control
	if grid_anchor == null:
		push_error("[GridManager] _cache_tile_nodes: GridAnchor 节点不存在")
		return
	for i: int in range(1, TILE_COUNT + 1):
		var tile: Sprite2D = grid_anchor.get_node_or_null("Tile_%d" % i) as Sprite2D
		_tile_nodes.append(tile)


func _load_map_config(map_id: int) -> Dictionary:
	var raw: Dictionary = DataManager.load_json(MAP_CONFIG_PATH)
	if raw.is_empty():
		return {}
	var levels: Dictionary = raw.get("levels", {})
	return levels.get(str(map_id), {})


func _apply_background(bg_path: String) -> void:
	if _map_bg == null or not is_instance_valid(_map_bg):
		push_error("[GridManager] _apply_background: MapBackground 引用无效")
		return
	var tex: Texture2D = load(bg_path)
	if tex == null:
		push_error("[GridManager] 无法加载背景贴图: %s" % bg_path)
		return
	_map_bg.texture = tex
	_map_bg.position = Vector2(REF_WIDTH / 2.0, REF_HEIGHT / 2.0)


func _apply_tile_textures(tile_dir: String, pattern: String) -> void:
	var loaded: int = 0
	for i: int in range(1, TILE_COUNT + 1):
		if i - 1 >= _tile_nodes.size():
			break
		var tile: Sprite2D = _tile_nodes[i - 1]
		if not is_instance_valid(tile):
			continue
		var file_name: String = pattern.replace("{n}", "%02d" % i)
		var path: String = "%s/%s" % [tile_dir, file_name]
		var tex: Texture2D = load(path)
		if tex:
			tile.texture = tex
			loaded += 1
	if loaded > 0:
		print("[GridManager] _apply_tile_textures: %d/%d 地块纹理已加载" % [loaded, TILE_COUNT])


func _position_all_tiles() -> void:
	for row: int in range(GRID_ROWS):
		for col: int in range(GRID_COLS):
			var index: int = row * GRID_COLS + col + 1
			if index - 1 >= _tile_nodes.size():
				continue
			var tile: Sprite2D = _tile_nodes[index - 1]
			if not is_instance_valid(tile):
				continue
			tile.position = Vector2(
				(col - 2) * _cell_size,
				(row - 2) * _cell_size
			)


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
