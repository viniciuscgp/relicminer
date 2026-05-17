extends Resource
class_name ItemStack

@export var item: Resource
@export_range(1, 999, 1, "or_greater") var amount := 1
@export var durability := -1.0


func setup(new_item: Resource, new_amount := 1, new_durability := -1.0) -> Resource:
	item = new_item
	amount = max(1, new_amount)
	durability = new_durability
	return self


func is_empty() -> bool:
	return item == null or amount <= 0


func get_total_weight() -> float:
	if item == null:
		return 0.0
	return item.weight_kg * amount


func get_stack_limit() -> int:
	if item == null:
		return 1
	return max(1, item.stack_limit)


func has_room() -> bool:
	return not is_empty() and amount < get_stack_limit()


func can_stack_with(other_item: Resource) -> bool:
	return item != null and other_item != null and item.id == other_item.id and item.can_stack()


func get_available_space() -> int:
	return max(0, get_stack_limit() - amount)


func has_durability() -> bool:
	return item != null and item.durability_max > 0.0


func get_durability() -> float:
	if durability >= 0.0:
		return durability
	if has_durability():
		return item.durability_max
	return 0.0
