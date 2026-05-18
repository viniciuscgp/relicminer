extends "res://scenes/components/actor_body.gd"
class_name EnemyBase

signal died(enemy: Node)
signal loot_opened(actor_inventory: Node, enemy_inventory: Node)
signal loot_open_failed(reason: String)

@export var loot_after_death := true
@export var disable_collision_on_death := true


func _ready() -> void:
	if combat_stats != null and combat_stats.has_signal("died"):
		combat_stats.connect("died", _on_stats_died)


func is_dead() -> bool:
	return combat_stats != null and combat_stats.has_method("is_dead") and bool(combat_stats.call("is_dead"))


func can_open_loot(actor_inventory: Node = null) -> bool:
	if not loot_after_death or not is_dead() or inventory == null:
		return false
	if not inventory.has_method("is_accessible"):
		return false
	return bool(inventory.call("is_accessible", actor_inventory))


func open_loot(actor_inventory: Node = null) -> bool:
	if inventory == null:
		loot_open_failed.emit(_text("message.enemy.no_inventory"))
		return false

	if not loot_after_death or not is_dead():
		loot_open_failed.emit(_text("message.enemy.cannot_loot_yet"))
		return false

	if not inventory.has_method("unlock_with"):
		loot_open_failed.emit(_text("message.inventory.cannot_open"))
		return false

	if not bool(inventory.call("unlock_with", actor_inventory)):
		loot_open_failed.emit(_text("message.locked"))
		return false

	loot_opened.emit(actor_inventory, inventory)
	return true


func _on_stats_died() -> void:
	if disable_collision_on_death:
		for child in get_children():
			if child is CollisionShape3D:
				child.disabled = true
	died.emit(self)


func _text(key: String) -> String:
	var localization := get_node_or_null("/root/LocalizationManager")
	if localization != null and localization.has_method("text"):
		return str(localization.call("text", key))
	return key
