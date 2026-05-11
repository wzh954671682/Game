extends CanvasLayer

## Battle settlement panel — victory / defeat result screen.
##
## Editor-First: all layout (position, anchors, offsets) is set in the .tscn file.
## This script ONLY does data filling, dynamic node creation, and animation.

# === @export ================================================================

@export_group("Animation")
@export var entrance_duration: float = 0.5
@export var item_bounce_duration: float = 0.6
@export var item_delay: float = 0.15
@export var freeze_delay: float = 1.2

@export_group("Colors")
@export var victory_color: Color = Color(1.0, 0.85, 0.1, 1.0)
@export var defeat_color: Color = Color(0.85, 0.15, 0.1, 1.0)
@export var overlay_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var gold_color: Color = Color(1.0, 0.85, 0.1)
@export var shard_color: Color = Color(0.4, 0.8, 1.0)

const COIN_ICON_PATH: String = "res://Assets/UI/item/jinbi.png"
const ICON_SIZE: float = 120.0

# === @onready ==============================================================

@onready var _background: TextureRect = $SafeAreaContainer/Wrapper/Background
@onready var _label_status: Label = $SafeAreaContainer/Wrapper/Background/Label_Status
@onready var _reward_container: Control = $SafeAreaContainer/Wrapper/Background/RewardContainer
@onready var _btn_action: Button = $SafeAreaContainer/Wrapper/Background/Btn_Action

# === state =================================================================

var _is_victory: bool = false
var _coin_amount: int = 0
var _shard_amount: int = 0
var _shard_icon_path: String = ""


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

	# Full-screen click blocker (only STOP in the entire panel)
	var overlay := ColorRect.new()
	overlay.name = "ClickBlocker"
	overlay.color = overlay_color
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	move_child(overlay, 0)

	_btn_action.pressed.connect(_on_btn_action_pressed)


func setup(is_victory: bool, coin: int, shard: int, shard_id: String = "") -> void:
	_is_victory = is_victory
	_coin_amount = coin
	_shard_amount = shard

	if not shard_id.is_empty():
		_shard_icon_path = "res://Assets/UI/item/hrro_suipian_%s.png" % shard_id

	_label_status.text = "胜利" if _is_victory else "失败"
	_label_status.add_theme_color_override(&"font_color", victory_color if _is_victory else defeat_color)
	_create_reward_icons()

	await get_tree().process_frame
	_play_entrance_animation()
	get_tree().create_timer(freeze_delay).timeout.connect(func(): Engine.time_scale = 0.0)


# ============================================================
# 奖励道具 — 水平排列, 数字叠加在图标右下角
# ============================================================

const ITEM_SPACING: float = 60.0

func _create_reward_icons() -> void:
	for child: Node in _reward_container.get_children():
		child.queue_free()

	var items: Array[Dictionary] = []
	items.append({"icon": COIN_ICON_PATH, "amount": _coin_amount})
	if _is_victory and _shard_amount > 0:
		items.append({"icon": _shard_icon_path, "amount": _shard_amount})

	for i in items.size():
		var item_ctrl := _make_reward_item(items[i]["icon"], items[i]["amount"])
		item_ctrl.position = Vector2(i * (ICON_SIZE + ITEM_SPACING), 0)
		_reward_container.add_child(item_ctrl)


func _make_reward_item(icon_path: String, amount: int) -> Control:
	var ctrl := Control.new()
	ctrl.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	ctrl.mouse_filter = Control.MOUSE_FILTER_PASS

	# 图标
	var icon := TextureRect.new()
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path) as Texture2D
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.layout_mode = 0
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	ctrl.add_child(icon)

	# 数字标签 — 图标右下角, 距边框30px
	var lbl := Label.new()
	lbl.text = str(amount)
	lbl.add_theme_font_size_override(&"font_size", 42)
	lbl.add_theme_color_override(&"font_color", Color.WHITE)
	lbl.add_theme_color_override(&"font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override(&"outline_size", 10)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	lbl.layout_mode = 1
	lbl.anchor_left = 1.0
	lbl.anchor_top = 1.0
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.offset_left = -120.0
	lbl.offset_top = -60.0
	lbl.offset_right = -30.0
	lbl.offset_bottom = -30.0
	lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
	ctrl.add_child(lbl)

	return ctrl


# ============================================================
# 入场动画
# ============================================================

func _play_entrance_animation() -> void:
	# Background: TRANS_BACK scale 0 → 1
	_background.pivot_offset = _background.size * 0.5
	_background.scale = Vector2.ZERO

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_background, "scale", Vector2.ONE, entrance_duration)

	# Items: sequential scale 0 → 1
	var delay: float = item_delay
	for child: Node in _reward_container.get_children():
		if child is Control:
			child.pivot_offset = child.custom_minimum_size * 0.5
			child.scale = Vector2.ZERO
			var row_tween := create_tween()
			row_tween.set_trans(Tween.TRANS_ELASTIC)
			row_tween.set_ease(Tween.EASE_OUT)
			row_tween.tween_property(child, "scale", Vector2.ONE, item_bounce_duration).set_delay(delay)
			delay += item_delay


# ============================================================
# 按钮回调
# ============================================================

func _on_btn_action_pressed() -> void:
	_save_rewards()
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://Scenes/MainScene.tscn")


func _save_rewards() -> void:
	SaveManager.save_data["gold"] = SaveManager.save_data["gold"] + _coin_amount
	SaveManager.save_data["shards"] = SaveManager.save_data["shards"] + _shard_amount
	SaveManager.save_game()
	print("[SettlementPanel] 结算存档: +金币%d +碎片%d" % [_coin_amount, _shard_amount])
