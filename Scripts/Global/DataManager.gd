extends Node

## Centralized JSON data loader (Autoload).
## All game configuration is read through this manager — no other script
## should call FileAccess or JSON.parse_string directly.

var error_messages: Dictionary = {}


func _ready() -> void:
	error_messages = load_json("res://Data/error_codes.json")


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
