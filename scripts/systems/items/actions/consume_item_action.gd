extends "res://scripts/systems/items/actions/item_action.gd"
class_name ConsumeItemAction


func _init() -> void:
	trigger = TRIGGER_PRIMARY
	display_name = "Consume"


func execute(actor: Node, equipment: Node, stack: Resource, slot: StringName, _held_instance: Node3D) -> bool:
	if actor == null or equipment == null or stack == null or bool(stack.call("is_empty")):
		return false

	var item: Resource = stack.get("item")
	if item == null:
		return false

	var stats: Node = actor.call("get_stats") if actor.has_method("get_stats") else null
	if stats != null:
		var hp_restore := float(item.get("hp_restore"))
		var hunger_restore := float(item.get("hunger_restore"))
		if hp_restore > 0.0 and stats.has_method("heal"):
			stats.call("heal", hp_restore)
		if hunger_restore > 0.0 and stats.has_method("restore_hunger"):
			stats.call("restore_hunger", hunger_restore)

	if not equipment.has_method("consume_equipped_item"):
		return false
	return bool(equipment.call("consume_equipped_item", slot, 1))
