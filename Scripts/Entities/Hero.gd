extends Node2D

## 英雄实体 — 精灵帧状态机 (Sprite-Sheet FSM)
## 状态: STANDBY (待机循环 + 拦截检测),
##       ATTACK (攻击循环, 第2帧造成伤害),
##       DEATH (死亡播放 → 渐隐 → queue_free).
##
## 与 Enemy.gd 保持相同的 Shader / Tween 表现标准.
## Phase 9 — 星级进化系统 (Star-Up) 已集成.

enum State { STANDBY, ATTACK, DEATH }

@export var hero_id: String = "001"
@export var current_star: int = 1
@export var max_block_count: int = 1
@export var attack_power: int = 10
@export var max_health: int = 100
@export var frame_interval: float = 0.12

var current_hp: int = max_health
var base_atk: int = 10
var base_hp: int = 100
var branch_path: String = ""

var current_blocked_enemies: Array[Node2D] = []

## 属性动态计算系统 (Phase 15.5)
var _config_data: Dictionary = {}
var _meta_bonuses: Dictionary = {}   ## 装备/天赋固定值加成, e.g. {"atk": 10, "hp": 50}
var _buff_bonuses: Dictionary = {}   ## 战斗 Buff 百分比加成, e.g. {"atk": 0.15, "hp": 0.0}

@onready var block_raycast: RayCast2D = $RayCast2D
@onready var sprite_2d: Sprite2D = $Sprite2D

const DETECT_INTERVAL: float = 0.1
const STAR_MULTIPLIERS: Dictionary = {
	1: 1.0,
	2: 1.5,
	3: 2.2,
	4: 3.0,
	5: 4.5,
}
const MAX_STAR: int = 5
const STAR_SCALE_STEP: float = 0.1
const SYNTHESIS_HP_RECOVERY: float = 0.2

# hero_id (模板) → sprite 文件夹编号 映射
const SPRITE_ID_MAP: Dictionary = {
	"shielder_01": "001",
	"gunner_01": "001",  # 机枪手暂无独立资源, 复用盾兵
}

var _state: int = State.STANDBY
var _current_frame: int = 0
var _frame_timer: float = 0.0
var _attack_hit_emitted: bool = false
var _detect_accumulator: float = 0.0
var _feedback_tween: Tween = null

var _frames_standby: Array[Texture2D] = []
var _frames_attack: Array[Texture2D] = []
var _frames_deal: Array[Texture2D] = []


# ============================================================
# 生命周期
# ============================================================

func _ready() -> void:
	z_index = 0
	_setup_flash_shader()
	if not hero_id.is_empty():
		_load_frames()
		_apply_state(State.STANDBY)


func _physics_process(delta: float) -> void:
	if _state == State.DEATH:
		_update_animation(delta)
		return

	# 拦截检测 (10 Hz)
	_detect_accumulator += delta
	if _detect_accumulator >= DETECT_INTERVAL:
		_detect_accumulator -= DETECT_INTERVAL
		try_intercept()

	_cleanup_dead_enemies()

	# 状态切换: 有拦截目标 → ATTACK, 无目标 → STANDBY
	if current_blocked_enemies.is_empty():
		if _state != State.STANDBY:
			_apply_state(State.STANDBY)
	else:
		if _state != State.ATTACK:
			_apply_state(State.ATTACK)

	_update_animation(delta)


# ============================================================
# 精灵帧加载 (自动定位: Assets/Heroes/hero_{sprite_id}/)
# ============================================================

func _load_frames() -> void:
	var sprite_id: String = SPRITE_ID_MAP.get(hero_id, hero_id)
	var base := "res://Assets/Heroes/hero_%s/" % sprite_id
	_frames_standby.clear()
	_frames_attack.clear()
	_frames_deal.clear()
	for i in range(4):
		var idx := "%02d" % i
		_frames_standby.append(load(base + "hero_%s_standby_%s.png" % [sprite_id, idx]))
		_frames_attack.append(load(base + "hero_%s_attack_%s.png" % [sprite_id, idx]))
		_frames_deal.append(load(base + "hero_%s_deal_%s.png" % [sprite_id, idx]))


