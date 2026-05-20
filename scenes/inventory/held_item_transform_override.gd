extends Resource
class_name HeldItemTransformOverride

@export var item_id: StringName
@export var position := Vector3.ZERO
@export var rotation_degrees := Vector3.ZERO
@export var scale := Vector3.ONE

@export_group("Bone Pose Override")
@export var pose_enabled := false
@export var upperarm_bone_name: StringName
@export var upperarm_rotation_degrees := Vector3.ZERO
@export var forearm_bone_name: StringName
@export var forearm_rotation_degrees := Vector3.ZERO
@export var hand_bone_name: StringName
@export var hand_rotation_degrees := Vector3.ZERO
