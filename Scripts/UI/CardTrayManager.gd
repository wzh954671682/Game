class_name CardTrayManager
extends Control

## Card tray HUD. Position calculated manually — no HBoxContainer.
## Cards use PRESET_CENTER anchors, offset_left/right for horizontal spread.
##
## Draw sequence:
##   1. Card deployed/discarded → tree_exiting fires
##   2. Remaining cards slide left to fill gap (0.3s)
##   3. After slide: queued new cards fly in from right edge (0.25s)
##
## Sibling push: selected card's neighbors pushed outward 120px.

signal card_created(card_ui: Control)

const CARD_W: float = 150.0
const CARD_H: float = 200.0
const HALF_W: float = CARD_W / 2.0
const HALF_H: float = CARD_H / 2.0
const SPACING: float = 150.0
const SLIDE_DUR: float = 0.3
const FLY_IN_DUR: float = 0.25
const PUSH_DUR: float = 0.18
const PUSH_OFFSET: float = 40.0
const MAX_VISIBLE: int = 5

var _card_scene: PackedScene = null
var _hero_templates: Dictionary = {}
var _cards: Array[Control] = []
var _pending_draws: Array[String] = []
var _awaiting_refill: bool = false
var _tween_slide: Tween = null
var _tween_push: Tween = null

var _hand_center_x: float = 450.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_calc_layout()


func setup(card_scene: PackedScene, hero_templates: Dictionary) -> void:
	_card_scene = card_scene
	_hero_templates = hero_templates
	get_tree().root.size_changed.connect(_calc_layout)
	if not DeckManager.card_drawn.is_connected(_on_card_drawn):
		DeckManager.card_drawn.connect(_on_card_drawn)
	_calc_layout.call_deferred()


# ============================================================
# 布局公式
# ============================================================

func _calc_layout(_caller: String = "") -> void:
	if size.x > 0.0:
		_hand_center_x = size.x / 2.0
		_reposition_all()


func _card_target_x(index: int, card_count: int = 0) -> float:
	if card_count <= 0:
		return _hand_center_x
	var total_width: float = (card_count - 1) * SPACING
	var start_x: float = _hand_center_x - total_width / 2.0
	return start_x + index * SPACING


func _clamp_center_x(cx: float) -> float:
	# 卡牌中心不超出容器边界 20px
	return clampf(cx, 20.0 + HALF_W, size.x - 20.0 - HALF_W)


func _apply_card_center(card: Control, center_x: float) -> void:
	card.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	var dx: float = _clamp_center_x(center_x) - size.x / 2.0
	card.offset_left = -HALF_W + dx
	card.offset_right = HALF_W + dx


func _tween_card_x(card: Control, center_x: float, duration: float) -> void:
	var dx: float = _clamp_center_x(center_x) - size.x / 2.0
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(card, "offset_left", -HALF_W + dx, duration)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(card, "offset_right", HALF_W + dx, duration)\
		.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)


# ============================================================
# 抽牌信号
# ============================================================

func _on_card_drawn(card_id: String) -> void:
	if _awaiting_refill:
		_pending_draws.append(card_id)
	else:
		_place_card(card_id)


# ============================================================
# 初始安置
# ============================================================

func _place_card(card_id: String) -> void:
	var card: Control = _instantiate_card(card_id)
	_cards.append(card)
	_reposition_all()
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

	_kill_push_tween()
	update_hand_layout(-1)

	if _tween_slide and _tween_slide.is_valid():
		_tween_slide.kill()

	_tween_slide = create_tween()
	_tween_slide.set_parallel(true)
	var count: int = _cards.size()
	for i: int in range(count):
		var cx: float = _card_target_x(i, count)
		var dx: float = cx - size.x / 2.0
		_tween_slide.tween_property(_cards[i], "offset_left", -HALF_W + dx, SLIDE_DUR)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tween_slide.tween_property(_cards[i], "offset_right", HALF_W + dx, SLIDE_DUR)\
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
		var cx: float = _card_target_x(count - 1, count)

		_apply_card_center(card, cx)
		card.offset_left += CARD_W + 80.0
		card.offset_right += CARD_W + 80.0
		card.scale = Vector2(0.6, 0.6)

		var dx: float = cx - size.x / 2.0
		var tween: Tween = create_tween()
		tween.set_parallel(true)
		tween.tween_property(card, "offset_left", -HALF_W + dx, FLY_IN_DUR)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "offset_right", HALF_W + dx, FLY_IN_DUR)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card, "scale", Vector2.ONE, FLY_IN_DUR)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

		card_created.emit(card)
		await get_tree().create_timer(0.08).timeout

	_awaiting_refill = false
	_reposition_all()


# ============================================================
# 摩西分海
# ============================================================

func update_hand_layout(selected_index: int = -1) -> void:
	_kill_push_tween()

	_tween_push = create_tween()
	_tween_push.set_parallel(true)

	var count: int = _cards.size()
	var push: float = PUSH_OFFSET if selected_index >= 0 and selected_index < count else 0.0
	var min_x: float = 20.0 + HALF_W
	var max_x: float = size.x - 20.0 - HALF_W

	# 1. 计算基础位置 + 整组平移
	var targets: Array[float] = []
	for i: int in range(count):
		var cx: float = _card_target_x(i, count)
		if i < selected_index:
			cx -= push
		elif i > selected_index:
			cx += push
		targets.append(cx)

	# 2. 左侧连锁约束 (从左向右传导)
	if selected_index > 0:
		targets[0] = maxf(targets[0], min_x)
		for i: int in range(1, selected_index):
			targets[i] = maxf(targets[i], targets[i - 1] + SPACING)

	# 3. 右侧连锁约束 (从右向左传导)
	if selected_index < count - 1:
		targets[count - 1] = minf(targets[count - 1], max_x)
		for i: int in range(count - 2, selected_index, -1):
			targets[i] = minf(targets[i], targets[i + 1] - SPACING)

	# 4. 选中卡牌与邻牌的间距保护
	if selected_index >= 0 and selected_index < count:
		if selected_index > 0:
			targets[selected_index - 1] = minf(targets[selected_index - 1], targets[selected_index] - SPACING)
		if selected_index < count - 1:
			targets[selected_index + 1] = maxf(targets[selected_index + 1], targets[selected_index] + SPACING)

	# 5. Tween
	for i: int in range(count):
		var dx: float = targets[i] - size.x / 2.0
		_tween_push.tween_property(_cards[i], "offset_left", -HALF_W + dx, PUSH_DUR)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		_tween_push.tween_property(_cards[i], "offset_right", HALF_W + dx, PUSH_DUR)\
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)

# ============================================================
# 全部重排
# ============================================================

func _reposition_all() -> void:
	var count: int = _cards.size()
	if count == 0:
		return

	# 计算基础位置 + 左右级联约束 (与 update_hand_layout 同模式)
	var targets: Array[float] = []
	for i: int in range(count):
		targets.append(_card_target_x(i, count))

	var min_x: float = 20.0 + HALF_W
	var max_x: float = size.x - 20.0 - HALF_W

	targets[0] = maxf(targets[0], min_x)
	for i: int in range(1, count):
		targets[i] = maxf(targets[i], targets[i - 1] + SPACING)

	targets[count - 1] = minf(targets[count - 1], max_x)
	for i: int in range(count - 2, -1, -1):
		targets[i] = minf(targets[i], targets[i + 1] - SPACING)

	for i: int in range(count):
		_apply_card_center(_cards[i], targets[i])


func _kill_push_tween() -> void:
	if _tween_push and _tween_push.is_valid():
		_tween_push.kill()
