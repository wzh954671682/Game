extends Node2D

## Phase 8 — 交互与手牌系统 (Card Tray System)
##
## 依赖: Scenes/Hero.tscn, Scenes/Enemy.tscn, Scenes/CardUI.tscn
## 用法: 直接运行 BattleTest.tscn 场景 (F6)
##
## 架构:
##   - CardTrayManager 管理卡牌托盘, 响应 DeckManager.card_drawn
##   - CardUI 自管理完整拖拽生命周期 (press → drag → release/cancel)
##   - BattleTest 只负责战场侧: 虚影/高亮/部署/敌人生成
##
## 功能:
##   - 底部卡牌托盘, 卡牌从 DeckManager 队列自动补充
##   - 拖拽卡牌到棋盘空格子部署英雄 (坐标: GridManager.get_logic_pos)
##   - 虚影跟随鼠标 + 绿色/红色网格高亮吸附预览
##   - 英雄拦截 + 击杀 + 顿帧 (Phase 6 功能保留)

const HERO_SCENE_PATH: String = "res://Scenes/Hero.tscn"
const ENEMY_SCENE_PATH: String = "res://Scenes/Enemy.tscn"
const CARD_SCENE_PATH: String = "res://Scenes/CardUI.tscn"
const HERO_DATA_PATH: String = "res://Data/heroes_progression.json"
const SPAWN_INTERVAL_SEC: float = 3.0
const SPAWN_OFFSET_ABOVE_SCREEN: float = -300.0
const INITIAL_CARD_POOL: Array[String] = ["shielder_01", "shielder_01", "shielder_01", "gunner_01", "gunner_01"]
const FALLBACK_CARD_ID: String = "shielder_01"

# Core systems
var _camera: Camera2D = null
var _spawn_timer: Timer = null
var _enemy_count: int = 0
var _hero_scene: PackedScene = null

# Hero templates: hero_id → Dictionary
var _hero_templates: Dictionary = {}

# Grid tracking
var _placed_heroes: Dictionary = {}  # Vector2i → Node2D

# Card tray manager (CardTrayManager class)
var _card_tray_manager: CardTrayManager = null

# Drag state (visual-only; lifecycle is owned by CardUI)
var _active_drag_card: Control = null
var _ghost_sprite: Sprite2D = null
var _highlight_grid_pos: Vector2i = Vector2i(-1, -1)
var _highlight_valid: bool = false


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_print_header()
	_validate_all_autoloads()
	_setup_camera()
	_load_scenes()
	_load_hero_templates()
	_create_drag_visuals()
	_setup_card_tray_manager()
	_connect_game_signals()
	_start_enemy_wave()
	_activate_deck_manager()

	print("[BattleTest] 初始化完毕 —— Phase 8 卡牌拖拽部署系统已就绪")
	print("[BattleTest] 等待卡牌补充...")


func _process(_delta: float) -> void:
	if _active_drag_card == null:
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	_ghost_sprite.global_position = mouse_pos

	var grid_pos: Vector2i = GridManager.get_logic_pos(mouse_pos)
	_highlight_grid_pos = grid_pos
	_highlight_valid = not _placed_heroes.has(grid_pos)

	_ghost_sprite.self_modulate = Color.GREEN if _highlight_valid else Color.RED
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
	var center: Vector2 = GridManager.get_grid_center()
	_camera.global_position = center
	add_child(_camera)
	_camera.make_current()

	print("[BattleTest] Camera2D 已对齐: 画面中心 = %s" % center)


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
# 卡牌托盘管理器 (CardTrayManager)
# ============================================================

func _setup_card_tray_manager() -> void:
	_card_tray_manager = CardTrayManager.new()
	_card_tray_manager.name = "CardTrayManager"
	_card_tray_manager.card_created.connect(_on_card_created)
	add_child(_card_tray_manager)

	var card_scene: PackedScene = load(CARD_SCENE_PATH)
	_card_tray_manager.setup(card_scene, _hero_templates)

	print("[BattleTest] CardTrayManager 已初始化")


func _on_card_created(card_ui: Control) -> void:
	card_ui.drag_started.connect(_on_card_drag_started)
	card_ui.drag_ended.connect(_on_card_drag_ended)
	card_ui.drag_cancelled.connect(_on_card_drag_cancelled)


# ============================================================
# 拖拽视觉元素 (虚影 + 网格高亮)
# ============================================================

