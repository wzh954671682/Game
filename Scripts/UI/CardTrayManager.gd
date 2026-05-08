class_name CardTrayManager
extends Control

## Manages the card tray HUD. Creates / destroys CardUI instances in response
## to DeckManager.card_drawn. Does NOT handle drag logic — that stays in the
## parent battle scene which connects to each card's signals via card_created.
##
## All layout values are read from GridManager (single source of truth).

signal card_created(card_ui: Control)

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
	_tray.layout_mode = 0  # manual position, not anchors
	_tray.alignment = BoxContainer.ALIGNMENT_CENTER
	_tray.add_theme_constant_override("separation", 8)
	add_child(_tray)
	_position_tray()
	get_tree().root.size_changed.connect(_position_tray)


func _position_tray() -> void:
	var design_w: float = float(GridManager.REF_WIDTH)
	var tray_width: float = minf(design_w - 30.0, TRAY_MAX_WIDTH)
	var tray_top: float = GridManager.get_card_tray_top()
	_tray.position = Vector2(
		(design_w - tray_width) / 2.0,
		tray_top,
	)
	_tray.size = Vector2(tray_width, GridManager.get_card_tray_height())


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
