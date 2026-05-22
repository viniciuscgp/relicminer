@tool
extends Node
class_name CharacterAnimationController

const WALKING := &"walking"
const RUNNING := &"running"
const JUMPING := &"jumping"
const SWIMING := &"swiming"
const PICKING := &"picking"
const SWIMMING_IDLW := &"swimming_idlw"
const SWORD_SLASH_VERTICAL := &"sword_slash_vertical"
const SWORD_ATTACK := &"sword_attack"
const STAFF_ATTACK := &"staff_attack"
const THROWING := &"throwing"
const MINING := &"mining"
const CHOPPING := &"chopping"
const IDLE := &"idle"

const REQUIRED_ANIMATIONS: Array[StringName] = [
	IDLE,
	WALKING,
	RUNNING,
	JUMPING,
	SWIMING,
	PICKING,
	SWIMMING_IDLW,
	SWORD_SLASH_VERTICAL,
	SWORD_ATTACK,
	STAFF_ATTACK,
	THROWING,
	MINING,
	CHOPPING,
]

const ACTION_ALIASES := {
	&"slash": SWORD_ATTACK,
	&"thrust": SWORD_SLASH_VERTICAL,
	&"swimming": SWIMING,
	&"swimming_idle": SWIMMING_IDLW,
}

const ANIMATION_MAP_PROPERTY_PREFIX := "animation_map/"
const MALE_ANIMATION_MAP_PROPERTY_PREFIX := "male_animation_map/"
const FEMALE_ANIMATION_MAP_PROPERTY_PREFIX := "female_animation_map/"
const MALE_CHARACTER_MODEL := &"Male"
const FEMALE_CHARACTER_MODEL := &"Female"
const CHARACTER_MODELS: Array[StringName] = [MALE_CHARACTER_MODEL, FEMALE_CHARACTER_MODEL]
const LEFT_HAND_SLOT := &"left_hand"

@export var model_root_path: NodePath = NodePath("../visual/PlayerAnimation"):
	set(value):
		model_root_path = value
		_refresh_animation_player()
		_notify_animation_map_changed()
@export var animation_player_path: NodePath:
	set(value):
		animation_player_path = value
		_refresh_animation_player()
		_notify_animation_map_changed()
