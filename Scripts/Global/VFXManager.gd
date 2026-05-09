extends Node

## Global VFX orchestrator (Autoload).
## - hit_stop: frame-freeze on kill
## - shake_camera: screen shake triggered by wall_hit
## - show_damage_text: floating damage numbers
##
## Runs in PROCESS_MODE_ALWAYS so it remains unaffected by Engine.time_scale.

var _hit_stop_count: int = 0

# Screen shake state
var _shake_intensity: float = 0.0
var _shake_remaining: float = 0.0

# Damage text canvas (persistent, reused for all popups)
var _damage_canvas: CanvasLayer = null

# 防堆叠: 单帧飘字上限与计数器
static var _popup_last_frame: int = -1
static var _popup_frame_count: int = 0
const POPUP_OFFSET_THRESHOLD: int = 5
const POPUP_MAX_PER_FRAME: int = 15


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	# 屏幕震动: 监听城墙受击信号
	if not GameEvents.wall_hit.is_connected(_on_wall_hit):
		GameEvents.wall_hit.connect(_on_wall_hit)


func _process(delta: float) -> void:
	if _shake_remaining <= 0.0:
		return

	_shake_remaining -= delta
	var camera := _find_camera()
	if camera == null:
		_shake_remaining = 0.0
		return

	if _shake_remaining <= 0.0:
		camera.offset = Vector2.ZERO
	else:
		camera.offset = Vector2(
			randf_range(-_shake_intensity, _shake_intensity),
			randf_range(-_shake_intensity, _shake_intensity)
		)


# ============================================================
# Hit Stop (帧冻结)
# ============================================================

func hit_stop(duration_sec: float = 0.05, time_scale: float = 0.1) -> void:
	_hit_stop_count += 1
	Engine.time_scale = time_scale

	# Timer 忽略 time_scale, 保证在真实时间内恢复
	await get_tree().create_timer(duration_sec, true, false, true).timeout

	_hit_stop_count -= 1
	if _hit_stop_count <= 0:
		_hit_stop_count = 0
		Engine.time_scale = 1.0


# ============================================================
# 屏幕震动
# ============================================================

func shake_camera(intensity: float, duration: float) -> void:
	_shake_intensity = intensity
	_shake_remaining = duration


func _on_wall_hit(_damage: int) -> void:
	shake_camera(5.0, 0.2)


# ============================================================
# 伤害飘字
# ============================================================

func _find_camera() -> Camera2D:
	for node in get_tree().root.get_children():
		if node is Camera2D and node.enabled:
			return node as Camera2D
		for child in node.get_children():
			if child is Camera2D and child.enabled:
				return child as Camera2D
			for grandchild in child.get_children():
				if grandchild is Camera2D and grandchild.enabled:
					return grandchild as Camera2D
	return null


func show_damage_text(world_pos: Vector2, value: int, is_crit: bool = false) -> void:
	# 防堆叠: 每帧重置计数器, 超上限直接丢弃
	var current_frame := Engine.get_process_frames()
	if current_frame != _popup_last_frame:
		_popup_last_frame = current_frame
		_popup_frame_count = 0

	if _popup_frame_count >= POPUP_MAX_PER_FRAME:
		return
	_popup_frame_count += 1

	var camera := _find_camera()
	if camera == null:
		return

	# CanvasLayer 必须挂在 Viewport 子树内 (如 BattleTest), 挂在 Window 下不渲染
	if _damage_canvas == null or not is_instance_valid(_damage_canvas):
		_damage_canvas = CanvasLayer.new()
		_damage_canvas.name = "DamageCanvas"
		_damage_canvas.layer = 100
		camera.get_parent().add_child(_damage_canvas)

	# canvas_transform 方向: canvas → world, 取逆得 world → canvas
	var screen_pos := camera.get_canvas_transform().affine_inverse() * world_pos

	# 单帧飘字 > 5 时施加随机微量偏移防止重叠
	if _popup_frame_count > POPUP_OFFSET_THRESHOLD:
		screen_pos += Vector2(randf_range(-30.0, 30.0), randf_range(-20.0, 20.0))

	var font_size: int = 54 if is_crit else 36
	var font_color: Color = Color.YELLOW if is_crit else Color.WHITE

	var label := Label.new()
	label.text = str(value)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", font_color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 3)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = screen_pos - Vector2(-90, 50)
	label.size = Vector2(80, 40)
	label.z_index = 20
	_damage_canvas.add_child(label)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", screen_pos.y - 120, 0.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.6).from(1.0)

	# 暴击弹性缩放
	if is_crit:
		label.scale = Vector2(0.5, 0.5)
		var scale_tween := create_tween()
		scale_tween.tween_property(label, "scale", Vector2.ONE, 0.1)\
			.set_trans(Tween.TRANS_ELASTIC)

	tween.finished.connect(label.queue_free)
