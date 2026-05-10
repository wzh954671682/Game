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
const CARD_SCENE_PATH: String = "res://Scenes/CardUI.tscn"
const BATTLE_UI_PATH: String = "res://Scenes/UI/BattleUI.tscn"
const HERO_DATA_PATH: String = "res://Data/heroes_progression.json"
const BATTLE_MAP_DATA_PATH: String = "res://Data/battle_map.json"
const INITIAL_CARD_POOL: Array[String] = [
	"shielder_01", "shielder_01", "shielder_01", "shielder_01", "shielder_01",
	"hero_002", "hero_002", "hero_002",
	"hero_003", "hero_003",
	"hero_004", "hero_004",
	"adventure_freeze", "global_heal", "buff_armor", "exclusive_cell",
	"exclusive_rapid_fire", "exclusive_stim",
]
const FALLBACK_CARD_ID: String = "shielder_01"

## Godot 4.6 — Control.LayoutMode enum not exposed to GDScript as named constants.
## 0 = position-based, 1 = anchor-based (see Control.layout_mode docs).
const LAYOUT_POSITION: int = 0
const LAYOUT_ANCHORS: int = 1

# === Wall state ===
var _wall_max_hp: int = 0
const WALL_FLASH_SEC: float = 0.15
const WALL_HP_TWEEN_SEC: float = 0.25

const WALL_COLOR_NORMAL: Color = Color(0.25, 0.35, 0.50, 0.92)
const WALL_COLOR_FLASH: Color = Color(0.90, 0.15, 0.10, 0.95)
const WALL_COLOR_DEAD: Color = Color(0.08, 0.06, 0.06, 0.70)

const HP_COLOR_GREEN: Color = Color(0.20, 0.80, 0.30, 0.95)
const HP_COLOR_YELLOW: Color = Color(0.90, 0.80, 0.15, 0.95)
const HP_COLOR_RED: Color = Color(0.85, 0.15, 0.10, 0.95)

# Stage config — map_id is derived from level_stage_config.json
@export var current_stage_id: String = "stage_001"
var _current_map_id: int = 1

# Core systems
var _map_sprite: Sprite2D = null
var _camera: Camera2D = null
var _wave_director: Node = null
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
var _wall_current_hp: int = 0
var _wall_displayed_hp: float = 0.0
var _wall_flash_active: bool = false
var _wall_is_dead: bool = false
var _wall_hp_tween: Tween = null
var _wall_flash_timer: Timer = null
var _wall_spawn_blocked: bool = false

# Player EXP state
var _player_level: int = 1
var _player_current_exp: int = 0
var _player_needed_exp: int = 100

# Scene-driven UI nodes (from BattleUI.tscn)
var _battle_ui: CanvasLayer = null
var _wall_node: TextureRect = null
var _hp_bar_fill: ColorRect = null
var _hp_fill_max_width: float = 0.0
var _hp_label: Label = null
var _tray_anchor: Control = null
var _grid_anchor: Control = null
var _hand_container: Control = null


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	_wall_max_hp = DataManager.wall_config.get("base_hp", 50)
	_wall_current_hp = _wall_max_hp
	_wall_displayed_hp = float(_wall_max_hp)
	_init_player_exp()
	_print_header()
	_validate_all_autoloads()
	_setup_camera()
	_load_map_background()
	_load_battle_ui()
	_setup_wave_director()
	_load_stage_data()
	_setup_grid_map()
	_load_scenes()
	_load_hero_templates()
	_create_drag_ghost()
	_setup_card_tray_manager()
	_setup_wall_flash_timer()
	_connect_game_signals()
	_launch_wave_director()
	_activate_deck_manager()

	print("[BattleTest] Grid center=%s  Wall boundary=%.0f  Tray top=%.0f" % [
		GridManager.get_grid_center(),
		GridManager.get_wall_boundary(),
		GridManager.get_card_tray_top(),
	])
	print("[BattleTest] 城墙 HP: %d/%d" % [_wall_current_hp, _wall_max_hp])


