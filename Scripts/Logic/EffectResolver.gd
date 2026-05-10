extends Node

## Card effect resolver (Autoload).
## Validates drop legality, resolves target entities, and dispatches
## data-driven actions from card_actions_config.json.

var _card_index: Dictionary = {}  ## card_id → card_data fast lookup


func _ready() -> void:
	_build_index()


func _build_index() -> void:
	_card_index.clear()
	var cards: Array = DataManager.card_actions_config.get("cards", [])
	for card in cards:
		if card is Dictionary:
			var cid: String = card.get("card_id", "")
			if not cid.is_empty():
				_card_index[cid] = card


func get_card_data(card_id: String) -> Dictionary:
	if _card_index.is_empty():
		_build_index()
	return _card_index.get(card_id, {})


func card_type_from_id(card_id: String) -> String:
	if _card_index.is_empty():
		_build_index()
	var data: Dictionary = _card_index.get(card_id, {})
	return data.get("card_type", "hero")


# ============================================================
# 目标解析
# ============================================================

func resolve_targets(card_data: Dictionary, drop_grid_pos: Vector2i) -> Dictionary:
	var restriction: Dictionary = card_data.get("target_restriction", {})
	var rtype: String = restriction.get("type", "none")

	match rtype:
		"none":
			return {"ok": true, "targets": []}
		"any_hero":
			var hero: Node2D = BattleManager.get_hero_at(drop_grid_pos)
			if hero == null:
				return {"ok": false, "error": "需要将卡牌拖放到英雄所在格子上"}
			return {"ok": true, "targets": [hero]}
		"specific_hero":
			var hero: Node2D = BattleManager.get_hero_at(drop_grid_pos)
			if hero == null:
				return {"ok": false, "error": "需要将卡牌拖放到英雄所在格子上"}
			var required_id: String = restriction.get("hero_id", "")
			if hero.hero_id != required_id:
				return {"ok": false, "error": "此卡牌仅限 %s 使用" % required_id}
			return {"ok": true, "targets": [hero]}
		_:
			return {"ok": false, "error": "未知的目标限制类型: %s" % rtype}


# ============================================================
# 效果执行
# ============================================================

func execute_card(card_data: Dictionary, resolved_targets: Array) -> void:
	var action_list: Array = card_data.get("action_list", [])
	for action in action_list:
		var targets: Array = _resolve_action_targets(action, resolved_targets)
		if targets.is_empty():
			continue
		_dispatch_action(action, targets)


func _resolve_action_targets(action: Dictionary, resolved: Array) -> Array:
	var target_type: String = action.get("target", "")
	match target_type:
		"all_enemies":
			return get_tree().get_nodes_in_group("enemies")
		"all_heroes":
			return _collect_field_heroes()
		"random_enemies":
			var enemies: Array = get_tree().get_nodes_in_group("enemies")
			var count: int = action.get("count", 1)
			enemies.shuffle()
			return enemies.slice(0, mini(count, enemies.size()))
		"random_hero":
			var heroes: Array = _collect_field_heroes()
			if heroes.is_empty():
				return []
			return [heroes.pick_random()]
		"target_hero", "target_enemy":
			return resolved
		_:
			push_warning("[EffectResolver] 未知 target 类型: " + target_type)
			return []


func _collect_field_heroes() -> Array:
	var heroes: Array = []
	for pos in BattleManager.grid_occupants:
		var entity: Node2D = BattleManager.grid_occupants[pos]
		if is_instance_valid(entity) and entity.has_method("init_hero"):
			heroes.append(entity)
	return heroes


# ============================================================
# Action 分发
# ============================================================

func _dispatch_action(action: Dictionary, targets: Array) -> void:
	var action_name: String = action.get("action", "")
	match action_name:
		"reduce_current_hp_percent": _exec_reduce_current_hp_percent(action, targets)
		"freeze":                     _exec_freeze(action, targets)
		"heal_full":                  _exec_heal_full(action, targets)
		"heal_percent":               _exec_heal_percent(action, targets)
		"buff_timed":                 _exec_buff_timed(action, targets)
		"buff_permanent":             _exec_buff_permanent(action, targets)
		"level_up":                   _exec_level_up(action, targets)
		"aoe_damage":                 _exec_aoe_damage(action, targets)
		"passive_on_hit":             _exec_passive_on_hit(action, targets)
		"passive_thorns":             _exec_passive_thorns(action, targets)
		"passive_atk_speed_stack":    _exec_passive_atk_speed_stack(action, targets)
		"passive_piercing":           _exec_passive_stub(action, targets, "passive_piercing: 穿透攻击 — Phase 3 待实现")
		"passive_mark_detonate":      _exec_passive_stub(action, targets, "passive_mark_detonate: 印记引爆 — Phase 3 待实现")
		"passive_burning_ground":     _exec_passive_stub(action, targets, "passive_burning_ground: 燃烧区域 — Phase 3 待实现")
		"passive_triage_heal":        _exec_passive_stub(action, targets, "passive_triage_heal: 战地分诊 — Phase 3 待实现")
		"passive_heal_buff":          _exec_passive_stub(action, targets, "passive_heal_buff: 治疗Buff — Phase 3 待实现")
		_:
			push_warning("[EffectResolver] 未知 action: " + action_name)


