extends Control

## Data-driven card UI.
##
## All visuals (background, icon, name) are resolved at runtime from
## rarity_config.json, card_display_config.json, and heroes_progression.json.

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
@onready var _discard_btn: TextureRect = $DiscardBtn

const DRAG_THRESHOLD: float = 10.0
const SELECTED_SCALE: Vector2 = Vector2(1.5, 1.5)
const DRAG_SCALE: Vector2 = Vector2(1.1, 1.1)

const CARD_BG_PATH: String = "res://Assets/UI/card/"
const CARD_ICON_PATH: String = "res://Assets/Heroes/heroshow/"


func _ready() -> void:
	pivot_offset = custom_minimum_size / 2.0
	_discard_btn.gui_input.connect(_on_discard_gui_input)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		pivot_offset = size / 2.0


# ============================================================
# 数据驱动入口
# ============================================================

func setup_card(p_card_id: String) -> void:
	card_id = p_card_id

	# 1. 查 card_display_config → rarity_id / icon / card_type
	var card_info: Dictionary = _find_card_info(card_id)

	# 2. 查 rarity_config → 底图
	var rarity_id: int = card_info.get("rarity_id", 1)
	var bg_name: String = _find_rarity_bg(rarity_id)
	_apply_texture("CardBG", CARD_BG_PATH + bg_name)

	# 3. 图标
	var icon_name: String = card_info.get("icon_image_name", "")
	if not icon_name.is_empty():
		_apply_texture("Icon", CARD_ICON_PATH + icon_name)

	# 4. 名称
	var card_type: String = card_info.get("card_type", "hero")
	hero_name = _resolve_card_name(card_id, card_type, card_info)
	if has_node("Label"):
		$Label.text = hero_name


func _find_card_info(p_card_id: String) -> Dictionary:
	var cards: Array = DataManager.card_display_config.get("cards", [])
	for entry in cards:
		if entry is Dictionary and entry.get("card_id", "") == p_card_id:
			return entry
	return {}


func _find_rarity_bg(p_rarity_id: int) -> String:
	var rarities: Array = DataManager.rarity_config.get("rarities", [])
	for entry in rarities:
		if entry is Dictionary and entry.get("rarity_id", 0) == p_rarity_id:
			return entry.get("bg_image_name", "quality_1.png")
	return "quality_1.png"


func _resolve_card_name(p_card_id: String, p_card_type: String, p_card_info: Dictionary) -> String:
	if p_card_type == "effect":
		return p_card_info.get("default_name", p_card_id)

	# hero 卡 → 读 heroes_progression.json
	var templates: Array = DataManager.heroes_progression.get("hero_base_templates", [])
	for entry in templates:
		if entry is Dictionary and entry.get("hero_id", "") == p_card_id:
			return entry.get("name", p_card_id)
	return p_card_id


func _apply_texture(node_name: String, path: String) -> void:
	if not has_node(node_name):
		return
	if not ResourceLoader.exists(path):
		push_warning("[CardUI] texture not found: " + path)
		return
	var node: TextureRect = get_node(node_name) as TextureRect
	if node:
		node.texture = load(path) as Texture2D


# ============================================================
# 向后兼容 — 旧的 setup() 挂载到 setup_card
# ============================================================

func setup(p_card_id: String, p_hero_name: String, _p_icon: Texture2D = null) -> void:
	setup_card(p_card_id)


# ============================================================
# 弃牌按钮
# ============================================================

func _on_discard_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_on_discard_pressed()


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
