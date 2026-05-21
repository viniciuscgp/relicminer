extends Node

const ItemStackScript := preload("res://scripts/systems/items/item_stack.gd")

signal changed
signal locked_changed(locked: bool)
signal item_added(item: Resource, amount: int)
signal item_removed(item_id: StringName, amount: int)

@export var display_name := "Inventory"
@export_range(1, 200, 1, "or_greater") var capacity_slots := 16
@export_range(0.0, 1000.0, 0.01, "or_greater") var max_weight_kg := 0.0
@export var locked := false
@export var required_key_id: StringName
@export var starting_items: Array[Resource] = []

var slots: Array[Resource] = []


func _ready() -> void:
	_load_starting_items()


func _load_starting_items() -> void:
	slots.clear()
	for resource in starting_items:
		var stack := _create_stack_from_starting_resource(resource)
		if stack == null or stack.is_empty():
			continue
		slots.append(stack)
	_trim_to_capacity()
	changed.emit()


func get_save_data() -> Dictionary:
	return {
		"display_name": display_name,
		"capacity_slots": capacity_slots,
		"max_weight_kg": max_weight_kg,
		"locked": locked,
		"required_key_id": String(required_key_id),
		"slots": _get_slots_save_data(),
	}


func apply_save_data(data: Dictionary) -> void:
	display_name = str(data.get("display_name", display_name))
	capacity_slots = max(1, int(data.get("capacity_slots", capacity_slots)))
	max_weight_kg = maxf(0.0, float(data.get("max_weight_kg", max_weight_kg)))
	locked = bool(data.get("locked", locked))
	required_key_id = StringName(str(data.get("required_key_id", String(required_key_id))))

	slots.clear()
	var saved_slots: Array = data.get("slots", [])
	for stack_data in saved_slots:
		if not stack_data is Dictionary:
			continue
		var stack := _create_stack_from_save_data(stack_data)
		if stack == null or stack.is_empty():
			continue
		slots.append(stack)
	_trim_to_capacity()
	locked_changed.emit(locked)
	changed.emit()


func _create_stack_from_starting_resource(resource: Resource) -> Resource:
	if resource == null:
		return null

	if resource.has_method("is_empty"):
		return resource.duplicate(true)

	if resource.has_method("create_world_instance") or resource.get("id") != null:
		var stack: Resource = ItemStackScript.new()
		stack.call("setup", resource, 1)
		return stack

	return null


func _get_slots_save_data() -> Array:
	var saved_slots: Array = []
	for stack in slots:
		if stack == null or stack.is_empty():
			continue
		var item: Resource = stack.get("item")
		if item == null:
			continue
		saved_slots.append({
			"item_path": item.resource_path,
			"item_id": String(item.get("id")),
			"amount": int(stack.get("amount")),
			"durability": float(stack.get("durability")),
		})
	return saved_slots


func _create_stack_from_save_data(data: Dictionary) -> Resource:
	var item_path := str(data.get("item_path", ""))
	if item_path.is_empty():
		return null

	var item := load(item_path) as Resource
	if item == null:
		push_warning("InventoryComponent: could not load saved item '%s'." % item_path)
		return null

	var stack: Resource = ItemStackScript.new()
	stack.call("setup", item, max(1, int(data.get("amount", 1))), float(data.get("durability", -1.0)))
	return stack


func is_accessible(actor_inventory: Node = null) -> bool:
	if not locked:
		return true
	if required_key_id == &"":
		return false
	return actor_inventory != null and bool(actor_inventory.call("has_key", required_key_id))


func unlock_with(actor_inventory: Node) -> bool:
	if not locked:
		return true
	if actor_inventory == null or not bool(actor_inventory.call("has_key", required_key_id)):
		return false

	locked = false
	locked_changed.emit(locked)
	changed.emit()
	return true


func get_total_weight() -> float:
	var total := 0.0
	for stack in slots:
		if stack != null:
			total += stack.get_total_weight()
	return total


