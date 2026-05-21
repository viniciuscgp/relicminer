extends Node

const SAVE_PATH := "user://savegame.json"
const SAVE_VERSION := 2

var _pending_scene_save_data: Dictionary = {}
var _removed_scene_node_paths: Array[String] = []


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
		"nodes": _get_nodes_save_data(scene),
		"removed_scene_nodes": _removed_scene_node_paths.duplicate(),
		"spawned_nodes": _get_spawned_nodes_save_data(scene),
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


func mark_scene_node_removed(node: Node) -> void:
	var scene := get_tree().current_scene
	if scene == null or node == null or node == scene or not scene.is_ancestor_of(node):
		return

	var path := str(scene.get_path_to(node))
	if path.is_empty() or _removed_scene_node_paths.has(path):
		return
	_removed_scene_node_paths.append(path)


func _apply_pending_scene_save_data() -> void:
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene == null:
		return

	_apply_payload_to_scene(_pending_scene_save_data, scene)
	_pending_scene_save_data = {}


func _apply_payload_to_scene(payload: Dictionary, scene: Node) -> void:
	_removed_scene_node_paths = _get_string_array(payload.get("removed_scene_nodes", []))
	_apply_removed_scene_nodes(scene, _removed_scene_node_paths)
	_spawn_saved_nodes(scene, payload.get("spawned_nodes", []))
	_apply_nodes_save_data(scene, payload.get("nodes", {}))

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


func _get_nodes_save_data(root: Node) -> Dictionary:
	var nodes := {}
	_collect_nodes_save_data(root, root, nodes)
	return nodes


func _collect_nodes_save_data(root: Node, node: Node, nodes: Dictionary) -> void:
	if node != root and _is_runtime_spawned_node(node):
		return

	if node != root and node.has_method("get_save_data"):
		var data: Variant = node.call("get_save_data")
		if data is Dictionary and not (data as Dictionary).is_empty():
			nodes[str(root.get_path_to(node))] = data

	for child in node.get_children():
		_collect_nodes_save_data(root, child, nodes)


func _apply_nodes_save_data(root: Node, nodes: Variant) -> void:
	if not nodes is Dictionary:
		return

	var node_data := nodes as Dictionary
	for path_text in node_data.keys():
		var node := root.get_node_or_null(NodePath(str(path_text)))
		if node == null or not node.has_method("apply_save_data"):
			continue

		var data: Variant = node_data.get(path_text)
		if data is Dictionary:
			node.call("apply_save_data", data)


func _get_spawned_nodes_save_data(root: Node) -> Array:
	var spawned: Array = []
	_collect_spawned_nodes_save_data(root, root, spawned)
	return spawned


func _collect_spawned_nodes_save_data(root: Node, node: Node, spawned: Array) -> void:
	if node != root and _is_runtime_spawned_node(node):
		var scene_path := str(node.call("get_spawn_scene_path"))
		if not scene_path.is_empty() and node.has_method("get_save_data"):
			spawned.append({
				"name": node.name,
				"parent_path": str(root.get_path_to(node.get_parent())),
				"scene_path": scene_path,
				"data": node.call("get_save_data"),
			})
		return

	for child in node.get_children():
		_collect_spawned_nodes_save_data(root, child, spawned)


func _spawn_saved_nodes(root: Node, saved_nodes: Variant) -> void:
	if not saved_nodes is Array:
		return

	for entry in saved_nodes:
		if not entry is Dictionary:
			continue
		var data := entry as Dictionary
		var scene_path := str(data.get("scene_path", ""))
		if scene_path.is_empty():
			continue

		var packed_scene := load(scene_path) as PackedScene
		if packed_scene == null:
			push_warning("SaveManager: could not load spawned scene '%s'." % scene_path)
			continue

		var parent_path := NodePath(str(data.get("parent_path", ".")))
		var parent := root.get_node_or_null(parent_path)
		if parent == null:
			parent = root

		var instance := packed_scene.instantiate()
		instance.name = str(data.get("name", instance.name))
		parent.add_child(instance)

		var state: Variant = data.get("data", {})
		if state is Dictionary and instance.has_method("apply_save_data"):
			instance.call("apply_save_data", state)


func _apply_removed_scene_nodes(root: Node, paths: Array[String]) -> void:
	for path in paths:
		var node := root.get_node_or_null(NodePath(path))
		if node != null and node != root:
			node.queue_free()


func _is_runtime_spawned_node(node: Node) -> bool:
	if not node.has_method("get_spawn_scene_path"):
		return false
	return node.owner == null


func _get_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item in value:
		var text := str(item)
		if not text.is_empty() and not result.has(text):
			result.append(text)
	return result


func _find_node_with_method(root: Node, method_name: StringName) -> Node:
	if root.has_method(method_name):
		return root

	for child in root.get_children():
		var found := _find_node_with_method(child, method_name)
		if found != null:
			return found

	return null
