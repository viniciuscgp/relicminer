extends Node

const SAVE_PATH := "user://savegame.json"
const SAVE_DIRECTORY := "user://saves"
const SAVE_SNAPSHOT_EXTENSION := "png"
const PLAYER_PROFILE_PATH := "user://player_profile.json"
const SAVE_VERSION := 2
const PLAYER_CHARACTER_MODEL_META := &"selected_player_character_model"
const DEFAULT_PLAYER_CHARACTER_MODEL := &"Male"
const VALID_PLAYER_CHARACTER_MODELS := ["Male", "Female"]

var _removed_scene_node_paths: Array[String] = []
var _last_save_errors: Array[String] = []
var _last_save_warnings: Array[String] = []
var _last_save_path := ""


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) or not get_save_entries().is_empty()


func save_current_game(save_name := "", snapshot_image: Image = null) -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		_last_save_errors.clear()
		_last_save_errors.append("No active scene.")
		return false

	var resolved_save_name := _normalize_save_name(str(save_name))
	if resolved_save_name.is_empty():
		resolved_save_name = suggest_save_name()

	var payload := {
		"version": SAVE_VERSION,
		"save_name": resolved_save_name,
		"saved_at_unix_time": Time.get_unix_time_from_system(),
		"scene_path": scene.scene_file_path,
		"player_character_model": _get_player_character_model(scene),
		"snapshot_path": _get_snapshot_path_for_name(resolved_save_name),
		"environment": _get_environment_save_data(scene),
		"nodes": _get_nodes_save_data(scene),
		"removed_scene_nodes": _removed_scene_node_paths.duplicate(),
		"spawned_nodes": _get_spawned_nodes_save_data(scene),
	}
	return save_payload(payload, resolved_save_name, snapshot_image)


func save_payload(payload: Dictionary, save_name := "", snapshot_image: Image = null) -> bool:
	_last_save_errors.clear()
	_last_save_warnings.clear()
	_last_save_path = ""

	var resolved_save_name := _normalize_save_name(str(save_name))
	if resolved_save_name.is_empty():
		resolved_save_name = _normalize_save_name(str(payload.get("save_name", "")))
	if resolved_save_name.is_empty():
		resolved_save_name = suggest_save_name()
	payload["save_name"] = resolved_save_name

	if not _validate_save_payload(payload):
		return false

	_store_player_character_model(str(payload.get("player_character_model", "")))
	var named_save_path := _get_save_path_for_name(resolved_save_name)
	var snapshot_path := _get_snapshot_path_for_name(resolved_save_name)
	payload["snapshot_path"] = snapshot_path
	if not _ensure_save_directory():
		return false

	if snapshot_image != null and not _write_snapshot_to_path(snapshot_image, snapshot_path):
		_last_save_warnings.append("Save snapshot could not be written.")

	if not _write_payload_to_path(payload, named_save_path):
		return false
	if not _write_payload_to_path(payload, SAVE_PATH):
		return false

	_last_save_path = named_save_path
	return true


func suggest_save_name() -> String:
	var datetime := Time.get_datetime_dict_from_system()
	return "RelicMiner %04d-%02d-%02d %02d-%02d" % [
		int(datetime.get("year", 0)),
		int(datetime.get("month", 0)),
		int(datetime.get("day", 0)),
		int(datetime.get("hour", 0)),
		int(datetime.get("minute", 0)),
	]


func get_last_save_path() -> String:
	return _last_save_path


func get_last_save_errors() -> Array[String]:
	return _last_save_errors.duplicate()


func get_last_save_warnings() -> Array[String]:
	return _last_save_warnings.duplicate()


func get_save_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not _ensure_save_directory():
		return entries

	var directory := DirAccess.open(SAVE_DIRECTORY)
	if directory == null:
		return entries

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "json":
			var path := "%s/%s" % [SAVE_DIRECTORY, file_name]
			var payload := _load_payload_from_path(path)
			if not payload.is_empty():
				entries.append(_build_save_entry(path, payload))
		file_name = directory.get_next()
	directory.list_dir_end()

	entries.sort_custom(_sort_save_entries_descending)
	return entries


