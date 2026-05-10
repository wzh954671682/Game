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
@export var exp_reward: int = 0
@export var can_strafe: bool = false
@export var bypass_intercept: bool = false
@export var explosion_damage: int = 0
@export var explosion_radius: int = 1
@export var hp_bar_show: bool = true
@export var hp_bar_y_offset: float = -60.0
@export var hp_bar_width: float = 80.0
@export var hp_bar_height: float = 14.0
@export var hp_bar_bg_color: Color = Color("161616")
@export var hp_bar_fill_color: Color = Color("4e5831")

var current_hp: int = max_health
var _is_paused: bool = false
var _is_frozen: bool = false
var _state: int = State.MOVE
var _current_frame: int = 0
var _frame_timer: float = 0.0
var _attack_hit_emitted: bool = false
var _strafe_timer: float = 0.0
var _strafe_direction: int = 0
var _strafe_target_x: float = 0.0
var _is_strafing: bool = false
const STRAFE_INTERVAL: float = 1.5
const STRAFE_SPEED: float = 150.0

var _frames_move: Array[Texture2D] = []
var _frames_attack: Array[Texture2D] = []
var _frames_deal: Array[Texture2D] = []

@onready var _sprite: Sprite2D = $Sprite2D
var hp_bar: ColorRect = null
var hp_bar_red: ColorRect = null


func _ready() -> void:
	z_index = 0
	current_hp = max_health
	add_to_group("enemies")
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
	if not hp_bar_show:
		return

	# 清理场景中旧有的 TextureProgressBar 节点
	for old_name in ["HPBar", "HPBarRed"]:
		var old := get_node_or_null(old_name)
		if old:
			old.queue_free()

	var half_w: float = hp_bar_width / 2.0
	var pos := Vector2(-half_w, hp_bar_y_offset)
	var bar_size := Vector2(hp_bar_width, hp_bar_height)

	hp_bar_red = ColorRect.new()
	hp_bar_red.name = "HPBarRed"
	hp_bar_red.color = hp_bar_bg_color
	hp_bar_red.size = bar_size
	hp_bar_red.position = pos
	add_child(hp_bar_red)

	hp_bar = ColorRect.new()
	hp_bar.name = "HPBar"
	hp_bar.color = hp_bar_fill_color
	hp_bar.size = bar_size
	hp_bar.position = pos
	add_child(hp_bar)


func _update_enemy_hp_bar() -> void:
	if hp_bar and is_instance_valid(hp_bar):
		var ratio: float = float(current_hp) / float(max_health) if max_health > 0 else 0.0
		hp_bar.size.x = hp_bar_width * ratio


func _physics_process(delta: float) -> void:
	if _is_frozen:
		return

	# Movement (only in MOVE state when not paused)
	if _state == State.MOVE and not _is_paused:
		global_position.y += move_speed * delta
		if can_strafe:
			_update_strafe(delta)
		if global_position.y > _bottom_boundary():
			GameEvents.wall_hit.emit(wall_damage)
			GameEvents.enemy_died.emit(global_position, 0)
			queue_free()

	_update_animation(delta)


func _update_strafe(delta: float) -> void:
	_strafe_timer -= delta
	if _strafe_timer <= 0.0:
		_strafe_timer = STRAFE_INTERVAL
		var logic_pos: Vector2i = GridManager.get_logic_pos(global_position)
		var new_col: int = clampi(logic_pos.x + (1 if randi() % 2 == 0 else -1), 0, 4)
		_strafe_target_x = GridManager.get_screen_pos(Vector2i(new_col, logic_pos.y)).x
		_is_strafing = true

	if _is_strafing:
		var diff: float = _strafe_target_x - global_position.x
		if absf(diff) < 3.0:
			global_position.x = _strafe_target_x
			_is_strafing = false
		else:
			global_position.x += signf(diff) * STRAFE_SPEED * delta


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


func freeze(duration: float) -> void:
	if _state == State.DEATH or _is_frozen:
		return
	_is_frozen = true
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	timer.timeout.connect(_on_thaw)
	add_child(timer)
	timer.start()


func _on_thaw() -> void:
	_is_frozen = false


func take_damage(amount: int) -> bool:
	if _state == State.DEATH:
		return false

	current_hp -= amount
	VFXManager.show_damage_text(global_position, amount)

	# 双层残影血条: 主条瞬扣, 残影条 0.4s lerp 追平
	var ratio: float = float(current_hp) / float(max_health) if max_health > 0 else 0.0
	var target_w: float = hp_bar_width * ratio
	if hp_bar and is_instance_valid(hp_bar):
		hp_bar.size.x = target_w
	if hp_bar_red and is_instance_valid(hp_bar_red):
		var red_tween := create_tween()
		red_tween.tween_property(hp_bar_red, "size:x", target_w, 0.4)

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

	if explosion_damage > 0:
		_trigger_explosion()

	GameEvents.enemy_died.emit(global_position, exp_reward)
	_apply_state(State.DEATH)

	# 死亡视觉增强: 缩放缩小 + 轻微上漂
	if _sprite:
		var death_tween := create_tween()
		death_tween.set_parallel(true)
		death_tween.tween_property(_sprite, "scale", Vector2(0.2, 0.2), 0.5)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		death_tween.tween_property(_sprite, "position:y", _sprite.position.y - 40, 0.5)


func _trigger_explosion() -> void:
	var radius_px: float = explosion_radius * 190.0
	var heroes = get_tree().get_nodes_in_group("heroes")
	for hero in heroes:
		if not is_instance_valid(hero):
			continue
		var dist: float = global_position.distance_to(hero.global_position)
		if dist <= radius_px and hero.has_method("take_damage"):
			hero.take_damage(explosion_damage)
	VFXManager.hit_stop(0.08)


func _on_death_animation_finished() -> void:
	set_process(false)
	set_physics_process(false)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()


func _bottom_boundary() -> float:
	return GridManager.get_wall_boundary()