# ============================================================
# Action 实现
# ============================================================

func _exec_reduce_current_hp_percent(action: Dictionary, targets: Array) -> void:
	var percent: float = action.get("value", 0.0) / 100.0
	var filter: String = action.get("target_filter", "")

	for enemy in targets:
		if not is_instance_valid(enemy) or not enemy.has_method("take_damage"):
			continue
		if filter == "not_boss" and enemy.get("is_boss"):
			continue
		var dmg: int = ceili(enemy.current_hp * percent)
		if dmg > 0:
			enemy.take_damage(dmg)


func _exec_freeze(action: Dictionary, targets: Array) -> void:
	var duration: float = action.get("duration", 0.0)
	for enemy in targets:
		if is_instance_valid(enemy) and enemy.has_method("freeze"):
			enemy.freeze(duration)


func _exec_heal_full(_action: Dictionary, targets: Array) -> void:
	for hero in targets:
		if not is_instance_valid(hero) or not hero.has_method("heal"):
			continue
		hero.heal(hero.max_health - hero.current_hp)


func _exec_heal_percent(action: Dictionary, targets: Array) -> void:
	var percent: float = action.get("value", 0.0) / 100.0
	for hero in targets:
		if not is_instance_valid(hero) or not hero.has_method("heal"):
			continue
		var amount: int = ceili(hero.max_health * percent)
		hero.heal(amount)


func _exec_buff_timed(action: Dictionary, targets: Array) -> void:
	var stat: String = action.get("stat", "")
	var value: float = action.get("value", 0.0)
	var duration: float = action.get("duration", 0.0)
	for hero in targets:
		if is_instance_valid(hero) and hero.has_method("apply_timed_buff"):
			hero.apply_timed_buff(stat, value, duration)


func _exec_buff_permanent(action: Dictionary, targets: Array) -> void:
	var stat: String = action.get("stat", "")
	var value: float = action.get("value", 0.0)
	for hero in targets:
		if is_instance_valid(hero) and hero.has_method("apply_permanent_buff"):
			hero.apply_permanent_buff(stat, value)


func _exec_level_up(action: Dictionary, targets: Array) -> void:
	var levels: int = action.get("value", 0)
	for hero in targets:
		if not is_instance_valid(hero):
			continue
		for _i in range(levels):
			if hero.current_star >= hero.MAX_STAR:
				break
			hero.star_up()


func _exec_aoe_damage(action: Dictionary, targets: Array) -> void:
	var damage: int = action.get("damage", 0)
	for enemy in targets:
		if is_instance_valid(enemy) and enemy.has_method("take_damage"):
			enemy.take_damage(damage)


func _exec_passive_on_hit(action: Dictionary, targets: Array) -> void:
	var stat: String = action.get("stat", "")
	var value: float = action.get("value", 0.0)
	for hero in targets:
		if is_instance_valid(hero) and hero.has_method("apply_passive"):
			hero.apply_passive({"type": "on_hit", "stat": stat, "value": value})


func _exec_passive_thorns(action: Dictionary, targets: Array) -> void:
	var percent: float = action.get("percent", 0.0)
	for hero in targets:
		if is_instance_valid(hero) and hero.has_method("apply_passive"):
			hero.apply_passive({"type": "thorns", "percent": percent})


func _exec_passive_atk_speed_stack(action: Dictionary, targets: Array) -> void:
	var max_stacks: int = action.get("max_stacks", 6)
	var stack_value: float = action.get("stack_value", 5.0)
	var decay_sec: float = action.get("decay_sec", 2.0)
	for hero in targets:
		if is_instance_valid(hero) and hero.has_method("apply_passive"):
			hero.apply_passive({"type": "atk_speed_stack", "max_stacks": max_stacks, "stack_value": stack_value, "decay_sec": decay_sec})


func _exec_passive_stub(action: Dictionary, targets: Array, msg: String) -> void:
	push_warning("[EffectResolver] " + msg)
	var action_name: String = action.get("action", "unknown")
	for hero in targets:
		if is_instance_valid(hero) and hero.has_method("apply_passive"):
			hero.apply_passive({"type": action_name, "raw": action.duplicate()})
