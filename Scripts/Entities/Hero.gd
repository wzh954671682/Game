extends Node2D

## Hero entity placed on the 5x5 grid. Uses a RayCast2D aimed upward to
## detect and intercept enemies in the same column at 10 Hz.
## Call init_hero(data) after instantiation to configure from a template.
##
## Phase 9 — 英雄合成与星级进化系统 (Star-Up System):
##   - can_star_up(card_id): checks same ID + star < 5
##   - star_up(): increments star, scales stats by multiplier, plays tween
##   - Each star adds +10% sprite scale (1.0 → 1.4 at 5★)
##   - Recovers 20% max HP on synthesis
##   - branch_path reserved for future A/B branching

@export var hero_id: String = ""
@export var current_star: int = 1
@export var max_block_count: int = 1
@export var attack_power: int = 10
@export var attack_speed: float = 1.0  # attacks per second
@export var max_health: int = 100
@export var current_hp: int = 100

var base_atk: int = 10
var base_hp: int = 100
var branch_path: String = ""

var current_blocked_enemies: Array[Node2D] = []

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
	hero_id = data.get("hero_id", "")
	current_star = 1
	max_block_count = data.get("block_count", 1)
	base_atk = data.get("base_atk", 10)
	base_hp = data.get("base_hp", 100)
	attack_speed = 1.0
	branch_path = ""

	_apply_star_stats()
	current_hp = max_health


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

	# Recover 20% max HP
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


func _apply_star_stats() -> void:
	var mult: float = STAR_MULTIPLIERS.get(current_star, 1.0)
	attack_power = int(floor(base_atk * mult))
	max_health = int(floor(base_hp * mult))


func _get_star_scale() -> float:
	return 1.0 + (current_star - 1) * STAR_SCALE_STEP


func _play_evolution_tween() -> void:
	if sprite_2d == null:
		return

	var target_scale: float = _get_star_scale()

	var tween: Tween = create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite_2d, "scale", Vector2.ONE * target_scale * 1.3, 0.12)
	tween.tween_property(sprite_2d, "scale", Vector2.ONE * target_scale, 0.15)


# ============================================================
# Phase 5-6 — 拦截 / 攻击 / 清理 (unchanged)
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
