extends Node3D
class_name InventoryContainer3D

signal opened(actor_inventory: Node, container_inventory: Node)
signal open_failed(reason: String)

@export var inventory_path: NodePath = NodePath("Inventory")

@onready var inventory: Node = get_node_or_null(inventory_path)


func get_inventory() -> Node:
	return inventory


func can_open(actor_inventory: Node = null) -> bool:
	return inventory != null and bool(inventory.call("is_accessible", actor_inventory))


func open(actor_inventory: Node = null) -> bool:
	if inventory == null:
		open_failed.emit("Este container nao possui inventario.")
		return false

	if not bool(inventory.call("unlock_with", actor_inventory)):
		open_failed.emit("Trancado.")
		return false

	opened.emit(actor_inventory, inventory)
	return true