func get_used_slots() -> int:
	var count := 0
	for stack in slots:
		if stack != null and not stack.is_empty():
			count += 1
	return count


func has_item(item_id: StringName, amount := 1) -> bool:
	return get_item_amount(item_id) >= amount


func get_item_amount(item_id: StringName) -> int:
	var total := 0
	for stack in slots:
		if stack != null and stack.item != null and stack.item.id == item_id:
			total += stack.amount
	return total


func has_key(key_id: StringName) -> bool:
	if key_id == &"":
		return false

	for stack in slots:
		if stack == null or stack.item == null:
			continue
		if stack.item.is_key_for(key_id):
			return true
	return false


func can_add_item(item: Resource, amount := 1) -> bool:
	return get_addable_amount(item, amount) >= amount


func get_addable_amount(item: Resource, amount := 1) -> int:
	if item == null or amount <= 0:
		return 0

	var accepted := 0
	var simulated_weight := get_total_weight()
	var simulated_slots := get_used_slots()
	var stack_space := _get_existing_stack_space(item)

	for _index in range(amount):
		if max_weight_kg > 0.0 and simulated_weight + item.weight_kg > max_weight_kg:
			break

		if stack_space > 0:
			stack_space -= 1
		elif simulated_slots < capacity_slots:
			simulated_slots += 1
			stack_space = max(0, item.stack_limit - 1)
		else:
			break

		accepted += 1
		simulated_weight += item.weight_kg

	return accepted


func add_item(item: Resource, amount := 1, durability := -1.0) -> int:
	var to_add: int = get_addable_amount(item, amount)
	if to_add <= 0:
		return 0

	var remaining := to_add
	if item.can_stack():
		remaining = _add_to_existing_stacks(item, remaining)

	while remaining > 0 and get_used_slots() < capacity_slots:
		var stack_amount: int = min(remaining, max(1, item.stack_limit))
		var stack: Resource = ItemStackScript.new()
		stack.call("setup", item, stack_amount, durability)
		slots.append(stack)
		remaining -= stack_amount

	var added := to_add - remaining
	if added > 0:
		item_added.emit(item, added)
		changed.emit()
	return added


func remove_item(item_id: StringName, amount := 1) -> int:
	if amount <= 0:
		return 0

	var remaining := amount
	for index in range(slots.size() - 1, -1, -1):
		var stack := slots[index]
		if stack == null or stack.item == null or stack.item.id != item_id:
			continue

		var removed: int = min(stack.amount, remaining)
		stack.amount -= removed
		remaining -= removed

		if stack.amount <= 0:
			slots.remove_at(index)
		if remaining <= 0:
			break

	var removed_total := amount - remaining
	if removed_total > 0:
		item_removed.emit(item_id, removed_total)
		changed.emit()
	return removed_total


func transfer_to(target: Node, item_id: StringName, amount := 1) -> int:
	if target == null or amount <= 0:
		return 0

	var moved := 0
	for stack in slots.duplicate():
		if stack == null or stack.item == null or stack.item.id != item_id:
			continue

		var wanted := amount - moved
		var accepted: int = int(target.call("add_item", stack.item, min(stack.amount, wanted), stack.durability))
		if accepted <= 0:
			break

		remove_item(item_id, accepted)
		moved += accepted
		if moved >= amount:
			break

	return moved


func _add_to_existing_stacks(item: Resource, amount: int) -> int:
	var remaining := amount
	for stack in slots:
		if remaining <= 0:
			break
		if stack == null or not stack.can_stack_with(item):
			continue

		var added: int = min(stack.get_available_space(), remaining)
		stack.amount += added
		remaining -= added
	return remaining


func _get_existing_stack_space(item: Resource) -> int:
	if item == null or not item.can_stack():
		return 0

	var space := 0
	for stack in slots:
		if stack != null and stack.can_stack_with(item):
			space += stack.get_available_space()
	return space


func _trim_to_capacity() -> void:
	while slots.size() > capacity_slots:
		slots.pop_back()
