extends Control

const LoadingScreen := preload("res://scenes/ui/loading.gd")

## Scene file path used for game scene.
@export_file("*.tscn") var game_scene_path := "res://scenes/locations/world.tscn"
## Scene file path used for character select scene.
@export_file("*.tscn") var character_select_scene_path := "res://scenes/ui/character_select.tscn"

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var load_button: Button = %LoadButton
@onready var options_button: Button = %OptionsButton
@onready var credits_button: Button = %CreditsButton
@onready var quit_button: Button = %QuitButton
@onready var footer_label: Label = %Footer
@onready var settings_menu: CanvasLayer = %SettingsMenu
@onready var save_load_dialog: Node = %SaveLoadDialog

var _localization_manager: Node
var _save_manager: Node


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings_menu.hide()
	save_load_dialog.hide()
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	_save_manager = get_node_or_null("/root/SaveManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)

	continue_button.pressed.connect(_continue_game)
	new_game_button.pressed.connect(_open_character_select)
	load_button.pressed.connect(_open_load_dialog)
	options_button.pressed.connect(_open_settings)
	credits_button.pressed.connect(_focus_credits)
	quit_button.pressed.connect(_quit_game)
	settings_menu.close_requested.connect(_close_settings)
	save_load_dialog.connect("load_confirmed", _on_save_dialog_load_confirmed)
	save_load_dialog.connect("delete_requested", _on_save_dialog_delete_requested)
	save_load_dialog.connect("cancelled", _on_save_dialog_closed)
	save_load_dialog.connect("result_closed", _on_save_dialog_closed)
	_configure_focus()
	_apply_localization()
	_apply_save_state()
	if continue_button.disabled:
		new_game_button.grab_focus()
	else:
		continue_button.grab_focus()


func _start_game() -> void:
	LoadingScreen.load_scene(get_tree(), game_scene_path)


func _open_character_select() -> void:
	var error: Error = LoadingScreen.load_scene(get_tree(), character_select_scene_path)
	if error != OK:
		_start_game()


func _continue_game() -> void:
	if _save_manager != null and _save_manager.has_method("load_game_scene"):
		if bool(_save_manager.call("load_game_scene", game_scene_path)):
			return
	_show_load_result(_text("ui.save_dialog.load_failed"), true)


func _open_load_dialog() -> void:
	save_load_dialog.call("open_load", _get_save_entries())


func _on_save_dialog_load_confirmed(entry: Dictionary) -> void:
	if _save_manager == null or not _save_manager.has_method("load_game_scene_from_path"):
		_show_load_result(_text("ui.save_dialog.failed_no_manager"), true)
		return

	var save_path := str(entry.get("path", ""))
	if save_path.is_empty():
		_show_load_result(_text("ui.save_dialog.no_save_selected"), true)
		return

	if bool(_save_manager.call("load_game_scene_from_path", save_path, game_scene_path)):
		return

	_show_load_result(_text("ui.save_dialog.load_failed"), true)


func _on_save_dialog_delete_requested(entry: Dictionary) -> void:
	if _save_manager == null or not _save_manager.has_method("delete_save_from_path"):
		_show_load_result(_text("ui.save_dialog.failed_no_manager"), true, "ui.save_dialog.delete_failed_title")
		return

	var save_path := str(entry.get("path", ""))
	if save_path.is_empty() or not bool(_save_manager.call("delete_save_from_path", save_path)):
		_show_load_result(_text("ui.save_dialog.delete_failed"), true, "ui.save_dialog.delete_failed_title")
		return

	_apply_save_state()
	save_load_dialog.call("refresh_entries", _get_save_entries(), false)


func _on_save_dialog_closed() -> void:
	_apply_save_state()
	if not load_button.disabled:
		load_button.grab_focus()
	elif not continue_button.disabled:
		continue_button.grab_focus()
	else:
		new_game_button.grab_focus()


func _open_settings() -> void:
	settings_menu.show()
	if settings_menu.has_method("focus_first"):
		settings_menu.call_deferred("focus_first")


func _close_settings() -> void:
	settings_menu.hide()
	options_button.grab_focus()


func _focus_credits() -> void:
	credits_button.grab_focus()


func _quit_game() -> void:
	get_tree().quit()


func _configure_focus() -> void:
	var buttons: Array[Button] = [
		continue_button,
		new_game_button,
		load_button,
		options_button,
		credits_button,
		quit_button,
	]

	for index in range(buttons.size()):
		var button := buttons[index]
		button.focus_mode = Control.FOCUS_ALL
		button.focus_neighbor_top = buttons[max(index - 1, 0)].get_path()
		button.focus_neighbor_bottom = buttons[min(index + 1, buttons.size() - 1)].get_path()


func _apply_localization() -> void:
	continue_button.text = _text("ui.menu.continue")
	new_game_button.text = _text("ui.menu.new_game")
	load_button.text = _text("ui.menu.load_game")
	options_button.text = _text("ui.menu.options")
	credits_button.text = _text("ui.menu.credits")
	quit_button.text = _text("ui.menu.quit")
	footer_label.text = _text("ui.menu.version")


func _apply_save_state() -> void:
	var has_save := _save_manager != null and _save_manager.has_method("has_save") and bool(_save_manager.call("has_save"))
	continue_button.disabled = not has_save
	load_button.disabled = not has_save


func _get_save_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _save_manager == null or not _save_manager.has_method("get_save_entries"):
		return entries

	var result: Variant = _save_manager.call("get_save_entries")
	if not result is Array:
		return entries

	for entry in result:
		if entry is Dictionary:
			entries.append((entry as Dictionary).duplicate(true))
	return entries


func _show_load_result(message: String, failed: bool, title_key := "") -> void:
	var resolved_title_key := title_key
	if resolved_title_key.is_empty():
		resolved_title_key = "ui.save_dialog.load_failed_title" if failed else "ui.save_dialog.saved_title"
	save_load_dialog.call("show_result", _text(resolved_title_key), message, failed)


func _on_language_changed(_language: String) -> void:
	_apply_localization()


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