@export var default_blend_time := 0.12
@export var action_lock_seconds := 0.45
@export var warn_missing_mapped_animations := true
@export_range(0.05, 1.0, 0.05) var underwater_drift_animation_speed := 0.25
@export_group("Locomotion Speed Matching")
## When enabled, walk/run animation speed is scaled from the character's real horizontal movement speed.
@export var match_locomotion_animation_to_ground_speed := true
## Real-world ground speed, in meters per second, that matches the imported walk cycle at 1.0x playback.
@export_range(0.1, 20.0, 0.1, "or_greater") var walk_animation_reference_speed := 3.0
## Real-world ground speed, in meters per second, that matches the imported run cycle at 1.0x playback.
@export_range(0.1, 20.0, 0.1, "or_greater") var run_animation_reference_speed := 8.0
## Lowest playback speed scale allowed after matching locomotion to ground speed.
@export_range(0.05, 10.0, 0.05, "or_greater") var min_locomotion_animation_speed_scale := 0.25
## Highest playback speed scale allowed after matching locomotion to ground speed.
@export_range(0.05, 10.0, 0.05, "or_greater") var max_locomotion_animation_speed_scale := 3.0
@export_group("Swimming Idle Rotation Override")
## When enabled, applies an extra local rotation to the active Male/Female model while swimming_idlw is playing.
@export var swimming_idle_rotation_override_enabled := false
## Extra local Euler rotation in degrees applied only during swimming_idlw. Use this when swimming_idlw reuses swiming but needs a different axis.
@export var swimming_idle_rotation_degrees := Vector3.ZERO
@export_group("Procedural Jump Fallback")
## When enabled, a simple bone pose is applied while jumping if the mapped jump animation is missing.
@export var procedural_jump_fallback_enabled := true
## Standard animation played under the procedural pose. Usually idle works best for a simple airborne pose.
@export var procedural_jump_base_animation: StringName = IDLE
## Spine bone used to lean the body during the procedural jump fallback.
@export var jump_fallback_spine_bone_name: StringName = &"Spine02"
@export var jump_fallback_spine_rotation_degrees := Vector3(-4.0, 0.0, 0.0)
## Shoulder bones used to open the arms during the procedural jump fallback.
@export var jump_fallback_left_clavicle_bone_name: StringName = &"L_Clavicle"
@export var jump_fallback_left_clavicle_rotation_degrees := Vector3(0.0, 0.0, 2.0)
@export var jump_fallback_right_clavicle_bone_name: StringName = &"R_Clavicle"
@export var jump_fallback_right_clavicle_rotation_degrees := Vector3(0.0, 0.0, -2.0)
## Arm bones used to create the simple airborne pose.
@export var jump_fallback_left_upperarm_bone_name: StringName = &"L_Upperarm"
@export var jump_fallback_left_upperarm_rotation_degrees := Vector3(0.0, 0.0, 8.0)
@export var jump_fallback_right_upperarm_bone_name: StringName = &"R_Upperarm"
@export var jump_fallback_right_upperarm_rotation_degrees := Vector3(0.0, 0.0, -8.0)
@export var jump_fallback_left_forearm_bone_name: StringName = &"L_Forearm"
@export var jump_fallback_left_forearm_rotation_degrees := Vector3(0.0, 0.0, 18.0)
@export var jump_fallback_right_forearm_bone_name: StringName = &"R_Forearm"
@export var jump_fallback_right_forearm_rotation_degrees := Vector3(0.0, 0.0, -18.0)
## Leg bones used to bend the legs during the procedural jump fallback.
@export var jump_fallback_left_thigh_bone_name: StringName = &"L_Thigh"
@export var jump_fallback_left_thigh_rotation_degrees := Vector3(7.0, 0.0, 2.0)
@export var jump_fallback_right_thigh_bone_name: StringName = &"R_Thigh"
@export var jump_fallback_right_thigh_rotation_degrees := Vector3(-7.0, 0.0, -2.0)
@export var jump_fallback_left_calf_bone_name: StringName = &"L_Calf"
@export var jump_fallback_left_calf_rotation_degrees := Vector3(-28.0, 0.0, 0.0)
@export var jump_fallback_right_calf_bone_name: StringName = &"R_Calf"
@export var jump_fallback_right_calf_rotation_degrees := Vector3(-28.0, 0.0, 0.0)
@export var jump_fallback_left_foot_bone_name: StringName = &"L_Foot"
@export var jump_fallback_left_foot_rotation_degrees := Vector3(8.0, 0.0, 0.0)
@export var jump_fallback_right_foot_bone_name: StringName = &"R_Foot"
@export var jump_fallback_right_foot_rotation_degrees := Vector3(8.0, 0.0, 0.0)
@export_group("Held Pose Override")
@export var equipment_path: NodePath = NodePath("../Equipment")
@export var skeleton_path: NodePath = NodePath("../visual/PlayerAnimation/Armature/Skeleton3D")

var animation_map: Dictionary = {
	WALKING: WALKING,
	RUNNING: RUNNING,
	JUMPING: JUMPING,
	SWIMING: SWIMING,
	PICKING: PICKING,
	SWIMMING_IDLW: SWIMMING_IDLW,
	SWORD_SLASH_VERTICAL: SWORD_SLASH_VERTICAL,
	SWORD_ATTACK: SWORD_ATTACK,
	STAFF_ATTACK: STAFF_ATTACK,
	THROWING: THROWING,
	MINING: MINING,
	CHOPPING: CHOPPING,
	IDLE: IDLE,
}

var character_animation_maps: Dictionary = {
	MALE_CHARACTER_MODEL: {},
	FEMALE_CHARACTER_MODEL: {},
}

var _animation_player: AnimationPlayer
var _equipment: Node
var _connected_equipment: Node
var _skeleton: Skeleton3D
var _current_standard_animation: StringName = &""
var _current_animation_speed := 1.0
var _action_locked_until_msec := 0
var _active_pose_override: Resource
var _procedural_jump_pose_active := false
var _procedural_jump_base_rotations := {}
var _swimming_idle_rotation_target: Node3D
var _swimming_idle_rotation_base_transform := Transform3D.IDENTITY
var _swimming_idle_rotation_active := false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_refresh_animation_player()
		_notify_animation_map_changed()


