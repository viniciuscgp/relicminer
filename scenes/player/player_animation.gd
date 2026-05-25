@tool
extends Node3D

const CHARACTER_MODEL_META := &"selected_player_character_model"
const DEFAULT_CHARACTER_MODEL := &"Male"
const AVAILABLE_CHARACTER_MODELS: Array[StringName] = [&"Male", &"Female"]

## Configures character model.
@export var character_model: StringName = DEFAULT_CHARACTER_MODEL:
	set(value):
		character_model = _normalize_character_model(value)
		if is_inside_tree():
			_apply_character_model()


func _enter_tree() -> void:
	var selected := character_model
	if get_tree().has_meta(CHARACTER_MODEL_META):
		selected = StringName(str(get_tree().get_meta(CHARACTER_MODEL_META)))
	else:
		var save_manager := get_node_or_null("/root/SaveManager")
		if save_manager != null and save_manager.has_method("get_player_character_model"):
			selected = save_manager.call("get_player_character_model")
	character_model = _normalize_character_model(selected)
	_apply_character_model()


func get_save_data() -> Dictionary:
	return {"character_model": String(character_model)}


func apply_save_data(data: Dictionary) -> void:
	if data.has("character_model"):
		set_character_model(StringName(str(data["character_model"])))


func set_character_model(value: StringName) -> void:
	character_model = _normalize_character_model(value)
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("set_player_character_model"):
		save_manager.call("set_player_character_model", character_model)
	else:
		get_tree().set_meta(CHARACTER_MODEL_META, character_model)
	_apply_character_model()
	_refresh_related_components.call_deferred()


func get_selected_character_model() -> StringName:
	return character_model


func get_active_model() -> Node3D:
	return get_node_or_null(NodePath(String(character_model))) as Node3D


func get_active_animation_player() -> AnimationPlayer:
	var active_model := get_active_model()
	if active_model == null:
		return null
	return _find_animation_player(active_model)


func get_active_skeleton() -> Skeleton3D:
	var active_model := get_active_model()
	if active_model == null:
		return null
	return _find_skeleton(active_model)


func _normalize_character_model(value: StringName) -> StringName:
	if AVAILABLE_CHARACTER_MODELS.has(value):
		return value
	return DEFAULT_CHARACTER_MODEL


func _apply_character_model() -> void:
	for model_name in AVAILABLE_CHARACTER_MODELS:
		var model := get_node_or_null(NodePath(String(model_name))) as Node3D
		if model == null:
			continue
		model.visible = model_name == character_model
		if model_name == character_model:
			move_child(model, 0)


func _refresh_related_components() -> void:
	var actor := _find_actor_root()
	if actor == null:
		return

	var animation_controller := actor.get_node_or_null("AnimationController")
	if animation_controller != null:
		if animation_controller.has_method("_refresh_animation_player"):
			animation_controller.call("_refresh_animation_player")
		if animation_controller.has_method("_refresh_held_pose_links"):
			animation_controller.call("_refresh_held_pose_links")

	var equipment := actor.get_node_or_null("Equipment")
	if equipment != null and equipment.has_method("refresh_skeleton"):
		equipment.call("refresh_skeleton")

	var controller := actor.get_node_or_null("PlayerController")
	if controller != null and controller.has_method("refresh_character_nodes"):
		controller.call("refresh_character_nodes")


func _find_actor_root() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("get_animation_controller"):
			return node
		node = node.get_parent()
	return null


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
