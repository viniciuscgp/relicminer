extends "res://scripts/systems/items/actions/item_action.gd"
class_name ThrowItemAction

## Speed value used for throw.
@export var throw_speed := 9.0
## Speed value used for upward.
@export var upward_speed := 1.5


func _init() -> void:
	trigger = TRIGGER_THROW
	display_name = "Throw"


func execute(actor: Node, equipment: Node, stack: Resource, slot: StringName, _held_instance: Node3D) -> bool:
	if actor == null or equipment == null or stack == null or bool(stack.call("is_empty")):
		return false
	if not equipment.has_method("throw_equipped_item"):
		return false

	var direction := Vector3.ZERO
	if equipment.has_method("get_aim_direction"):
		direction = equipment.call("get_aim_direction")
	elif actor is Node3D:
		direction = -(actor as Node3D).global_transform.basis.z

	if direction.length_squared() < 0.001:
		return false
	direction = direction.normalized()

	if actor.has_method("play_action_animation"):
		actor.call("play_action_animation", &"throwing")

	return bool(equipment.call("throw_equipped_item", slot, throw_speed, upward_speed))
