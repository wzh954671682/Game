extends Node

## Central battle orchestrator (Autoload).
## Manages forced displacement chains, grid occupancy, and coordinates
## multi-entity interactions on the 5x5 board.

const MAX_RECURSIVE_DEPTH: int = 5
const VICTORY_PANEL_PATH: String = "res://Scenes/UI/VictoryPanel.tscn"
const DEFEAT_PANEL_PATH: String = "res://Scenes/UI/DefeatPanel.tscn"

var grid_occupants: Dictionary = {}
var current_stage_id: String = "stage_001"


func apply_displacement(target: Node2D, target_logic_pos: Vector2i) -> void:
	_apply_displacement_recursive(target, target_logic_pos, 0)


func register_entity(entity: Node2D, logic_pos: Vector2i) -> void:
	grid_occupants[logic_pos] = entity


func unregister_entity(entity: Node2D) -> void:
	_remove_occupant(entity)


func _apply_displacement_recursive(target: Node2D, target_logic_pos: Vector2i, depth: int) -> void:
	if depth >= MAX_RECURSIVE_DEPTH:
		push_warning("BattleManager: 强制位移达到最大递归深度 " + str(MAX_RECURSIVE_DEPTH) + "，目标: " + target.name)
		return

	# 边界 clamp: 防止位移超出 5x5 网格
	target_logic_pos.x = clampi(target_logic_pos.x, 0, GridManager.GRID_COLS - 1)
	target_logic_pos.y = clampi(target_logic_pos.y, 0, GridManager.GRID_ROWS - 1)

	var occupant: Variant = grid_occupants.get(target_logic_pos, null)
	if occupant != null and occupant != target:
		var next_logic_pos: Vector2i = target_logic_pos + Vector2i(0, -1)
		_apply_displacement_recursive(occupant as Node2D, next_logic_pos, depth + 1)

	_remove_occupant(target)
	grid_occupants[target_logic_pos] = target

	var screen_pos: Vector2 = GridManager.get_screen_pos(target_logic_pos)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "global_position", screen_pos, 0.25)
	tween.finished.connect(_on_displacement_finished.bind(target, target_logic_pos))


func _remove_occupant(entity: Node2D) -> void:
	for pos: Vector2i in grid_occupants.keys():
		if grid_occupants[pos] == entity:
			grid_occupants.erase(pos)
			return


func get_hero_at(pos: Vector2i) -> Node2D:
	var occupant: Variant = grid_occupants.get(pos, null)
	if occupant != null and is_instance_valid(occupant) and occupant.has_method("try_intercept"):
		return occupant as Node2D
	return null


func _on_displacement_finished(entity: Node2D, logic_pos: Vector2i) -> void:
	if not is_instance_valid(entity):
		return

	# 仅对非英雄实体 (怪物) 触发英雄拦截重检
	if entity.has_method("try_intercept"):
		return

	# 边界安全检查
	if logic_pos.x < 0 or logic_pos.x >= GridManager.GRID_COLS or logic_pos.y < 0 or logic_pos.y >= GridManager.GRID_ROWS:
		push_warning("BattleManager: 实体 %s 位移后坐标 (%d,%d) 超出 5x5 边界" % [entity.name, logic_pos.x, logic_pos.y])
		return

	var hero: Node2D = get_hero_at(logic_pos)
	if hero != null:
		hero.try_intercept()


func show_settlement(is_victory: bool) -> void:
	var stages: Dictionary = DataManager.stage_config.get("stages", {})
	var stage_data: Dictionary = stages.get(current_stage_id, {})
	var rewards: Dictionary = stage_data.get("rewards", {})

	var reward_data: Dictionary
	if is_victory:
		reward_data = rewards.get("victory", {"coin": 0, "shard": 0})
	else:
		reward_data = rewards.get("defeat", {"coin": 0})

	var coin: int = reward_data.get("coin", 0)
	var shard: int = reward_data.get("shard", 0)
	var shard_id: String = reward_data.get("shard_id", "")

	var scene_path: String = VICTORY_PANEL_PATH if is_victory else DEFEAT_PANEL_PATH
	var panel_scene: PackedScene = load(scene_path)
	var panel: CanvasLayer = panel_scene.instantiate()

	var scene_root: Node = get_tree().current_scene
	scene_root.add_child(panel)
	panel.setup(is_victory, coin, shard, shard_id)
