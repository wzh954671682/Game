extends Node2D

## Hero entity placed on the 5x5 grid. Uses a RayCast2D aimed upward to
## detect and intercept enemies in the same column at 10 Hz.
## Call init_hero(data) after instantiation to configure from a template.

@export var max_block_count: int = 1
var current_blocked_enemies: Array[Node2D] = []

@onready var block_raycast: RayCast2D = $RayCast2D

const DETECT_INTERVAL: float = 0.1
var _detect_accumulator: float = 0.0


func _physics_process(delta: float) -> void:
	_detect_accumulator += delta
	if _detect_accumulator < DETECT_INTERVAL:
		return
	_detect_accumulator -= DETECT_INTERVAL
	try_intercept()


func init_hero(data: Dictionary) -> void:
	max_block_count = data.get("block_count", 1)


func try_intercept() -> void:
	if current_blocked_enemies.size() >= max_block_count:
		return

	block_raycast.force_raycast_update()

	if not block_raycast.is_colliding():
		return

	var collider: Variant = block_raycast.get_collider()
	if collider == null or not collider is Node2D:
		return

	var enemy: Node2D = collider as Node2D
	if current_blocked_enemies.has(enemy):
		return

	current_blocked_enemies.append(enemy)

	if enemy.has_method("set_paused"):
		enemy.set_paused(true)

	print("[Intercepted] 英雄拦截怪物: %s (当前拦截数: %d/%d)" % [enemy.name, current_blocked_enemies.size(), max_block_count])
