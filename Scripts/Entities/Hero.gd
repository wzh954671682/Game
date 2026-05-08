extends Node2D

## Hero entity placed on the 5x5 grid. Uses a RayCast2D aimed upward to
## detect and intercept enemies in the same column at 10 Hz.
## Call init_hero(data) after instantiation to configure from a template.

@export var max_block_count: int = 1
@export var attack_power: int = 10
@export var attack_speed: float = 1.0  # attacks per second

var current_blocked_enemies: Array[Node2D] = []

@onready var block_raycast: RayCast2D = $RayCast2D

const DETECT_INTERVAL: float = 0.1
var _detect_accumulator: float = 0.0
var _attack_cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	# Interception scan at 10 Hz
	_detect_accumulator += delta
	if _detect_accumulator >= DETECT_INTERVAL:
		_detect_accumulator -= DETECT_INTERVAL
		try_intercept()

	# Attack logic: ticks every frame, fires at attack_speed intervals
	if not current_blocked_enemies.is_empty():
		_attack_cooldown -= delta
		if _attack_cooldown <= 0.0:
			_attack_cooldown = 1.0 / attack_speed
			_attack_current_target()
	else:
		_attack_cooldown = 0.0


func init_hero(data: Dictionary) -> void:
	max_block_count = data.get("block_count", 1)
	attack_power = data.get("base_atk", 10)
	attack_speed = 1.0


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


func _attack_current_target() -> void:
	_cleanup_dead_enemies()

	if current_blocked_enemies.is_empty():
		return

	var target: Node2D = current_blocked_enemies[0]
	if not is_instance_valid(target):
		current_blocked_enemies.pop_front()
		return

	var target_name: String = target.name

	if target.has_method("take_damage"):
		var killed: bool = target.take_damage(attack_power)
		if killed:
			current_blocked_enemies.pop_front()
			VFXManager.hit_stop(0.05)
			print("[Kill] 英雄击杀怪物: %s (剩余拦截: %d)" % [target_name, current_blocked_enemies.size()])


func _cleanup_dead_enemies() -> void:
	var i: int = current_blocked_enemies.size() - 1
	while i >= 0:
		if not is_instance_valid(current_blocked_enemies[i]):
			current_blocked_enemies.remove_at(i)
		i -= 1
