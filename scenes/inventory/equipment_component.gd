@tool
extends Node
class_name EquipmentComponent

const RIGHT_HAND := &"right_hand"
const LEFT_HAND := &"left_hand"
const PRIMARY := &"primary"
const SECONDARY := &"secondary"
const THROW := &"throw"
const LIVE_PREVIEW_PATH := "user://held_transform_override_preview.json"
const LIVE_PREVIEW_POLL_INTERVAL := 0.1

signal changed
signal equipped(slot: StringName, stack: Resource)
signal unequipped(slot: StringName, stack: Resource)
signal action_executed(slot: StringName, trigger: StringName, action: Resource)

var _watched_held_transform_overrides := {}
var _pending_equipped_slots_save_data: Dictionary = {}
var _live_preview_overrides := {}
var _live_preview_payload_text := ""
var _live_preview_poll_time := 0.0

@export_group("Node References")
## NodePath used to locate the actor node in the Node References settings.
@export var actor_path: NodePath = NodePath("..")
## NodePath used to locate the inventory node in the Node References settings.
@export var inventory_path: NodePath = NodePath("../Inventory")
## NodePath used to locate the inventory dropper node in the Node References settings.
@export var inventory_dropper_path: NodePath = NodePath("../InventoryDropper")
## NodePath used to locate the aim source node in the Node References settings.
@export var aim_source_path: NodePath

@export_group("Socket Paths")
## NodePath used to locate the right hand socket node in the Socket Paths settings.
@export var right_hand_socket_path: NodePath = NodePath("../EquipmentSockets/RightHandSocket")
## NodePath used to locate the left hand socket node in the Socket Paths settings.
@export var left_hand_socket_path: NodePath = NodePath("../EquipmentSockets/LeftHandSocket")
## Fallback NodePath used to locate the skeleton node in the Socket Paths settings.
@export var skeleton_path: NodePath = NodePath("../visual/PlayerAnimation/Male/Armature/Skeleton3D")

@export_group("Bone Sockets")
## Name used for right hand bone in the Bone Sockets settings.
@export var right_hand_bone_name: StringName = &"R_Hand"
## Name used for right hand bone socket in the Bone Sockets settings.
@export var right_hand_bone_socket_name := "RightHandBoneSocket"
## Name used for left hand bone in the Bone Sockets settings.
@export var left_hand_bone_name: StringName = &"L_Hand"
## Name used for left hand bone socket in the Bone Sockets settings.
@export var left_hand_bone_socket_name := "LeftHandBoneSocket"

@export_group("Runtime Behavior")
## Controls whether compensate socket scale is enabled in the Runtime Behavior settings.
@export var compensate_socket_scale := true
## Controls whether refresh held transforms in game is enabled in the Runtime Behavior settings.
@export var refresh_held_transforms_in_game := true
## Controls whether editor live preview overrides is used in the Runtime Behavior settings.
@export var use_editor_live_preview_overrides := true

@export_group("Held Transform Overrides")
## Configures held transform overrides in the Held Transform Overrides settings.
@export var held_transform_overrides: Array[HeldItemTransformOverride] = []:
	set(value):
		held_transform_overrides = _make_unique_held_transform_overrides(value, held_transform_overrides.size())
		_watch_held_transform_overrides()
		if is_node_ready():
			_refresh_held_transforms()

@onready var actor: Node = get_node_or_null(actor_path)
@onready var inventory: Node = get_node_or_null(inventory_path)
@onready var inventory_dropper: Node = get_node_or_null(inventory_dropper_path)
@onready var right_hand_socket: Node3D = get_node_or_null(right_hand_socket_path) as Node3D
@onready var left_hand_socket: Node3D = get_node_or_null(left_hand_socket_path) as Node3D
@onready var skeleton: Skeleton3D = get_node_or_null(skeleton_path) as Skeleton3D if not skeleton_path.is_empty() else null
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
	held_transform_overrides = _make_unique_held_transform_overrides(held_transform_overrides, held_transform_overrides.size())
	_watch_held_transform_overrides()
	if Engine.is_editor_hint():
		return

	refresh_skeleton()
	if inventory != null and inventory.has_signal("changed"):
		inventory.connect("changed", _validate_equipped_stacks)


func refresh_skeleton() -> void:
	skeleton = null
	if actor != null:
		var player_animation := actor.get_node_or_null("visual/PlayerAnimation")
		if player_animation != null and player_animation.has_method("get_active_skeleton"):
			skeleton = player_animation.call("get_active_skeleton") as Skeleton3D
	if skeleton == null:
		skeleton = get_node_or_null(skeleton_path) as Skeleton3D if not skeleton_path.is_empty() else null
	if skeleton == null and actor != null:
		skeleton = _find_skeleton(actor)
	right_hand_socket = _get_or_create_bone_socket(right_hand_socket, right_hand_bone_name, right_hand_bone_socket_name)
	left_hand_socket = _get_or_create_bone_socket(left_hand_socket, left_hand_bone_name, left_hand_bone_socket_name)


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_refresh_editor_live_preview_overrides(_delta)
	if refresh_held_transforms_in_game:
		_refresh_held_transforms()


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


