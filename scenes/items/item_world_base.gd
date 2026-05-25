extends RigidBody3D
class_name ItemWorldBase

const InventoryComponentScene := preload("res://scenes/inventory/inventory_component.tscn")

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
signal opened(actor_inventory: Node, container_inventory: Node)
signal open_failed(reason: String)

## Item resource represented by this stack or world object.
@export var item: Resource
## Number of item units represented by this stack or world object.
@export_range(1, 999, 1, "or_greater") var amount := 1
## Current durability value; negative values use the item default.
@export var durability := -1.0
## Controls whether remove when empty is enabled.
@export var remove_when_empty := true

@export_group("Physics")
## Configures default mass kg in the Physics settings.
@export_range(0.1, 500.0, 0.1, "or_greater") var default_mass_kg := 1.0
## Controls whether contents affect mass is enabled in the Physics settings.
@export var contents_affect_mass := true

@export_group("Inventory")
## Controls whether this object has inventory in the Inventory settings.
@export var has_inventory := false
## NodePath used to locate the inventory node in the Inventory settings.
@export var inventory_path: NodePath = NodePath("InventoryComponent")
## Name used for inventory display in the Inventory settings.
@export var inventory_display_name := ""
## Configures capacity slots in the Inventory settings.
@export_range(1, 200, 1, "or_greater") var capacity_slots := 8
## Weight value used for max weight kg in the Inventory settings.
@export_range(0.0, 1000.0, 0.01, "or_greater") var max_weight_kg := 0.0
## Controls whether locked is enabled in the Inventory settings.
@export var locked := false
## ID used to match or reference required key in the Inventory settings.
@export var required_key_id: StringName
## Configures starting items in the Inventory settings.
@export var starting_items: Array[Resource] = []

@onready var inventory: Node = get_node_or_null(inventory_path)

var is_open := false


func _ready() -> void:
	continuous_cd = true
	_ensure_inventory()
	_apply_inventory_exports()
	_apply_physics_from_item()
	if inventory != null and inventory.has_signal("changed"):
		inventory.connect("changed", _apply_physics_from_item)


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
	if has_inventory and inventory != null and inventory.has_method("get_used_slots") and int(inventory.call("get_used_slots")) > 0:
		pickup_failed.emit(_text("message.inventory.cannot_pickup_non_empty_container"))
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
		_queue_free_persistently()

	return added


func has_container_inventory() -> bool:
	return has_inventory and inventory != null


func get_inventory() -> Node:
	return inventory


func get_base_weight_kg() -> float:
	if item != null:
		return float(item.get("weight_kg"))
	return default_mass_kg


func get_contents_weight_kg() -> float:
	if not has_container_inventory() or not inventory.has_method("get_total_weight"):
		return 0.0
	return float(inventory.call("get_total_weight"))


func get_total_weight() -> float:
	return get_base_weight_kg() + get_contents_weight_kg()


func can_open(actor_inventory: Node = null) -> bool:
	if not has_container_inventory():
		return false
	if inventory == null or not inventory.has_method("is_accessible"):
		return false
	return bool(inventory.call("is_accessible", actor_inventory))


func open(actor_inventory: Node = null) -> bool:
	if not has_container_inventory():
		return false
	if inventory == null:
		open_failed.emit(_text("message.container.no_inventory"))
		return false

	if inventory.has_method("unlock_with") and not bool(inventory.call("unlock_with", actor_inventory)):
		open_failed.emit(_text("message.locked"))
		return false

	set_open(true)
	opened.emit(actor_inventory, inventory)
	return true


func close() -> void:
	set_open(false)


func set_open(opened: bool) -> void:
	is_open = opened


func get_save_data() -> Dictionary:
	var data := {
		"item_path": item.resource_path if item != null else "",
		"item_id": String(item.get("id")) if item != null else "",
		"amount": amount,
		"durability": durability,
		"remove_when_empty": remove_when_empty,
		"has_inventory": has_inventory,
		"is_open": is_open,
		"transform": _transform_to_save_data(global_transform),
		"linear_velocity": _vector3_to_save_data(linear_velocity),
		"angular_velocity": _vector3_to_save_data(angular_velocity),
		"sleeping": sleeping,
		"freeze": freeze,
	}
	if has_container_inventory() and inventory.has_method("get_save_data"):
		data["inventory"] = inventory.call("get_save_data")
	return data