func _setup_flash_shader() -> void:
	var shader: Shader = load("res://Assets/Shaders/hit_flash.gdshader")
	if shader == null:
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	sprite_2d.material = mat


# ============================================================
# 动画更新 (帧驱动, 与 Enemy.gd 同模式)
# ============================================================

func _update_animation(delta: float) -> void:
	_frame_timer -= delta
	if _frame_timer > 0.0:
		return
	_frame_timer = frame_interval

	var frames: Array[Texture2D]
	match _state:
		State.STANDBY: frames = _frames_standby
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

	sprite_2d.texture = frames[_current_frame]

	# ATTACK 状态: 第2帧 (attack_02) 发出伤害信号
	if _state == State.ATTACK and _current_frame == 2 and not _attack_hit_emitted:
		_attack_hit_emitted = true
		_deal_damage_to_target()


func _apply_state(new_state: int) -> void:
	_state = new_state
	_current_frame = 0
	_frame_timer = 0.0
	_attack_hit_emitted = false

	var frames: Array[Texture2D]
	match _state:
		State.STANDBY: frames = _frames_standby
		State.ATTACK: frames = _frames_attack
		State.DEATH:  frames = _frames_deal

	if not frames.is_empty():
		sprite_2d.texture = frames[0]
		sprite_2d.scale = Vector2.ONE * _get_star_scale()
	else:
		sprite_2d.texture = null


# ============================================================
# 伤害输出 (attack_02 帧触发)
# ============================================================

func _deal_damage_to_target() -> void:
	if current_blocked_enemies.is_empty():
		return

	var target: Node2D = current_blocked_enemies[0]
	if not is_instance_valid(target):
		current_blocked_enemies.pop_front()
		return

	if target.has_method("take_damage"):
		var dmg: int = int(floor(get_final_stats("atk")))
		var killed: bool = target.take_damage(dmg)
		_play_attack_feedback()
		if killed:
			current_blocked_enemies.pop_front()
			VFXManager.hit_stop(0.05)


func _play_attack_feedback() -> void:
	## 攻击时轻微 upscale 回弹
	if sprite_2d == null:
		return
	var target_scale: float = _get_star_scale()
	# 重置到基础缩放 (终止可能重叠的上一次回弹 Tween)
	sprite_2d.scale = Vector2.ONE * target_scale
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()
	_feedback_tween = create_tween()
	_feedback_tween.set_trans(Tween.TRANS_BACK)
	_feedback_tween.set_ease(Tween.EASE_OUT)
	_feedback_tween.tween_property(sprite_2d, "scale", Vector2.ONE * target_scale * 1.15, 0.06)
	_feedback_tween.tween_property(sprite_2d, "scale", Vector2.ONE * target_scale, 0.1)


# ============================================================
# 受击反馈 (hit_flash Shader, 与 Enemy.gd 相同)
# ============================================================

func _play_hit_flash() -> void:
	if sprite_2d.material == null:
		return
	sprite_2d.material.set_shader_parameter("flash_amount", 1.0)
	var tween := create_tween()
	tween.tween_property(sprite_2d.material, "shader_parameter/flash_amount", 0.0, 0.15)


# ============================================================
# 死亡
# ============================================================

func _die() -> void:
	# 释放所有被拦截的敌人
	for enemy in current_blocked_enemies:
		if is_instance_valid(enemy) and enemy.has_method("set_paused"):
			enemy.set_paused(false)
	current_blocked_enemies.clear()

	_apply_state(State.DEATH)


func _on_death_animation_finished() -> void:
	set_process(false)
	set_physics_process(false)

	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.5)
	await tween.finished
	queue_free()


