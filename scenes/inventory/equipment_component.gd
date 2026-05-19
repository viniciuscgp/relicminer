extends Node
class_name EquipmentComponent

const RIGHT_HAND := &"right_hand"
const LEFT_HAND := &"left_hand"
const PRIMARY := &"primary"
const SECONDARY := &"secondary"
const THROW := &"throw"

signal changed
signal equipped(slot: StringName, stack: Resource)
signal unequipped(slot: StringName, stack: Resource)
signal action_executed(slot: StringName, trigger: StringName, action: Resource)

@export var actor_path: NodePath = NodePath("..")
@export var inventory_path: NodePath = NodePath("../Inventory")
@export var inventory_dropper_path: NodePath = NodePath("../InventoryDropper")
@export var right_hand_socket_path: NodePath = NodePath("../EquipmentSockets/RightHandSocket")
@export var left_hand_socket_path: NodePath = NodePath("../EquipmentSockets/LeftHandSocket")
@export var aim_source_path: NodePath

@onready var actor: Node = get_node_or_null(actor_path)
@onready var inventory: Node = get_node_or_null(inventory_path)
@onready var inventory_dropper: Node = get_node_or_null(inventory_dropper_path)
@onready var right_hand_socket: Node3D = get_node_or_null(right_hand_socket_path) as Node3D
@onready var left_hand_socket: Node3D = get_node_or_null(left_hand_socket_path) as Node3D
@onready var aim_source: Node3D = get_node_or_null(aim_source_path) as Node3D

var _equipped_stacks := {
	RIGHT_HAND: null,
	LEFT_HAND: null,
}
var _held_instances := {
	RIGHT_HAND: null,
	LEFT_HAND: null,
}


func _ready() -> void:
	if inventory != null and inventory.has_signal("changed"):
		inventory.connect("changed", _validate_equipped_stacks)


func equip_stack(stack: Resource, slot: StringName = &"") -> bool:
	if stack == null or bool(stack.call("is_empty")):
		return false

	var item: Resource = stack.get("item")
	if item == null:
		return false

	var resolved_slot := _resolve_slot(item, slot)
	if not _equipped_stacks.has(resolved_slot):
		return false

	_clear_held_instance(resolved_slot)
	_equipped_stacks[resolved_slot] = stack
	_create_held_instance(resolved_slot, stack)
	equipped.emit(resolved_slot, stack)
	changed.emit()
	return true


func unequip(slot: StringName) -> bool:
	if not _equipped_stacks.has(slot):
		return false

	var stack: Resource = _equipped_stacks[slot]
	_clear_held_instance(slot)
	_equipped_stacks[slot] = null
	unequipped.emit(slot, stack)
	changed.emit()
	return true


func get_equipped_stack(slot: StringName) -> Resource:
	if not _equipped_stacks.has(slot):
		return null
	return _equipped_stacks[slot]


func get_equipped_item(slot: StringName) -> Resource:
	var stack := get_equipped_stack(slot)
	if stack == null or bool(stack.call("is_empty")):
		return null
	return stack.get("item") as Resource


func use_primary(slot: StringName = &"") -> bool:
	return use_action(_resolve_action_slot(slot), PRIMARY)


func use_secondary(slot: StringName = &"") -> bool:
	return use_action(_resolve_action_slot(slot), SECONDARY)


func throw_equipped(slot: StringName = &"") -> bool:
	return use_action(_resolve_action_slot(slot), THROW)


func use_action(slot: StringName, trigger: StringName) -> bool:
	var stack := get_equipped_stack(slot)
	if stack == null or bool(stack.call("is_empty")):
		return false

	var item: Resource = stack.get("item")
	if item == null or not item.has_method("get_action_for_trigger"):
		return false

	var action: Resource = item.call("get_action_for_trigger", trigger)
	if action == null or not action.has_method("execute"):
		return false

	var held_instance := _held_instances.get(slot) as Node3D
	if action.has_method("can_execute") and not bool(action.call("can_execute", actor, self, stack, slot, held_instance)):
		return false

	var executed := bool(action.call("execute", actor, self, stack, slot, held_instance))
	if executed:
		action_executed.emit(slot, trigger, action)
		_validate_equipped_stacks()
	return executed


