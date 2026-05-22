extends Resource
class_name HeldItemTransformOverride

@export_group("Item Matching")
@export var item_id: StringName
@export var additional_item_ids: Array[StringName] = []

@export_group("Held Transform")
@export var position := Vector3.ZERO:
	set(value):
		position = value
		emit_changed()
@export var rotation_degrees := Vector3.ZERO:
	set(value):
		rotation_degrees = value
		emit_changed()
@export var scale := Vector3.ONE:
	set(value):
		scale = value
		emit_changed()

@export_group("Bone Pose Override")
@export var pose_enabled := false
@export var upperarm_bone_name: StringName
@export var upperarm_rotation_degrees := Vector3.ZERO
@export var forearm_bone_name: StringName
@export var forearm_rotation_degrees := Vector3.ZERO
@export var hand_bone_name: StringName
@export var hand_rotation_degrees := Vector3.ZERO


func matches_item(target_item_id: StringName) -> bool:
	if target_item_id == &"":
		return false
	if item_id == target_item_id:
		return true
	return additional_item_ids.has(target_item_id)
