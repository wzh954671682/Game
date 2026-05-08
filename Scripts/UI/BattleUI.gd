extends CanvasLayer

## Thin script for BattleUI CanvasLayer.
## Handles deadlock-rescue banner visibility and exposes GridAnchor position.

@onready var _rescue_banner: Control = $RescueBanner


func _ready() -> void:
	if not GameEvents.deadlock_rescue_triggered.is_connected(_on_rescue_triggered):
		GameEvents.deadlock_rescue_triggered.connect(_on_rescue_triggered)


func _on_rescue_triggered() -> void:
	_rescue_banner.visible = true
	_rescue_banner.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(_rescue_banner, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.5)
	tween.tween_property(_rescue_banner, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _rescue_banner.visible = false)