func _ready() -> void:
	process_priority = 1000
	process_physics_priority = 1000
	_refresh_animation_player()
	_refresh_held_pose_links()
	if Engine.is_editor_hint():
		_notify_animation_map_changed()

	if not Engine.is_editor_hint() and warn_missing_mapped_animations:
		_warn_missing_mapped_animations()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_apply_procedural_jump_pose()
		_apply_swimming_idle_rotation_override()
		_apply_held_pose_override()


func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_apply_procedural_jump_pose()
		_apply_swimming_idle_rotation_override()
		_apply_held_pose_override()


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var animation_hint := _get_animation_hint_string()
	properties.append({
		"name": "Default Animation Map",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
		"hint_string": ANIMATION_MAP_PROPERTY_PREFIX,
	})

	_append_animation_map_properties(properties, ANIMATION_MAP_PROPERTY_PREFIX, animation_hint)

	properties.append({
		"name": "Male Animation Map",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
		"hint_string": MALE_ANIMATION_MAP_PROPERTY_PREFIX,
	})
	_append_animation_map_properties(properties, MALE_ANIMATION_MAP_PROPERTY_PREFIX, animation_hint)

	properties.append({
		"name": "Female Animation Map",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
		"hint_string": FEMALE_ANIMATION_MAP_PROPERTY_PREFIX,
	})
	_append_animation_map_properties(properties, FEMALE_ANIMATION_MAP_PROPERTY_PREFIX, animation_hint)

	return properties


func _get(property: StringName) -> Variant:
	var property_name := String(property)
	var map_info := _get_animation_map_property_info(property_name)
	if map_info.is_empty():
		return null

	var standard_animation: StringName = map_info["standard_animation"]
	var character_model: StringName = map_info["character_model"]
	if character_model != &"":
		var mapped: Variant = _get_character_animation_map_value(character_model, standard_animation)
		if mapped != null:
			return mapped
		return _get_default_animation_map_value(standard_animation)
	return _get_default_animation_map_value(standard_animation)


func _set(property: StringName, value: Variant) -> bool:
	var property_name := String(property)
	var map_info := _get_animation_map_property_info(property_name)
	if map_info.is_empty():
		return false

	var standard_animation: StringName = map_info["standard_animation"]
	var character_model: StringName = map_info["character_model"]
	if character_model != &"":
		_set_character_animation_map_value(character_model, standard_animation, StringName(str(value)))
	else:
		animation_map[standard_animation] = StringName(str(value))
	return true


func _append_animation_map_properties(properties: Array[Dictionary], prefix: String, animation_hint: String) -> void:
	for standard_animation in REQUIRED_ANIMATIONS:
		properties.append({
			"name": "%s%s" % [prefix, standard_animation],
			"type": TYPE_STRING_NAME,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": animation_hint,
			"usage": PROPERTY_USAGE_DEFAULT,
		})


func _get_animation_map_property_info(property_name: String) -> Dictionary:
	if property_name.begins_with(ANIMATION_MAP_PROPERTY_PREFIX):
		return {
			"character_model": &"",
			"standard_animation": StringName(property_name.trim_prefix(ANIMATION_MAP_PROPERTY_PREFIX)),
		}
	if property_name.begins_with(MALE_ANIMATION_MAP_PROPERTY_PREFIX):
		return {
			"character_model": MALE_CHARACTER_MODEL,
			"standard_animation": StringName(property_name.trim_prefix(MALE_ANIMATION_MAP_PROPERTY_PREFIX)),
		}
	if property_name.begins_with(FEMALE_ANIMATION_MAP_PROPERTY_PREFIX):
		return {
			"character_model": FEMALE_CHARACTER_MODEL,
			"standard_animation": StringName(property_name.trim_prefix(FEMALE_ANIMATION_MAP_PROPERTY_PREFIX)),
		}
	return {}


func _get_default_animation_map_value(standard_animation: StringName) -> StringName:
	var normalized := _normalize_standard_name(standard_animation)
	var mapped: Variant = animation_map.get(normalized, normalized)
	if mapped == null:
		return &""
	return StringName(str(mapped))