func get_save_data() -> Dictionary:
	var equipped_slots := {}
	for slot in _equipped_stacks.keys():
		var stack: Resource = _equipped_stacks.get(slot)
		equipped_slots[String(slot)] = _stack_to_save_data(stack)
	return {"equipped_slots": equipped_slots}


func apply_save_data(data: Dictionary) -> void:
	_clear_equipped_slots()
	_pending_equipped_slots_save_data = data.get("equipped_slots", {})
	if is_inside_tree():
		_apply_pending_equipped_slots_save_data.call_deferred()
	else:
		_apply_pending_equipped_slots_save_data()


func _apply_pending_equipped_slots_save_data() -> void:
	var equipped_slots := _pending_equipped_slots_save_data.duplicate(true)
	_pending_equipped_slots_save_data.clear()
	_clear_equipped_slots()
	for slot_text in equipped_slots.keys():
		var slot := StringName(str(slot_text))
		if not _equipped_stacks.has(slot):
			continue
		var stack_data: Variant = equipped_slots.get(slot_text)
		if not stack_data is Dictionary:
			continue
		if (stack_data as Dictionary).is_empty():
			continue
		var stack := _find_inventory_stack_for_save_data(stack_data)
		if stack != null:
			_equipped_stacks[slot] = stack
			_create_held_instance(slot, stack)
	changed.emit()


func _clear_equipped_slots() -> void:
	for slot in _equipped_stacks.keys():
		_clear_held_instance(slot)
		_equipped_stacks[slot] = null


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

	_play_equipment_action_animation(item, trigger)
	var executed := bool(action.call("execute", actor, self, stack, slot, held_instance))
	if executed:
		action_executed.emit(slot, trigger, action)
		_validate_equipped_stacks()
	return executed


func throw_equipped_item(slot: StringName, throw_speed := 9.0, upward_speed := 1.5) -> bool:
	var stack := get_equipped_stack(slot)
	if stack == null or bool(stack.call("is_empty")):
		return false

	if inventory_dropper == null:
		return false

	var thrown := false
	if inventory_dropper.has_method("throw_stack"):
		thrown = bool(inventory_dropper.call("throw_stack", stack, 1, get_aim_direction(), throw_speed, upward_speed))
	else:
		var item: Resource = stack.get("item")
		if item == null or not inventory_dropper.has_method("throw_item"):
			return false
		var durability := float(stack.get("durability"))
		thrown = bool(inventory_dropper.call("throw_item", item, 1, durability, get_aim_direction(), throw_speed, upward_speed))
	if thrown:
		unequip(slot)
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


func _make_unique_held_transform_overrides(overrides: Array[HeldItemTransformOverride], previous_size := -1) -> Array[HeldItemTransformOverride]:
	var prepared: Array[HeldItemTransformOverride] = []
	var seen := {}
	for index in range(overrides.size()):
		var override := overrides[index]
		if override == null and previous_size >= 0 and index >= previous_size:
			var previous_override := _find_previous_held_transform_override(prepared)
			if previous_override != null:
				override = _duplicate_held_transform_override(previous_override)

		if override == null:
			prepared.append(null)
			continue

		var prepared_override := override
		var instance_id := override.get_instance_id()
		if seen.has(instance_id):
			prepared_override = _duplicate_held_transform_override(override)

		seen[prepared_override.get_instance_id()] = true
		prepared.append(prepared_override)
	return prepared


func _find_previous_held_transform_override(overrides: Array[HeldItemTransformOverride]) -> HeldItemTransformOverride:
	for index in range(overrides.size() - 1, -1, -1):
		var override := overrides[index]
		if override != null:
			return override
	return null


func _duplicate_held_transform_override(override: HeldItemTransformOverride) -> HeldItemTransformOverride:
	var duplicate := override.duplicate(true) as HeldItemTransformOverride
	if duplicate == null:
		return null
	duplicate.resource_path = ""
	return duplicate


