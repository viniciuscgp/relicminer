extends Control

@export_file("*.tscn") var game_scene_path := "res://scenes/locations/world.tscn"

@onready var continue_button: Button = %ContinueButton
@onready var new_game_button: Button = %NewGameButton
@onready var load_button: Button = %LoadButton
@onready var options_button: Button = %OptionsButton
@onready var credits_button: Button = %CreditsButton
@onready var quit_button: Button = %QuitButton
@onready var settings_menu: CanvasLayer = %SettingsMenu


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings_menu.hide()

	continue_button.pressed.connect(_start_game)
	new_game_button.pressed.connect(_start_game)
	load_button.pressed.connect(_start_game)
	options_button.pressed.connect(_open_settings)
	credits_button.pressed.connect(_focus_credits)
	quit_button.pressed.connect(_quit_game)
	settings_menu.close_requested.connect(_close_settings)
	_configure_focus()
	continue_button.grab_focus()


func _start_game() -> void:
	get_tree().change_scene_to_file(game_scene_path)


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
