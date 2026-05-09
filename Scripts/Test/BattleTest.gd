extends Node2D

## Phase 10+ — 场景驱动 UI (Scene-Driven Layout)
##
## 布局从 BattleUI.tscn 读取, 用户可在 Godot 编辑器中可视调整
## 城墙 / 血条 / 手牌托盘位置, 无需修改代码.
##
## BattleUI.tscn (CanvasLayer) 结构:
##   Wall (ColorRect)          — 城墙视觉实体
##     HPBarBg (ColorRect)     — 血条背景
##     HPBarFill (ColorRect)   — 血条填充 (代码控制宽度)
##   CardTrayAnchor (ColorRect) — 手牌托盘占位标记

const HERO_SCENE_PATH: String = "res://Scenes/Hero.tscn"
const ENEMY_SCENE_PATH: String = "res://Scenes/Enemy.tscn"
const CARD_SCENE_PATH: String = "res://Scenes/CardUI.tscn"
const BATTLE_UI_PATH: String = "res://Scenes/UI/BattleUI.tscn"
const HERO_DATA_PATH: String = "res://Data/heroes_progression.json"
const BATTLE_MAP_DATA_PATH: String = "res://Data/battle_map.json"
const SPAWN_INTERVAL_SEC: float = 3.0
const SPAWN_OFFSET_ABOVE_SCREEN: float = -300.0
const INITIAL_CARD_POOL: Array[String] = [
	"shielder_01", "shielder_01", "shielder_01", "shielder_01", "shielder_01",
	"gunner_01", "gunner_01", "gunner_01", "gunner_01", "gunner_01",
]
const FALLBACK_CARD_ID: String = "shielder_01"

# === Wall state ===
const WALL_MAX_HP: int = 50
const WALL_FLASH_SEC: float = 0.15
const WALL_HP_TWEEN_SEC: float = 0.25

const WALL_COLOR_NORMAL: Color = Color(0.25, 0.35, 0.50, 0.92)
const WALL_COLOR_FLASH: Color = Color(0.90, 0.15, 0.10, 0.95)
const WALL_COLOR_DEAD: Color = Color(0.08, 0.06, 0.06, 0.70)

const HP_COLOR_GREEN: Color = Color(0.20, 0.80, 0.30, 0.95)
const HP_COLOR_YELLOW: Color = Color(0.90, 0.80, 0.15, 0.95)
const HP_COLOR_RED: Color = Color(0.85, 0.15, 0.10, 0.95)

# Level config (map per level)
@export var current_level_id: String = "level_01"
@export var current_map_id: int = 1

# Core systems
var _map_sprite: Sprite2D = null
var _camera: Camera2D = null
var _spawn_timer: Timer = null
var _enemy_count: int = 0
var _hero_scene: PackedScene = null

# Hero templates: hero_id → Dictionary
var _hero_templates: Dictionary = {}

# Grid tracking
var _placed_heroes: Dictionary = {}  # Vector2i → Node2D

# Card tray
var _card_tray_manager: CardTrayManager = null

# Drag state (visual-only; lifecycle is owned by CardUI)
var _active_drag_card: Control = null
var _ghost_sprite: Sprite2D = null
var _highlight_grid_pos: Vector2i = Vector2i(-1, -1)
var _highlight_valid: bool = false
var _highlight_synthesis: bool = false

# Wall state
var _wall_current_hp: int = WALL_MAX_HP
var _wall_displayed_hp: float = float(WALL_MAX_HP)
var _wall_flash_active: bool = false
var _wall_is_dead: bool = false
var _wall_hp_tween: Tween = null
var _wall_flash_timer: Timer = null
var _wall_spawn_blocked: bool = false

