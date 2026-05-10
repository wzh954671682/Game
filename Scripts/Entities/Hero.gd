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
@export var attack_range: int = 1
@export var heal_percent: float = 0.0
@export var heal_interval: float = 2.0
@export var hp_bar_show: bool = true
@export var hp_bar_y_offset: float = 80.0
@export var hp_bar_width: float = 80.0
@export var hp_bar_height: float = 14.0
@export var hp_bar_bg_color: Color = Color("161616")
@export var hp_bar_fill_color: Color = Color("4e5831")

var current_hp: int = max_health
var base_atk: int = 10
var base_hp: int = 100
var branch_path: String = ""

var current_blocked_enemies: Array[Node2D] = []

## 属性动态计算系统 (Phase 15.5)
var _config_data: Dictionary = {}
var _meta_bonuses: Dictionary = {}   ## 装备/天赋固定值加成, e.g. {"atk": 10, "hp": 50}
var _buff_bonuses: Dictionary = {}   ## 战斗 Buff 百分比加成, e.g. {"atk": 0.15, "hp": 0.0}
var passive_effects: Array[Dictionary] = []  ## 被动效果列表
var _timed_buff_timers: Dictionary = {}  ## stat → Timer (限时Buff自动清理)
var _atk_speed_stacks: int = 0
var _atk_speed_decay_timer: Timer = null
var _base_frame_interval: float = 0.12
var _ranged_target: Node2D = null
var _projectile_script: Script = null
var _heal_accumulator: float = 0.0
var _heal_aura: Sprite2D = null

const HEAL_AURA_PATH: String = "res://Assets/UI/effects/fuzhu_zhouwei.png"
var _hp_bar_bg: ColorRect = null
var _hp_bar_fill: ColorRect = null

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

# hero_id → sprite 文件前缀映射
const SPRITE_PREFIX_MAP: Dictionary = {
	"shielder_01": "001",
	"hero_002": "001",
	"hero_003": "001",
	"hero_004": "001",
}

const PROJECTILE_SPRITE_MAP: Dictionary = {
	"hero_002": "res://Assets/UI/effects/zidan_01.png",
	"hero_003": "res://Assets/UI/effects/zidan_02/",
}

const PROJECTILE_SPEED: float = 600.0

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
	add_to_group("heroes")
	_setup_flash_shader()
	_apply_attack_range()
	_setup_hp_bar()
	if heal_percent > 0.0:
		_setup_heal_aura()
	if not hero_id.is_empty():
		_load_frames()
		_apply_state(State.STANDBY)


func _physics_process(delta: float) -> void:
	if _state == State.DEATH:
		_update_animation(delta)
		return

	# 远程英雄: 搜索同列敌人而非拦截
	if attack_range >= 4:
		_detect_accumulator += delta
		if _detect_accumulator >= DETECT_INTERVAL:
			_detect_accumulator -= DETECT_INTERVAL
			_ranged_target = _find_ranged_target()
		_cleanup_dead_enemies()
		if _ranged_target != null and is_instance_valid(_ranged_target):
			if _state != State.ATTACK:
				_apply_state(State.ATTACK)
		else:
			_ranged_target = null
			if _state != State.STANDBY:
				_apply_state(State.STANDBY)
		_update_animation(delta)
		return

	# 近战英雄: 拦截检测
	_detect_accumulator += delta
	if _detect_accumulator >= DETECT_INTERVAL:
		_detect_accumulator -= DETECT_INTERVAL
		try_intercept()

	_cleanup_dead_enemies()

	if current_blocked_enemies.is_empty():
		if _state != State.STANDBY:
			_apply_state(State.STANDBY)
	else:
		if _state != State.ATTACK:
			_apply_state(State.ATTACK)

	# 辅助治疗光环
	if heal_percent > 0.0:
		_heal_accumulator += delta
		if _heal_accumulator >= heal_interval:
			_heal_accumulator -= heal_interval
			_heal_nearby_allies()

	_update_animation(delta)


# ============================================================
# 精灵帧加载 (自动定位: Assets/Heroes/hero_{sprite_id}/)
# ============================================================

func _load_frames() -> void:
	var prefix: String = SPRITE_PREFIX_MAP.get(hero_id, hero_id)
	var folder: String = hero_id if hero_id.begins_with("hero_") else ("hero_" + prefix)
	var base := "res://Assets/Heroes/%s/" % folder
	_frames_standby.clear()
	_frames_attack.clear()
	_frames_deal.clear()
	for i in range(4):
		var idx := "%02d" % i
		_frames_standby.append(load(base + "hero_%s_standby_%s.png" % [prefix, idx]))
		_frames_attack.append(load(base + "hero_%s_attack_%s.png" % [prefix, idx]))
		_frames_deal.append(load(base + "hero_%s_deal_%s.png" % [prefix, idx]))


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
	# 远程英雄: 发射弹丸
	if attack_range >= 4:
		if _ranged_target == null or not is_instance_valid(_ranged_target):
			return
		_spawn_projectile(_ranged_target)
		_play_attack_feedback()
		_trigger_attack_passives()
		return

	# 近战英雄: 直接伤害
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
		_trigger_attack_passives()
		if killed:
			current_blocked_enemies.pop_front()
			VFXManager.hit_stop(0.05)