func _get_character_animation_map_value(character_model: StringName, standard_animation: StringName) -> Variant:
	if not CHARACTER_MODELS.has(character_model):
		return null

	var normalized := _normalize_standard_name(standard_animation)
	var character_map := _get_character_animation_map(character_model)
	if not character_map.has(normalized):
		return null

	var mapped: Variant = character_map.get(normalized)
	if mapped == null or str(mapped).is_empty():
		return null
	return StringName(str(mapped))


func _set_character_animation_map_value(character_model: StringName, standard_animation: StringName, animation_name: StringName) -> void:
	if not CHARACTER_MODELS.has(character_model):
		return
	var character_map := _get_character_animation_map(character_model)
	character_map[_normalize_standard_name(standard_animation)] = animation_name
	character_animation_maps[character_model] = character_map


func _get_character_animation_map(character_model: StringName) -> Dictionary:
	var map_value: Variant = character_animation_maps.get(character_model, {})
	if map_value is Dictionary:
		return map_value
	return {}


func _get_active_character_model() -> StringName:
	var model_root := get_node_or_null(model_root_path)
	if not Engine.is_editor_hint() and model_root != null and model_root.has_method("get_selected_character_model"):
		var character_model := StringName(str(model_root.call("get_selected_character_model")))
		if CHARACTER_MODELS.has(character_model):
			return character_model
	return &""


func _refresh_animation_player() -> void:
	_animation_player = null
	var model_root := get_node_or_null(model_root_path)
	if model_root == null:
		model_root = get_parent()
	if not Engine.is_editor_hint() and model_root != null and model_root.has_method("get_active_animation_player"):
		_animation_player = model_root.call("get_active_animation_player") as AnimationPlayer
	if _animation_player == null:
		_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player == null and model_root != null:
		_animation_player = _find_animation_player(model_root)


func _refresh_held_pose_links() -> void:
	_set_held_pose_equipment(get_node_or_null(equipment_path))
	_skeleton = null
	var model_root := get_node_or_null(model_root_path)
	if model_root == null:
		model_root = get_parent()
	if not Engine.is_editor_hint() and model_root != null and model_root.has_method("get_active_skeleton"):
		_skeleton = model_root.call("get_active_skeleton") as Skeleton3D
	if _skeleton == null:
		_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null and model_root != null:
		_skeleton = _find_skeleton(model_root)


func _set_held_pose_equipment(equipment: Node) -> void:
	if _connected_equipment == equipment:
		_equipment = equipment
		return

	if _connected_equipment != null and is_instance_valid(_connected_equipment) and _connected_equipment.has_signal("changed"):
		if _connected_equipment.changed.is_connected(_on_equipment_changed):
			_connected_equipment.changed.disconnect(_on_equipment_changed)

	_equipment = equipment
	_connected_equipment = equipment
	if _connected_equipment != null and _connected_equipment.has_signal("changed"):
		if not _connected_equipment.changed.is_connected(_on_equipment_changed):
			_connected_equipment.changed.connect(_on_equipment_changed)


func _on_equipment_changed() -> void:
	_apply_held_pose_override()


func get_required_animations() -> Array[StringName]:
	return REQUIRED_ANIMATIONS.duplicate()


func resolve_animation_name(standard_animation: StringName) -> StringName:
	var normalized: StringName = _normalize_standard_name(standard_animation)
	var character_model := _get_active_character_model()
	var mapped: Variant = _get_character_animation_map_value(character_model, normalized)
	if mapped == null:
		mapped = _get_default_animation_map_value(normalized)
	return StringName(str(mapped))


func has_standard_animation(standard_animation: StringName) -> bool:
	var resolved := resolve_animation_name(standard_animation)
	return _has_animation(resolved)


