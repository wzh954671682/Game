class_name CardTrayManager
extends Control

## Manages the card tray HUD. All card positions are manually calculated —
## HBoxContainer auto-layout is deliberately avoided to prevent conflicts
## with Tween-driven position animations.
##
## Draw sequence:
##   1. Card deployed/discarded → tree_exiting fires
##   2. Remaining cards slide left to fill gap (0.3s)
##   3. After slide: queued new cards fly in from right edge (0.25s)
##
## Sibling push ("摩西分海"):
##   When a card enters SELECTED (scale 1.5x), adjacent cards slide outward
##   to make visual room. Logic lives here, not in individual CardUI nodes.
##
## Initial cards pop in place with scale 0→1.

signal card_created(card_ui: Control)

const CARD_W: float = 150.0
const CARD_H: float = 200.0
const CARD_GAP: float = 8.0
const SPACING: float = CARD_W + CARD_GAP  # 158.0
const SLIDE_DUR: float = 0.3
const FLY_IN_DUR: float = 0.25
const PUSH_DUR: float = 0.18
const PUSH_EXTRA: float = 15.0
const MAX_VISIBLE: int = 5

var _card_scene: PackedScene = null
var _hero_templates: Dictionary = {}
var _cards: Array[Control] = []
var _pending_draws: Array[String] = []
var _awaiting_refill: bool = false
var _tween_slide: Tween = null
var _tween_push: Tween = null

var _tray_y: float = 0.0
var _tray_h: float = 0.0
var _hand_center_x: float = 0.0


func setup(card_scene: PackedScene, hero_templates: Dictionary) -> void:
	_card_scene = card_scene
	_hero_templates = hero_templates
	_calc_layout()
	get_tree().root.size_changed.connect(_calc_layout)
	if not DeckManager.card_drawn.is_connected(_on_card_drawn):
		DeckManager.card_drawn.connect(_on_card_drawn)


# ============================================================
# 布局计算
# ============================================================

func _calc_layout(_caller: String = "") -> void:
	# CardStartMarker 现在视为整把手牌的绝对中心点
	var hand_center := GridManager.get_card_start_pos()
	_hand_center_x = hand_center.x
	_tray_y = hand_center.y - CARD_H / 2.0
	_tray_h = GridManager.get_card_tray_height()

	_reposition_instant()


func _card_target_x(index: int, card_count: int = 0) -> float:
	# 居中排版: 手牌几何中心 = _hand_center_x
	if card_count <= 0:
		return _hand_center_x
	var total_width: float = (card_count - 1) * SPACING
	var start_x: float = _hand_center_x - total_width / 2.0
	return start_x + index * SPACING


func _card_target_y() -> float:
	return _tray_y + _tray_h / 2.0


func _card_target(index: int, card_count: int) -> Vector2:
	return Vector2(_card_target_x(index, card_count), _card_target_y())


# ============================================================
# 抽牌信号 (来自 DeckManager)
# ============================================================

func _on_card_drawn(card_id: String) -> void:
	if _awaiting_refill:
		_pending_draws.append(card_id)
	else:
		_place_card(card_id)


# ============================================================
# 初始安置 (pop-in)
# ============================================================

func _place_card(card_id: String) -> void:
	var card: Control = _instantiate_card(card_id)
	_cards.append(card)

	var target: Vector2 = _card_target(_cards.size() - 1, _cards.size())
	card.position = target
	card.scale = Vector2.ZERO

	var tween: Tween = create_tween()
	tween.tween_property(card, "scale", Vector2.ONE, 0.3)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	card_created.emit(card)


func _instantiate_card(card_id: String) -> Control:
	var template: Dictionary = _hero_templates.get(card_id, {})
	var hero_name: String = template.get("name", card_id)

	var card: Control = _card_scene.instantiate()
	card.setup(card_id, hero_name, null)
	card.tree_exiting.connect(_on_card_removed.bind(card))
	add_child(card)
	return card


# ============================================================
# 卡牌移除 → 滑位补空
# ============================================================

func _on_card_removed(card: Control) -> void:
	_cards.erase(card)
	_awaiting_refill = true

	# 卡牌被移除时, 清除避让状态
	_kill_push_tween()
	update_hand_layout(-1)

	if _tween_slide and _tween_slide.is_valid():
		_tween_slide.kill()

	_tween_slide = create_tween()
	_tween_slide.set_parallel(true)

	var count: int = _cards.size()
	for i: int in range(count):
		var c: Control = _cards[i]
		var target: Vector2 = _card_target(i, count)
		_tween_slide.tween_property(c, "position", target, SLIDE_DUR)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

	_tween_slide.finished.connect(_on_slide_finished)


func _on_slide_finished() -> void:
	_process_refill()


func _process_refill() -> void:
	while not _pending_draws.is_empty():
		var card_id: String = _pending_draws.pop_front()
		var card: Control = _instantiate_card(card_id)
		_cards.append(card)

		var count: int = _cards.size()
		var target: Vector2 = _card_target(count - 1, count)

		card.position = Vector2(target.x + CARD_W + 80.0, target.y)
		card.scale = Vector2(0.6, 0.6)

		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "position", target, FLY_IN_DUR)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2.ONE, FLY_IN_DUR)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		card_created.emit(card)

		await get_tree().create_timer(0.08).timeout

	_awaiting_refill = false
	_reposition_instant()


# ============================================================
# "摩西分海" — 选中卡牌时相邻牌向外避让
# ============================================================

func update_hand_layout(selected_index: int = -1) -> void:
	_kill_push_tween()

	_tween_push = create_tween()
	_tween_push.set_parallel(true)

	var count: int = _cards.size()
	var push_offset: float = 0.0

	if selected_index >= 0 and selected_index < count:
		# 膨胀宽度 = (CARD_W * 1.5 - CARD_W) / 2 + 额外留白
		push_offset = CARD_W * 0.25 + PUSH_EXTRA

	for i: int in range(count):
		var target_x: float = _card_target_x(i, count)
		if selected_index >= 0:
			if i < selected_index:
				target_x -= push_offset
			elif i > selected_index:
				target_x += push_offset

		var target := Vector2(target_x, _card_target_y())
		_tween_push.tween_property(_cards[i], "position", target, PUSH_DUR)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


func _kill_push_tween() -> void:
	if _tween_push and _tween_push.is_valid():
		_tween_push.kill()


# ============================================================
# 瞬移 (无动画)
# ============================================================

func _reposition_instant() -> void:
	var count: int = _cards.size()
	for i: int in range(count):
		_cards[i].position = _card_target(i, count)
