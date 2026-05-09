extends Control

## Self-contained draggable card with 3-state input FSM.
##
## States:
##   IDLE     — resting in tray. Press+move>10px → DRAGGING. Press+release → SELECTED.
##   SELECTED — click-to-inspect. Scale 1.5x, z_index high. Click outside → IDLE.
##              Press+move>10px from SELECTED → DRAGGING.
##   DRAGGING — follow mouse, rotation feedback ±5°. Release → deploy or cancel → IDLE.

enum State { IDLE, SELECTED, DRAGGING }

signal drag_started(card_ui: Control)
signal drag_ended(card_ui: Control, screen_pos: Vector2)
signal drag_cancelled(card_ui: Control)

var card_id: String = ""
var hero_name: String = ""

var _state: int = State.IDLE
var _start_click_pos: Vector2 = Vector2.ZERO
var _mouse_pressed: bool = false
var _hover_tween: Tween = null
var _prev_mouse_x: float = 0.0
var _discard_btn: Button = null

const DRAG_THRESHOLD: float = 10.0
const SELECTED_SCALE: Vector2 = Vector2(1.5, 1.5)
const DRAG_SCALE: Vector2 = Vector2(1.1, 1.1)


func _ready() -> void:
	pivot_offset = custom_minimum_size / 2.0
	_create_discard_button()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size / 2.0


func _create_discard_button() -> void:
	var btn: Button = Button.new()
	btn.name = "DiscardBtn"
	btn.text = "[X]"
	btn.visible = false
	btn.layout_mode = 1  # LAYOUT_MODE_ANCHORS (Godot 4.6: LayoutMode enum not exposed as named constant)
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


# ============================================================
# 输入: 仅在卡牌自身区域响应 (_gui_input)
# ============================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_start_click_pos = get_global_mouse_position()
			_mouse_pressed = true
			accept_event()
			return

		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_mouse_pressed = false
			match _state:
				State.DRAGGING:
					_complete_drag(get_global_mouse_position())
				State.IDLE:
					_enter_selected()
			accept_event()
			return

	elif event is InputEventMouseMotion and _mouse_pressed:
		var dist: float = get_global_mouse_position().distance_to(_start_click_pos)
		if dist >= DRAG_THRESHOLD and _state != State.DRAGGING:
			_enter_dragging()
			accept_event()
			return


# ============================================================
# 全局输入: DRAGGING 时捕获释放/取消 + SELECTED 时检测外部点击
# ============================================================

func _input(event: InputEvent) -> void:
	match _state:
		State.DRAGGING:
			_input_dragging(event)
		State.SELECTED:
			_input_selected(event)


func _input_dragging(event: InputEvent) -> void:
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
		var mm: InputEventMouseMotion = event as InputEventMouseMotion
		var target: float = clampf(mm.relative.x * 0.3, -5.0, 5.0)
		rotation_degrees = lerpf(rotation_degrees, target, 0.35)


func _input_selected(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if not get_global_rect().has_point(get_global_mouse_position()):
			_exit_selected()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_start_click_pos = get_global_mouse_position()
			_mouse_pressed = true


# ============================================================
# 状态切换
# ============================================================

func _enter_selected() -> void:
	_state = State.SELECTED
	set_process_input(true)

	_kill_hover_tween()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", SELECTED_SCALE, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	z_index = 10

	if _discard_btn:
		_discard_btn.visible = true

	_notify_tray(true)


func _exit_selected() -> void:
	_enter_idle()


func _enter_dragging() -> void:
	_state = State.DRAGGING
	set_process_input(true)

	_prev_mouse_x = get_global_mouse_position().x
	rotation_degrees = 0.0
	modulate = Color(1.0, 1.0, 1.0, 0.35)

	_kill_hover_tween()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", DRAG_SCALE, 0.12)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	z_index = 10

	if _discard_btn:
		_discard_btn.visible = true

	_notify_tray(false)
	drag_started.emit(self)


func _enter_idle() -> void:
	_state = State.IDLE
	_mouse_pressed = false
	modulate = Color.WHITE
	rotation_degrees = 0.0
	set_process_input(false)

	_kill_hover_tween()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2.ONE, 0.18)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	z_index = 0

	if _discard_btn:
		_discard_btn.visible = false

	_notify_tray(false)


# ============================================================
# 通知手牌管理器更新避让布局
# ============================================================

func _notify_tray(is_selected: bool) -> void:
	var p := get_parent()
	if p and p is CardTrayManager:
		(p as CardTrayManager).update_hand_layout(get_index() if is_selected else -1)


# ============================================================
# 拖拽生命周期
# ============================================================

func _complete_drag(release_pos: Vector2) -> void:
	_enter_idle()
	drag_ended.emit(self, release_pos)


func cancel_drag() -> void:
	if _state != State.DRAGGING:
		return
	_enter_idle()
	drag_cancelled.emit(self)


# ============================================================
# 弃牌系统
# ============================================================

func _on_discard_pressed() -> void:
	_mouse_pressed = false
	modulate = Color.WHITE
	rotation_degrees = 0.0
	set_process_input(false)
	z_index = 0
	_state = State.IDLE

	if not drag_cancelled.get_connections().is_empty():
		drag_cancelled.emit(self)

	for conn in drag_started.get_connections():
		drag_started.disconnect(conn.callable)
	for conn in drag_ended.get_connections():
		drag_ended.disconnect(conn.callable)
	for conn in drag_cancelled.get_connections():
		drag_cancelled.disconnect(conn.callable)

	DeckManager.discard_card(card_id)

	_kill_hover_tween()

	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2.ZERO, 0.2)\
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.finished.connect(queue_free)


# ============================================================
# 辅助
# ============================================================

func _kill_hover_tween() -> void:
	if _hover_tween and _hover_tween.is_valid():
		_hover_tween.kill()