func play_standard_animation(standard_animation: StringName, blend_time := -1.0, custom_speed := 1.0, lock_action := false, force_restart := false) -> bool:
	if _animation_player == null:
		return false

	var normalized := _normalize_standard_name(standard_animation)
	var resolved := resolve_animation_name(normalized)
	if not _has_animation(resolved):
		resolved = _get_first_available_animation()
		if resolved == &"":
			return false

	if not force_restart and _current_standard_animation == normalized and _animation_player.is_playing():
		if signf(_current_animation_speed) == signf(custom_speed):
			_set_animation_speed(custom_speed)
			return true

	var blend := default_blend_time if blend_time < 0.0 else blend_time
	_set_animation_speed(custom_speed)
	_animation_player.play(resolved, blend, -1.0 if custom_speed < 0.0 else 1.0, custom_speed < 0.0)
	_current_standard_animation = normalized

	if lock_action:
		var duration := action_lock_seconds
		if _animation_player.current_animation_length > 0.0:
			duration = minf(_animation_player.current_animation_length, maxf(action_lock_seconds, 0.0))
		_action_locked_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)

	return true


func _set_animation_speed(custom_speed: float) -> void:
	if _animation_player == null:
		return
	if is_equal_approx(custom_speed, 0.0):
		custom_speed = 1.0
	if is_equal_approx(_current_animation_speed, custom_speed) and is_equal_approx(_animation_player.speed_scale, absf(custom_speed)):
		return
	_animation_player.speed_scale = absf(custom_speed)
	_current_animation_speed = custom_speed


func play_action_animation(standard_animation: StringName) -> bool:
	return play_standard_animation(standard_animation, default_blend_time, 1.0, true, true)


func set_locomotion_state(moving: bool, running: bool, jumping: bool, swimming: bool, backward := false, swim_drift := false, ground_speed := -1.0) -> void:
	if Time.get_ticks_msec() < _action_locked_until_msec:
		if not jumping:
			_clear_procedural_jump_pose()
			_clear_swimming_idle_rotation_override()
		return

	if jumping:
		_clear_swimming_idle_rotation_override()
		if has_standard_animation(JUMPING):
			_clear_procedural_jump_pose()
			play_standard_animation(JUMPING)
		else:
			_play_procedural_jump_fallback()
		return

	_clear_procedural_jump_pose()

	if swimming:
		if swim_drift:
			_clear_swimming_idle_rotation_override()
			play_standard_animation(SWIMING, default_blend_time, underwater_drift_animation_speed)
			return
		play_standard_animation(SWIMING if moving else SWIMMING_IDLW)
		if moving:
			_clear_swimming_idle_rotation_override()
		else:
			_apply_swimming_idle_rotation_override()
		return

	_clear_swimming_idle_rotation_override()

	if moving:
		var locomotion_animation := RUNNING if running else WALKING
		var locomotion_speed := _get_locomotion_animation_speed(locomotion_animation, ground_speed)
		if backward:
			play_standard_animation(WALKING, default_blend_time, -locomotion_speed)
			return
		play_standard_animation(locomotion_animation, default_blend_time, locomotion_speed)
		return

	play_standard_animation(IDLE)


func _get_locomotion_animation_speed(standard_animation: StringName, ground_speed: float) -> float:
	if not match_locomotion_animation_to_ground_speed or ground_speed < 0.0:
		return 1.0

	var reference_speed := run_animation_reference_speed if standard_animation == RUNNING else walk_animation_reference_speed
	if reference_speed <= 0.0:
		return 1.0

	var min_scale := minf(min_locomotion_animation_speed_scale, max_locomotion_animation_speed_scale)
	var max_scale := maxf(min_locomotion_animation_speed_scale, max_locomotion_animation_speed_scale)
	return clampf(maxf(ground_speed, 0.0) / reference_speed, min_scale, max_scale)


func _play_procedural_jump_fallback() -> void:
	if not procedural_jump_fallback_enabled:
		_clear_procedural_jump_pose()
		play_standard_animation(IDLE)
		return

	if _skeleton == null:
		_refresh_held_pose_links()

	if _skeleton == null:
		_clear_procedural_jump_pose()
		play_standard_animation(IDLE)
		return

	play_standard_animation(procedural_jump_base_animation)
	if not _procedural_jump_pose_active:
		_capture_procedural_jump_base_rotations()
	_procedural_jump_pose_active = true
	_apply_procedural_jump_pose()


