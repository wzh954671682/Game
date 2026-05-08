extends Control

## Draggable card for the card tray. Press to start dragging, release to deploy.
## Emits signals so the battle scene can manage the ghost preview and deployment.

signal drag_started(card_ui: Control)
signal drag_ended(card_ui: Control)

var card_id: String = ""
var hero_name: String = ""
var _is_dragging: bool = false
var _original_modulate: Color = Color.WHITE


func setup(p_card_id: String, p_hero_name: String) -> void:
	card_id = p_card_id
	hero_name = p_hero_name
	var label: Label = $Label
	if label:
		label.text = p_hero_name


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if not event.pressed:
		return

	_is_dragging = true
	_original_modulate = modulate
	modulate = Color(1.0, 1.0, 1.0, 0.35)
	drag_started.emit(self)
	accept_event()


func cancel_drag() -> void:
	_is_dragging = false
	modulate = _original_modulate