func load_game_scene_from_path(save_path: String, fallback_scene_path := "") -> bool:
	var payload := load_payload(save_path)
	if payload.is_empty():
		return false
	if not _write_payload_to_path(payload, SAVE_PATH):
		return false
	return _load_payload_scene(payload, fallback_scene_path)


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
	return _load_payload_scene(payload, fallback_scene_path)


func _load_payload_scene(payload: Dictionary, fallback_scene_path := "") -> bool:
	var scene_path := str(payload.get("scene_path", ""))
	if scene_path.is_empty():
		scene_path = fallback_scene_path
	if scene_path.is_empty():
		return false

	_apply_global_save_metadata(payload)
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		push_error("SaveManager: failed to load scene '%s'." % scene_path)
		return false

	var scene := packed_scene.instantiate()
	if scene == null:
		push_error("SaveManager: failed to instantiate scene '%s'." % scene_path)
		return false

	var tree := get_tree()
	var old_scene := tree.current_scene
	if old_scene != null:
		tree.root.remove_child(old_scene)
		old_scene.queue_free()

	tree.root.add_child(scene)
	tree.current_scene = scene
	_apply_payload_to_scene(payload, scene)
	_notify_scene_loaded(scene)
	return true


func load_payload(save_path := "") -> Dictionary:
	var resolved_path := str(save_path)
	if resolved_path.is_empty():
		resolved_path = _get_latest_save_path()
	if resolved_path.is_empty():
		return {}
	return _load_payload_from_path(resolved_path)


func _load_payload_from_path(save_path: String) -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}

	var file := FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		push_error("SaveManager: failed to open save file '%s' for reading." % save_path)
		return {}

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("SaveManager: save file '%s' does not contain a Dictionary payload." % save_path)
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


func _apply_payload_to_scene(payload: Dictionary, scene: Node) -> void:
	_apply_global_save_metadata(payload)
	_removed_scene_node_paths = _get_string_array(payload.get("removed_scene_nodes", []))
	_apply_removed_scene_nodes(scene, _removed_scene_node_paths)
	_spawn_saved_nodes(scene, payload.get("spawned_nodes", []))
	_apply_nodes_save_data(scene, payload.get("nodes", {}))

	var environment_data: Dictionary = payload.get("environment", {})
	if not environment_data.is_empty():
		_apply_environment_save_data(scene, environment_data)


func _notify_scene_loaded(node: Node) -> void:
	if node.has_method("refresh_after_load"):
		node.call("refresh_after_load")

	for child in node.get_children():
		_notify_scene_loaded(child)


func _get_environment_save_data(root: Node) -> Dictionary:
	var environment := _find_node_with_method(root, &"get_environment_save_data")
	if environment == null:
		return {}
	return environment.call("get_environment_save_data")


func _get_player_character_model(root: Node) -> String:
	var player_animation := _find_node_with_method(root, &"get_selected_character_model")
	if player_animation != null:
		return _normalize_player_character_model(str(player_animation.call("get_selected_character_model")))
	if get_tree().has_meta(PLAYER_CHARACTER_MODEL_META):
		return _normalize_player_character_model(str(get_tree().get_meta(PLAYER_CHARACTER_MODEL_META)))
	return _load_stored_player_character_model()


func _apply_global_save_metadata(payload: Dictionary) -> void:
	var character_model := _normalize_player_character_model(str(payload.get("player_character_model", "")))
	if character_model.is_empty():
		var nodes: Variant = payload.get("nodes", {})
		if nodes is Dictionary:
			for node_data in (nodes as Dictionary).values():
				if node_data is Dictionary and (node_data as Dictionary).has("character_model"):
					character_model = _normalize_player_character_model(str((node_data as Dictionary).get("character_model", "")))
					break
	if character_model.is_empty():
		character_model = _load_stored_player_character_model()
	if character_model.is_empty():
		character_model = DEFAULT_PLAYER_CHARACTER_MODEL
	if not character_model.is_empty():
		get_tree().set_meta(PLAYER_CHARACTER_MODEL_META, StringName(character_model))
		_store_player_character_model(character_model)


