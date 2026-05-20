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
const LEFT_HAND_SLOT := &"left_hand"
const TORCH_ID := &"simple_torch"

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
@export_group("Torch Pose")
@export var equipment_path: NodePath = NodePath("../Equipment")
@export var skeleton_path: NodePath = NodePath("../visual/PlayerAnimation/Armature/Skeleton3D")
@export var torch_pose_enabled := true
@export var torch_item_ids: Array[StringName] = [TORCH_ID]
@export var torch_upperarm_bone_name: StringName = &"L_Upperarm"
@export var torch_upperarm_rotation_degrees := Vector3(-72.0, 0.0, -34.0)
@export var torch_forearm_bone_name: StringName = &"L_Forearm"
@export var torch_forearm_rotation_degrees := Vector3(-8.0, 0.0, -8.0)

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

var _animation_player: AnimationPlayer
var _equipment: Node
var _skeleton: Skeleton3D
var _current_standard_animation: StringName = &""
var _action_locked_until_msec := 0
var _torch_pose_active := false


func _enter_tree() -> void:
	if Engine.is_editor_hint():
		_refresh_animation_player()
		_notify_animation_map_changed()


func _ready() -> void:
	process_priority = 1000
	process_physics_priority = 1000
	_refresh_animation_player()
	_refresh_torch_pose_links()
	if Engine.is_editor_hint():
		_notify_animation_map_changed()

	if not Engine.is_editor_hint() and warn_missing_mapped_animations:
		_warn_missing_mapped_animations()


func _process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_apply_torch_pose_override()


func _physics_process(_delta: float) -> void:
	if not Engine.is_editor_hint():
		_apply_torch_pose_override()


func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []
	var animation_hint := _get_animation_hint_string()
	properties.append({
		"name": "Animation Map",
		"type": TYPE_NIL,
		"usage": PROPERTY_USAGE_GROUP,
		"hint_string": ANIMATION_MAP_PROPERTY_PREFIX,
	})

	for standard_animation in REQUIRED_ANIMATIONS:
		properties.append({
			"name": "%s%s" % [ANIMATION_MAP_PROPERTY_PREFIX, standard_animation],
			"type": TYPE_STRING_NAME,
			"hint": PROPERTY_HINT_ENUM,
			"hint_string": animation_hint,
			"usage": PROPERTY_USAGE_DEFAULT,
		})

	return properties


func _get(property: StringName) -> Variant:
	var property_name := String(property)
	if not property_name.begins_with(ANIMATION_MAP_PROPERTY_PREFIX):
		return null

	var standard_animation := StringName(property_name.trim_prefix(ANIMATION_MAP_PROPERTY_PREFIX))
	return resolve_animation_name(standard_animation)


func _set(property: StringName, value: Variant) -> bool:
	var property_name := String(property)
	if not property_name.begins_with(ANIMATION_MAP_PROPERTY_PREFIX):
		return false

	var standard_animation := StringName(property_name.trim_prefix(ANIMATION_MAP_PROPERTY_PREFIX))
	animation_map[standard_animation] = StringName(str(value))
	return true


func _refresh_animation_player() -> void:
	_animation_player = get_node_or_null(animation_player_path) as AnimationPlayer
	if _animation_player == null:
		var model_root := get_node_or_null(model_root_path)
		if model_root == null:
			model_root = get_parent()
		if model_root != null:
			_animation_player = _find_animation_player(model_root)


func _refresh_torch_pose_links() -> void:
	_equipment = get_node_or_null(equipment_path)
	_skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if _skeleton == null:
		var model_root := get_node_or_null(model_root_path)
		if model_root == null:
			model_root = get_parent()
		if model_root != null:
			_skeleton = _find_skeleton(model_root)


func get_required_animations() -> Array[StringName]:
	return REQUIRED_ANIMATIONS.duplicate()


func resolve_animation_name(standard_animation: StringName) -> StringName:
	var normalized: StringName = _normalize_standard_name(standard_animation)
	var mapped: Variant = animation_map.get(normalized, normalized)
	if mapped == null:
		return &""
	return StringName(str(mapped))


func has_standard_animation(standard_animation: StringName) -> bool:
	var resolved := resolve_animation_name(standard_animation)
	return _has_animation(resolved)


