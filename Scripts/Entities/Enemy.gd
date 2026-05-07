extends Area2D

## Enemy entity that moves downward each frame. Reaching the viewport
## bottom triggers wall_hit and self-destructs.

@export var move_speed: float = 100.0
@export var max_health: int = 100
@export var wall_damage: int = 1

var _current_health: int = max_health


func _ready() -> void:
	_current_health = max_health


func _physics_process(delta: float) -> void:
	global_position.y += move_speed * delta

	if global_position.y > _bottom_boundary():
		GameEvents.wall_hit.emit(wall_damage)
		queue_free()


func _bottom_boundary() -> float:
	return get_viewport().get_visible_rect().size.y