# Scene-driven UI nodes (from BattleUI.tscn)
var _battle_ui: CanvasLayer = null
var _wall_node: TextureRect = null
var _hp_bar_fill: ColorRect = null
var _hp_fill_max_width: float = 0.0
var _hp_label: Label = null
var _tray_anchor: ColorRect = null
var _grid_anchor: Control = null
var _hand_container: Control = null


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_print_header()
	_validate_all_autoloads()
	_setup_camera()
	_load_map_background()
	_load_battle_ui()
	_setup_grid_map()
	_load_scenes()
	_load_hero_templates()
	_create_drag_ghost()
	_setup_card_tray_manager()
	_setup_wall_flash_timer()
	_connect_game_signals()
	_start_enemy_wave()
	_activate_deck_manager()

	print("[BattleTest] Grid center=%s  Wall boundary=%.0f  Tray top=%.0f" % [
		GridManager.get_grid_center(),
		GridManager.get_wall_boundary(),
		GridManager.get_card_tray_top(),
	])
	print("[BattleTest] 城墙 HP: %d/%d" % [_wall_current_hp, WALL_MAX_HP])


func _process(_delta: float) -> void:
	if _active_drag_card == null:
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	_ghost_sprite.global_position = mouse_pos

	var grid_pos: Vector2i = GridManager.get_logic_pos(mouse_pos)
	_highlight_grid_pos = grid_pos

	# Phase 9: synthesis detection
	_highlight_synthesis = false
	if _placed_heroes.has(grid_pos):
		var existing: Node2D = _placed_heroes[grid_pos]
		if existing.has_method("can_star_up") and existing.can_star_up(_active_drag_card.card_id):
			_highlight_synthesis = true
			_highlight_valid = false
		else:
			_highlight_valid = false
	else:
		_highlight_valid = true

	if _highlight_synthesis:
		_ghost_sprite.self_modulate = Color.GOLD
	elif _highlight_valid:
		_ghost_sprite.self_modulate = Color.GREEN
	else:
		_ghost_sprite.self_modulate = Color.RED
	queue_redraw()


# ============================================================
# Autoload 校验
# ============================================================

func _validate_all_autoloads() -> void:
	var autoloads: Dictionary = {
		"GameEvents"    = GameEvents,
		"DataManager"   = DataManager,
		"GridManager"   = GridManager,
		"BattleManager" = BattleManager,
		"DeckManager"   = DeckManager,
		"VFXManager"    = VFXManager,
		"SaveManager"   = SaveManager,
	}

	var missing: PackedStringArray = []
	for name: String in autoloads:
		if not is_instance_valid(autoloads[name]):
			missing.append(name)

	if not missing.is_empty():
		push_error("[BattleTest] Autoload 缺失 (%d/%d): %s" % [missing.size(), autoloads.size(), ", ".join(missing)])
	else:
		print("[BattleTest] 全部 %d 个 Autoload 单例校验通过" % autoloads.size())


# ============================================================
# Camera2D
# ============================================================

func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "BattleCamera"
	_camera.enabled = true
	_camera.global_position = Vector2(GridManager.REF_WIDTH / 2.0, GridManager.REF_HEIGHT / 2.0)
	add_child(_camera)
	_camera.make_current()

	print("[BattleTest] Camera2D 视口中心对齐: %s" % _camera.global_position)


# ============================================================
# 关卡地图背景 (从 battle_map.json 读表)
# ============================================================

func _load_map_background() -> void:
	if not has_node("MapBackground"):
		push_error("[BattleTest] MapBackground 节点缺失, 请在 BattleTest.tscn 中确认")
		return
	_map_sprite = $MapBackground
	print("[BattleTest] MapBackground 节点引用已获取")


# ============================================================
# 场景驱动 UI — 加载 BattleUI.tscn, 读取节点位置注入 GridManager
# ============================================================