func _spawn_projectile(target: Node2D) -> void:
	if _projectile_script == null:
		_projectile_script = load("res://Scripts/Entities/HeroProjectile.gd")
	var proj := Area2D.new()
	proj.set_script(_projectile_script)
	proj.global_position = global_position + Vector2(0, -40)
	get_parent().add_child(proj)
	var sprite_path: String = PROJECTILE_SPRITE_MAP.get(hero_id, "")
	var dmg: int = int(floor(get_final_stats("atk")))
	proj.setup(sprite_path, target, PROJECTILE_SPEED, dmg)


func _trigger_attack_passives() -> void:
	for passive in passive_effects:
		match passive.get("type", ""):
			"atk_speed_stack":
				var max_stacks: int = passive.get("max_stacks", 6)
				var stack_val: float = passive.get("stack_value", 5.0)
				var decay: float = passive.get("decay_sec", 2.0)
				_atk_speed_stacks = mini(_atk_speed_stacks + 1, max_stacks)
				frame_interval = _base_frame_interval * (1.0 - _atk_speed_stacks * stack_val / 100.0)
				if _atk_speed_decay_timer and is_instance_valid(_atk_speed_decay_timer):
					_atk_speed_decay_timer.start(decay)
				else:
					_atk_speed_decay_timer = Timer.new()
					_atk_speed_decay_timer.one_shot = true
					_atk_speed_decay_timer.wait_time = decay
					_atk_speed_decay_timer.timeout.connect(_on_atk_speed_decay)
					add_child(_atk_speed_decay_timer)
					_atk_speed_decay_timer.start()


func _on_atk_speed_decay() -> void:
	_atk_speed_stacks = 0
	frame_interval = _base_frame_interval


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
	attack_range = data.get("attack_range", 1)
	heal_percent = data.get("heal_percent", 0.0)
	heal_interval = data.get("heal_interval", 2.0)
	base_atk = data.get("base_atk", 10)
	base_hp = data.get("base_hp", 100)
	branch_path = ""
	_config_data = data

	_apply_star_stats()
	current_hp = max_health
	_base_frame_interval = frame_interval

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
	_update_hp_bar()

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


# ============================================================
# Buff / 被动 接口 (EffectResolver 调用)
# ============================================================

func apply_permanent_buff(stat: String, value: float) -> void:
	_buff_bonuses[stat] = _buff_bonuses.get(stat, 0.0) + value / 100.0
	_apply_star_stats()


func apply_timed_buff(stat: String, value: float, duration: float) -> void:
	var pct: float = value / 100.0
	_buff_bonuses[stat] = _buff_bonuses.get(stat, 0.0) + pct
	_apply_star_stats()

	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = duration
	timer.timeout.connect(_on_timed_buff_expire.bind(stat, pct))
	add_child(timer)
	timer.start()
	_timed_buff_timers[stat] = timer


func _on_timed_buff_expire(stat: String, pct: float) -> void:
	_buff_bonuses[stat] = maxf(_buff_bonuses.get(stat, 0.0) - pct, 0.0)
	_apply_star_stats()
	_timed_buff_timers.erase(stat)


func apply_passive(passive_data: Dictionary) -> void:
	var existing_type: String = passive_data.get("type", "")
	for i in range(passive_effects.size()):
		if passive_effects[i].get("type", "") == existing_type:
			passive_effects[i] = passive_data
			return
	passive_effects.append(passive_data)


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

func _apply_attack_range() -> void:
	if block_raycast == null:
		return
	var cell_size: float = 190.0
	block_raycast.target_position = Vector2(0, -attack_range * cell_size)


func _setup_heal_aura() -> void:
	if not ResourceLoader.exists(HEAL_AURA_PATH):
		return
	_heal_aura = Sprite2D.new()
	_heal_aura.name = "HealAura"
	_heal_aura.texture = load(HEAL_AURA_PATH) as Texture2D
	_heal_aura.centered = true
	_heal_aura.z_index = -1
	_heal_aura.visible = false
	_heal_aura.modulate.a = 0.3
	add_child(_heal_aura)


func _heal_nearby_allies() -> void:
	var heal_range: float = 190.0
	var did_heal: bool = false
	for h in get_tree().get_nodes_in_group("heroes"):
		var ally := h as Node2D
		if ally == null or ally == self or not is_instance_valid(ally):
			continue
		var diff := ally.global_position - global_position
		if absf(diff.x) <= heal_range and absf(diff.y) <= heal_range:
			var amount: int = ceili(ally.get("max_health") * heal_percent / 100.0)
			if ally.has_method("heal"):
				ally.heal(amount)
				did_heal = true
	if did_heal and _heal_aura and is_instance_valid(_heal_aura):
		_pulse_heal_aura()


