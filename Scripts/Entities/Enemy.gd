extends Area2D

## Enemy entity that moves downward each frame. Supports pausing
## via set_paused() so heroes can freeze it during interception.
## When HP reaches 0 through take_damage(), plays a death animation
## (scale → 0 + fade) and emits GameEvents.enemy_died.

@export var move_speed: float = 100.0
@export var max_health: int = 100
@export var wall_damage: int = 1

var current_hp: int = max_health
var _is_paused: bool = false


func _ready() -> void:
	current_hp = max_health


func _physics_process(delta: float) -> void:
	if _is_paused:
		return

	global_position.y += move_speed * delta

	if global_position.y > _bottom_boundary():
		GameEvents.wall_hit.emit(wall_damage)
		queue_free()


func set_paused(is_paused: bool) -> void:
	_is_paused = is_paused


func take_damage(amount: int) -> bool:
	current_hp -= amount
	if current_hp <= 0:
		_die()
		return true
	return false


func _die() -> void:
	set_process(false)
	set_physics_process(false)
	monitoring = false
	monitorable = false

	GameEvents.enemy_died.emit(global_position)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "scale", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK)
	tween.tween_property(self, "modulate:a", 0.0, 0.3)

	await tween.finished
	queue_free()


func _bottom_boundary() -> float:
	return GridManager.get_wall_boundary()
