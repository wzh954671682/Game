extends Node

## Hidden card queue (FIFO), auto-fill, discard, and anti-lock rescue system.
## Registered as Autoload. UI calls into this — never the reverse.

signal card_drawn(card_id: String)

const MAX_HAND_SIZE: int = 5
const INITIAL_SILENCE_SEC: float = 5.0
const RESCUE_COOLDOWN_SEC: float = 4.0
const DRAW_INTERVAL_SEC: float = 0.1
const SCAN_INTERVAL_SEC: float = 1.0

var card_queue: Array[String] = []
var hand_count: int = 0
var field_hero_count: int = 0

var _silence_elapsed: float = 0.0
var _rescue_cooldown_left: float = 0.0
var _scan_accumulator: float = 0.0
var _is_drawing: bool = false
var _battle_active: bool = false


func _physics_process(delta: float) -> void:
	if not _battle_active:
		return

	if _silence_elapsed < INITIAL_SILENCE_SEC:
		_silence_elapsed += delta
		return

	if _rescue_cooldown_left > 0.0:
		_rescue_cooldown_left = maxf(_rescue_cooldown_left - delta, 0.0)

	_scan_accumulator += delta
	if _scan_accumulator < SCAN_INTERVAL_SEC:
		return
	_scan_accumulator -= SCAN_INTERVAL_SEC
	_check_deadlock()


func start_battle() -> void:
	_battle_active = true
	_silence_elapsed = 0.0
	_rescue_cooldown_left = 0.0
	_scan_accumulator = 0.0
	card_queue.clear()
	hand_count = 0
	field_hero_count = 0


func enqueue_card(card_id: String) -> void:
	card_queue.append(card_id)
	_try_fill_hand()


func enqueue_cards(card_ids: Array[String]) -> void:
	card_queue.append_array(card_ids)
	_try_fill_hand()


func discard_card(_card_id: String) -> void:
	hand_count = maxi(hand_count - 1, 0)
	_try_fill_hand()


func on_card_deployed() -> void:
	hand_count = maxi(hand_count - 1, 0)
	field_hero_count += 1
	_try_fill_hand()


func on_effect_used() -> void:
	hand_count = maxi(hand_count - 1, 0)
	_try_fill_hand()


func on_hero_died() -> void:
	field_hero_count = maxi(field_hero_count - 1, 0)
	if _silence_elapsed >= INITIAL_SILENCE_SEC and card_queue.is_empty() and hand_count == 0:
		_check_deadlock()


func _try_fill_hand() -> void:
	if _is_drawing:
		return
	_draw_loop()


func _draw_loop() -> void:
	_is_drawing = true
	while hand_count < MAX_HAND_SIZE and not card_queue.is_empty():
		var drawn_id: String = card_queue.pop_front()
		hand_count += 1
		card_drawn.emit(drawn_id)
		await get_tree().create_timer(DRAW_INTERVAL_SEC).timeout
	_is_drawing = false


func _check_deadlock() -> void:
	if _rescue_cooldown_left > 0.0:
		return
	if hand_count == 0 and card_queue.is_empty() and field_hero_count == 0:
		_trigger_rescue()


func _trigger_rescue() -> void:
	_rescue_cooldown_left = RESCUE_COOLDOWN_SEC
	GameEvents.deadlock_rescue_triggered.emit()

	var rescue_cards: Array[String] = _load_rescue_package()
	for card_id: String in rescue_cards:
		card_queue.append(card_id)
	_try_fill_hand()


func _load_rescue_package() -> Array[String]:
	var config: Dictionary = DataManager.load_json("res://Data/battle_logic_config.json")
	if config.is_empty():
		return _fallback_rescue_package()

	var rescue: Dictionary = config.get("rescue_system", {})
	var package: Array = rescue.get("package_content", [])
	if package.is_empty():
		return _fallback_rescue_package()

	var cards: Array[String] = []
	for entry: Dictionary in package:
		var hero_id: String = entry.get("hero_id", "")
		var count: int = entry.get("count", 0)
		if hero_id.is_empty() or count <= 0:
			continue
		for _i: int in range(count):
			cards.append(hero_id)
	if cards.is_empty():
		return _fallback_rescue_package()
	return cards


func _fallback_rescue_package() -> Array[String]:
	return ["shielder_01", "shielder_01", "shielder_01", "hero_002", "hero_002"]
