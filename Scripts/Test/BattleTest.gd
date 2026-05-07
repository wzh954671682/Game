extends Node2D

## Phase 5 —— 视觉验证测试 (Battle Visual Test)
##
## 依赖: Scenes/Hero.tscn, Scenes/Enemy.tscn (用户已创建)
## 用法: 直接运行 BattleTest.tscn 场景 (F6)
##
## 功能:
##   - 校验全部 7 个 Autoload 单例可用性
##   - 动态创建 Camera2D 并对齐棋盘中心
##   - 从 Hero.tscn 实例化英雄，部署到网格中心 (2,2)
##   - 每 3 秒从顶部的随机列实例化 Enemy.tscn，模拟波次进攻
##   - 监听 wall_hit / enemy_died 全局信号

const HERO_SCENE_PATH: String = "res://Scenes/Hero.tscn"
const ENEMY_SCENE_PATH: String = "res://Scenes/Enemy.tscn"
const GRID_CENTER: Vector2i = Vector2i(2, 2)
const SPAWN_INTERVAL_SEC: float = 3.0
const SPAWN_OFFSET_ABOVE_SCREEN: float = -300.0

var _hero: Node2D = null
var _camera: Camera2D = null
var _spawn_timer: Timer = null
var _enemy_count: int = 0


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_print_header()
	_validate_all_autoloads()
	_setup_camera()
	_spawn_hero()
	_connect_signals()
	_start_enemy_wave()
	_activate_deck_manager()

	print("[BattleTest] 初始化完毕 —— 英雄已就位, 等待敌人波次...")


# ============================================================
# Autoload 可用性校验
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
# Camera2D —— 动态创建并对齐棋盘中心
# ============================================================

func _setup_camera() -> void:
	_camera = Camera2D.new()
	_camera.name = "BattleCamera"
	_camera.enabled = true
	# 默认 ANCHOR_MODE_DRAG_CENTER: camera.global_position 即为画面显示中心
	var center: Vector2 = GridManager.get_grid_center()
	_camera.global_position = center
	add_child(_camera)
	_camera.make_current()

	print("[BattleTest] Camera2D 已对齐: 画面中心 = %s" % center)


# ============================================================
# 英雄实例化 (从 Hero.tscn)
# ============================================================

func _spawn_hero() -> void:
	var hero_scene: PackedScene = load(HERO_SCENE_PATH)
	if hero_scene == null:
		push_error("[BattleTest] 无法加载 Hero.tscn: " + HERO_SCENE_PATH)
		return

	_hero = hero_scene.instantiate()
	_hero.name = "BattleTestHero"

	var screen_pos: Vector2 = GridManager.get_screen_pos(GRID_CENTER)
	_hero.global_position = screen_pos

	add_child(_hero)
	BattleManager.register_entity(_hero, GRID_CENTER)

	print("[BattleTest] 英雄已部署: 逻辑格子 %s | 屏幕坐标 (%.0f, %.0f)" % [GRID_CENTER, screen_pos.x, screen_pos.y])


# ============================================================
# 全局信号连接
# ============================================================

func _connect_signals() -> void:
	if not GameEvents.wall_hit.is_connected(_on_wall_hit):
		GameEvents.wall_hit.connect(_on_wall_hit)
	if not GameEvents.enemy_died.is_connected(_on_enemy_died):
		GameEvents.enemy_died.connect(_on_enemy_died)


# ============================================================
# 敌人波次计时器
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


# ============================================================
# 敌人实例化 (从 Enemy.tscn)
# ============================================================

func _spawn_enemy() -> void:
	var enemy_scene: PackedScene = load(ENEMY_SCENE_PATH)
	if enemy_scene == null:
		push_error("[BattleTest] 无法加载 Enemy.tscn: " + ENEMY_SCENE_PATH)
		return

	# 随机列 (0-4)，Y 在屏幕顶部上方
	var col: int = randi_range(0, 4)
	var spawn_logic: Vector2i = Vector2i(col, 0)
	var screen_pos: Vector2 = GridManager.get_screen_pos(spawn_logic)
	screen_pos.y += SPAWN_OFFSET_ABOVE_SCREEN

	var enemy: Area2D = enemy_scene.instantiate()
	_enemy_count += 1
	enemy.name = "Enemy_%03d" % _enemy_count

	# 略微随机化速度，让视觉上不单调
	enemy.set("move_speed", 90.0 + randf_range(-20.0, 40.0))
	enemy.global_position = screen_pos

	add_child(enemy)

	print("[BattleTest] 敌人生成 #%d | 列=%d | pos=(%.0f, %.0f) | speed=%.1f" % [
		_enemy_count, col, screen_pos.x, screen_pos.y, enemy.get("move_speed")
	])


# ============================================================
# DeckManager 激活
# ============================================================

func _activate_deck_manager() -> void:
	DeckManager.start_battle()
	print("[BattleTest] DeckManager 战斗状态已激活")


# ============================================================
# 全局信号回调
# ============================================================

func _on_wall_hit(damage: int) -> void:
	push_warning("[BattleTest] >>> 城墙受击! 伤害 = %d <<<" % damage)


func _on_enemy_died(pos: Vector2) -> void:
	print("[BattleTest] 敌人死亡于 (%d, %d)" % [int(pos.x), int(pos.y)])


# ============================================================
# 辅助输出
# ============================================================

func _print_header() -> void:
	print("=")
	print("  Phase 5 — BattleTest 视觉验证")
	print("  1 英雄(中心) + 每 %.1fs 随机列生成敌人" % SPAWN_INTERVAL_SEC)
	print("  分辨率: 1080x2160 | stretch=canvas_items/expand")
	print("=")
