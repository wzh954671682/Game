extends Node2D

## Phase 7 — 卡牌拖拽部署系统
##
## 依赖: Scenes/Hero.tscn, Scenes/Enemy.tscn, Scenes/CardUI.tscn
## 用法: 直接运行 BattleTest.tscn 场景 (F6)
##
## 功能:
##   - 底部卡牌托盘，卡牌从 DeckManager 队列自动补充
##   - 拖拽卡牌到棋盘空格子部署英雄
##   - 虚影跟随鼠标 + 绿色/红色网格高亮
##   - 卡牌弹跳入场动画
##   - 英雄拦截 + 击杀 + 顿帧 (Phase 6 功能保留)

const HERO_SCENE_PATH: String = "res://Scenes/Hero.tscn"
const ENEMY_SCENE_PATH: String = "res://Scenes/Enemy.tscn"
const CARD_SCENE_PATH: String = "res://Scenes/CardUI.tscn"
const HERO_DATA_PATH: String = "res://Data/heroes_progression.json"
const SPAWN_INTERVAL_SEC: float = 3.0
const SPAWN_OFFSET_ABOVE_SCREEN: float = -300.0
const INITIAL_CARD_POOL: Array[String] = ["shielder_01", "shielder_01", "shielder_01", "gunner_01", "gunner_01"]
const FALLBACK_CARD_ID: String = "shielder_01"
const CARD_TRAY_HEIGHT: float = 220.0
const CARD_TRAY_BOTTOM_MARGIN: float = 20.0

# Core systems
var _camera: Camera2D = null
var _spawn_timer: Timer = null
var _enemy_count: int = 0
var _hero_scene: PackedScene = null
var _card_scene: PackedScene = null

# Hero templates: hero_id → Dictionary
var _hero_templates: Dictionary = {}

# Grid tracking
var _placed_heroes: Dictionary = {}  # Vector2i → Node2D

# Card tray
var _card_tray: HBoxContainer = null

# Drag state
var _active_drag_card: Control = null
var _ghost_sprite: Sprite2D = null
var _highlight_grid_pos: Vector2i = Vector2i(-1, -1)
var _highlight_valid: bool = false
var _drag_world_pos: Vector2 = Vector2.ZERO


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_print_header()
	_validate_all_autoloads()
	_setup_camera()
	_load_scenes()
	_load_hero_templates()
	_create_card_tray()
	_create_drag_visuals()
	_connect_deck_signals()
	_connect_game_signals()
	_start_enemy_wave()
	_activate_deck_manager()
	set_process_input(true)

	print("[BattleTest] 初始化完毕 —— 从底部卡牌槽拖拽英雄到棋盘")
	print("[BattleTest] 等待卡牌补充...")


func _process(_delta: float) -> void:
	if _active_drag_card == null:
		return

	_drag_world_pos = get_global_mouse_position()
	_ghost_sprite.global_position = _drag_world_pos

	var grid_pos: Vector2i = GridManager.get_logic_pos(_drag_world_pos)
	_highlight_grid_pos = grid_pos
	_highlight_valid = not _placed_heroes.has(grid_pos)

	_ghost_sprite.self_modulate = Color.GREEN if _highlight_valid else Color.RED
	queue_redraw()


func _input(event: InputEvent) -> void:
	if _active_drag_card == null:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_end_card_drag()


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

	_card_scene = load(CARD_SCENE_PATH)
	if _card_scene == null:
		push_error("[BattleTest] 无法加载 CardUI.tscn")


# ============================================================
# 英雄模板 (所有模板, 按 hero_id 索引)
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
# 卡牌托盘 (底部 HBoxContainer)
# ============================================================

func _create_card_tray() -> void:
	_card_tray = HBoxContainer.new()
	_card_tray.name = "CardTray"
	_card_tray.layout_mode = 0
	_card_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_tray.add_theme_constant_override("separation", 8)
	add_child(_card_tray)
	_position_card_tray()
	get_tree().root.size_changed.connect(_position_card_tray)


