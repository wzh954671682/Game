extends Node2D

## Hero entity placed on the 5x5 grid. Uses a RayCast2D aimed upward to
## detect and intercept enemies in the same column at 10 Hz.

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


func try_intercept() -> void:
	if current_blocked_enemies.size() >= max_block_count:
		return

	if not block_raycast.is_colliding():
		return

	var collider: Variant = block_raycast.get_collider()
	if collider == null or not collider is Node2D:
		return

	if current_blocked_enemies.has(collider as Node2D):
		return

	current_blocked_enemies.append(collider as Node2D)
	print("英雄成功拦截怪物: ", (collider as Node2D).name)