func _process(_delta: float) -> void:
	if _active_drag_card == null:
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	_ghost_sprite.global_position = mouse_pos

	var grid_pos: Vector2i = GridManager.get_logic_pos(mouse_pos)
	_highlight_grid_pos = grid_pos

	# Highlight: effect cards always valid, hero cards use synthesis logic
	var card_type: String = EffectResolver.card_type_from_id(_active_drag_card.card_id)
	if card_type != "hero":
		_highlight_synthesis = false
		_highlight_valid = true
	else:
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
	for autoload_name: String in autoloads:
		if not is_instance_valid(autoloads[autoload_name]):
			missing.append(autoload_name)

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
	_tray_anchor = _battle_ui.get_node_or_null("CardTrayAnchor") as Control
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
		_hp_label.text = "%d/%d" % [_wall_current_hp, _wall_max_hp]

	if _grid_anchor:
		var anchor_center := _grid_anchor.global_position + _grid_anchor.size * 0.5
		GridManager.set_grid_anchor_pos(anchor_center)

		# Reparent GridAnchor from CanvasLayer → Node2D world.
		# GridAnchor is a Control with anchor-based layout (anchors_preset=7),
		# which collapses under Node2D. Save the screen position, switch to
		# position-based layout, and restore so tiles + enemy spawns stay correct.
		var saved_pos: Vector2 = _grid_anchor.global_position
		_battle_ui.remove_child(_grid_anchor)
		add_child(_grid_anchor)
		_grid_anchor.layout_mode = LAYOUT_POSITION
		_grid_anchor.global_position = saved_pos

		var card_marker: Control = _battle_ui.get_node_or_null("CardTrayAnchor/CardStartMarker") as Control
		if card_marker:
			var card_start := card_marker.global_position + card_marker.size * 0.5
			GridManager.set_card_start_pos(card_start)

	print("[BattleTest] BattleUI.tscn 已加载到 CanvasLayer, GridAnchor 已移至 2D 世界")


# ============================================================
# Grid map — 委托 GridManager 加载关卡背景 + 地块纹理
# ============================================================

func _setup_grid_map() -> void:
	if _grid_anchor == null or _map_sprite == null:
		push_error("[BattleTest] _setup_grid_map: GridAnchor 或 MapBackground 未就绪")
		return

	GridManager.setup_map(_grid_anchor, _map_sprite)
	GridManager.load_battle_map(_current_map_id)


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
		_card_tray_manager.layout_mode = LAYOUT_ANCHORS
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

	var grid_pos: Vector2i = GridManager.get_logic_pos(world_pos)

	# Effect card branch — data-driven, no grid deployment
	if EffectResolver.card_type_from_id(card_ui.card_id) != "hero":
		_handle_effect_card(card_ui, grid_pos)
		return

	# Reject hero drops below the wall
	if world_pos.y > GridManager.get_wall_boundary():
		_cancel_deploy(card_ui)
		return

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


# ============================================================
# 效果卡处理
# ============================================================

func _handle_effect_card(card_ui: Control, grid_pos: Vector2i) -> void:
	var card_data: Dictionary = EffectResolver.get_card_data(card_ui.card_id)
	if card_data.is_empty():
		print("[BattleTest] 效果卡数据未找到: " + card_ui.card_id)
		_cancel_deploy(card_ui)
		return

	var result: Dictionary = EffectResolver.resolve_targets(card_data, grid_pos)
	if not result.get("ok", false):
		print("[BattleTest] 效果卡释放失败: " + result.get("error", "未知错误"))
		_cancel_deploy(card_ui)
		return

	EffectResolver.execute_card(card_data, result.get("targets", []))

	var vfx_path: String = card_data.get("vfx_prefab_path", "")
	if not vfx_path.is_empty():
		var vfx_pos: Vector2 = GridManager.get_grid_center()
		var targets: Array = result.get("targets", [])
		if targets.size() > 0 and is_instance_valid(targets[0]):
			vfx_pos = (targets[0] as Node2D).global_position
		VFXManager.play_skill_vfx(vfx_path, vfx_pos)

	_destroy_card(card_ui, true)


func _destroy_card(card_ui: Control, is_effect: bool = false) -> void:
	if card_ui.drag_started.is_connected(_on_card_drag_started):
		card_ui.drag_started.disconnect(_on_card_drag_started)
	if card_ui.drag_ended.is_connected(_on_card_drag_ended):
		card_ui.drag_ended.disconnect(_on_card_drag_ended)
	if card_ui.drag_cancelled.is_connected(_on_card_drag_cancelled):
		card_ui.drag_cancelled.disconnect(_on_card_drag_cancelled)
	card_ui.queue_free()

	if is_effect:
		DeckManager.on_effect_used()
	else:
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
	GameEvents.card_deployed.emit(grid_pos, card_ui.card_id)

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
	if not GameEvents.stage_victory.is_connected(_on_stage_victory):
		GameEvents.stage_victory.connect(_on_stage_victory)
	if not GameEvents.game_over.is_connected(_on_game_over):
		GameEvents.game_over.connect(_on_game_over)


# ============================================================
# 城墙受击 — 操控 ColorRect 节点 (不再用 _draw)
# ============================================================

