extends Node

## Central battle orchestrator (Autoload).
## Manages forced displacement chains, grid occupancy, and coordinates
## multi-entity interactions on the 5x5 board.

const MAX_RECURSIVE_DEPTH: int = 5

var _grid_occupants: Dictionary = {}


func apply_displacement(target: Node2D, target_logic_pos: Vector2i) -> void:
	_apply_displacement_recursive(target, target_logic_pos, 0)


func register_entity(entity: Node2D, logic_pos: Vector2i) -> void:
	_grid_occupants[logic_pos] = entity


func unregister_entity(entity: Node2D) -> void:
	_remove_occupant(entity)


func _apply_displacement_recursive(target: Node2D, target_logic_pos: Vector2i, depth: int) -> void:
	if depth >= MAX_RECURSIVE_DEPTH:
		push_warning("BattleManager: 强制位移达到最大递归深度 " + str(MAX_RECURSIVE_DEPTH) + "，目标: " + target.name)
		return

	var occupant: Variant = _grid_occupants.get(target_logic_pos, null)
	if occupant != null and occupant != target:
		var next_logic_pos: Vector2i = target_logic_pos + Vector2i(0, -1)
		_apply_displacement_recursive(occupant as Node2D, next_logic_pos, depth + 1)

	_remove_occupant(target)
	_grid_occupants[target_logic_pos] = target

	var screen_pos: Vector2 = GridManager.get_screen_pos(target_logic_pos)

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_QUART)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(target, "global_position", screen_pos, 0.25)


func _remove_occupant(entity: Node2D) -> void:
	for pos: Vector2i in _grid_occupants.keys():
		if _grid_occupants[pos] == entity:
			_grid_occupants.erase(pos)
			return
