extends Area2D

## Boss missile — flies in a set direction, uses sprite for visual.

var _direction: Vector2 = Vector2.DOWN
var _speed: float = 250.0
var _damage: int = 50
var _lifetime: float = 5.0

@onready var _sprite: Sprite2D = $Sprite2D


func _init() -> void:
	collision_layer = 1
	collision_mask = 1
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 16.0
	shape.shape = circle
	shape.name = "CollisionShape2D"
	add_child(shape)

	var sp := Sprite2D.new()
	sp.name = "Sprite2D"
	sp.centered = true
	add_child(sp)


func _ready() -> void:
	area_entered.connect(_on_hit)
	body_entered.connect(_on_hit)


func setup(direction: Vector2, speed: float, damage: int, sprite_path: String = "") -> void:
	_direction = direction.normalized()
	_speed = speed
	_damage = damage
	if not sprite_path.is_empty() and ResourceLoader.exists(sprite_path):
		_sprite.texture = load(sprite_path) as Texture2D


func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_lifetime -= delta
	if _lifetime <= 0.0:
		queue_free()


func _on_hit(target: Node) -> void:
	if not target.is_in_group("heroes"):
		return
	if not is_instance_valid(target) or not target.has_method("take_damage"):
		return
	target.take_damage(_damage)
	queue_free()