func _apply_procedural_jump_pose() -> void:
	if not _procedural_jump_pose_active:
		return
	if _skeleton == null:
		_refresh_held_pose_links()
	if _skeleton == null:
		_procedural_jump_pose_active = false
		return

	for pose_entry in _get_procedural_jump_pose_entries():
		_set_bone_pose_rotation_with_saved_base(pose_entry["bone_name"], pose_entry["rotation_degrees"])

	if _skeleton.has_method("force_update_all_bone_transforms"):
		_skeleton.call("force_update_all_bone_transforms")


func _clear_procedural_jump_pose() -> void:
	if not _procedural_jump_pose_active or _skeleton == null:
		_procedural_jump_pose_active = false
		return

	for pose_entry in _get_procedural_jump_pose_entries():
		var bone_name: StringName = pose_entry["bone_name"]
		var bone_index := _get_bone_index(bone_name)
		if bone_index == -1:
			continue
		var base_rotation: Variant = _procedural_jump_base_rotations.get(bone_name)
		if base_rotation is Quaternion:
			_skeleton.set_bone_pose_rotation(bone_index, base_rotation)
		else:
			_reset_bone_pose(bone_name)
	_procedural_jump_base_rotations.clear()
	_procedural_jump_pose_active = false


func _capture_procedural_jump_base_rotations() -> void:
	_procedural_jump_base_rotations.clear()
	if _skeleton == null:
		return

	for pose_entry in _get_procedural_jump_pose_entries():
		var bone_name: StringName = pose_entry["bone_name"]
		var bone_index := _get_bone_index(bone_name)
		if bone_index != -1:
			_procedural_jump_base_rotations[bone_name] = _skeleton.get_bone_pose_rotation(bone_index)


func _set_bone_pose_rotation_with_saved_base(bone_name: StringName, rotation_degrees: Vector3) -> void:
	if _skeleton == null or bone_name == &"":
		return

	var bone_index := _get_bone_index(bone_name)
	if bone_index == -1:
		return

	var base_rotation: Variant = _procedural_jump_base_rotations.get(bone_name)
	if not base_rotation is Quaternion:
		base_rotation = _skeleton.get_bone_pose_rotation(bone_index)
		_procedural_jump_base_rotations[bone_name] = base_rotation

	var offset := Quaternion.from_euler(Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	))
	_skeleton.set_bone_pose_rotation(bone_index, base_rotation * offset)


func _get_procedural_jump_pose_entries() -> Array[Dictionary]:
	return [
		{"bone_name": jump_fallback_spine_bone_name, "rotation_degrees": jump_fallback_spine_rotation_degrees},
		{"bone_name": jump_fallback_left_clavicle_bone_name, "rotation_degrees": jump_fallback_left_clavicle_rotation_degrees},
		{"bone_name": jump_fallback_right_clavicle_bone_name, "rotation_degrees": jump_fallback_right_clavicle_rotation_degrees},
		{"bone_name": jump_fallback_left_upperarm_bone_name, "rotation_degrees": jump_fallback_left_upperarm_rotation_degrees},
		{"bone_name": jump_fallback_right_upperarm_bone_name, "rotation_degrees": jump_fallback_right_upperarm_rotation_degrees},
		{"bone_name": jump_fallback_left_forearm_bone_name, "rotation_degrees": jump_fallback_left_forearm_rotation_degrees},
		{"bone_name": jump_fallback_right_forearm_bone_name, "rotation_degrees": jump_fallback_right_forearm_rotation_degrees},
		{"bone_name": jump_fallback_left_thigh_bone_name, "rotation_degrees": jump_fallback_left_thigh_rotation_degrees},
		{"bone_name": jump_fallback_right_thigh_bone_name, "rotation_degrees": jump_fallback_right_thigh_rotation_degrees},
		{"bone_name": jump_fallback_left_calf_bone_name, "rotation_degrees": jump_fallback_left_calf_rotation_degrees},
		{"bone_name": jump_fallback_right_calf_bone_name, "rotation_degrees": jump_fallback_right_calf_rotation_degrees},
		{"bone_name": jump_fallback_left_foot_bone_name, "rotation_degrees": jump_fallback_left_foot_rotation_degrees},
		{"bone_name": jump_fallback_right_foot_bone_name, "rotation_degrees": jump_fallback_right_foot_rotation_degrees},
	]


