extends Node

## Global VFX orchestrator (Autoload). Handles hit-stop (frame freeze)
## and will later manage screen shake, death particles, etc.
##
## Runs in PROCESS_MODE_ALWAYS so it remains unaffected by Engine.time_scale.

var _hit_stop_count: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func hit_stop(duration_sec: float = 0.05, time_scale: float = 0.1) -> void:
	_hit_stop_count += 1
	Engine.time_scale = time_scale

	# Timer must ignore time_scale so the restore fires in real-time seconds
	# regardless of the current Engine.time_scale value.
	await get_tree().create_timer(duration_sec, true, false, true).timeout

	_hit_stop_count -= 1
	if _hit_stop_count <= 0:
		_hit_stop_count = 0
		Engine.time_scale = 1.0
