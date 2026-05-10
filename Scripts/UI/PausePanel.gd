extends CanvasLayer

## Pause overlay — shown when player taps pause button during battle.

@onready var _btn_continue: Button = $ContentVBox/ButtonHBox/BtnContinue
@onready var _btn_home: Button = $ContentVBox/ButtonHBox/BtnHome


func _ready() -> void:
	_btn_continue.pressed.connect(_on_continue_pressed)
	_btn_home.pressed.connect(_on_home_pressed)
	hide()


func show_pause() -> void:
	show()
	get_tree().paused = true


func _on_continue_pressed() -> void:
	hide()
	get_tree().paused = false


func _on_home_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://Scenes/MainScene.tscn")
