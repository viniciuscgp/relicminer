extends StaticBody3D
class_name Chest

signal opened(actor_inventory: Node, chest_inventory: Node)
signal open_failed(reason: String)

@export var inventory_path: NodePath = NodePath("InventoryComponent")

@onready var inventory: Node = get_node_or_null(inventory_path)


func get_inventory() -> Node:
	return inventory


func can_open(actor_inventory: Node = null) -> bool:
	if inventory == null:
		return false
	return bool(inventory.call("is_accessible", actor_inventory))


func open(actor_inventory: Node = null) -> bool:
	if inventory == null:
		open_failed.emit(_text("message.chest.no_inventory"))
		return false

	if not bool(inventory.call("unlock_with", actor_inventory)):
		open_failed.emit(_text("message.locked"))
		return false

	opened.emit(actor_inventory, inventory)
	return true


func _text(key: String) -> String:
	var localization := get_node_or_null("/root/LocalizationManager")
	if localization != null and localization.has_method("text"):
		return str(localization.call("text", key))
	return key