func _position_card_tray() -> void:
	if _card_tray == null:
		return
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tray_width: float = minf(vp_size.x - 30.0, 820.0)
	_card_tray.position = Vector2(
		(vp_size.x - tray_width) / 2.0,
		vp_size.y - CARD_TRAY_HEIGHT - CARD_TRAY_BOTTOM_MARGIN
	)
	_card_tray.size = Vector2(tray_width, CARD_TRAY_HEIGHT)


# ============================================================
# 拖拽视觉元素 (虚影 + 高亮)
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
	var half: Vector2 = Vector2(95, 95)  # half of REF_CELL_SIZE
	var rect: Rect2 = Rect2(cell_center - half, half * 2)
	var color: Color = Color.GREEN if _highlight_valid else Color.RED
	color.a = 0.25
	draw_rect(rect, color, true)
	draw_rect(rect, color, false, 2.0)


# ============================================================
# DeckManager 信号 — 卡牌补充
# ============================================================

func _connect_deck_signals() -> void:
	if not DeckManager.card_drawn.is_connected(_on_card_drawn):
		DeckManager.card_drawn.connect(_on_card_drawn)


func _on_card_drawn(card_id: String) -> void:
	if _card_scene == null:
		push_error("[BattleTest] CardUI 场景未加载, 无法创建卡牌")
		return

	var template: Dictionary = _hero_templates.get(card_id, _hero_templates.get(FALLBACK_CARD_ID, {}))
	var hero_name: String = template.get("name", card_id)

	var card: Control = _card_scene.instantiate()
	card.setup(card_id, hero_name)
	card.drag_started.connect(_on_card_drag_started)
	card.drag_ended.connect(_on_card_drag_ended)

	_card_tray.add_child(card)
	_animate_card_entrance(card)

	print("[BattleTest] 卡牌入槽: %s (%s)" % [hero_name, card_id])


func _animate_card_entrance(card: Control) -> void:
	card.scale = Vector2.ZERO
	var tween: Tween = create_tween()
	tween.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ============================================================
# 卡牌拖拽信号
# ============================================================

func _on_card_drag_started(card_ui: Control) -> void:
	_active_drag_card = card_ui
	_ghost_sprite.visible = true
	print("[BattleTest] 拖拽开始: %s" % card_ui.hero_name)


func _on_card_drag_ended(card_ui: Control) -> void:
	# 备用路径: CardUI 暂不发射 drag_ended, 主路径为 _input → _end_card_drag
	_end_card_drag()


func _end_card_drag() -> void:
	var card: Control = _active_drag_card
	_active_drag_card = null
	_ghost_sprite.visible = false
	_highlight_grid_pos = Vector2i(-1, -1)
	queue_redraw()

	if card == null:
		return

	var world_pos: Vector2 = _drag_world_pos

	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	if not vp_rect.has_point(world_pos):
		print("[BattleTest] 拖放取消: 目标在视口外")
		card.cancel_drag()
		return

	var grid_pos: Vector2i = GridManager.get_logic_pos(world_pos)

	if _placed_heroes.has(grid_pos):
		print("[BattleTest] 拖放取消: 格子 %s 已有英雄" % grid_pos)
		card.cancel_drag()
		return

	_deploy_hero_from_card(grid_pos, card)

	card.drag_started.disconnect(_on_card_drag_started)
	card.drag_ended.disconnect(_on_card_drag_ended)
	card.queue_free()
	DeckManager.on_card_deployed()

	print("[BattleTest] 卡牌消耗: %s, 手牌=%d, 场上=%d" % [
		card.hero_name, DeckManager.hand_count, DeckManager.field_hero_count,
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
	# 填充初始卡池
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
	print("  Phase 7 — 卡牌拖拽部署系统")
	print("  从底部卡牌槽拖拽英雄到 5x5 棋盘部署")
	print("  分辨率: 1080x2160 | stretch=canvas_items/expand")
	print("=")
