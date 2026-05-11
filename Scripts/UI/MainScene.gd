extends CanvasLayer

const PANEL_SHOP := 0
const PANEL_HERO := 1
const PANEL_BATTLE := 2
const PANEL_CAMP := 3
const PANEL_GUILD := 4

@onready var panels: Array[Control] = [
	$PanelContainer/PreloadPanels/ShopPanel,
	$PanelContainer/HeroPanel,
	$PanelContainer/HomePanel,
	$PanelContainer/PreloadPanels/CampPanel,
	$PanelContainer/PreloadPanels/GuildPanel
]

@onready var nav_buttons: Array[Button] = [
	$NavLayer/BottomNavBar/BtnNav0,
	$NavLayer/BottomNavBar/BtnNav1,
	$NavLayer/BottomNavBar/BtnNav2,
	$NavLayer/BottomNavBar/BtnNav3,
	$NavLayer/BottomNavBar/BtnNav4
]

@onready var squad_slots: Array[Control] = [
	$PanelContainer/HeroPanel/SquadContainer/Slot0,
	$PanelContainer/HeroPanel/SquadContainer/Slot1,
	$PanelContainer/HeroPanel/SquadContainer/Slot2,
	$PanelContainer/HeroPanel/SquadContainer/Slot3
]

@onready var hero_list_content: HBoxContainer = $PanelContainer/HeroPanel/HeroList/HeroListContent

@onready var _level_label: Label = $PanelContainer/HomePanel/LevelSelect/LevelLabel
@onready var _btn_level_left: Button = $PanelContainer/HomePanel/LevelSelect/BtnLevelLeft
@onready var _btn_level_right: Button = $PanelContainer/HomePanel/LevelSelect/BtnLevelRight

var _hero_list_populated := false
var _current_level_index: int = 1
var _total_levels: int = 1


func _ready() -> void:
	for i in range(nav_buttons.size()):
		nav_buttons[i].pressed.connect(_on_nav_button_pressed.bind(i))

	# 初始化关卡选择
	var stages: Dictionary = DataManager.stage_config.get("stages", {})
	_total_levels = stages.size()
	_current_level_index = SaveManager.save_data.get("selected_level", 1)
	_current_level_index = clampi(_current_level_index, 1, _total_levels)
	_refresh_level_display()

	switch_panel(PANEL_BATTLE)


func switch_panel(index: int) -> void:
	for i in range(panels.size()):
		var is_active := i == index
		panels[i].visible = is_active
		panels[i].set_process(is_active)
	for i in range(nav_buttons.size()):
		nav_buttons[i].disabled = (i == index)

	if index == PANEL_HERO and not _hero_list_populated:
		_populate_hero_panel()
		_hero_list_populated = true


func _on_nav_button_pressed(index: int) -> void:
	switch_panel(index)


func _on_start_battle_pressed() -> void:
	SaveManager.save_data["selected_stage"] = "stage_%03d" % _current_level_index
	SaveManager.save_data["selected_level"] = _current_level_index
	get_tree().change_scene_to_file("res://Scenes/BattleTest.tscn")


func _on_level_left_pressed() -> void:
	if _current_level_index > 1:
		_current_level_index -= 1
		_refresh_level_display()


func _on_level_right_pressed() -> void:
	if _current_level_index < _total_levels:
		_current_level_index += 1
		_refresh_level_display()


func _refresh_level_display() -> void:
	_level_label.text = "第%d关" % _current_level_index
	_btn_level_left.visible = _current_level_index > 1
	_btn_level_right.visible = _current_level_index < _total_levels


# ============================================================
# HeroPanel — 英雄列表 & 拖拽上阵
# ============================================================

func _populate_hero_panel() -> void:
	_populate_hero_list()
	_load_squad_from_save()


func _populate_hero_list() -> void:
	var cards: Array = DataManager.card_display_config.get("cards", [])
	var card_scene := preload("res://Scenes/CardUI.tscn")

	for card in cards:
		if card.get("card_type", "") != "hero":
			continue

		var card_ui := card_scene.instantiate()
		card_ui.setup_card(card["card_id"])

		# 主菜单隐藏弃牌按钮，禁用弃牌交互
		var discard := card_ui.get_node_or_null("DiscardBtn")
		if discard:
			discard.visible = false
			discard.mouse_filter = Control.MOUSE_FILTER_IGNORE

		card_ui.drag_ended.connect(_on_card_drag_ended)
		hero_list_content.add_child(card_ui)


func _on_card_drag_ended(card_ui: Control, screen_pos: Vector2) -> void:
	for i in range(squad_slots.size()):
		if squad_slots[i].get_global_rect().has_point(screen_pos):
			_assign_to_squad(card_ui.card_id, i)
			return


func _assign_to_squad(hero_id: String, slot_index: int) -> void:
	var squad: Array = SaveManager.save_data.get("squad", [])
	while squad.size() <= slot_index:
		squad.append("")
	squad[slot_index] = hero_id
	SaveManager.save_data["squad"] = squad
	SaveManager.save_game()
	_load_squad_from_save()


# ============================================================
# 阵容槽位视觉
# ============================================================

func _load_squad_from_save() -> void:
	var squad: Array = SaveManager.save_data.get("squad", [])
	for i in range(squad_slots.size()):
		var slot := squad_slots[i]
		var slot_bg: ColorRect = slot.get_node_or_null("SlotBg")
		var empty_label: Label = slot.get_node_or_null("EmptyLabel")
		var hero_icon: TextureRect = slot.get_node_or_null("HeroIcon")
		var quality_frame: TextureRect = slot.get_node_or_null("QualityFrame")

		if i < squad.size() and not squad[i].is_empty():
			_show_hero_in_slot(squad[i], slot_bg, empty_label, hero_icon, quality_frame)
		else:
			_show_empty_slot(slot_bg, empty_label, hero_icon, quality_frame)


func _show_hero_in_slot(hero_id: String, slot_bg: ColorRect, empty_label: Label, hero_icon: TextureRect, quality_frame: TextureRect) -> void:
	if empty_label:
		empty_label.visible = false
	if hero_icon:
		hero_icon.visible = true
		var icon_name := _resolve_hero_icon(hero_id)
		var icon_path := "res://Assets/Heroes/heroshow/" + icon_name
		if ResourceLoader.exists(icon_path):
			hero_icon.texture = load(icon_path)
	if quality_frame:
		quality_frame.visible = true
	if slot_bg:
		slot_bg.color = Color(0.08, 0.15, 0.08, 0.85)


func _resolve_hero_icon(hero_id: String) -> String:
	var cards: Array = DataManager.card_display_config.get("cards", [])
	for entry in cards:
		if entry is Dictionary and entry.get("card_id", "") == hero_id:
			return entry.get("icon_image_name", hero_id + ".png")
	return hero_id + ".png"


func _show_empty_slot(slot_bg: ColorRect, empty_label: Label, hero_icon: TextureRect, quality_frame: TextureRect) -> void:
	if empty_label:
		empty_label.visible = true
	if hero_icon:
		hero_icon.visible = false
	if quality_frame:
		quality_frame.visible = false
	if slot_bg:
		slot_bg.color = Color(0.12, 0.12, 0.18, 0.85)