func _pulse_heal_aura() -> void:
	_heal_aura.visible = true
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_SINE)
	tw.tween_property(_heal_aura, "modulate:a", 0.7, 0.2)
	tw.tween_property(_heal_aura, "modulate:a", 0.3, 0.3)
	tw.tween_callback(func():
		if _heal_aura and is_instance_valid(_heal_aura):
			_heal_aura.visible = false
	)


func _find_ranged_target() -> Node2D:
	var range_px: float = attack_range * 190.0
	var best: Node2D = null
	var best_y: float = -INF
	for e in get_tree().get_nodes_in_group("enemies"):
		var enemy := e as Node2D
		if enemy == null or not is_instance_valid(enemy):
			continue
		var diff := enemy.global_position - global_position
		if diff.y > 0 or diff.y < -range_px:
			continue
		if absf(diff.x) > 95.0:
			continue
		if diff.y > best_y:
			best_y = diff.y
			best = enemy
	return best


func _setup_hp_bar() -> void:
	if not hp_bar_show:
		return

	_hp_bar_bg = ColorRect.new()
	_hp_bar_bg.name = "HPBarBg"
	_hp_bar_bg.color = hp_bar_bg_color
	_hp_bar_bg.size = Vector2(hp_bar_width, hp_bar_height)
	_hp_bar_bg.position = Vector2(-hp_bar_width / 2.0, hp_bar_y_offset)
	add_child(_hp_bar_bg)

	_hp_bar_fill = ColorRect.new()
	_hp_bar_fill.name = "HPBarFill"
	_hp_bar_fill.color = hp_bar_fill_color
	_hp_bar_fill.size = Vector2(hp_bar_width, hp_bar_height)
	_hp_bar_fill.position = Vector2(-hp_bar_width / 2.0, hp_bar_y_offset)
	add_child(_hp_bar_fill)


func _update_hp_bar() -> void:
	if _hp_bar_fill and is_instance_valid(_hp_bar_fill):
		var ratio: float = float(current_hp) / float(max_health) if max_health > 0 else 0.0
		_hp_bar_fill.size.x = hp_bar_width * ratio


func heal(amount: int) -> void:
	current_hp = mini(current_hp + amount, max_health)
	_update_hp_bar()


func try_intercept() -> void:
	block_raycast.force_raycast_update()

	if not block_raycast.is_colliding():
		return

	var collider: Variant = block_raycast.get_collider()
	if collider == null or not collider is Node2D:
		return

	var enemy: Node2D = collider as Node2D
	if current_blocked_enemies.has(enemy):
		return

	# 蝙蝠等飞行单位绕过拦截
	if enemy.get("bypass_intercept") == true:
		return

	current_blocked_enemies.append(enemy)

	if enemy.has_method("set_paused"):
		enemy.set_paused(true)

		if enemy.has_signal("attack_hit") and not enemy.attack_hit.is_connected(_on_enemy_attack_hit):
			enemy.attack_hit.connect(_on_enemy_attack_hit.bind(enemy))

	print("[Intercepted] 英雄拦截怪物: %s (当前拦截数: %d/%d)" % [enemy.name, current_blocked_enemies.size(), max_block_count])


func _release_enemy(enemy: Node2D) -> void:
	current_blocked_enemies.erase(enemy)


func _cleanup_dead_enemies() -> void:
	var i: int = current_blocked_enemies.size() - 1
	while i >= 0:
		if not is_instance_valid(current_blocked_enemies[i]):
			current_blocked_enemies.remove_at(i)
		i -= 1


func take_damage(amount: int) -> void:
	if _state == State.DEATH:
		return
	current_hp -= amount
	_play_hit_flash()
	if current_hp <= 0:
		current_hp = 0
		_die()


func _on_enemy_attack_hit(damage: int, attacker: Node2D = null) -> void:
	if _state == State.DEATH:
		return
	current_hp -= damage
	_play_hit_flash()

	# 被动效果触发
	for passive in passive_effects:
		match passive.get("type", ""):
			"on_hit":
				var stat: String = passive.get("stat", "hp")
				var val: float = passive.get("value", 0.0)
				_meta_bonuses[stat] = _meta_bonuses.get(stat, 0.0) + val
				_apply_star_stats()
				current_hp = mini(current_hp + int(val), max_health)
			"thorns":
				if attacker != null and is_instance_valid(attacker) and attacker.has_method("take_damage"):
					var reflect_dmg: int = ceili(max_health * passive.get("percent", 0.0) / 100.0)
					if reflect_dmg > 0:
						attacker.take_damage(reflect_dmg)

	_update_hp_bar()
	if current_hp <= 0:
		current_hp = 0
		_die()
