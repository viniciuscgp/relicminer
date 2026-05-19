extends Node
class_name InventoryDropper

@export var inventory_path: NodePath = NodePath("../Inventory")
@export var drop_distance := 1.25
@export var drop_height := 0.75
@export var drop_up_speed := 0.12
@export var drop_light_forward_speed := 0.25
@export var drop_forward_speed := 0.75
@export var light_mass_threshold := 0.12

@onready var inventory: Node = get_node_or_null(inventory_path)

var _actor: Node3D


func _ready() -> void:
	_actor = get_parent() as Node3D


func drop_stack(stack: Resource, amount := 1) -> bool:
	if stack == null or bool(stack.call("is_empty")):
		return false

	var item: Resource = stack.get("item")
	if item == null:
		return false

	var durability := float(stack.get("durability"))
	return drop_item(item, amount, durability)


func drop_item(item: Resource, amount := 1, durability := -1.0) -> bool:
	return _drop_item_internal(item, amount, durability, Vector3.ZERO, false)


func throw_item(item: Resource, amount := 1, durability := -1.0, direction := Vector3.FORWARD, speed := 9.0, upward_speed := 1.5) -> bool:
	var throw_velocity := direction.normalized() * speed + Vector3.UP * upward_speed
	return _drop_item_internal(item, amount, durability, throw_velocity, true)


func _drop_item_internal(item: Resource, amount := 1, durability := -1.0, velocity_override := Vector3.ZERO, has_velocity_override := false) -> bool:
	if item == null or inventory == null or not inventory.has_method("remove_item"):
		return false
	if not item.has_method("create_world_instance"):
		return false

	var world_item := item.call("create_world_instance", amount, durability) as Node
	if world_item == null:
		return false

	var removed := int(inventory.call("remove_item", item.get("id"), amount))
	if removed <= 0:
		world_item.queue_free()
		return false

	if removed != amount and world_item.has_method("setup"):
		world_item.call("setup", item, removed, durability)

	_add_dropped_item_to_world(world_item, velocity_override, has_velocity_override)
	return true


func _add_dropped_item_to_world(world_item: Node, velocity_override := Vector3.ZERO, has_velocity_override := false) -> void:
	var parent := get_tree().current_scene
	if parent == null and _actor != null:
		parent = _actor.get_parent()
	if parent == null:
		add_child(world_item)
	else:
		parent.add_child(world_item)

	if not (world_item is Node3D):
		return

	var dropped := world_item as Node3D
	if _actor == null:
		dropped.global_position = Vector3.ZERO
		return

	var forward := -_actor.global_transform.basis.z.normalized()
	dropped.global_position = _actor.global_position + forward * drop_distance + Vector3.UP * drop_height
	if dropped is RigidBody3D:
		var body := dropped as RigidBody3D
		if has_velocity_override:
			body.linear_velocity = velocity_override
		else:
			var forward_speed := drop_forward_speed if body.mass > light_mass_threshold else drop_light_forward_speed
			body.linear_velocity = forward * forward_speed + Vector3.UP * drop_up_speed
		body.angular_velocity = Vector3.ZERO
