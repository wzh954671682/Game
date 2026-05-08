extends Control

## Self-contained draggable card. Owns its full drag lifecycle:
## - _gui_input detects the initial press → starts drag, sets semi-transparent
## - _input (enabled via set_process_input during drag) catches release/cancel globally
## - Emits drag_started, drag_ended (with screen_pos), drag_cancelled

signal drag_started(card_ui: Control)
signal drag_ended(card_ui: Control, screen_pos: Vector2)
signal drag_cancelled(card_ui: Control)

var card_id: String = ""
var hero_name: String = ""
var _is_dragging: bool = false


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
	modulate = Color(1.0, 1.0, 1.0, 0.35)
	set_process_input(true)
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


func _complete_drag(release_pos: Vector2) -> void:
	_is_dragging = false
	modulate = Color.WHITE
	set_process_input(false)
	drag_ended.emit(self, release_pos)


func cancel_drag() -> void:
	if not _is_dragging:
		return
	_is_dragging = false
	modulate = Color.WHITE
	set_process_input(false)
	drag_cancelled.emit(self)
