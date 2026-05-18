extends RigidBody3D
class_name ItemWorldBase

const MIN_PHYSICS_MASS := 0.1
const MAX_PHYSICS_MASS := 50.0
const MIN_SURFACE_FRICTION := 0.8
const MAX_SURFACE_FRICTION := 2.4
const MIN_LINEAR_DAMP := 0.15
const MAX_LINEAR_DAMP := 1.25
const MIN_ANGULAR_DAMP := 1.5
const MAX_ANGULAR_DAMP := 12.0

signal picked_up(actor_inventory: Node, amount: int)
signal pickup_failed(reason: String)

@export var item: Resource
@export_range(1, 999, 1, "or_greater") var amount := 1
@export var durability := -1.0
@export var remove_when_empty := true


func _ready() -> void:
	continuous_cd = true
	_apply_physics_from_item()


func setup(new_item: Resource, new_amount := 1, new_durability := -1.0) -> void:
	item = new_item
	amount = max(1, new_amount)
	durability = new_durability
	_apply_physics_from_item()


func get_display_name() -> String:
	if item == null:
		return "Item"

	if item.has_method("get_display_name"):
		return str(item.call("get_display_name"))

	var item_name := str(item.get("display_name"))
	if item_name.is_empty():
		return str(item.get("id"))
	return item_name


func try_pickup(actor_inventory: Node) -> int:
	if item == null:
		pickup_failed.emit(_text("message.item.no_definition"))
		return 0

	if actor_inventory == null or not actor_inventory.has_method("add_item"):
		pickup_failed.emit(_text("message.target.no_inventory"))
		return 0

	var added := int(actor_inventory.call("add_item", item, amount, durability))
	if added <= 0:
		pickup_failed.emit(_text("message.inventory.full"))
		return 0

	amount -= added
	picked_up.emit(actor_inventory, added)

	if amount <= 0 and remove_when_empty:
		queue_free()

	return added


func _apply_physics_from_item() -> void:
	if item == null:
		return

	var weight := float(item.get("weight_kg"))
	mass = clampf(weight, MIN_PHYSICS_MASS, MAX_PHYSICS_MASS)
	linear_damp = _map_weight_to_range(weight, MIN_LINEAR_DAMP, MAX_LINEAR_DAMP)
	angular_damp = _map_weight_to_range(weight, MAX_ANGULAR_DAMP, MIN_ANGULAR_DAMP)
	_apply_physics_material(_map_weight_to_range(weight, MAX_SURFACE_FRICTION, MIN_SURFACE_FRICTION))


func _apply_physics_material(friction: float) -> void:
	var material := PhysicsMaterial.new()
	material.friction = friction
	material.bounce = 0.0
	physics_material_override = material


func _map_weight_to_range(weight: float, light_value: float, heavy_value: float) -> float:
	var t := inverse_lerp(MIN_PHYSICS_MASS, 10.0, clampf(weight, MIN_PHYSICS_MASS, 10.0))
	return lerpf(light_value, heavy_value, t)


func _text(key: String) -> String:
	var localization := get_node_or_null("/root/LocalizationManager")
	if localization != null and localization.has_method("text"):
		return str(localization.call("text", key))
	return key
