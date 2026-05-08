extends Area2D

## Enemy with sprite-sheet FSM.
## States: MOVE (loops move frames while descending),
## ATTACK (loops attack frames, emits attack_hit on frame 2),
## DEATH (plays deal frames once → fade → queue_free).

enum State { MOVE, ATTACK, DEATH }

signal attack_hit(damage: int)

@export var move_speed: float = 100.0
@export var max_health: int = 100
@export var wall_damage: int = 1
@export var attack_damage: int = 5
@export var monster_id: String = "01"
@export var frame_interval: float = 0.1

var current_hp: int = max_health
var _is_paused: bool = false
var _state: int = State.MOVE
var _current_frame: int = 0
var _frame_timer: float = 0.0
var _attack_hit_emitted: bool = false

var _frames_move: Array[Texture2D] = []
var _frames_attack: Array[Texture2D] = []
var _frames_deal: Array[Texture2D] = []

@onready var _sprite: Sprite2D = $Sprite2D


func _ready() -> void:
	current_hp = max_health
	_load_frames()
	_setup_flash_shader()
	_apply_state(State.MOVE)


func _load_frames() -> void:
	var base := "res://Assets/Monsters/monster_%s/" % monster_id
	for i in range(4):
		var idx := "%02d" % i
		_frames_move.append(load(base + "monster%s_move_%s.png" % [monster_id, idx]))
		_frames_attack.append(load(base + "monster%s_attack_%s.png" % [monster_id, idx]))
		_frames_deal.append(load(base + "monster%s_deal_%s.png" % [monster_id, idx]))


func _setup_flash_shader() -> void:
	var shader: Shader = load("res://Assets/Shaders/hit_flash.gdshader")
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_sprite.material = mat


func _physics_process(delta: float) -> void:
	# Movement (only in MOVE state when not paused)
	if _state == State.MOVE and not _is_paused:
		global_position.y += move_speed * delta
		if global_position.y > _bottom_boundary():
			GameEvents.wall_hit.emit(wall_damage)
			queue_free()

	_update_animation(delta)


func _update_animation(delta: float) -> void:
	_frame_timer -= delta
	if _frame_timer > 0.0:
		return
	_frame_timer = frame_interval

	var frames: Array[Texture2D]
	match _state:
		State.MOVE:   frames = _frames_move
		State.ATTACK: frames = _frames_attack
		State.DEATH:  frames = _frames_deal
		_:            return

	if frames.is_empty():
		return

	_current_frame += 1

	if _state == State.DEATH:
		if _current_frame >= frames.size():
			_current_frame = frames.size() - 1
			_on_death_animation_finished()
			return
	else:
		_current_frame %= frames.size()
		if _current_frame == 0:
			_attack_hit_emitted = false

	_sprite.texture = frames[_current_frame]

	if _state == State.ATTACK and _current_frame == 2 and not _attack_hit_emitted:
		_attack_hit_emitted = true
		attack_hit.emit(attack_damage)


func _apply_state(new_state: int) -> void:
	_state = new_state
	_current_frame = 0
	_frame_timer = 0.0
	_attack_hit_emitted = false

	var frames: Array[Texture2D]
	match _state:
		State.MOVE:   frames = _frames_move
		State.ATTACK: frames = _frames_attack
		State.DEATH:  frames = _frames_deal

	_sprite.texture = frames[0] if not frames.is_empty() else null


func set_paused(is_paused: bool) -> void:
	if _state == State.DEATH:
		return
	_is_paused = is_paused
	if is_paused:
		_apply_state(State.ATTACK)
	else:
		_apply_state(State.MOVE)


func take_damage(amount: int) -> bool:
	if _state == State.DEATH:
		return false

	current_hp -= amount

	if current_hp <= 0:
		_die()
		return true

	_play_hit_flash()
	return false


func _play_hit_flash() -> void:
	if _sprite.material == null:
		return
	_sprite.material.set_shader_parameter("flash_amount", 1.0)
	var tween := create_tween()
	tween.tween_property(_sprite.material, "shader_parameter/flash_amount", 0.0, 0.15)


func _die() -> void:
	_state = State.DEATH
	monitoring = false
	monitorable = false

	GameEvents.enemy_died.emit(global_position)
	_apply_state(State.DEATH)


func _on_death_animation_finished() -> void:
	set_process(false)
	set_physics_process(false)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()


func _bottom_boundary() -> float:
	return GridManager.get_wall_boundary()