func set_player_character_model(character_model: StringName) -> void:
	var normalized := _normalize_player_character_model(str(character_model))
	if normalized.is_empty():
		normalized = DEFAULT_PLAYER_CHARACTER_MODEL
	get_tree().set_meta(PLAYER_CHARACTER_MODEL_META, StringName(normalized))
	_store_player_character_model(normalized)


func get_player_character_model() -> StringName:
	if get_tree().has_meta(PLAYER_CHARACTER_MODEL_META):
		var normalized := _normalize_player_character_model(str(get_tree().get_meta(PLAYER_CHARACTER_MODEL_META)))
		if not normalized.is_empty():
			return StringName(normalized)
	return StringName(_load_stored_player_character_model())


func _store_player_character_model(character_model: String) -> void:
	var normalized := _normalize_player_character_model(character_model)
	if normalized.is_empty():
		return
	if not _ensure_user_directory():
		return

	var file := FileAccess.open(PLAYER_PROFILE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveManager: failed to open player profile '%s' for writing." % PLAYER_PROFILE_PATH)
		return
	file.store_string(JSON.stringify({"player_character_model": normalized}, "\t"))


func _load_stored_player_character_model() -> String:
	if not FileAccess.file_exists(PLAYER_PROFILE_PATH):
		return ""
	var file := FileAccess.open(PLAYER_PROFILE_PATH, FileAccess.READ)
	if file == null:
		return ""
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return ""
	return _normalize_player_character_model(str((parsed as Dictionary).get("player_character_model", "")))


func _normalize_player_character_model(character_model: String) -> String:
	if VALID_PLAYER_CHARACTER_MODELS.has(character_model):
		return character_model
	return ""


func _ensure_save_directory() -> bool:
	if not _ensure_user_directory():
		return false
	var save_directory_path := ProjectSettings.globalize_path(SAVE_DIRECTORY)
	var error := DirAccess.make_dir_recursive_absolute(save_directory_path)
	if error != OK:
		var message := "SaveManager: failed to create save directory '%s'. Error: %s" % [save_directory_path, error]
		_last_save_errors.append(message)
		push_error(message)
		return false
	return true


func _ensure_user_directory() -> bool:
	var user_directory_path := ProjectSettings.globalize_path("user://")
	var error := DirAccess.make_dir_recursive_absolute(user_directory_path)
	if error != OK:
		var message := "SaveManager: failed to create user data directory '%s'. Error: %s" % [user_directory_path, error]
		if not _last_save_errors.has(message):
			_last_save_errors.append(message)
		push_error(message)
		return false
	return true


func _write_payload_to_path(payload: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		var message := "SaveManager: failed to open save file '%s' for writing." % path
		_last_save_errors.append(message)
		push_error(message)
		return false

	file.store_string(JSON.stringify(payload, "\t"))
	file.flush()
	return true


func _write_snapshot_to_path(snapshot_image: Image, path: String) -> bool:
	var image := snapshot_image.duplicate()
	var max_width := 640
	if image.get_width() > max_width and image.get_width() > 0:
		var aspect := float(image.get_height()) / float(image.get_width())
		image.resize(max_width, max(1, int(round(max_width * aspect))), Image.INTERPOLATE_LANCZOS)

	var error: Error = image.save_png(path)
	if error != OK:
		push_warning("SaveManager: failed to write save snapshot '%s'. Error: %s" % [path, error])
		return false
	return true


func _get_latest_save_path() -> String:
	if FileAccess.file_exists(SAVE_PATH):
		return SAVE_PATH
	var entries := get_save_entries()
	if entries.is_empty():
		return ""
	return str(entries[0].get("path", ""))


func _get_save_path_for_name(save_name: String) -> String:
	return "%s/%s.json" % [SAVE_DIRECTORY, _sanitize_save_file_name(save_name)]


func _get_snapshot_path_for_name(save_name: String) -> String:
	return "%s/%s.%s" % [SAVE_DIRECTORY, _sanitize_save_file_name(save_name), SAVE_SNAPSHOT_EXTENSION]


func _build_save_entry(path: String, payload: Dictionary) -> Dictionary:
	var save_name := _normalize_save_name(str(payload.get("save_name", "")))
	if save_name.is_empty():
		save_name = path.get_file().get_basename().replace("_", " ")

	var saved_at := int(payload.get("saved_at_unix_time", 0))
	var snapshot_path := str(payload.get("snapshot_path", ""))
	if snapshot_path.is_empty():
		snapshot_path = _get_snapshot_path_for_name(save_name)

	var nodes: Variant = payload.get("nodes", {})
	var spawned_nodes: Variant = payload.get("spawned_nodes", [])
	var removed_scene_nodes: Variant = payload.get("removed_scene_nodes", [])
	return {
		"path": path,
		"save_name": save_name,
		"saved_at_unix_time": saved_at,
		"scene_path": str(payload.get("scene_path", "")),
		"player_character_model": str(payload.get("player_character_model", "")),
		"snapshot_path": snapshot_path,
		"node_count": (nodes as Dictionary).size() if nodes is Dictionary else 0,
		"spawned_node_count": (spawned_nodes as Array).size() if spawned_nodes is Array else 0,
		"removed_node_count": (removed_scene_nodes as Array).size() if removed_scene_nodes is Array else 0,
	}


func _sort_save_entries_descending(a: Dictionary, b: Dictionary) -> bool:
	var a_time := int(a.get("saved_at_unix_time", 0))
	var b_time := int(b.get("saved_at_unix_time", 0))
	if a_time == b_time:
		return str(a.get("save_name", "")) < str(b.get("save_name", ""))
	return a_time > b_time


func _normalize_save_name(save_name: String) -> String:
	var normalized := save_name.strip_edges()
	while normalized.find("  ") >= 0:
		normalized = normalized.replace("  ", " ")
	return normalized


func _sanitize_save_file_name(save_name: String) -> String:
	var sanitized := _normalize_save_name(save_name)
	var invalid_characters := ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
	for character in invalid_characters:
		sanitized = sanitized.replace(character, "_")
	sanitized = sanitized.replace(" ", "_")
	while sanitized.find("__") >= 0:
		sanitized = sanitized.replace("__", "_")
	sanitized = sanitized.strip_edges()
	if sanitized.is_empty() or sanitized == "." or sanitized == "..":
		sanitized = "save"
	return sanitized


func _validate_save_payload(payload: Dictionary) -> bool:
	_last_save_errors.clear()
	_last_save_warnings.clear()

	if int(payload.get("version", 0)) <= 0:
		_last_save_errors.append("Save payload is missing version.")
	if str(payload.get("scene_path", "")).is_empty():
		_last_save_errors.append("Save payload is missing scene_path.")
	if str(payload.get("save_name", "")).strip_edges().is_empty():
		_last_save_errors.append("Save payload is missing save_name.")

	var nodes: Variant = payload.get("nodes", {})
	if not nodes is Dictionary:
		_last_save_errors.append("Save payload nodes field is not a Dictionary.")
	else:
		var node_data := nodes as Dictionary
		_require_saved_node(node_data, "Player")
		_require_saved_node(node_data, "Player/Inventory")
		_require_saved_node(node_data, "Player/PlayerStats")
		_require_saved_node(node_data, "Player/Equipment")
		_require_saved_node(node_data, "Player/visual/PlayerAnimation")

	var environment: Variant = payload.get("environment", {})
	if not environment is Dictionary or (environment as Dictionary).is_empty():
		_last_save_warnings.append("Environment data was not found in save payload.")
	var spawned_nodes: Variant = payload.get("spawned_nodes", [])
	if not spawned_nodes is Array:
		_last_save_errors.append("Save payload spawned_nodes field is not an Array.")
	var removed_scene_nodes: Variant = payload.get("removed_scene_nodes", [])
	if not removed_scene_nodes is Array:
		_last_save_errors.append("Save payload removed_scene_nodes field is not an Array.")

	for message in _last_save_errors:
		push_error("SaveManager: %s" % message)
	for message in _last_save_warnings:
		push_warning("SaveManager: %s" % message)
	return _last_save_errors.is_empty()


func _require_saved_node(node_data: Dictionary, node_path: String) -> void:
	if not node_data.has(node_path):
		_last_save_warnings.append("Expected save data for '%s' was not found." % node_path)


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