func throw_equipped_item(slot: StringName, throw_speed := 9.0, upward_speed := 1.5) -> bool:
	var stack := get_equipped_stack(slot)
	if stack == null or bool(stack.call("is_empty")):
		return false

	var item: Resource = stack.get("item")
	if item == null or inventory_dropper == null or not inventory_dropper.has_method("throw_item"):
		return false

	var durability := float(stack.get("durability"))
	var thrown := bool(inventory_dropper.call("throw_item", item, 1, durability, get_aim_direction(), throw_speed, upward_speed))
	if thrown:
		_validate_equipped_stacks()
	return thrown


func consume_equipped_item(slot: StringName, amount := 1) -> bool:
	var stack := get_equipped_stack(slot)
	if stack == null or bool(stack.call("is_empty")):
		return false

	var item: Resource = stack.get("item")
	if item == null or inventory == null or not inventory.has_method("remove_item"):
		return false

	var removed := int(inventory.call("remove_item", item.get("id"), amount))
	if removed > 0:
		_validate_equipped_stacks()
	return removed > 0


func get_aim_origin() -> Vector3:
	if aim_source != null:
		return aim_source.global_position
	if actor is Node3D:
		return (actor as Node3D).global_position + Vector3.UP * 0.9
	return Vector3.ZERO


func get_aim_direction() -> Vector3:
	if aim_source != null:
		return -aim_source.global_transform.basis.z.normalized()
	if actor is Node3D:
		return -(actor as Node3D).global_transform.basis.z.normalized()
	return Vector3.FORWARD


func _resolve_slot(item: Resource, requested_slot: StringName) -> StringName:
	if requested_slot != &"":
		return requested_slot
	if item != null and item.has_method("get_default_equipment_slot"):
		return item.call("get_default_equipment_slot")
	return RIGHT_HAND


func _resolve_action_slot(requested_slot: StringName) -> StringName:
	if requested_slot != &"":
		return requested_slot
	if _has_equipped_stack(RIGHT_HAND):
		return RIGHT_HAND
	if _has_equipped_stack(LEFT_HAND):
		return LEFT_HAND
	return RIGHT_HAND


func _has_equipped_stack(slot: StringName) -> bool:
	var stack := get_equipped_stack(slot)
	return stack != null and not bool(stack.call("is_empty"))


func _get_socket(slot: StringName) -> Node3D:
	if slot == LEFT_HAND:
		return left_hand_socket
	return right_hand_socket


func _create_held_instance(slot: StringName, stack: Resource) -> void:
	var socket := _get_socket(slot)
	if socket == null:
		return

	var item: Resource = stack.get("item")
	if item == null or not item.has_method("create_held_instance"):
		return

	var held := item.call("create_held_instance", int(stack.get("amount")), float(stack.get("durability"))) as Node3D
	if held == null:
		return

	socket.add_child(held)
	_prepare_held_node(held)
	_apply_held_transform(held, item)
	_set_held_light_enabled(held, true)
	_held_instances[slot] = held


func _prepare_held_node(node: Node) -> void:
	if node is RigidBody3D:
		var body := node as RigidBody3D
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO

	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0

	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true

	if node is Area3D:
		var area := node as Area3D
		area.monitoring = false
		area.monitorable = false

	for child in node.get_children():
		_prepare_held_node(child)


func _apply_held_transform(held: Node3D, item: Resource) -> void:
	held.position = item.get("held_position")
	held.rotation_degrees = item.get("held_rotation_degrees")
	held.scale = item.get("held_scale")


func _clear_held_instance(slot: StringName) -> void:
	var held := _held_instances.get(slot) as Node
	if held != null and is_instance_valid(held):
		_set_held_light_enabled(held, false)
		held.queue_free()
	_held_instances[slot] = null


func _set_held_light_enabled(node: Node, enabled: bool) -> void:
	if node is Light3D:
		(node as Light3D).visible = enabled

	if node.name.to_lower().contains("flame"):
		if node is Node3D:
			(node as Node3D).visible = enabled
		elif node is CanvasItem:
			(node as CanvasItem).visible = enabled

	for child in node.get_children():
		_set_held_light_enabled(child, enabled)


func _validate_equipped_stacks() -> void:
	var changed_slots := false
	for slot in _equipped_stacks.keys():
		var stack: Resource = _equipped_stacks[slot]
		if stack == null:
			continue
		if bool(stack.call("is_empty")) or not _inventory_contains_stack(stack):
			_clear_held_instance(slot)
			_equipped_stacks[slot] = null
			changed_slots = true
	if changed_slots:
		changed.emit()


func _inventory_contains_stack(stack: Resource) -> bool:
	if inventory == null:
		return true

	var slots: Array = inventory.get("slots")
	return slots.has(stack)