func _load_battle_ui() -> void:
	var ui_scene: PackedScene = load(BATTLE_UI_PATH)
	if ui_scene == null:
		push_error("[BattleTest] 无法加载 BattleUI.tscn, 回退到常量布局")
		return

	_battle_ui = ui_scene.instantiate()
	_battle_ui.name = "BattleUI"
	add_child(_battle_ui)

	_wall_node = _battle_ui.get_node_or_null("Wall") as TextureRect
	_hp_bar_fill = _battle_ui.get_node_or_null("Wall/HPBarFill") as ColorRect
	_hp_label = _battle_ui.get_node_or_null("Wall/HPLabel") as Label
	_tray_anchor = _battle_ui.get_node_or_null("CardTrayAnchor") as ColorRect
	_grid_anchor = _battle_ui.get_node_or_null("GridAnchor") as Control
	_hand_container = _battle_ui.get_node_or_null("HandContainer") as Control

	if _wall_node and _tray_anchor:
		var wall_rect := Rect2(_wall_node.position, _wall_node.size)
		var tray_rect := Rect2(_tray_anchor.position, _tray_anchor.size)
		GridManager.apply_scene_layout(wall_rect, tray_rect)
	else:
		push_error("[BattleTest] BattleUI.tscn 节点缺失, 回退到常量布局")

	if _hp_bar_fill:
		_hp_fill_max_width = _hp_bar_fill.size.x

	if _hp_label:
		_hp_label.text = "%d/%d" % [_wall_current_hp, WALL_MAX_HP]

	if _grid_anchor:
		var anchor_center := _grid_anchor.global_position + _grid_anchor.size * 0.5
		GridManager.set_grid_anchor_pos(anchor_center)

		var card_marker: Control = _battle_ui.get_node_or_null("CardTrayAnchor/CardStartMarker") as Control
		if card_marker:
			var card_start := card_marker.global_position + card_marker.size * 0.5
			GridManager.set_card_start_pos(card_start)

	print("[BattleTest] BattleUI.tscn 已加载到 CanvasLayer")


# ============================================================
# Grid map — 委托 GridManager 加载关卡背景 + 地块纹理
# ============================================================

func _setup_grid_map() -> void:
	if _battle_ui == null or _map_sprite == null:
		push_error("[BattleTest] _setup_grid_map: BattleUI 或 MapBackground 未就绪")
		return

	GridManager.setup_map(_battle_ui, _map_sprite)
	GridManager.load_battle_map(current_map_id)


# ============================================================
# 场景资源预加载
# ============================================================

func _load_scenes() -> void:
	_hero_scene = load(HERO_SCENE_PATH)
	if _hero_scene == null:
		push_error("[BattleTest] 无法加载 Hero.tscn")


# ============================================================
# 英雄模板
# ============================================================

func _load_hero_templates() -> void:
	var raw: Dictionary = DataManager.load_json(HERO_DATA_PATH)
	if raw.is_empty():
		push_error("[BattleTest] heroes_progression.json 加载失败")
		return

	var templates: Array = raw.get("hero_base_templates", [])
	if templates.is_empty():
		push_error("[BattleTest] hero_base_templates 为空")
		return

	for t: Dictionary in templates:
		var hid: String = t.get("hero_id", "")
		if hid.is_empty():
			continue
		_hero_templates[hid] = t

	print("[BattleTest] 英雄模板加载: %d 个 (%s)" % [_hero_templates.size(), ", ".join(_hero_templates.keys())])


# ============================================================
# 卡牌托盘 (挂载在 BattleUI CanvasLayer 下)
# ============================================================

func _setup_card_tray_manager() -> void:
	_card_tray_manager = CardTrayManager.new()
	_card_tray_manager.name = "CardTrayManager"
	_card_tray_manager.card_created.connect(_on_card_created)

	if _hand_container:
		_card_tray_manager.layout_mode = 1
		_card_tray_manager.anchors_preset = 15
		_hand_container.add_child(_card_tray_manager)
	elif _battle_ui:
		_battle_ui.add_child(_card_tray_manager)
	else:
		push_error("[BattleTest] 无法挂载 CardTrayManager")
		return

	var card_scene: PackedScene = load(CARD_SCENE_PATH)
	_card_tray_manager.setup(card_scene, _hero_templates)

	print("[BattleTest] CardTrayManager 已挂载到 HandContainer")

