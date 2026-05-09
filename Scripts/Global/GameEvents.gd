extends Node

## Global event bus singleton (Autoload).
## All communication between UI, battle logic, and entities flows through
## these signals — never through direct node references.

signal wall_hit(damage: int)
signal enemy_died(pos: Vector2)
signal card_deployed(logic_pos: Vector2i, hero_id: String)
signal deadlock_rescue_triggered()
signal wall_hp_changed(current_hp: int, max_hp: int)
signal game_over()
signal stage_victory(stage_id: String)
