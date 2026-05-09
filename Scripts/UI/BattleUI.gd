extends CanvasLayer

## BattleUI CanvasLayer script.
## - Top HUD: rank badge, EXP bar, pause button
## - Deadlock-rescue banner fade-in/out
## - Queue count label ("9+" logic)

# === Top HUD ==============================================================
@onready var _medal_bg: TextureRect = $TopWrapper/RankNode/MedalBG
@onready var _battle_level_label: Label = $TopWrapper/RankNode/BattleLevel
@onready var _exp_progress_bar: TextureProgressBar = $TopWrapper/ExpBarNode/ExpProgressBar
@onready var _exp_label: Label = $TopWrapper/ExpBarNode/ExpLabel
@onready var _pause_button: Button = $TopWrapper/PauseButton

# === Banner / Deck =======================================================
@onready var _rescue_banner: Control = $RescueBanner
@onready var _deck_count_label: Label = $DeckCountLabel

# === Pause ===============================================================
var _pause_panel: CanvasLayer = null


func _ready() -> void:
	if not GameEvents.deadlock_rescue_triggered.is_connected(_on_rescue_triggered):
		GameEvents.deadlock_rescue_triggered.connect(_on_rescue_triggered)

	_pause_button.pressed.connect(_on_pause_pressed)
	_load_pause_panel()

	_update_queue_label()
	var timer: Timer = Timer.new()
	timer.name = "QueuePollTimer"
	timer.wait_time = 0.5
	timer.timeout.connect(_update_queue_label)
	add_child(timer)
	timer.start()


# ============================================================
# 经验 / 等级 (placeholder — 接入 playerBattleEXP.json 后替换)
# ============================================================

func update_exp(current_exp: int, needed_exp: int) -> void:
	_exp_label.text = "%d/%d" % [current_exp, needed_exp]
	_exp_progress_bar.max_value = float(needed_exp)
	_exp_progress_bar.value = float(current_exp)


func update_battle_level(level: int) -> void:
	_battle_level_label.text = str(level)


# ============================================================
# 暂停
# ============================================================

func _load_pause_panel() -> void:
	var pscene: PackedScene = load("res://Scenes/UI/PausePanel.tscn")
	_pause_panel = pscene.instantiate()
	add_child(_pause_panel)


func _on_pause_pressed() -> void:
	if _pause_panel:
		_pause_panel.show_pause()


# ============================================================
# 救援横幅
# ============================================================

func _on_rescue_triggered() -> void:
	_rescue_banner.visible = true
	_rescue_banner.modulate.a = 0.0

	var tween := create_tween()
	tween.set_parallel(false)
	tween.tween_property(_rescue_banner, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.5)
	tween.tween_property(_rescue_banner, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	tween.tween_callback(func(): _rescue_banner.visible = false)


# ============================================================
# 牌库计数
# ============================================================

func _update_queue_label() -> void:
	if _deck_count_label == null:
		return
	var count: int = DeckManager.card_queue.size()
	_deck_count_label.text = str(count) if count <= 9 else "9+"
	_deck_count_label.visible = count > 0
