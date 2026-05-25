@tool
extends Resource
class_name HeldItemTransformOverride

const LIVE_PREVIEW_PATH := "user://held_transform_override_preview.json"

@export_group("Item Matching")
## ID used to match or reference item in the Item Matching settings.
@export var item_id: StringName:
	set(value):
		item_id = value
		_notify_override_changed()
## Additional IDs accepted for additional item matching in the Item Matching settings.
@export var additional_item_ids: Array[StringName] = []:
	set(value):
		additional_item_ids = value
		_notify_override_changed()

@export_group("Held Transform")
## Configures position in the Held Transform settings.
@export var position := Vector3.ZERO:
	set(value):
		position = value
		_notify_override_changed()
## Configures rotation degrees in the Held Transform settings.
@export var rotation_degrees := Vector3.ZERO:
	set(value):
		rotation_degrees = value
		_notify_override_changed()
## Configures scale in the Held Transform settings.
@export var scale := Vector3.ONE:
	set(value):
		scale = value
		_notify_override_changed()

@export_group("Bone Pose Override")
## Enables pose in the Bone Pose Override settings.
@export var pose_enabled := false:
	set(value):
		pose_enabled = value
		_notify_override_changed()
## Name used for upperarm bone in the Bone Pose Override settings.
@export var upperarm_bone_name: StringName:
	set(value):
		upperarm_bone_name = value
		_notify_override_changed()
## Configures upperarm rotation degrees in the Bone Pose Override settings.
@export var upperarm_rotation_degrees := Vector3.ZERO:
	set(value):
		upperarm_rotation_degrees = value
		_notify_override_changed()
## Name used for forearm bone in the Bone Pose Override settings.
@export var forearm_bone_name: StringName:
	set(value):
		forearm_bone_name = value
		_notify_override_changed()
## Configures forearm rotation degrees in the Bone Pose Override settings.
@export var forearm_rotation_degrees := Vector3.ZERO:
	set(value):
		forearm_rotation_degrees = value
		_notify_override_changed()
## Name used for hand bone in the Bone Pose Override settings.
@export var hand_bone_name: StringName:
	set(value):
		hand_bone_name = value
		_notify_override_changed()
## Configures hand rotation degrees in the Bone Pose Override settings.
@export var hand_rotation_degrees := Vector3.ZERO:
	set(value):
		hand_rotation_degrees = value
		_notify_override_changed()


func matches_item(target_item_id: StringName) -> bool:
	if target_item_id == &"":
		return false
	if item_id == target_item_id:
		return true
	return additional_item_ids.has(target_item_id)


func _notify_override_changed() -> void:
	emit_changed()
	if Engine.is_editor_hint():
		_write_live_preview()


func _write_live_preview() -> void:
	if item_id == &"":
		return

	var preview_data := _load_live_preview_data()
	var override_data := _to_live_preview_data()
	preview_data[String(item_id)] = override_data
	for additional_item_id in additional_item_ids:
		if additional_item_id != &"":
			preview_data[String(additional_item_id)] = override_data

	var file := FileAccess.open(LIVE_PREVIEW_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(preview_data, "\t"))


func _load_live_preview_data() -> Dictionary:
	if not FileAccess.file_exists(LIVE_PREVIEW_PATH):
		return {}

	var file := FileAccess.open(LIVE_PREVIEW_PATH, FileAccess.READ)
	if file == null:
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _to_live_preview_data() -> Dictionary:
	return {
		"item_id": String(item_id),
		"additional_item_ids": _string_name_array_to_string_array(additional_item_ids),
		"position": _vector3_to_array(position),
		"rotation_degrees": _vector3_to_array(rotation_degrees),
		"scale": _vector3_to_array(scale),
		"pose_enabled": pose_enabled,
		"upperarm_bone_name": String(upperarm_bone_name),
		"upperarm_rotation_degrees": _vector3_to_array(upperarm_rotation_degrees),
		"forearm_bone_name": String(forearm_bone_name),
		"forearm_rotation_degrees": _vector3_to_array(forearm_rotation_degrees),
		"hand_bone_name": String(hand_bone_name),
		"hand_rotation_degrees": _vector3_to_array(hand_rotation_degrees),
	}


func _vector3_to_array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _string_name_array_to_string_array(values: Array[StringName]) -> Array:
	var result: Array = []
	for value in values:
		result.append(String(value))
	return result