func apply_save_data(data: Dictionary) -> void:
	var item_path := str(data.get("item_path", ""))
	if not item_path.is_empty():
		var saved_item := load(item_path) as Resource
		if saved_item != null:
			item = saved_item
		else:
			push_warning("ItemWorldBase: could not load saved item '%s'." % item_path)

	amount = max(1, int(data.get("amount", amount)))
	durability = float(data.get("durability", durability))
	remove_when_empty = bool(data.get("remove_when_empty", remove_when_empty))
	has_inventory = bool(data.get("has_inventory", has_inventory))
	is_open = bool(data.get("is_open", is_open))

	_ensure_inventory()
	_apply_inventory_exports()
	var inventory_data: Dictionary = data.get("inventory", {})
	if has_container_inventory() and inventory.has_method("apply_save_data"):
		inventory.call("apply_save_data", inventory_data)

	if data.has("transform"):
		global_transform = _transform_from_save_data(data["transform"], global_transform)
	linear_velocity = _vector3_from_save_data(data.get("linear_velocity", []), linear_velocity)
	angular_velocity = _vector3_from_save_data(data.get("angular_velocity", []), angular_velocity)
	sleeping = bool(data.get("sleeping", sleeping))
	freeze = bool(data.get("freeze", freeze))
	_apply_physics_from_item()


func get_spawn_scene_path() -> String:
	if not scene_file_path.is_empty():
		return scene_file_path
	if item != null:
		var world_scene: PackedScene = item.get("world_scene")
		if world_scene != null:
			return world_scene.resource_path
	return ""


func _ensure_inventory() -> void:
	if not has_inventory or inventory != null:
		return

	var inventory_instance := InventoryComponentScene.instantiate()
	inventory_instance.name = _get_inventory_node_name()
	add_child(inventory_instance)
	inventory = inventory_instance


func _get_inventory_node_name() -> String:
	var path := str(inventory_path)
	if path.is_empty() or path == ".":
		return "InventoryComponent"
	return path.get_file()


func _apply_inventory_exports() -> void:
	if not has_inventory or inventory == null:
		return

	var resolved_display_name := inventory_display_name
	if resolved_display_name.is_empty():
		resolved_display_name = get_display_name()

	inventory.set("display_name", resolved_display_name)
	inventory.set("capacity_slots", capacity_slots)
	inventory.set("max_weight_kg", max_weight_kg)
	inventory.set("locked", locked)
	inventory.set("required_key_id", required_key_id)
	inventory.set("starting_items", starting_items)
	if inventory.has_method("_load_starting_items"):
		inventory.call("_load_starting_items")


func _apply_physics_from_item() -> void:
	var weight := get_base_weight_kg()
	if contents_affect_mass:
		weight += get_contents_weight_kg()

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


func _queue_free_persistently() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("mark_scene_node_removed"):
		save_manager.call("mark_scene_node_removed", self)
	queue_free()


func _transform_to_save_data(value: Transform3D) -> Dictionary:
	return {
		"origin": _vector3_to_save_data(value.origin),
		"basis_x": _vector3_to_save_data(value.basis.x),
		"basis_y": _vector3_to_save_data(value.basis.y),
		"basis_z": _vector3_to_save_data(value.basis.z),
	}


func _transform_from_save_data(data: Variant, fallback: Transform3D) -> Transform3D:
	if not data is Dictionary:
		return fallback
	var dict := data as Dictionary
	return Transform3D(
		Basis(
			_vector3_from_save_data(dict.get("basis_x", []), fallback.basis.x),
			_vector3_from_save_data(dict.get("basis_y", []), fallback.basis.y),
			_vector3_from_save_data(dict.get("basis_z", []), fallback.basis.z)
		),
		_vector3_from_save_data(dict.get("origin", []), fallback.origin)
	)


func _vector3_to_save_data(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _vector3_from_save_data(data: Variant, fallback: Vector3) -> Vector3:
	if not data is Array:
		return fallback
	var values := data as Array
	if values.size() < 3:
		return fallback
	return Vector3(float(values[0]), float(values[1]), float(values[2]))
