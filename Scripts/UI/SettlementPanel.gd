extends CanvasLayer

## Battle settlement panel — victory / defeat result screen.
##
## Layout: open VictoryPanel.tscn or DefeatPanel.tscn in the Godot editor
## to visually adjust panel size, font sizes, colors, and spacing.
##
## Sizing: tweak @export vars in the Inspector (grouped under "Settlement Layout").

# === @export: editable in Godot Inspector ===================================

@export_group("Panel Layout")
@export var panel_width: float = 600.0
@export var panel_height: float = 420.0

@export_group("Typography")
@export var status_font_size: int = 64
@export var reward_font_size: int = 42
@export var button_font_size: int = 36

@export_group("Reward Icons")
@export var icon_size: float = 80.0
@export var icon_spacing: int = 40
@export var icon_bounce_delay: float = 0.15

@export_group("Animation")
@export var entrance_duration: float = 0.5
@export var icon_bounce_duration: float = 0.6
@export var initial_delay: float = 0.3
@export var freeze_delay: float = 1.2

@export_group("Colors")
@export var victory_color: Color = Color(1.0, 0.85, 0.1, 1.0)
@export var defeat_color: Color = Color(0.85, 0.15, 0.1, 1.0)
@export var overlay_color: Color = Color(0.0, 0.0, 0.0, 0.55)
@export var gold_color: Color = Color(1.0, 0.85, 0.1)
@export var shard_color: Color = Color(0.4, 0.8, 1.0)

# === constants ==============================================================

const COIN_ICON_PATH: String = "res://Assets/UI/item/jinbi.png"
const PANEL_SLIDE_OFFSET: float = 120.0

# === @onready: nodes from TSCN ==============================================

@onready var _panel: Panel = $SafeAreaContainer/Panel
@onready var _label_status: Label = $SafeAreaContainer/Panel/VBoxContainer/Label_Status
@onready var _reward_container: HBoxContainer = $SafeAreaContainer/Panel/VBoxContainer/RewardContainer
@onready var _btn_action: Button = $SafeAreaContainer/Panel/VBoxContainer/Btn_Action

# === state ==================================================================

var _is_victory: bool = false
var _coin_amount: int = 0
var _shard_amount: int = 0
var _shard_icon_path: String = ""


func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS

	# Full-screen click blocker (behind SafeAreaContainer)
	var overlay := ColorRect.new()
	overlay.name = "ClickBlocker"
	overlay.color = overlay_color
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	move_child(overlay, 0)

	# --- Panel: explicit visibility guard ---
	_panel.visible = true
	_panel.modulate = Color.WHITE
	_panel.z_index = 0

	# --- Panel: debug background (solid color, guaranteed visible) ---
	var dbg_style := StyleBoxFlat.new()
	dbg_style.bg_color = Color(0.12, 0.14, 0.22, 0.96)
	_panel.add_theme_stylebox_override(&"panel", dbg_style)

	# --- Panel: prevent size collapse ---
	_panel.custom_minimum_size = Vector2(panel_width, panel_height)
	_panel.set_h_size_flags(Control.SIZE_SHRINK_CENTER)
	_panel.set_v_size_flags(Control.SIZE_SHRINK_CENTER)
	# Force anchor resolution while in tree
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -panel_width / 2.0
	_panel.offset_right = panel_width / 2.0
	_panel.offset_top = -panel_height / 2.0
	_panel.offset_bottom = panel_height / 2.0

	# --- Reward container: prevent collapse before icons are added ---
	_reward_container.custom_minimum_size = Vector2(400, 100)

	_label_status.add_theme_font_size_override(&"font_size", status_font_size)
	_btn_action.add_theme_font_size_override(&"font_size", button_font_size)

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

	# Wait one frame so Godot resolves VBoxContainer→Panel→SafeArea layout chain
	await get_tree().process_frame

	_play_entrance_animation()

	# Freeze battle after animations complete
	get_tree().create_timer(freeze_delay).timeout.connect(func(): Engine.time_scale = 0.0)


# ============================================================
# 奖励图标 (动态生成)
# ============================================================

func _create_reward_icons() -> void:
	for child: Node in _reward_container.get_children():
		child.queue_free()

	# Gold icon + label
	var gold_icon := TextureRect.new()
	gold_icon.texture = load(COIN_ICON_PATH) as Texture2D
	gold_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	gold_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	gold_icon.custom_minimum_size = Vector2(icon_size, icon_size)
	gold_icon.pivot_offset = Vector2(icon_size / 2.0, icon_size / 2.0)
	_reward_container.add_child(gold_icon)

	var gold_label := Label.new()
	gold_label.text = "+%d" % _coin_amount
	gold_label.add_theme_font_size_override(&"font_size", reward_font_size)
	gold_label.add_theme_color_override(&"font_color", gold_color)
	gold_label.add_theme_constant_override(&"outline_size", 4)
	gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_reward_container.add_child(gold_label)

	# Shard icon + label (victory only)
	if _is_victory and _shard_amount > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(icon_spacing, 0)
		_reward_container.add_child(spacer)

		var shard_icon := TextureRect.new()
		if not _shard_icon_path.is_empty() and ResourceLoader.exists(_shard_icon_path):
			shard_icon.texture = load(_shard_icon_path) as Texture2D
		shard_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		shard_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shard_icon.custom_minimum_size = Vector2(icon_size, icon_size)
		shard_icon.pivot_offset = Vector2(icon_size / 2.0, icon_size / 2.0)
		_reward_container.add_child(shard_icon)

		var shard_label := Label.new()
		shard_label.text = "+%d" % _shard_amount
		shard_label.add_theme_font_size_override(&"font_size", reward_font_size)
		shard_label.add_theme_color_override(&"font_color", shard_color)
		shard_label.add_theme_constant_override(&"outline_size", 4)
		shard_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_reward_container.add_child(shard_label)


# ============================================================
# 入场动画 (modulate + slide, NOT scale — scale stays at 1)
# ============================================================

func _play_entrance_animation() -> void:
	# Force center preset again now that layout has resolved
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_panel.offset_left = -panel_width / 2.0
	_panel.offset_right = panel_width / 2.0
	_panel.offset_top = -panel_height / 2.0
	_panel.offset_bottom = panel_height / 2.0
	# Hardcoded pivot — do NOT read _panel.size (may be stale / zero)
	_panel.pivot_offset = Vector2(panel_width / 2.0, panel_height / 2.0)

	# Slide up from below
	_panel.position.y += PANEL_SLIDE_OFFSET

	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(_panel, "position:y", _panel.position.y - PANEL_SLIDE_OFFSET, entrance_duration)

	# Reward icons: sequential elastic bounce (from scale 0 → 1)
	var delay: float = initial_delay
	for child: Node in _reward_container.get_children():
		if child is TextureRect:
			child.scale = Vector2.ZERO
			var icon_tween := create_tween()
			icon_tween.set_trans(Tween.TRANS_ELASTIC)
			icon_tween.set_ease(Tween.EASE_OUT)
			icon_tween.tween_property(child, "scale", Vector2.ONE, icon_bounce_duration).set_delay(delay)
			delay += icon_bounce_delay


# ============================================================
# 按钮回调
# ============================================================

func _on_btn_action_pressed() -> void:
	_save_rewards()
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _save_rewards() -> void:
	SaveManager.save_data["gold"] = SaveManager.save_data["gold"] + _coin_amount
	SaveManager.save_data["shards"] = SaveManager.save_data["shards"] + _shard_amount
	SaveManager.save_game()
	print("[SettlementPanel] 结算存档: +金币%d +碎片%d" % [_coin_amount, _shard_amount])