func _on_card_created(card_ui: Control) -> void:
	card_ui.drag_started.connect(_on_card_drag_started)
	card_ui.drag_ended.connect(_on_card_drag_ended)
	card_ui.drag_cancelled.connect(_on_card_drag_cancelled)


# ============================================================
# 拖拽幽灵 (仍在 Node2D 世界)
# ============================================================

func _create_drag_ghost() -> void:
	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.name = "DragGhost"
	_ghost_sprite.texture = preload("res://icon.svg")
	_ghost_sprite.z_index = 100
	_ghost_sprite.visible = false
	add_child(_ghost_sprite)


func _setup_wall_flash_timer() -> void:
	_wall_flash_timer = Timer.new()
	_wall_flash_timer.name = "WallFlashTimer"
	_wall_flash_timer.one_shot = true
	_wall_flash_timer.wait_time = WALL_FLASH_SEC
	_wall_flash_timer.timeout.connect(_on_wall_flash_end)
	add_child(_wall_flash_timer)


func _on_wall_flash_end() -> void:
	_wall_flash_active = false
	if _wall_node:
		_wall_node.self_modulate = WALL_COLOR_DEAD if _wall_is_dead else Color.WHITE


# ============================================================
# _draw() — 仅保留网格高亮 (城墙/血条改为 ColorRect 节点)
# ============================================================

func _draw() -> void:
	if _active_drag_card != null:
		_draw_grid_highlight()


func _draw_grid_highlight() -> void:
	var cell_center: Vector2 = GridManager.get_screen_pos(_highlight_grid_pos)
	var half: Vector2 = Vector2(95, 95)
	var rect: Rect2 = Rect2(cell_center - half, half * 2)
	var color: Color
	if _highlight_synthesis:
		color = Color.GOLD
	elif _highlight_valid:
		color = Color.GREEN
	else:
		color = Color.RED
	color.a = 0.25
	draw_rect(rect, color, true)
	draw_rect(rect, color, false, 2.0)


# ============================================================
# 卡牌拖拽信号
# ============================================================

func _on_card_drag_started(card_ui: Control) -> void:
	_active_drag_card = card_ui
	_ghost_sprite.visible = true


func _on_card_drag_ended(card_ui: Control, _screen_pos: Vector2) -> void:
	_ghost_sprite.visible = false
	_highlight_grid_pos = Vector2i(-1, -1)
	_highlight_synthesis = false
	queue_redraw()

	# Use world-space mouse position (same coordinate system as _process)
	var world_pos: Vector2 = get_global_mouse_position()

	# Reject drops onto the card tray
	if world_pos.y > GridManager.get_card_tray_top():
		_cancel_deploy(card_ui)
		return

	# Reject drops below the wall (below game area)
	if world_pos.y > GridManager.get_wall_boundary():
		_cancel_deploy(card_ui)
		return

	var grid_pos: Vector2i = GridManager.get_logic_pos(world_pos)

	# Phase 9: synthesis detection
	if _placed_heroes.has(grid_pos):
		var existing_hero: Node2D = _placed_heroes[grid_pos]
		var same_id: bool = existing_hero.get("hero_id") == card_ui.card_id
		var can_up: bool = existing_hero.has_method("can_star_up") and existing_hero.can_star_up(card_ui.card_id)

		if same_id and can_up:
			_synthesize_hero(existing_hero, card_ui)
			_destroy_card(card_ui)
			return
		elif same_id:
			print("[BattleTest] 星级已满: %s 已达5★, 无法继续合成" % card_ui.hero_name)

		_cancel_deploy(card_ui)
		return

	_deploy_hero_from_card(grid_pos, card_ui)
	_destroy_card(card_ui)


