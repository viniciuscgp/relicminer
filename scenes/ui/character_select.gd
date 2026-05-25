extends Control

const CHARACTER_MODEL_META := &"selected_player_character_model"
const LoadingScreen := preload("res://scenes/ui/loading.gd")

## Scene file path used for game scene.
@export_file("*.tscn") var game_scene_path := "res://scenes/locations/world.tscn"
## Scene file path used for main menu scene.
@export_file("*.tscn") var main_menu_scene_path := "res://scenes/ui/main_menu.tscn"

@onready var title_label: Label = %TitleLabel
@onready var male_button: Button = %MaleButton
@onready var female_button: Button = %FemaleButton
@onready var back_button: Button = %BackButton

var _localization_manager: Node
var _save_manager: Node


func _ready() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	_save_manager = get_node_or_null("/root/SaveManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)

	male_button.pressed.connect(_start_male_game)
	female_button.pressed.connect(_start_female_game)
	back_button.pressed.connect(_back_to_menu)
	_configure_focus()
	_apply_localization()
	male_button.grab_focus()


func _start_male_game() -> void:
	_start_game(&"Male")


func _start_female_game() -> void:
	_start_game(&"Female")


func _start_game(character_model: StringName) -> void:
	if _save_manager != null and _save_manager.has_method("set_player_character_model"):
		_save_manager.call("set_player_character_model", character_model)
	else:
		get_tree().set_meta(CHARACTER_MODEL_META, character_model)
	LoadingScreen.load_scene(get_tree(), game_scene_path)


func _back_to_menu() -> void:
	LoadingScreen.load_scene(get_tree(), main_menu_scene_path)


func _configure_focus() -> void:
	male_button.focus_neighbor_right = female_button.get_path()
	male_button.focus_neighbor_bottom = back_button.get_path()
	female_button.focus_neighbor_left = male_button.get_path()
	female_button.focus_neighbor_bottom = back_button.get_path()
	back_button.focus_neighbor_top = male_button.get_path()


func _apply_localization() -> void:
	title_label.text = _text("ui.character_select.title")
	male_button.text = _text("ui.character_select.male")
	female_button.text = _text("ui.character_select.female")
	back_button.text = _text("ui.character_select.back")


func _on_language_changed(_language: String) -> void:
	_apply_localization()


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
