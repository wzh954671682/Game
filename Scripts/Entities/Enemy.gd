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
@export var is_elite: bool = false
@export var is_boss: bool = false

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
@onready var hp_bar: TextureProgressBar = null if not has_node("HPBar") else $HPBar
@onready var hp_bar_red: TextureProgressBar = null if not has_node("HPBarRed") else $HPBarRed


func _ready() -> void:
	z_index = 0
	current_hp = max_health
	_load_frames()
	_setup_flash_shader()
	_setup_hp_bars()
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


func _setup_hp_bars() -> void:
	if not is_elite and not is_boss:
		return

	var style_fg := StyleBoxFlat.new()
	style_fg.bg_color = Color.RED if is_boss else Color.ORANGE
	var style_bg := StyleBoxFlat.new()
	style_bg.bg_color = Color(0.4, 0.0, 0.0, 0.8)

	if hp_bar_red and is_instance_valid(hp_bar_red):
		hp_bar_red.max_value = max_health
		hp_bar_red.value = max_health
		hp_bar_red.add_theme_stylebox_override("fill", style_bg)
		hp_bar_red.add_theme_stylebox_override("background", StyleBoxEmpty.new())
		hp_bar_red.size = Vector2(80, 8)
		hp_bar_red.position = Vector2(-40, -80)
		hp_bar_red.show()

	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.max_value = max_health
		hp_bar.value = max_health
		hp_bar.add_theme_stylebox_override("fill", style_fg)
		hp_bar.add_theme_stylebox_override("background", StyleBoxEmpty.new())
		hp_bar.size = Vector2(80, 8)
		hp_bar.position = Vector2(-40, -80)
		hp_bar.z_index = 1
		hp_bar.show()


func _physics_process(delta: float) -> void:
	# Movement (only in MOVE state when not paused)
	if _state == State.MOVE and not _is_paused:
		global_position.y += move_speed * delta
		if global_position.y > _bottom_boundary():
			GameEvents.wall_hit.emit(wall_damage)
			GameEvents.enemy_died.emit(global_position)
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
	VFXManager.show_damage_text(global_position, amount)

	# 双层残影血条: 主条瞬扣, 残影条 0.4s lerp 追平
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.value = current_hp
	if hp_bar_red and is_instance_valid(hp_bar_red):
		var red_tween := create_tween()
		red_tween.tween_property(hp_bar_red, "value", current_hp, 0.4)

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

	# 死亡视觉增强: 缩放缩小 + 轻微上漂
	if _sprite:
		var death_tween := create_tween()
		death_tween.set_parallel(true)
		death_tween.tween_property(_sprite, "scale", Vector2(0.2, 0.2), 0.5)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		death_tween.tween_property(_sprite, "position:y", _sprite.position.y - 40, 0.5)


func _on_death_animation_finished() -> void:
	set_process(false)
	set_physics_process(false)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()


func _bottom_boundary() -> float:
	return GridManager.get_wall_boundary()