func play_standard_animation(standard_animation: StringName, blend_time := -1.0, custom_speed := 1.0, lock_action := false) -> bool:
	if _animation_player == null:
		return false

	var normalized := _normalize_standard_name(standard_animation)
	var resolved := resolve_animation_name(normalized)
	if not _has_animation(resolved):
		resolved = _get_first_available_animation()
		if resolved == &"":
			return false

	if _current_standard_animation == normalized and _animation_player.is_playing():
		return true

	var blend := default_blend_time if blend_time < 0.0 else blend_time
	_animation_player.play(resolved, blend, custom_speed)
	_current_standard_animation = normalized

	if lock_action:
		var duration := action_lock_seconds
		if _animation_player.current_animation_length > 0.0:
			duration = minf(_animation_player.current_animation_length, maxf(action_lock_seconds, 0.0))
		_action_locked_until_msec = Time.get_ticks_msec() + int(duration * 1000.0)

	return true


func play_action_animation(standard_animation: StringName) -> bool:
	return play_standard_animation(standard_animation, default_blend_time, 1.0, true)


func set_locomotion_state(moving: bool, running: bool, jumping: bool, swimming: bool) -> void:
	if Time.get_ticks_msec() < _action_locked_until_msec:
		return

	if jumping:
		play_standard_animation(JUMPING)
		return

	if swimming:
		play_standard_animation(SWIMING if moving else SWIMMING_IDLW)
		return

	if moving:
		play_standard_animation(RUNNING if running else WALKING)
		return

	play_standard_animation(IDLE)


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
		for animation_name in _animation_player.get_animation_list():
			var animation_name_text := String(animation_name)
			if not animation_names.has(animation_name_text):
				animation_names.append(animation_name_text)

	for mapped_animation in animation_map.values():
		var mapped_animation_text := str(mapped_animation)
		if mapped_animation_text != "" and not animation_names.has(mapped_animation_text):
			animation_names.append(mapped_animation_text)

	return ",".join(animation_names)


func _notify_animation_map_changed() -> void:
	if Engine.is_editor_hint() and is_inside_tree():
		notify_property_list_changed()


func _apply_torch_pose_override() -> void:
	if not torch_pose_enabled:
		_clear_torch_pose_override()
		return

	if _equipment == null or _skeleton == null:
		_refresh_torch_pose_links()

	if _equipment == null or _skeleton == null:
		_clear_torch_pose_override()
		return

	if not _is_torch_equipped():
		_clear_torch_pose_override()
		return

	_set_bone_pose_rotation(torch_upperarm_bone_name, torch_upperarm_rotation_degrees)
	_set_bone_pose_rotation(torch_forearm_bone_name, torch_forearm_rotation_degrees)
	_torch_pose_active = true

	if _skeleton.has_method("force_update_all_bone_transforms"):
		_skeleton.call("force_update_all_bone_transforms")


func _clear_torch_pose_override() -> void:
	if not _torch_pose_active or _skeleton == null:
		_torch_pose_active = false
		return

	_reset_bone_pose(torch_upperarm_bone_name)
	_reset_bone_pose(torch_forearm_bone_name)
	_torch_pose_active = false


func _is_torch_equipped() -> bool:
	if _equipment == null or not _equipment.has_method("get_equipped_item"):
		return false

	var item := _equipment.call("get_equipped_item", LEFT_HAND_SLOT) as Resource
	if item == null:
		return false

	var item_id := StringName(item.get("id"))
	if torch_item_ids.has(item_id):
		return true
	return String(item_id).to_lower().contains("torch")


func _set_bone_pose_rotation(bone_name: StringName, rotation_degrees: Vector3) -> void:
	if _skeleton == null or bone_name == &"":
		return

	var bone_index := _skeleton.find_bone(String(bone_name))
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

	var bone_index := _skeleton.find_bone(String(bone_name))
	if bone_index != -1:
		_skeleton.reset_bone_pose(bone_index)


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer

	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


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
		var resolved := resolve_animation_name(standard_animation)
		if not _has_animation(resolved):
			push_warning(
				"Character animation '%s' is mapped to '%s', but the model AnimationPlayer does not have it."
				% [standard_animation, resolved]
			)
