extends Node

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 1

var _pending_scene_save_data: Dictionary = {}


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_current_game() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false

	var payload := {
		"version": SAVE_VERSION,
		"saved_at_unix_time": Time.get_unix_time_from_system(),
		"scene_path": scene.scene_file_path,
		"environment": _get_environment_save_data(scene),
	}
	return save_payload(payload)


func save_payload(payload: Dictionary) -> bool:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open save file '%s' for writing." % SAVE_PATH)
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	return true


func load_current_game() -> bool:
	var payload := load_payload()
	if payload.is_empty():
		return false

	var scene := get_tree().current_scene
	if scene == null:
		return false

	_apply_payload_to_scene(payload, scene)
	return true


func load_game_scene(fallback_scene_path := "") -> bool:
	var payload := load_payload()
	if payload.is_empty():
		return false

	var scene_path := str(payload.get("scene_path", ""))
	if scene_path.is_empty():
		scene_path = fallback_scene_path
	if scene_path.is_empty():
		return false

	var error := get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SaveManager: failed to change scene to '%s'. Error: %s" % [scene_path, error])
		return false

	_pending_scene_save_data = payload
	_apply_pending_scene_save_data.call_deferred()
	return true


func load_payload() -> Dictionary:
	if not has_save():
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveManager: failed to open save file '%s' for reading." % SAVE_PATH)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("SaveManager: save file '%s' does not contain a Dictionary payload." % SAVE_PATH)
		return {}

	return parsed


func _apply_pending_scene_save_data() -> void:
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene == null:
		return

	_apply_payload_to_scene(_pending_scene_save_data, scene)
	_pending_scene_save_data = {}


func _apply_payload_to_scene(payload: Dictionary, scene: Node) -> void:
	var environment_data: Dictionary = payload.get("environment", {})
	if not environment_data.is_empty():
		_apply_environment_save_data(scene, environment_data)


func _get_environment_save_data(root: Node) -> Dictionary:
	var environment := _find_node_with_method(root, &"get_environment_save_data")
	if environment == null:
		return {}
	return environment.call("get_environment_save_data")


func _apply_environment_save_data(root: Node, data: Dictionary) -> void:
	var environment := _find_node_with_method(root, &"apply_environment_save_data")
	if environment == null:
		return
	environment.call("apply_environment_save_data", data)


func _find_node_with_method(root: Node, method_name: StringName) -> Node:
	if root.has_method(method_name):
		return root

	for child in root.get_children():
		var found := _find_node_with_method(child, method_name)
		if found != null:
			return found

	return null
