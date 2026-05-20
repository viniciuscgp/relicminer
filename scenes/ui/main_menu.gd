extends Control

@export_file("*.tscn") var game_scene_path := "res://scenes/locations/world.tscn"

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var load_button: Button = %LoadButton
@onready var options_button: Button = %OptionsButton
@onready var credits_button: Button = %CreditsButton
@onready var quit_button: Button = %QuitButton
@onready var footer_label: Label = %Footer
@onready var settings_menu: CanvasLayer = %SettingsMenu

var _localization_manager: Node
var _save_manager: Node


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings_menu.hide()
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	_save_manager = get_node_or_null("/root/SaveManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)

	continue_button.pressed.connect(_load_game)
	new_game_button.pressed.connect(_start_game)
	load_button.pressed.connect(_load_game)
	options_button.pressed.connect(_open_settings)
	credits_button.pressed.connect(_focus_credits)
	quit_button.pressed.connect(_quit_game)
	settings_menu.close_requested.connect(_close_settings)
	_configure_focus()
	_apply_localization()
	_apply_save_state()
	if continue_button.disabled:
		new_game_button.grab_focus()
	else:
		continue_button.grab_focus()


func _start_game() -> void:
	get_tree().change_scene_to_file(game_scene_path)


func _load_game() -> void:
	if _save_manager != null and _save_manager.has_method("load_game_scene"):
		if bool(_save_manager.call("load_game_scene", game_scene_path)):
			return
	_start_game()


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


func _on_language_changed(_language: String) -> void:
	_apply_localization()


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
