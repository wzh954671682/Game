extends Control
## Debug monitor — logs size/position changes on Wrapper node every frame.

var _last: Dictionary = {}

func _ready() -> void:
	print("[WrapperMonitor] ===== READY frame=%d ======" % Engine.get_process_frames())
	_snapshot()
	_dump_current()
	if get_parent():
		get_parent().resized.connect(_on_parent_resized)

func _dump_current() -> void:
	var parent_ctrl := get_parent() as Control
	var p_size: Vector2 = parent_ctrl.size if parent_ctrl else Vector2.ZERO
	var sa: MarginContainer = parent_ctrl.get_parent() as MarginContainer if parent_ctrl else null
	var sa_margins: Dictionary = {}
	if sa:
		for k: String in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			sa_margins[k] = sa.get_theme_constant(k)
	print("[WrapperMonitor]  size=%s  pos=%s  global_pos=%s  offsets=(L:%d T:%d R:%d B:%d)  parent_size=%s  safearea_margins=%s" % [
		size, position, global_position,
		offset_left, offset_top, offset_right, offset_bottom,
		p_size, sa_margins
	])

func _snapshot() -> void:
	_last = {
		size = size, position = position, global_position = global_position,
		offset_left = offset_left, offset_top = offset_top,
		offset_right = offset_right, offset_bottom = offset_bottom,
	}

func _process(_delta: float) -> void:
	if size != _last.size or position != _last.position or global_position != _last.global_position \
		or offset_left != _last.offset_left or offset_top != _last.offset_top \
		or offset_right != _last.offset_right or offset_bottom != _last.offset_bottom:
		var changes := PackedStringArray()
		if size != _last.size: changes.append("size: %s→%s" % [_last.size, size])
		if position != _last.position: changes.append("pos: %s→%s" % [_last.position, position])
		if global_position != _last.global_position: changes.append("global: %s→%s" % [_last.global_position, global_position])
		if offset_left != _last.offset_left: changes.append("L:%d→%d" % [_last.offset_left, offset_left])
		if offset_top != _last.offset_top: changes.append("T:%d→%d" % [_last.offset_top, offset_top])
		if offset_right != _last.offset_right: changes.append("R:%d→%d" % [_last.offset_right, offset_right])
		if offset_bottom != _last.offset_bottom: changes.append("B:%d→%d" % [_last.offset_bottom, offset_bottom])
		print("[WrapperMonitor] frame=%d | %s" % [Engine.get_process_frames(), " | ".join(changes)])
		_dump_current()
		_snapshot()

func _on_parent_resized() -> void:
	print("[WrapperMonitor] parent_resized frame=%d" % Engine.get_process_frames())
	_dump_current()
	_snapshot()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		print("[WrapperMonitor] NOTIFICATION_RESIZED frame=%d size=%s" % [Engine.get_process_frames(), size])
