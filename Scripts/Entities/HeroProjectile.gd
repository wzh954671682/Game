extends Area2D

## Hero ranged projectile — flies straight up, supports single image or sequence frames.

var _speed: float = 500.0
var _damage: int = 10
var _lifetime: float = 4.0
var _sprite: Sprite2D = null
var _frames: Array[Texture2D] = []
var _frame_index: int = 0
var _frame_timer: float = 0.0
var _frame_interval: float = 0.08


func _init() -> void:
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 24)
	shape.shape = rect
	shape.name = "CollisionShape2D"
	add_child(shape)

	_sprite = Sprite2D.new()
	_sprite.name = "Sprite2D"
	_sprite.centered = true
	add_child(_sprite)


func _ready() -> void:
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)


func setup(sprite_path: String, _target: Node2D, speed: float, damage: int) -> void:
	_speed = speed
	_damage = damage
	if sprite_path.ends_with("/"):
		_load_sequence_frames(sprite_path)
	else:
		_load_single_frame(sprite_path)


func _load_single_frame(path: String) -> void:
	if ResourceLoader.exists(path):
		_sprite.texture = load(path) as Texture2D


func _load_sequence_frames(folder: String) -> void:
	_frames.clear()
	var dir := DirAccess.open(folder)
	if dir == null:
		return
	dir.list_dir_begin()
	var files: Array[String] = []
	var fn := dir.get_next()
	while not fn.is_empty():
		if fn.ends_with(".png") and not fn.ends_with(".png.import"):
			files.append(fn)
		fn = dir.get_next()
	dir.list_dir_end()
	files.sort()
	for f in files:
		var tex: Texture2D = load(folder + f) as Texture2D
		if tex:
			_frames.append(tex)
	if not _frames.is_empty():
		_sprite.texture = _frames[0]


func _physics_process(delta: float) -> void:
	global_position.y -= _speed * delta

	if not _frames.is_empty():
		_frame_timer += delta
		if _frame_timer >= _frame_interval:
			_frame_timer -= _frame_interval
			_frame_index = (_frame_index + 1) % _frames.size()
			_sprite.texture = _frames[_frame_index]

	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _on_hit(target: Node) -> void:
	if not target.is_in_group("enemies"):
		return
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	target.take_damage(_damage)
	queue_free()
