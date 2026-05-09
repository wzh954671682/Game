extends Node

## Centralized JSON data loader (Autoload).
## All game configuration is read through this manager — no other script
## should call FileAccess or JSON.parse_string directly.

var error_messages: Dictionary = {}
var monster_templates: Dictionary = {}
var stage_config: Dictionary = {}
var wall_config: Dictionary = {}

const MONSTER_TEMPLATES_PATH: String = "res://Data/monster_templates.json"
const STAGE_CONFIG_PATH: String = "res://Data/level_stage_config.json"
const WALL_CONFIG_PATH: String = "res://Data/wall_config.json"


func _ready() -> void:
	error_messages = load_json("res://Data/error_codes.json")
	monster_templates = load_json(MONSTER_TEMPLATES_PATH)
	stage_config = load_json(STAGE_CONFIG_PATH)
	wall_config = load_json(WALL_CONFIG_PATH)


func load_json(file_path: String) -> Dictionary:
	if not FileAccess.file_exists(file_path):
		push_error("DataManager: file not found — " + file_path)
		return {}

	var file: FileAccess = FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		push_error("DataManager: failed to open file — " + file_path)
		return {}

	var raw_text: String = file.get_as_text()
	file.close()

	if raw_text.is_empty():
		push_error("DataManager: file is empty — " + file_path)
		return {}

	var result: Variant = JSON.parse_string(raw_text)
	if result == null or not result is Dictionary:
		push_error("DataManager: invalid JSON structure in — " + file_path)
		return {}

	return result as Dictionary
