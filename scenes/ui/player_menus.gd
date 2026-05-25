extends Node

const LoadingScreen := preload("res://scenes/ui/loading.gd")

## Controls whether pause when inventory open is enabled.
@export var pause_when_inventory_open := true
## Scene file path used for main menu scene.
@export_file("*.tscn") var main_menu_scene_path := "res://scenes/ui/main_menu.tscn"

@onready var pause_menu: CanvasLayer = %PauseMenu
@onready var inventory_menu: CanvasLayer = %InventoryMenu
@onready var settings_menu: CanvasLayer = %SettingsMenu
@onready var save_load_dialog: Node = %SaveLoadDialog

const SAVE_DIALOG_MODE_SAVE := &"save"
const SAVE_DIALOG_MODE_LOAD := &"load"

var _return_to_pause_after_inventory := false
var _return_to_pause_after_save_dialog := false
var _open_container: Node
var _save_load_mode := SAVE_DIALOG_MODE_SAVE
var _pending_save_snapshot: Image
var _localization_manager: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.hide()
	save_load_dialog.hide()

	pause_menu.resume_requested.connect(close_all)
	pause_menu.inventory_requested.connect(_open_inventory_from_pause)
	pause_menu.settings_requested.connect(open_settings)
	pause_menu.save_requested.connect(save_game)
	pause_menu.load_requested.connect(load_game)
	pause_menu.abandon_requested.connect(abandon_game)
	inventory_menu.close_requested.connect(_on_inventory_close_requested)
	settings_menu.close_requested.connect(_on_settings_close_requested)
	save_load_dialog.connect("save_confirmed", _on_save_dialog_save_confirmed)
	save_load_dialog.connect("load_confirmed", _on_save_dialog_load_confirmed)
	save_load_dialog.connect("delete_requested", _on_save_dialog_delete_requested)
	save_load_dialog.connect("cancelled", _on_save_dialog_cancelled)
	save_load_dialog.connect("result_closed", _on_save_dialog_result_closed)


func _input(event: InputEvent) -> void:
	if _is_save_dialog_visible():
		return

	if event.is_action_pressed("pause_menu"):
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()


func open_pause_menu() -> void:
	_close_open_container()
	inventory_menu.hide()
	settings_menu.hide()
	pause_menu.show()
	_set_ui_mode(true)
	get_tree().paused = true
	_focus_menu(pause_menu)


func open_inventory(inventory_override: Node = null, opened_container: Node = null) -> void:
	_close_open_container()
	_return_to_pause_after_inventory = false
	_open_container = opened_container
	pause_menu.hide()
	settings_menu.hide()
	if inventory_menu.has_method("set_inventory_override"):
		inventory_menu.call("set_inventory_override", inventory_override)
	if inventory_menu.has_method("refresh"):
		inventory_menu.call("refresh")
	inventory_menu.show()
	_set_ui_mode(true)
	if pause_when_inventory_open:
		get_tree().paused = true
	_focus_menu(inventory_menu)


func open_settings() -> void:
	_close_open_container()
	_return_to_pause_after_inventory = false
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.show()
	_set_ui_mode(true)
	get_tree().paused = true
	_focus_menu(settings_menu)


func close_all() -> void:
	_close_open_container()
	_return_to_pause_after_inventory = false
	_return_to_pause_after_save_dialog = false
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.hide()
	save_load_dialog.hide()
	if inventory_menu.has_method("set_inventory_override"):
		inventory_menu.call("set_inventory_override", null)
	get_tree().paused = false
	_set_ui_mode(false)


func abandon_game() -> void:
	_return_to_pause_after_inventory = false
	_return_to_pause_after_save_dialog = false
	get_tree().paused = false
	_set_ui_mode(true)
	LoadingScreen.load_scene(get_tree(), main_menu_scene_path)


func save_game() -> void:
	_open_save_load_dialog(SAVE_DIALOG_MODE_SAVE)


func load_game() -> void:
	_open_save_load_dialog(SAVE_DIALOG_MODE_LOAD)


func _open_save_load_dialog(mode: StringName) -> void:
	_save_load_mode = mode
	_return_to_pause_after_save_dialog = pause_menu.visible
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.hide()
	_set_ui_mode(true)

	var entries := _get_save_entries()
	if _save_load_mode == SAVE_DIALOG_MODE_SAVE:
		_pending_save_snapshot = await _capture_save_snapshot()
		save_load_dialog.call("open_save", entries, _suggest_save_name(), _pending_save_snapshot)
	else:
		_pending_save_snapshot = null
		save_load_dialog.call("open_load", entries)


func _on_save_dialog_save_confirmed(save_name: String) -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("save_current_game"):
		_show_save_result(_text("ui.save_dialog.failed_no_manager"), true)
		return

	var resolved_save_name := save_name.strip_edges()
	if resolved_save_name.is_empty():
		resolved_save_name = _suggest_save_name()

	var snapshot := _pending_save_snapshot
	if snapshot == null:
		snapshot = await _capture_save_snapshot()

	var saved := bool(save_manager.call("save_current_game", resolved_save_name, snapshot))
	if saved:
		_pending_save_snapshot = null
		_show_save_result(_text("ui.save_dialog.saved", [resolved_save_name]), false)
		return

	_show_save_result(_text("ui.save_dialog.failed"), true)


