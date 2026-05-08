class_name CardTrayManager
extends Control

## Manages the card tray HUD. Creates / destroys CardUI instances in response
## to DeckManager.card_drawn. Does NOT handle drag logic — that stays in the
## parent battle scene which connects to each card's signals via card_created.

signal card_created(card_ui: Control)

const TRAY_HEIGHT: float = 220.0
const TRAY_BOTTOM_MARGIN: float = 20.0
const TRAY_MAX_WIDTH: float = 820.0

var _card_scene: PackedScene = null
var _hero_templates: Dictionary = {}
var _tray: HBoxContainer = null


func setup(card_scene: PackedScene, hero_templates: Dictionary) -> void:
	_card_scene = card_scene
	_hero_templates = hero_templates
	_create_tray()
	if not DeckManager.card_drawn.is_connected(_on_card_drawn):
		DeckManager.card_drawn.connect(_on_card_drawn)


func _create_tray() -> void:
	_tray = HBoxContainer.new()
	_tray.name = "CardTray"
	_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	_tray.add_theme_constant_override("separation", 8)
	add_child(_tray)
	_position_tray()
	get_tree().root.size_changed.connect(_position_tray)


func _position_tray() -> void:
	var vp_size: Vector2 = get_viewport().get_visible_rect().size
	var tray_width: float = minf(vp_size.x - 30.0, TRAY_MAX_WIDTH)
	_tray.position = Vector2(
		(vp_size.x - tray_width) / 2.0,
		vp_size.y - TRAY_HEIGHT - TRAY_BOTTOM_MARGIN
	)
	_tray.size = Vector2(tray_width, TRAY_HEIGHT)


func _on_card_drawn(card_id: String) -> void:
	if _card_scene == null:
		push_error("CardTrayManager: card_scene not set")
		return

	var template: Dictionary = _hero_templates.get(card_id, {})
	var hero_name: String = template.get("name", card_id)

	var card: Control = _card_scene.instantiate()
	card.setup(card_id, hero_name, null)
	_tray.add_child(card)

	card.scale = Vector2.ZERO
	var tween: Tween = create_tween()
	tween.tween_property(card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	card_created.emit(card)