func _on_wall_hit(damage: int) -> void:
	if _wall_is_dead:
		return

	var old_hp: int = _wall_current_hp
	_wall_current_hp = maxi(_wall_current_hp - damage, 0)

	if _hp_label:
		_hp_label.text = "%d/%d" % [_wall_current_hp, _wall_max_hp]

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

	GameEvents.wall_hp_changed.emit(_wall_current_hp, _wall_max_hp)

	print("[BattleTest] 城墙受击! 伤害=%d, HP: %d/%d" % [damage, _wall_current_hp, _wall_max_hp])

	if _wall_current_hp <= 0:
		_trigger_game_over()


func _on_wall_hp_tween_step(value: float) -> void:
	_wall_displayed_hp = value
	if _hp_bar_fill:
		var ratio: float = _wall_displayed_hp / float(_wall_max_hp)
		_hp_bar_fill.size.x = _hp_fill_max_width * ratio
		if ratio > 0.5:
			_hp_bar_fill.color = HP_COLOR_GREEN
		elif ratio > 0.25:
			_hp_bar_fill.color = HP_COLOR_YELLOW
		else:
			_hp_bar_fill.color = HP_COLOR_RED

	if _hp_label:
		_hp_label.text = "%d/%d" % [int(_wall_displayed_hp), _wall_max_hp]


func _trigger_game_over() -> void:
	_wall_is_dead = true
	_wall_spawn_blocked = true

	if _wall_node:
		_wall_node.self_modulate = WALL_COLOR_DEAD

	if _wave_director:
		_wave_director.set_process(false)

	GameEvents.game_over.emit()
	push_error("[BattleTest] ========== 城墙已毁! 游戏结束 ==========")


# ============================================================
# WaveDirector — 数据驱动波次
# ============================================================

func _setup_wave_director() -> void:
	var wd_script: Script = load("res://Scripts/Logic/WaveDirector.gd")
	if wd_script == null:
		push_error("[BattleTest] 无法加载 WaveDirector.gd")
		return

	_wave_director = Node.new()
	_wave_director.name = "WaveDirector"
	_wave_director.set_script(wd_script)
	add_child(_wave_director)

	print("[BattleTest] WaveDirector 已挂载")


func _load_stage_data() -> void:
	var stages: Dictionary = DataManager.stage_config.get("stages", {})
	var stage_data: Dictionary = stages.get(current_stage_id, {})

	if stage_data.is_empty():
		push_error("[BattleTest] stage_id 不存在: " + current_stage_id)
		return

	_current_map_id = stage_data.get("map_id", 1)
	BattleManager.current_stage_id = current_stage_id
	print("[BattleTest] 关卡数据已加载: stage=%s map=%d" % [current_stage_id, _current_map_id])


func _launch_wave_director() -> void:
	if _wave_director == null:
		push_error("[BattleTest] WaveDirector 未就绪, 无法开怪")
		return

	_wave_director.load_stage_script(current_stage_id)
	print("[BattleTest] 波次导演已启动: stage=%s" % current_stage_id)


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

func _on_enemy_died(_pos: Vector2, exp_reward: int) -> void:
	if exp_reward > 0:
		_add_exp(exp_reward)


func _init_player_exp() -> void:
	var levels: Array = DataManager.player_battle_exp.get("levels", [])
	if levels.size() > 0:
		_player_needed_exp = levels[0].get("exp_required", 100)


func _add_exp(amount: int) -> void:
	_player_current_exp += amount
	while _player_current_exp >= _player_needed_exp:
		_player_current_exp -= _player_needed_exp
		_player_level += 1
		_player_needed_exp = _get_needed_exp(_player_level)
	if _battle_ui and _battle_ui.has_method("update_exp"):
		_battle_ui.update_exp(_player_current_exp, _player_needed_exp)
	if _battle_ui and _battle_ui.has_method("update_battle_level"):
		_battle_ui.update_battle_level(_player_level)


func _get_needed_exp(level: int) -> int:
	var levels: Array = DataManager.player_battle_exp.get("levels", [])
	for entry in levels:
		if entry is Dictionary and entry.get("level", 0) == level:
			return entry.get("exp_required", _player_needed_exp)
	return _player_needed_exp


func _on_stage_victory(stage_id: String) -> void:
	print("[BattleTest] 关卡胜利: %s" % stage_id)
	_wall_spawn_blocked = true
	BattleManager.show_settlement(true)


func _on_game_over() -> void:
	print("[BattleTest] 关卡失败, 弹出结算")
	BattleManager.show_settlement(false)


# ============================================================
# 辅助
# ============================================================

func _print_header() -> void:
	print("=")
	print("  Phase 10+ — 场景驱动 UI (BattleUI.tscn)")
	print("  城墙/血条/手牌位置 → 编辑 Scenes/UI/BattleUI.tscn 即可可视调整")
	print("  分辨率: 1080x2160 | stretch=canvas_items/expand")
	print("=")
