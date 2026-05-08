extends CanvasLayer

## BattleUI CanvasLayer script.
## - Deadlock-rescue banner fade-in/out
## - Queue count label ("9+" logic)

@onready var _rescue_banner: Control = $RescueBanner
@onready var _deck_count_label: Label = $DeckCountLabel


func _ready() -> void:
	if not GameEvents.deadlock_rescue_triggered.is_connected(_on_rescue_triggered):
		GameEvents.deadlock_rescue_triggered.connect(_on_rescue_triggered)

	_update_queue_label()
	var timer: Timer = Timer.new()
	timer.name = "QueuePollTimer"
	timer.wait_time = 0.5
	timer.timeout.connect(_update_queue_label)
	add_child(timer)
	timer.start()


func _on_rescue_triggered() -> void:
	_rescue_banner.visible = true
	_rescue_banner.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(_rescue_banner, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.5)
	tween.tween_property(_rescue_banner, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _rescue_banner.visible = false)


func _update_queue_label() -> void:
	if _deck_count_label == null:
		return
	var count: int = DeckManager.card_queue.size()
	_deck_count_label.text = str(count) if count <= 9 else "9+"
	_deck_count_label.visible = count > 0
