extends Node

## Data-driven wave director.
## Reads stage config from DataManager and spawns enemies on schedule.
## No hardcoded timing — everything comes from level_stage_config.json.

const ENEMY_SCENE_PATH: String = "res://Scenes/Enemy.tscn"
const SPAWN_OFFSET_ABOVE_SCREEN: float = -300.0

var _stage_id: String = ""
var _map_id: int = 1
var _waves: Array = []
var _wave_index: int = 0
var _stage_elapsed: float = 0.0
var _active: bool = false
var _all_spawned: bool = false

var _alive_enemy_count: int = 0
var _enemy_scene: PackedScene = null
var _spawn_counter: int = 0


func _ready() -> void:
	_enemy_scene = load(ENEMY_SCENE_PATH)
	if _enemy_scene == null:
		push_error("[WaveDirector] 无法加载 Enemy.tscn")

	if not GameEvents.enemy_died.is_connected(_on_enemy_died):
		GameEvents.enemy_died.connect(_on_enemy_died)


func _process(delta: float) -> void:
	if not _active:
		return

	_stage_elapsed += delta

	while _wave_index < _waves.size():
		var entry: Dictionary = _waves[_wave_index]
		if entry.spawn_time > _stage_elapsed:
			break
		_spawn(entry)
		_wave_index += 1

	if _wave_index >= _waves.size() and not _all_spawned:
		_all_spawned = true
		print("[WaveDirector] 全部 %d 波已派出, 等待清场..." % _waves.size())


func load_stage_script(stage_id: String) -> void:
	var stages: Dictionary = DataManager.stage_config.get("stages", {})
	var stage_data: Dictionary = stages.get(stage_id, {})

	if stage_data.is_empty():
		push_error("[WaveDirector] stage_id 不存在: " + stage_id)
		return

	_stage_id = stage_id
	_map_id = stage_data.get("map_id", 1)
	_waves = stage_data.get("waves", [])

	if _waves.is_empty():
		push_error("[WaveDirector] 关卡无波次数据: " + stage_id)
		return

	_wave_index = 0
	_stage_elapsed = 0.0
	_active = true
	_all_spawned = false
	_alive_enemy_count = 0
	_spawn_counter = 0

	print("[WaveDirector] 关卡脚本已加载: %s (map=%d, 波次=%d)" % [_stage_id, _map_id, _waves.size()])


func get_map_id() -> int:
	return _map_id


func get_wave_index() -> int:
	return _wave_index


func is_last_wave() -> bool:
	return _wave_index >= _waves.size()


func is_active() -> bool:
	return _active


func _spawn(entry: Dictionary) -> void:
	if _enemy_scene == null:
		push_error("[WaveDirector] Enemy.tscn 未加载, 无法生成")
		return

	var monster_id: String = entry.get("monster_id", "monster_01")
	var lane: int = clampi(entry.get("lane", 2), 0, 4)
	var hp_mult: float = entry.get("hp_multiplier", 1.0)

	var templates: Dictionary = DataManager.monster_templates.get("monster_templates", {})
	var template: Dictionary = templates.get(monster_id, {})

	var enemy: Area2D = _enemy_scene.instantiate()
	_spawn_counter += 1
	enemy.name = "Enemy_%03d" % _spawn_counter

	enemy.set("monster_id", monster_id.trim_prefix("monster_"))
	enemy.set("move_speed", template.get("base_speed", 100.0))
	enemy.set("max_health", int(template.get("base_hp", 100) * hp_mult))
	enemy.set("wall_damage", template.get("base_wall_damage", 1))
	enemy.set("attack_damage", template.get("base_attack_damage", 5))

	var spawn_logic: Vector2i = Vector2i(lane, 0)
	var screen_pos: Vector2 = GridManager.get_screen_pos(spawn_logic)
	screen_pos.y += SPAWN_OFFSET_ABOVE_SCREEN
	enemy.global_position = screen_pos

	get_parent().add_child(enemy)
	_alive_enemy_count += 1

	print("[WaveDirector] 波次 %d/%d: %s lane=%d hp×%.1f" % [
		_wave_index, _waves.size(), monster_id, lane, hp_mult,
	])


func _on_enemy_died(_pos: Vector2) -> void:
	_alive_enemy_count = maxi(_alive_enemy_count - 1, 0)
	_check_victory()


func _check_victory() -> void:
	if not _all_spawned:
		return
	if _alive_enemy_count > 0:
		return

	_active = false
	print("[WaveDirector] 关卡胜利: %s" % _stage_id)
	GameEvents.stage_victory.emit(_stage_id)
