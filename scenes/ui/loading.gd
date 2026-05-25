extends Control

const SCENE_PATH := "res://scenes/ui/loading.tscn"
const META_TARGET_SCENE_PATH := &"loading_target_scene_path"
const META_SAVE_PAYLOAD := &"loading_save_payload"

@onready var _progress_bar: ProgressBar = get_node_or_null("TextureRect/ProgressBar") as ProgressBar
@onready var _label: Label = get_node_or_null("TextureRect/Label") as Label

var _target_scene_path := ""
var _save_payload: Dictionary = {}
var _progress: Array[float] = [0.0]
var _load_started := false
var _finished := false


static func load_scene(tree: SceneTree, target_scene_path: String, save_payload: Dictionary = {}) -> Error:
	if tree == null or target_scene_path.is_empty():
		return ERR_INVALID_PARAMETER
	if not ResourceLoader.exists(target_scene_path, "PackedScene"):
		return ERR_FILE_NOT_FOUND

	tree.paused = false
	tree.set_meta(META_TARGET_SCENE_PATH, target_scene_path)
	if save_payload.is_empty():
		if tree.has_meta(META_SAVE_PAYLOAD):
			tree.remove_meta(META_SAVE_PAYLOAD)
	else:
		tree.set_meta(META_SAVE_PAYLOAD, save_payload.duplicate(true))

	return tree.change_scene_to_file(SCENE_PATH)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_target_scene_path = str(get_tree().get_meta(META_TARGET_SCENE_PATH, ""))
	var payload: Variant = get_tree().get_meta(META_SAVE_PAYLOAD, {})
	if payload is Dictionary:
		_save_payload = (payload as Dictionary).duplicate(true)

	if _progress_bar != null:
		_progress_bar.min_value = 0.0
		_progress_bar.max_value = 100.0
		_progress_bar.value = 0.0
	if _label != null:
		_label.text = "Loading"

	if _target_scene_path.is_empty():
		push_error("LoadingScreen: no target scene path was provided.")
		return

	var error := ResourceLoader.load_threaded_request(_target_scene_path, "PackedScene")
	if error != OK:
		push_error("LoadingScreen: failed to request scene '%s'. Error: %s" % [_target_scene_path, error])
		return
	_load_started = true


func _process(_delta: float) -> void:
	if not _load_started or _finished:
		return

	var status := ResourceLoader.load_threaded_get_status(_target_scene_path, _progress)
	_update_progress(_progress[0])
	match status:
		ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_finished = true
			push_error("LoadingScreen: invalid scene resource '%s'." % _target_scene_path)
		ResourceLoader.THREAD_LOAD_FAILED:
			_finished = true
			push_error("LoadingScreen: failed to load scene '%s'." % _target_scene_path)
		ResourceLoader.THREAD_LOAD_LOADED:
			_finished = true
			_update_progress(1.0)
			call_deferred("_finish_loading")


func _finish_loading() -> void:
	var packed_scene := ResourceLoader.load_threaded_get(_target_scene_path) as PackedScene
	if packed_scene == null:
		push_error("LoadingScreen: loaded resource is not a PackedScene: '%s'." % _target_scene_path)
		return

	var scene := packed_scene.instantiate()
	if scene == null:
		push_error("LoadingScreen: failed to instantiate scene '%s'." % _target_scene_path)
		return

	var tree := get_tree()
	var old_scene := tree.current_scene
	tree.root.add_child(scene)
	tree.current_scene = scene
	_clear_loading_metadata(tree)
	_apply_save_payload_if_needed(tree, scene)

	if old_scene != null:
		tree.root.remove_child(old_scene)
		old_scene.queue_free()


func _update_progress(value: float) -> void:
	if _progress_bar == null:
		return
	_progress_bar.value = clampf(value, 0.0, 1.0) * 100.0


func _apply_save_payload_if_needed(tree: SceneTree, scene: Node) -> void:
	if _save_payload.is_empty():
		return
	var save_manager := tree.root.get_node_or_null("SaveManager")
	if save_manager != null and save_manager.has_method("apply_loaded_scene_payload"):
		save_manager.call("apply_loaded_scene_payload", _save_payload, scene)


func _clear_loading_metadata(tree: SceneTree) -> void:
	if tree.has_meta(META_TARGET_SCENE_PATH):
		tree.remove_meta(META_TARGET_SCENE_PATH)
	if tree.has_meta(META_SAVE_PAYLOAD):
		tree.remove_meta(META_SAVE_PAYLOAD)