func _create_drag_visuals() -> void:
	_ghost_sprite = Sprite2D.new()
	_ghost_sprite.name = "DragGhost"
	_ghost_sprite.texture = preload("res://icon.svg")
	_ghost_sprite.z_index = 100
	_ghost_sprite.visible = false
	add_child(_ghost_sprite)


func _draw() -> void:
	if _active_drag_card == null:
		return

	var cell_center: Vector2 = GridManager.get_screen_pos(_highlight_grid_pos)
	var half: Vector2 = Vector2(95, 95)  # REF_CELL_SIZE / 2
	var rect: Rect2 = Rect2(cell_center - half, half * 2)
	var color: Color = Color.GREEN if _highlight_valid else Color.RED
	color.a = 0.25
	draw_rect(rect, color, true)
	draw_rect(rect, color, false, 2.0)


# ============================================================
# 卡牌拖拽信号 (CardUI → BattleTest)
# ============================================================

func _on_card_drag_started(card_ui: Control) -> void:
	_active_drag_card = card_ui
	_ghost_sprite.visible = true


func _on_card_drag_ended(card_ui: Control, screen_pos: Vector2) -> void:
	_ghost_sprite.visible = false
	_highlight_grid_pos = Vector2i(-1, -1)
	queue_redraw()

	var vp_rect: Rect2 = get_viewport().get_visible_rect()

	# Reject drops on the card tray area
	var tray_top: float = vp_rect.size.y - CardTrayManager.TRAY_HEIGHT - CardTrayManager.TRAY_BOTTOM_MARGIN
	if screen_pos.y > tray_top:
		_cancel_deploy(card_ui)
		return

	# Reject drops outside viewport
	if not vp_rect.has_point(screen_pos):
		_cancel_deploy(card_ui)
		return

	# Coordinate alignment: hand area → grid logic → screen position
	var grid_pos: Vector2i = GridManager.get_logic_pos(screen_pos)

	# Reject drops on occupied cells
	if _placed_heroes.has(grid_pos):
		_cancel_deploy(card_ui)
		return

	# Deploy hero and consume card
	_deploy_hero_from_card(grid_pos, card_ui)
	_destroy_card(card_ui)


func _on_card_drag_cancelled(card_ui: Control) -> void:
	_active_drag_card = null
	_ghost_sprite.visible = false
	_highlight_grid_pos = Vector2i(-1, -1)
	queue_redraw()


func _cancel_deploy(card_ui: Control) -> void:
	_active_drag_card = null
	card_ui.cancel_drag()


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
	# Coordinate: grid logic → screen pixel → hero world position
	hero.global_position = GridManager.get_screen_pos(grid_pos)
	hero.init_hero(template)

	add_child(hero)
	BattleManager.register_entity(hero, grid_pos)
	_placed_heroes[grid_pos] = hero

	print("[BattleTest] 英雄部署: %s → 格子 %s" % [card_ui.hero_name, grid_pos])


# ============================================================
# GameEvents 信号
# ============================================================

func _connect_game_signals() -> void:
	if not GameEvents.wall_hit.is_connected(_on_wall_hit):
		GameEvents.wall_hit.connect(_on_wall_hit)
	if not GameEvents.enemy_died.is_connected(_on_enemy_died):
		GameEvents.enemy_died.connect(_on_enemy_died)


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
# DeckManager 激活
# ============================================================

func _activate_deck_manager() -> void:
	DeckManager.start_battle()
	DeckManager.enqueue_cards(INITIAL_CARD_POOL)
	print("[BattleTest] DeckManager 战斗状态已激活, 初始卡池 %d 张" % INITIAL_CARD_POOL.size())


# ============================================================
# 信号回调
# ============================================================

func _on_wall_hit(damage: int) -> void:
	push_warning("[BattleTest] >>> 城墙受击! 伤害 = %d <<<" % damage)


func _on_enemy_died(pos: Vector2) -> void:
	pass  # 死亡日志由 Hero.gd 的 [Kill] 负责


# ============================================================
# 辅助
# ============================================================

func _print_header() -> void:
	print("=")
	print("  Phase 8 — 交互与手牌系统 (Card Tray System)")
	print("  CardTrayManager + CardUI 自管理拖拽 + Ghost/Highlight")
	print("  分辨率: 1080x2160 | stretch=canvas_items/expand")
	print("=")