func _on_card_drag_cancelled(card_ui: Control) -> void:
	_active_drag_card = null
	_ghost_sprite.visible = false
	_highlight_grid_pos = Vector2i(-1, -1)
	_highlight_synthesis = false
	queue_redraw()


func _cancel_deploy(card_ui: Control) -> void:
	_active_drag_card = null
	_highlight_synthesis = false
	card_ui.cancel_drag()


func _synthesize_hero(hero: Node2D, card_ui: Control) -> void:
	_active_drag_card = null
	_highlight_synthesis = false
	hero.star_up()
	print("[BattleTest] 合成成功: %s → %d★ (%s)" % [card_ui.hero_name, hero.current_star, hero.get_star_label()])


func _destroy_card(card_ui: Control) -> void:
	if card_ui.drag_started.is_connected(_on_card_drag_started):
		card_ui.drag_started.disconnect(_on_card_drag_started)
	if card_ui.drag_ended.is_connected(_on_card_drag_ended):
		card_ui.drag_ended.disconnect(_on_card_drag_ended)
	if card_ui.drag_cancelled.is_connected(_on_card_drag_cancelled):
		card_ui.drag_cancelled.disconnect(_on_card_drag_cancelled)
	card_ui.queue_free()
	DeckManager.on_card_deployed()
	_active_drag_card = null

	print("[BattleTest] 卡牌消耗: %s, 手牌=%d, 场上=%d" % [
		card_ui.hero_name, DeckManager.hand_count, DeckManager.field_hero_count,
	])


# ============================================================
# 英雄部署
# ============================================================

func _deploy_hero_from_card(grid_pos: Vector2i, card_ui: Control) -> void:
	if _hero_scene == null:
		push_error("[BattleTest] Hero.tscn 未加载")
		return

	var template: Dictionary = _hero_templates.get(card_ui.card_id, _hero_templates.get(FALLBACK_CARD_ID, {}))

	var hero: Node2D = _hero_scene.instantiate()
	hero.name = "Hero_%s" % card_ui.hero_name

	var drop_start := GridManager.get_screen_pos(grid_pos)
	drop_start.y -= 200.0
	hero.global_position = drop_start
	hero.init_hero(template)

	add_child(hero)
	BattleManager.apply_displacement(hero, grid_pos)
	_sync_placed_heroes()

	print("[BattleTest] 英雄部署: %s → 格子 %s" % [card_ui.hero_name, grid_pos])


# ============================================================
# Grid 同步
# ============================================================

func _sync_placed_heroes() -> void:
	_placed_heroes.clear()
	for pos: Vector2i in BattleManager.grid_occupants:
		var entity: Node2D = BattleManager.grid_occupants[pos]
		if entity.has_method("init_hero"):
			_placed_heroes[pos] = entity


# ============================================================
# GameEvents 信号
# ============================================================

func _connect_game_signals() -> void:
	if not GameEvents.wall_hit.is_connected(_on_wall_hit):
		GameEvents.wall_hit.connect(_on_wall_hit)
	if not GameEvents.enemy_died.is_connected(_on_enemy_died):
		GameEvents.enemy_died.connect(_on_enemy_died)


# ============================================================
# 城墙受击 — 操控 ColorRect 节点 (不再用 _draw)
# ============================================================

func _on_wall_hit(damage: int) -> void:
	if _wall_is_dead:
		return

	var old_hp: int = _wall_current_hp
	_wall_current_hp = maxi(_wall_current_hp - damage, 0)

	if _hp_label:
		_hp_label.text = "%d/%d" % [_wall_current_hp, WALL_MAX_HP]

	# Red flash via Wall ColorRect
	_wall_flash_active = true
	_wall_flash_timer.start()
	if _wall_node:
		_wall_node.self_modulate = WALL_COLOR_FLASH

	# Smooth HP bar via tween (controls HPBarFill ColorRect)
	if _wall_hp_tween and _wall_hp_tween.is_valid():
		_wall_hp_tween.kill()
	_wall_hp_tween = create_tween()
	_wall_hp_tween.tween_method(
		_on_wall_hp_tween_step,
		float(old_hp),
		float(_wall_current_hp),
		WALL_HP_TWEEN_SEC,
	)

	GameEvents.wall_hp_changed.emit(_wall_current_hp, WALL_MAX_HP)

	print("[BattleTest] 城墙受击! 伤害=%d, HP: %d/%d" % [damage, _wall_current_hp, WALL_MAX_HP])

	if _wall_current_hp <= 0:
		_trigger_game_over()