# ============================================================
# 初始化 (由 BattleTest 调用)
# ============================================================

func init_hero(data: Dictionary) -> void:
	hero_id = data.get("hero_id", "")
	current_star = 1
	max_block_count = data.get("block_count", 1)
	base_atk = data.get("base_atk", 10)
	base_hp = data.get("base_hp", 100)
	branch_path = ""
	_config_data = data

	_apply_star_stats()
	current_hp = max_health

	# 如果已经在场景树中 (编辑器放置的英雄), 立即加载帧
	if is_inside_tree():
		_load_frames()
		_apply_state(State.STANDBY)


# ============================================================
# Phase 9 — 合成星级进化系统
# ============================================================

func can_star_up(card_id: String) -> bool:
	return hero_id == card_id and current_star < MAX_STAR


func star_up() -> void:
	if current_star >= MAX_STAR:
		return

	current_star += 1
	_apply_star_stats()

	# 恢复 20% 最大生命
	current_hp = mini(current_hp + int(ceil(max_health * SYNTHESIS_HP_RECOVERY)), max_health)

	_play_evolution_tween()

	print("[StarUp] %s 合成至 %d★ | ATK=%d HP=%d/%d | 缩放=%.1f" % [
		hero_id, current_star, attack_power, current_hp, max_health,
		_get_star_scale(),
	])


func get_star_label() -> String:
	var stars: String = "★"
	for _i: int in range(2, current_star + 1):
		stars += "★"
	return stars


func get_final_stats(stat_name: String) -> float:
	var base: float = 0.0
	match stat_name:
		"atk":
			base = float(_config_data.get("base_atk", base_atk))
		"hp":
			base = float(_config_data.get("base_hp", base_hp))
		"atk_speed":
			var fi: float = _config_data.get("base_frame_interval", frame_interval)
			base = 1.0 / fi if fi > 0.0 else 1.0 / frame_interval
		_:
			return 0.0

	var meta: float = _meta_bonuses.get(stat_name, 0.0)
	var star_bonus: float = STAR_MULTIPLIERS.get(current_star, 1.0) - 1.0
	var buff: float = _buff_bonuses.get(stat_name, 0.0)

	return (base + meta) * (1.0 + star_bonus) * (1.0 + buff)


func _apply_star_stats() -> void:
	attack_power = int(floor(get_final_stats("atk")))
	max_health = int(floor(get_final_stats("hp")))


func _get_star_scale() -> float:
	return 1.0 + (current_star - 1) * STAR_SCALE_STEP


func _play_evolution_tween() -> void:
	if sprite_2d == null:
		return

	# 终止攻击回弹 Tween (避免缩放冲突)
	if _feedback_tween and _feedback_tween.is_valid():
		_feedback_tween.kill()

	var target_scale: float = _get_star_scale()

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_2d, "scale", Vector2.ONE * target_scale * 1.3, 0.12)
	tween.tween_property(sprite_2d, "scale", Vector2.ONE * target_scale, 0.15)


# ============================================================
# 拦截系统 (RayCast2D 向上检测, 10 Hz)
# ============================================================

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

		if enemy.has_signal("attack_hit") and not enemy.attack_hit.is_connected(_on_enemy_attack_hit):
			enemy.attack_hit.connect(_on_enemy_attack_hit)

	print("[Intercepted] 英雄拦截怪物: %s (当前拦截数: %d/%d)" % [enemy.name, current_blocked_enemies.size(), max_block_count])


func _cleanup_dead_enemies() -> void:
	var i: int = current_blocked_enemies.size() - 1
	while i >= 0:
		if not is_instance_valid(current_blocked_enemies[i]):
			current_blocked_enemies.remove_at(i)
		i -= 1


func _on_enemy_attack_hit(damage: int) -> void:
	if _state == State.DEATH:
		return
	current_hp -= damage
	_play_hit_flash()
	if current_hp <= 0:
		current_hp = 0
		_die()
