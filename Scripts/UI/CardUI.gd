extends Control

## Self-contained draggable card. Owns its full drag lifecycle:
## - _gui_input detects the initial press → starts drag, sets semi-transparent
## - _input (enabled via set_process_input during drag) catches release/cancel globally
## - Emits drag_started, drag_ended (with screen_pos), drag_cancelled
##
## Phase 11 — 卡牌手感强化: 拖拽时 scale→1.1 + z_index=100 + 水平移动旋转反馈 ±5°
## Phase 12 — 弃牌系统: 动态 [X] 按钮, DeckManager.discard_card + scale→0 销毁动画

signal drag_started(card_ui: Control)
signal drag_ended(card_ui: Control, screen_pos: Vector2)
signal drag_cancelled(card_ui: Control)

var card_id: String = ""
var hero_name: String = ""

var _is_dragging: bool = false
var _hover_tween: Tween = null
var _prev_mouse_x: float = 0.0
var _discard_btn: Button = null


func _ready() -> void:
	_create_discard_button()


func _create_discard_button() -> void:
	var btn: Button = Button.new()
	btn.name = "DiscardBtn"
	btn.text = "[X]"
	btn.visible = false
	btn.layout_mode = 1
	btn.anchor_left = 0.5
	btn.anchor_right = 0.5
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.offset_left = -20.0
	btn.offset_top = -30.0
	btn.offset_right = 20.0
	btn.offset_bottom = 0.0
	btn.mouse_filter = Control.MOUSE_FILTER_STOP
	btn.pressed.connect(_on_discard_pressed)
	_discard_btn = btn
	add_child(btn)


func setup(p_card_id: String, p_hero_name: String, p_icon: Texture2D = null) -> void:
	card_id = p_card_id
	hero_name = p_hero_name

	if has_node("Icon"):
		var icon_rect: TextureRect = $Icon
		if p_icon:
			icon_rect.texture = p_icon

	if has_node("Label"):
		var label: Label = $Label
		label.text = p_hero_name


func _gui_input(event: InputEvent) -> void:
	if _is_dragging:
		accept_event()
		return

	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return

	_is_dragging = true
	_prev_mouse_x = get_global_mouse_position().x
	rotation_degrees = 0.0
	modulate = Color(1.0, 1.0, 1.0, 0.35)
	set_process_input(true)

	# 悬浮强化: scale → 1.1, z_index → 100
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2(1.1, 1.1), 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	z_index = 100

	if _discard_btn:
		_discard_btn.visible = true

	drag_started.emit(self)
	accept_event()


func _input(event: InputEvent) -> void:
	if not _is_dragging:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_complete_drag(get_global_mouse_position())
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel_drag()
		accept_event()
	elif event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		cancel_drag()
		accept_event()
	elif event is InputEventMouseMotion:
		# 拖拽旋转反馈: 水平增量 → lerp 限制 ±5°
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var target: float = clampf(mm.relative.x * 0.3, -5.0, 5.0)
		rotation_degrees = lerpf(rotation_degrees, target, 0.35)


func _complete_drag(release_pos: Vector2) -> void:
	_end_drag_state()
	drag_ended.emit(self, release_pos)


func cancel_drag() -> void:
	if not _is_dragging:
		return
	_end_drag_state()
	drag_cancelled.emit(self)


func _end_drag_state() -> void:
	_is_dragging = false
	modulate = Color.WHITE
	rotation_degrees = 0.0
	set_process_input(false)

	# 还原 scale 与 z_index
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	z_index = 0

	if _discard_btn:
		_discard_btn.visible = false


# ============================================================
# Task 2 — 弃牌系统
# ============================================================

func _on_discard_pressed() -> void:
	# 终止拖拽状态, 通知 BattleTest 释放引用
	if _is_dragging:
		_is_dragging = false
		modulate = Color.WHITE
		rotation_degrees = 0.0
		set_process_input(false)
		z_index = 0
		drag_cancelled.emit(self)

	# 断连所有外部信号
	for conn in drag_started.get_connections():
		drag_started.disconnect(conn.callable)
	for conn in drag_ended.get_connections():
		drag_ended.disconnect(conn.callable)
	for conn in drag_cancelled.get_connections():
		drag_cancelled.disconnect(conn.callable)

	DeckManager.discard_card(card_id)

	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()

	# 销毁动画: scale → 0, 0.2s → queue_free
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)