func _on_wall_hp_tween_step(value: float) -> void:
	_wall_displayed_hp = value
	if _hp_bar_fill:
		var ratio: float = _wall_displayed_hp / float(WALL_MAX_HP)
		_hp_bar_fill.size.x = _hp_fill_max_width * ratio
		if ratio > 0.5:
			_hp_bar_fill.color = HP_COLOR_GREEN
		elif ratio > 0.25:
			_hp_bar_fill.color = HP_COLOR_YELLOW
		else:
			_hp_bar_fill.color = HP_COLOR_RED

	if _hp_label:
		_hp_label.text = "%d/%d" % [int(_wall_displayed_hp), WALL_MAX_HP]


func _trigger_game_over() -> void:
	_wall_is_dead = true
	_wall_spawn_blocked = true

	if _wall_node:
		_wall_node.self_modulate = WALL_COLOR_DEAD

	if _spawn_timer:
		_spawn_timer.stop()

	GameEvents.game_over.emit()
	push_error("[BattleTest] ========== 城墙已毁! 游戏结束 ==========")


# ============================================================
# 敌人波次
# ============================================================

func _start_enemy_wave() -> void:
	_spawn_timer = Timer.new()
	_spawn_timer.name = "EnemyWaveSpawner"
	_spawn_timer.wait_time = SPAWN_INTERVAL_SEC
	_spawn_timer.one_shot = false
	_spawn_timer.timeout.connect(_on_spawn_tick)
	add_child(_spawn_timer)
	_spawn_timer.start()

	print("[BattleTest] 敌人波次已启动: 间隔 %.1f 秒" % SPAWN_INTERVAL_SEC)


func _on_spawn_tick() -> void:
	if _wall_spawn_blocked:
		return
	_spawn_enemy()


func _spawn_enemy() -> void:
	var enemy_scene: PackedScene = load(ENEMY_SCENE_PATH)
	if enemy_scene == null:
		push_error("[BattleTest] 无法加载 Enemy.tscn")
		return

	var col: int = randi_range(0, 4)
	var spawn_logic: Vector2i = Vector2i(col, 0)
	var screen_pos: Vector2 = GridManager.get_screen_pos(spawn_logic)
	screen_pos.y += SPAWN_OFFSET_ABOVE_SCREEN

	var enemy: Area2D = enemy_scene.instantiate()
	_enemy_count += 1
	enemy.name = "Enemy_%03d" % _enemy_count
	enemy.set("move_speed", 90.0 + randf_range(-20.0, 40.0))
	enemy.global_position = screen_pos

	add_child(enemy)


# ============================================================
# DeckManager
# ============================================================

func _activate_deck_manager() -> void:
	DeckManager.start_battle()
	DeckManager.enqueue_cards(INITIAL_CARD_POOL)
	print("[BattleTest] DeckManager 战斗状态已激活, 初始卡池 %d 张" % INITIAL_CARD_POOL.size())


# ============================================================
# 信号回调
# ============================================================

func _on_enemy_died(pos: Vector2) -> void:
	pass


# ============================================================
# 辅助
# ============================================================

func _print_header() -> void:
	print("=")
	print("  Phase 10+ — 场景驱动 UI (BattleUI.tscn)")
	print("  城墙/血条/手牌位置 → 编辑 Scenes/UI/BattleUI.tscn 即可可视调整")
	print("  分辨率: 1080x2160 | stretch=canvas_items/expand")
	print("=")
