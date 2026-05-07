extends Area2D

## Enemy entity that moves downward each frame. Supports pausing
## via set_paused() so heroes can freeze it during interception.

@export var move_speed: float = 100.0
@export var max_health: int = 100
@export var wall_damage: int = 1

var _current_health: int = max_health
var _is_paused: bool = false


func _ready() -> void:
	_current_health = max_health


func _physics_process(delta: float) -> void:
	if _is_paused:
		return

	global_position.y += move_speed * delta

	if global_position.y > _bottom_boundary():
		GameEvents.wall_hit.emit(wall_damage)
		queue_free()


func set_paused(is_paused: bool) -> void:
	_is_paused = is_paused


func _bottom_boundary() -> float:
	return get_viewport().get_visible_rect().size.y