func _watch_held_transform_overrides() -> void:
	var active_overrides := {}
	for override in held_transform_overrides:
		if override == null:
			continue

		var instance_id := override.get_instance_id()
		active_overrides[instance_id] = override
		if not override.changed.is_connected(_on_held_transform_override_changed):
			override.changed.connect(_on_held_transform_override_changed)

	for instance_id in _watched_held_transform_overrides.keys():
		if active_overrides.has(instance_id):
			continue

		var watched_override: HeldItemTransformOverride = _watched_held_transform_overrides[instance_id]
		if watched_override != null and watched_override.changed.is_connected(_on_held_transform_override_changed):
			watched_override.changed.disconnect(_on_held_transform_override_changed)

	_watched_held_transform_overrides = active_overrides


func _on_held_transform_override_changed() -> void:
	if is_node_ready():
		_refresh_held_transforms()
	changed.emit()


func _play_equipment_action_animation(item: Resource, trigger: StringName) -> void:
	if actor == null or item == null or trigger != PRIMARY or not actor.has_method("play_action_animation"):
		return

	if bool(item.get("is_mining_tool")):
		actor.call("play_action_animation", &"mining")
		return

	var item_id := String(item.get("id")).to_lower()
	if item_id.contains("axe"):
		actor.call("play_action_animation", &"chopping")


func _get_socket(slot: StringName) -> Node3D:
	if slot == LEFT_HAND:
		return left_hand_socket
	return right_hand_socket


func _get_or_create_bone_socket(fallback_socket: Node3D, bone_name: StringName, socket_name: String) -> Node3D:
	if skeleton == null or bone_name == &"":
		return fallback_socket

	var bone_index := skeleton.find_bone(String(bone_name))
	if bone_index == -1:
		push_warning("Could not attach equipment to missing bone '%s'." % bone_name)
		return fallback_socket

	for child in skeleton.get_children():
		var attachment := child as BoneAttachment3D
		if attachment != null and StringName(attachment.bone_name) == bone_name:
			return attachment

	var socket := BoneAttachment3D.new()
	socket.name = socket_name
	socket.bone_name = String(bone_name)
	skeleton.add_child(socket)
	return socket


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D

	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


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
	_apply_held_transform(held, item, socket)
	_set_held_light_enabled(held, true)
	_held_instances[slot] = held


func _refresh_held_transforms() -> void:
	for slot in _held_instances.keys():
		var held := _held_instances.get(slot) as Node3D
		if held == null or not is_instance_valid(held):
			continue

		var stack: Resource = _equipped_stacks.get(slot)
		if stack == null or bool(stack.call("is_empty")):
			continue

		var item: Resource = stack.get("item")
		if item == null:
			continue

		_apply_held_transform(held, item, _get_socket(slot))


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


func _apply_held_transform(held: Node3D, item: Resource, socket: Node3D) -> void:
	var held_position: Vector3 = item.get("held_position")
	var held_rotation_degrees: Vector3 = item.get("held_rotation_degrees")
	var held_scale: Vector3 = item.get("held_scale")
	var override := _get_held_transform_override(StringName(item.get("id")))
	if override != null:
		held_position = override.position
		held_rotation_degrees = override.rotation_degrees
		held_scale = override.scale

	if compensate_socket_scale:
		var socket_scale := _get_safe_socket_scale(socket)
		held_position = _divide_vector3(held_position, socket_scale)
		held_scale = _divide_vector3(held_scale, socket_scale)

	held.position = held_position
	held.rotation_degrees = held_rotation_degrees
	held.scale = held_scale


func _get_safe_socket_scale(socket: Node3D) -> Vector3:
	if socket == null:
		return Vector3.ONE

	var socket_scale := socket.global_transform.basis.get_scale().abs()
	if is_zero_approx(socket_scale.x):
		socket_scale.x = 1.0
	if is_zero_approx(socket_scale.y):
		socket_scale.y = 1.0
	if is_zero_approx(socket_scale.z):
		socket_scale.z = 1.0
	return socket_scale


func _divide_vector3(value: Vector3, divisor: Vector3) -> Vector3:
	return Vector3(value.x / divisor.x, value.y / divisor.y, value.z / divisor.z)


func _get_held_transform_override(item_id: StringName) -> HeldItemTransformOverride:
	var live_preview_override := _live_preview_overrides.get(item_id) as HeldItemTransformOverride
	if live_preview_override != null:
		return live_preview_override

	for index in range(held_transform_overrides.size() - 1, -1, -1):
		var override := held_transform_overrides[index]
		if override != null and override.matches_item(item_id):
			return override
	return null


func get_held_transform_override(item_id: StringName) -> Resource:
	return _get_held_transform_override(item_id)