func _apply_swimming_idle_rotation_override() -> void:
	if not swimming_idle_rotation_override_enabled or swimming_idle_rotation_degrees == Vector3.ZERO:
		_clear_swimming_idle_rotation_override()
		return
	if _current_standard_animation != SWIMMING_IDLW:
		_clear_swimming_idle_rotation_override()
		return

	var target := _get_active_character_model_node()
	if target == null:
		_clear_swimming_idle_rotation_override()
		return

	if _swimming_idle_rotation_target != target:
		_clear_swimming_idle_rotation_override()
		_swimming_idle_rotation_target = target
		_swimming_idle_rotation_base_transform = target.transform
		_swimming_idle_rotation_active = true
	elif not _swimming_idle_rotation_active:
		_swimming_idle_rotation_base_transform = target.transform
		_swimming_idle_rotation_active = true

	var base_scale := _swimming_idle_rotation_base_transform.basis.get_scale()
	var base_rotation := _swimming_idle_rotation_base_transform.basis.get_rotation_quaternion()
	var offset_rotation := Quaternion.from_euler(Vector3(
		deg_to_rad(swimming_idle_rotation_degrees.x),
		deg_to_rad(swimming_idle_rotation_degrees.y),
		deg_to_rad(swimming_idle_rotation_degrees.z)
	))
	var rotated_transform := _swimming_idle_rotation_base_transform
	rotated_transform.basis = Basis(base_rotation * offset_rotation).scaled(base_scale)
	target.transform = rotated_transform


func _clear_swimming_idle_rotation_override() -> void:
	if _swimming_idle_rotation_active and _swimming_idle_rotation_target != null and is_instance_valid(_swimming_idle_rotation_target):
		_swimming_idle_rotation_target.transform = _swimming_idle_rotation_base_transform
	_swimming_idle_rotation_target = null
	_swimming_idle_rotation_base_transform = Transform3D.IDENTITY
	_swimming_idle_rotation_active = false


func _get_active_character_model_node() -> Node3D:
	var model_root := get_node_or_null(model_root_path)
	if model_root != null and model_root.has_method("get_active_model"):
		return model_root.call("get_active_model") as Node3D
	return null


func _normalize_standard_name(animation_name: StringName) -> StringName:
	return ACTION_ALIASES.get(animation_name, animation_name)


func _has_animation(animation_name: StringName) -> bool:
	return _animation_player != null and animation_name != &"" and _animation_player.has_animation(animation_name)


func _get_first_available_animation() -> StringName:
	if _animation_player == null:
		return &""

	var animation_list := _animation_player.get_animation_list()
	if animation_list.is_empty():
		return &""
	return animation_list[0]


func _get_animation_hint_string() -> String:
	var animation_names := PackedStringArray([""])
	if _animation_player == null:
		_refresh_animation_player()

	if _animation_player != null:
		_append_animation_player_names(animation_names, _animation_player)

	var model_root := get_node_or_null(model_root_path)
	if model_root != null:
		var animation_players: Array[AnimationPlayer] = []
		_collect_animation_players(model_root, animation_players)
		for player in animation_players:
			_append_animation_player_names(animation_names, player)

	for mapped_animation in animation_map.values():
		var mapped_animation_text := str(mapped_animation)
		if mapped_animation_text != "" and not animation_names.has(mapped_animation_text):
			animation_names.append(mapped_animation_text)

	for character_map_value in character_animation_maps.values():
		if not character_map_value is Dictionary:
			continue
		for mapped_animation in (character_map_value as Dictionary).values():
			var mapped_animation_text := str(mapped_animation)
			if mapped_animation_text != "" and not animation_names.has(mapped_animation_text):
				animation_names.append(mapped_animation_text)

	return ",".join(animation_names)


func _append_animation_player_names(animation_names: PackedStringArray, player: AnimationPlayer) -> void:
	for animation_name in player.get_animation_list():
		var animation_name_text := String(animation_name)
		if not animation_names.has(animation_name_text):
			animation_names.append(animation_name_text)


func _notify_animation_map_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		notify_property_list_changed()


