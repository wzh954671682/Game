extends Node2D

## Phase 6 —— 交互部署与拦截验证
##
## 依赖: Scenes/Hero.tscn, Scenes/Enemy.tscn
## 用法: 直接运行 BattleTest.tscn 场景 (F6)
##
## 功能:
##   - 点击 5x5 棋盘任意空格子部署英雄
##   - 英雄自动检测上方同列敌人并拦截（暂停敌人移动）
##   - 每 3 秒从顶部随机列生成敌人
##   - 控制台输出 [Intercepted] 拦截日志

const HERO_SCENE_PATH: String = "res://Scenes/Hero.tscn"
const ENEMY_SCENE_PATH: String = "res://Scenes/Enemy.tscn"
const HERO_DATA_PATH: String = "res://Data/heroes_progression.json"
const SPAWN_INTERVAL_SEC: float = 3.0
const SPAWN_OFFSET_ABOVE_SCREEN: float = -300.0

var _camera: Camera2D = null
var _spawn_timer: Timer = null
var _enemy_count: int = 0
var _hero_scene: PackedScene = null
var _hero_template: Dictionary = {}
var _placed_heroes: Dictionary = {}  # Vector2i → Node2D


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_print_header()
	_validate_all_autoloads()
	_setup_camera()
	_load_hero_scene()
	_load_hero_template()
	_setup_input()
	_connect_signals()
	_start_enemy_wave()
	_activate_deck_manager()

	print("[BattleTest] 初始化完毕 —— 点击棋盘空格子部署英雄")


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
# 资源预加载
# ============================================================

func _load_hero_scene() -> void:
	_hero_scene = load(HERO_SCENE_PATH)
	if _hero_scene == null:
		push_error("[BattleTest] 无法加载 Hero.tscn: " + HERO_SCENE_PATH)


func _load_hero_template() -> void:
	var raw: Dictionary = DataManager.load_json(HERO_DATA_PATH)
	if raw.is_empty():
		push_error("[BattleTest] heroes_progression.json 加载失败")
		return

	var templates: Array = raw.get("hero_base_templates", [])
	if templates.is_empty():
		push_error("[BattleTest] hero_base_templates 为空")
		return

	_hero_template = templates[0] as Dictionary
	print("[BattleTest] 英雄模板加载: %s (block_count=%d)" % [
		_hero_template.get("hero_id", "???"),
		_hero_template.get("block_count", 1),
	])


# ============================================================
# 输入配置
# ============================================================

func _setup_input() -> void:
	set_process_unhandled_input(true)


# ============================================================
# 点击部署英雄
# ============================================================

func _unhandled_input(event: InputEvent) -> void:
	if _hero_scene == null:
		return

	if not (event is InputEventMouseButton):
		return
	if not event.pressed:
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var world_pos: Vector2 = get_global_mouse_position()

	# 校验点击在视口范围内
	var vp_rect: Rect2 = get_viewport().get_visible_rect()
	if not vp_rect.has_point(world_pos):
		return

	var grid_pos: Vector2i = GridManager.get_logic_pos(world_pos)

	# 该格子已有英雄
	if _placed_heroes.has(grid_pos):
		print("[BattleTest] 格子 %s 已存在英雄，忽略点击" % grid_pos)
		return

	_deploy_hero(grid_pos)


func _deploy_hero(grid_pos: Vector2i) -> void:
	var hero: Node2D = _hero_scene.instantiate()
	hero.name = "Hero_%d_%d" % [grid_pos.x, grid_pos.y]
	hero.global_position = GridManager.get_screen_pos(grid_pos)

	if _hero_template.has("block_count"):
		hero.init_hero(_hero_template)

	add_child(hero)
	BattleManager.register_entity(hero, grid_pos)
	_placed_heroes[grid_pos] = hero

	print("[BattleTest] 英雄部署于格子 %s | screen=(%.0f, %.0f)" % [
		grid_pos, hero.global_position.x, hero.global_position.y,
	])


# ============================================================
# 全局信号
# ============================================================

func _connect_signals() -> void:
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
		push_error("[BattleTest] 无法加载 Enemy.tscn: " + ENEMY_SCENE_PATH)
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

	print("[BattleTest] 敌人生成 #%d | 列=%d | pos=(%.0f, %.0f)" % [
		_enemy_count, col, screen_pos.x, screen_pos.y,
	])


# ============================================================
# DeckManager
# ============================================================

func _activate_deck_manager() -> void:
	DeckManager.start_battle()
	print("[BattleTest] DeckManager 战斗状态已激活")


# ============================================================
# 信号回调
# ============================================================

func _on_wall_hit(damage: int) -> void:
	push_warning("[BattleTest] >>> 城墙受击! 伤害 = %d <<<" % damage)


func _on_enemy_died(pos: Vector2) -> void:
	print("[BattleTest] 敌人死亡于 (%d, %d)" % [int(pos.x), int(pos.y)])


# ============================================================
# 辅助
# ============================================================

func _print_header() -> void:
	print("=")
	print("  Phase 6 — 交互部署与拦截验证")
	print("  点击棋盘空格子部署英雄 | 每 %.1fs 随机列生成敌人" % SPAWN_INTERVAL_SEC)
	print("  分辨率: 1080x2160 | stretch=canvas_items/expand")
	print("=")