func _on_save_dialog_load_confirmed(entry: Dictionary) -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("load_game_scene_from_path"):
		_show_save_result(_text("ui.save_dialog.failed_no_manager"), true)
		return

	var save_path := str(entry.get("path", ""))
	if save_path.is_empty():
		_show_save_result(_text("ui.save_dialog.no_save_selected"), true)
		return

	var fallback_scene_path := ""
	if get_tree().current_scene != null:
		fallback_scene_path = get_tree().current_scene.scene_file_path

	var was_paused := get_tree().paused
	pause_menu.hide()
	get_tree().paused = false
	_set_ui_mode(true)
	if bool(save_manager.call("load_game_scene_from_path", save_path, fallback_scene_path)):
		return

	get_tree().paused = was_paused
	_show_save_result(_text("ui.save_dialog.load_failed"), true)


func _on_save_dialog_delete_requested(entry: Dictionary) -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("delete_save_from_path"):
		_show_save_result(_text("ui.save_dialog.failed_no_manager"), true)
		return

	var save_path := str(entry.get("path", ""))
	if save_path.is_empty() or not bool(save_manager.call("delete_save_from_path", save_path)):
		_show_save_result(_text("ui.save_dialog.delete_failed"), true, "ui.save_dialog.delete_failed_title")
		return

	save_load_dialog.call("refresh_entries", _get_save_entries(), false)


func _on_save_dialog_cancelled() -> void:
	_pending_save_snapshot = null
	_return_to_pause_menu_after_dialog()


func _on_save_dialog_result_closed() -> void:
	_return_to_pause_menu_after_dialog()


func _return_to_pause_menu_after_dialog() -> void:
	if _return_to_pause_after_save_dialog:
		open_pause_menu()
	_return_to_pause_after_save_dialog = false


func _get_save_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("get_save_entries"):
		return entries

	var result: Variant = save_manager.call("get_save_entries")
	if not result is Array:
		return entries

	for entry in result:
		if entry is Dictionary:
			entries.append((entry as Dictionary).duplicate(true))
	return entries


func _suggest_save_name() -> String:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("suggest_save_name"):
		return str(save_manager.call("suggest_save_name"))
	return _fallback_save_name()


func _capture_save_snapshot() -> Image:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return get_viewport().get_texture().get_image()


func _show_save_result(message: String, failed: bool, title_key := "") -> void:
	var failed_title_key := "ui.save_dialog.load_failed_title" if _save_load_mode == SAVE_DIALOG_MODE_LOAD else "ui.save_dialog.failed_title"
	var resolved_title_key := title_key
	if resolved_title_key.is_empty():
		resolved_title_key = failed_title_key if failed else "ui.save_dialog.saved_title"
	var title := _text(resolved_title_key)
	save_load_dialog.call("show_result", title, message, failed)


func _fallback_save_name() -> String:
	var datetime := Time.get_datetime_dict_from_system()
	return "RelicMiner %04d-%02d-%02d %02d-%02d" % [
		int(datetime.get("year", 0)),
		int(datetime.get("month", 0)),
		int(datetime.get("day", 0)),
		int(datetime.get("hour", 0)),
		int(datetime.get("minute", 0)),
	]


func _toggle_pause_menu() -> void:
	if settings_menu.visible:
		open_pause_menu()
	elif pause_menu.visible:
		close_all()
	else:
		open_pause_menu()


func _toggle_inventory() -> void:
	if inventory_menu.visible:
		close_all()
	else:
		open_inventory()


func _open_inventory_from_pause() -> void:
	open_inventory()
	_return_to_pause_after_inventory = true


func _on_inventory_close_requested() -> void:
	if _return_to_pause_after_inventory:
		_return_to_pause_after_inventory = false
		open_pause_menu()
		return

	if get_tree().paused and pause_when_inventory_open:
		close_all()
	else:
		inventory_menu.hide()
		if inventory_menu.has_method("set_inventory_override"):
			inventory_menu.call("set_inventory_override", null)
		_close_open_container()
		_set_ui_mode(false)


func _on_settings_close_requested() -> void:
	open_pause_menu()


func _set_ui_mode(enabled: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled or not _should_capture_mouse_after_ui() else Input.MOUSE_MODE_CAPTURED


func _focus_menu(menu: Node) -> void:
	if menu.has_method("focus_first"):
		menu.call_deferred("focus_first")


func _close_open_container() -> void:
	if _open_container != null and is_instance_valid(_open_container) and _open_container.has_method("close"):
		_open_container.call("close")
	_open_container = null


func _is_save_dialog_visible() -> bool:
	return save_load_dialog != null and bool(save_load_dialog.get("visible"))


func _should_capture_mouse_after_ui() -> bool:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("get_settings"):
		var settings: Dictionary = audio_manager.call("get_settings")
		return str(settings.get("input_mode", "keyboard")) != "joystick"
	return true


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