func _refresh_editor_live_preview_overrides(delta: float) -> void:
	if not use_editor_live_preview_overrides or not OS.is_debug_build():
		return

	_live_preview_poll_time -= delta
	if _live_preview_poll_time > 0.0:
		return
	_live_preview_poll_time = LIVE_PREVIEW_POLL_INTERVAL

	if not FileAccess.file_exists(LIVE_PREVIEW_PATH):
		if not _live_preview_overrides.is_empty():
			_live_preview_overrides.clear()
			changed.emit()
		_live_preview_payload_text = ""
		return

	var file := FileAccess.open(LIVE_PREVIEW_PATH, FileAccess.READ)
	if file == null:
		return

	var payload_text := file.get_as_text()
	if payload_text == _live_preview_payload_text:
		return
	_live_preview_payload_text = payload_text

	var parsed: Variant = JSON.parse_string(payload_text)
	if not parsed is Dictionary:
		return

	var loaded_overrides := {}
	for key in (parsed as Dictionary).keys():
		var data: Variant = (parsed as Dictionary).get(key)
		if not data is Dictionary:
			continue
		var override := _live_preview_override_from_data(data as Dictionary)
		if override != null:
			loaded_overrides[StringName(str(key))] = override

	_live_preview_overrides = loaded_overrides
	_refresh_held_transforms()
	changed.emit()


func _live_preview_override_from_data(data: Dictionary) -> HeldItemTransformOverride:
	var preview := HeldItemTransformOverride.new()
	preview.item_id = StringName(str(data.get("item_id", "")))
	preview.additional_item_ids = _string_name_array_from_variant(data.get("additional_item_ids", []))
	preview.position = _vector3_from_variant(data.get("position", []), Vector3.ZERO)
	preview.rotation_degrees = _vector3_from_variant(data.get("rotation_degrees", []), Vector3.ZERO)
	preview.scale = _vector3_from_variant(data.get("scale", []), Vector3.ONE)
	preview.pose_enabled = bool(data.get("pose_enabled", false))
	preview.upperarm_bone_name = StringName(str(data.get("upperarm_bone_name", "")))
	preview.upperarm_rotation_degrees = _vector3_from_variant(data.get("upperarm_rotation_degrees", []), Vector3.ZERO)
	preview.forearm_bone_name = StringName(str(data.get("forearm_bone_name", "")))
	preview.forearm_rotation_degrees = _vector3_from_variant(data.get("forearm_rotation_degrees", []), Vector3.ZERO)
	preview.hand_bone_name = StringName(str(data.get("hand_bone_name", "")))
	preview.hand_rotation_degrees = _vector3_from_variant(data.get("hand_rotation_degrees", []), Vector3.ZERO)
	return preview


func _vector3_from_variant(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array:
		return fallback
	var values := value as Array
	if values.size() < 3:
		return fallback
	return Vector3(float(values[0]), float(values[1]), float(values[2]))


func _string_name_array_from_variant(value: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if not value is Array:
		return result
	for item in value:
		result.append(StringName(str(item)))
	return result


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


func _stack_to_save_data(stack: Resource) -> Dictionary:
	if stack == null or bool(stack.call("is_empty")):
		return {}
	var item: Resource = stack.get("item")
	if item == null:
		return {}
	var data := {
		"item_path": item.resource_path,
		"item_id": String(item.get("id")),
		"amount": int(stack.get("amount")),
		"durability": float(stack.get("durability")),
	}
	var inventory_slot_index := _get_inventory_stack_index(stack)
	if inventory_slot_index >= 0:
		data["inventory_slot_index"] = inventory_slot_index
	return data


func _find_inventory_stack_for_save_data(data: Dictionary) -> Resource:
	if inventory == null:
		return null
	var slots: Array = inventory.get("slots")
	var inventory_slot_index := int(data.get("inventory_slot_index", -1))
	if inventory_slot_index >= 0 and inventory_slot_index < slots.size():
		var indexed_stack: Resource = slots[inventory_slot_index]
		if _stack_matches_save_data(indexed_stack, data):
			return indexed_stack

	for stack in slots:
		if _stack_matches_save_data(stack, data):
			return stack
	return null


func _get_inventory_stack_index(stack: Resource) -> int:
	if inventory == null:
		return -1
	var slots: Array = inventory.get("slots")
	return slots.find(stack)


func _stack_matches_save_data(stack: Resource, data: Dictionary) -> bool:
	if stack == null or bool(stack.call("is_empty")):
		return false

	var item: Resource = stack.get("item")
	if item == null:
		return false

	var item_path := str(data.get("item_path", ""))
	var item_id := str(data.get("item_id", ""))
	if item_path.is_empty() and item_id.is_empty():
		return false
	if not item_path.is_empty() and item.resource_path != item_path:
		return false
	if item_path.is_empty() and not item_id.is_empty() and str(item.get("id")) != item_id:
		return false

	if data.has("amount") and int(stack.get("amount")) != int(data.get("amount")):
		return false

	var saved_durability := float(data.get("durability", -1.0))
	return is_equal_approx(float(stack.get("durability")), saved_durability)
