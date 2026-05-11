extends Node

## Encrypted local save system (Autoload).
## Stores player progress in user:// with AES encryption via ConfigFile.

const SAVE_PATH: String = "user://save_game.dat"
const ENCRYPTION_KEY: String = "PocketHeroV1_ReplaceThisKey"

var save_data: Dictionary = {
	gold = 0,
	shards = 0,
	max_level = 1,
	selected_level = 1,
	selected_stage = "stage_001",
	unlocked_cards = ["hero_01"]
}


func _ready() -> void:
	load_game()


func save_game() -> void:
	var config := ConfigFile.new()
	config.set_value("player", "gold", save_data["gold"])
	config.set_value("player", "shards", save_data["shards"])
	config.set_value("player", "max_level", save_data["max_level"])
	config.set_value("player", "selected_level", save_data["selected_level"])
	config.set_value("player", "selected_stage", save_data["selected_stage"])
	config.set_value("player", "unlocked_cards", save_data["unlocked_cards"])

	var err: Error = config.save_encrypted_pass(SAVE_PATH, ENCRYPTION_KEY)
	if err != OK:
		push_error("SaveManager: 加密存档写入失败 — " + error_string(err))


func load_game() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		push_warning("SaveManager: 存档文件不存在（首次启动），使用默认数据")
		return

	var config := ConfigFile.new()
	var err: Error = config.load_encrypted_pass(SAVE_PATH, ENCRYPTION_KEY)
	if err != OK:
		push_error("SaveManager: 加密存档读取失败 (" + error_string(err) + ")，回滚使用默认数据")
		return

	save_data["gold"] = config.get_value("player", "gold", save_data["gold"])
	save_data["shards"] = config.get_value("player", "shards", save_data["shards"])
	save_data["max_level"] = config.get_value("player", "max_level", save_data["max_level"])
	save_data["selected_level"] = config.get_value("player", "selected_level", save_data["selected_level"])
	save_data["selected_stage"] = config.get_value("player", "selected_stage", save_data["selected_stage"])
	save_data["unlocked_cards"] = config.get_value("player", "unlocked_cards", save_data["unlocked_cards"])

	print("SaveManager: 存档已加载 — 金币=%d, 碎片=%d, 最高关卡=%d" % [save_data["gold"], save_data["shards"], save_data["max_level"]])
