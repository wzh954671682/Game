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


func show_damage_text(world_pos: Vector2, value: int) -> void:
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

	var label := Label.new()
	label.text = str(value)
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color.WHITE)
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
	tween.finished.connect(label.queue_free)
