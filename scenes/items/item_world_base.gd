extends Area3D
class_name ItemWorldBase

signal picked_up(actor_inventory: Node, amount: int)
signal pickup_failed(reason: String)

@export var item: Resource
@export_range(1, 999, 1, "or_greater") var amount := 1
@export var durability := -1.0
@export var remove_when_empty := true


func setup(new_item: Resource, new_amount := 1, new_durability := -1.0) -> void:
	item = new_item
	amount = max(1, new_amount)
	durability = new_durability


func get_display_name() -> String:
	if item == null:
		return "Item"

	var item_name := str(item.get("display_name"))
	if item_name.is_empty():
		return str(item.get("id"))
	return item_name


func try_pickup(actor_inventory: Node) -> int:
	if item == null:
		pickup_failed.emit("Este item nao possui definicao.")
		return 0

	if actor_inventory == null or not actor_inventory.has_method("add_item"):
		pickup_failed.emit("O alvo nao possui inventario.")
		return 0

	var added := int(actor_inventory.call("add_item", item, amount, durability))
	if added <= 0:
		pickup_failed.emit("Inventario cheio.")
		return 0

	amount -= added
	picked_up.emit(actor_inventory, added)

	if amount <= 0 and remove_when_empty:
		queue_free()

	return added