func _apply_held_pose_override() -> void:
	_refresh_active_held_pose_skeleton()
	if _equipment == null:
		_refresh_held_pose_links()

	if _equipment == null or _skeleton == null:
		_clear_held_pose_override()
		return

	var pose_override := _get_equipped_pose_override()
	if pose_override == null:
		_clear_held_pose_override()
		return

	if _active_pose_override != pose_override:
		_clear_held_pose_override()
		_active_pose_override = pose_override

	_set_bone_pose_rotation(pose_override.upperarm_bone_name, pose_override.upperarm_rotation_degrees)
	_set_bone_pose_rotation(pose_override.forearm_bone_name, pose_override.forearm_rotation_degrees)
	_set_bone_pose_rotation(pose_override.hand_bone_name, pose_override.hand_rotation_degrees)

	if _skeleton.has_method("force_update_all_bone_transforms"):
		_skeleton.call("force_update_all_bone_transforms")


func _refresh_active_held_pose_skeleton() -> void:
	var model_root := get_node_or_null(model_root_path)
	if model_root == null:
		model_root = get_parent()
	if not Engine.is_editor_hint() and model_root != null and model_root.has_method("get_active_skeleton"):
		var active_skeleton := model_root.call("get_active_skeleton") as Skeleton3D
		if active_skeleton != null and active_skeleton != _skeleton:
			_clear_held_pose_override()
			_skeleton = active_skeleton


func _clear_held_pose_override() -> void:
	if _active_pose_override == null or _skeleton == null:
		_active_pose_override = null
		return

	if _active_pose_override.get("upperarm_bone_name") != null:
		_reset_bone_pose(_active_pose_override.get("upperarm_bone_name"))
	if _active_pose_override.get("forearm_bone_name") != null:
		_reset_bone_pose(_active_pose_override.get("forearm_bone_name"))
	if _active_pose_override.get("hand_bone_name") != null:
		_reset_bone_pose(_active_pose_override.get("hand_bone_name"))
	_active_pose_override = null


func _get_equipped_pose_override() -> Resource:
	if _equipment == null or not _equipment.has_method("get_equipped_item") or not _equipment.has_method("get_held_transform_override"):
		return null

	var item := _equipment.call("get_equipped_item", LEFT_HAND_SLOT) as Resource
	if item == null:
		return null

	var item_id := StringName(item.get("id"))
	var override := _equipment.call("get_held_transform_override", item_id) as Resource
	if override == null or not bool(override.get("pose_enabled")):
		return null
	return override


func _set_bone_pose_rotation(bone_name: StringName, rotation_degrees: Vector3) -> void:
	if _skeleton == null or bone_name == &"":
		return

	var bone_index := _get_bone_index(bone_name)
	if bone_index == -1:
		return

	_skeleton.set_bone_pose_rotation(bone_index, Quaternion.from_euler(Vector3(
		deg_to_rad(rotation_degrees.x),
		deg_to_rad(rotation_degrees.y),
		deg_to_rad(rotation_degrees.z)
	)))


func _reset_bone_pose(bone_name: StringName) -> void:
	if _skeleton == null or bone_name == &"":
		return

	var bone_index := _get_bone_index(bone_name)
	if bone_index != -1:
		_skeleton.reset_bone_pose(bone_index)


func _get_bone_index(bone_name: StringName) -> int:
	if _skeleton == null or bone_name == &"":
		return -1
	return _skeleton.find_bone(String(bone_name))


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _collect_animation_players(node: Node, output: Array[AnimationPlayer]) -> void:
	if node is AnimationPlayer:
		output.append(node as AnimationPlayer)
		return

	for child in node.get_children():
		_collect_animation_players(child, output)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D

	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _warn_missing_mapped_animations() -> void:
	if _animation_player == null:
		push_warning("%s could not find an AnimationPlayer under %s." % [name, model_root_path])
		return

	for standard_animation in REQUIRED_ANIMATIONS:
		if standard_animation == JUMPING and procedural_jump_fallback_enabled:
			continue

		var resolved := resolve_animation_name(standard_animation)
		if not _has_animation(resolved):
			push_warning(
				"Character animation '%s' is mapped to '%s', but the model AnimationPlayer does not have it."
				% [standard_animation, resolved]
			)
