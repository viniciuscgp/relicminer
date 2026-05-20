extends Node

@export var pause_when_inventory_open := true
@export_file("*.tscn") var main_menu_scene_path := "res://scenes/ui/main_menu.tscn"

@onready var pause_menu: CanvasLayer = %PauseMenu
@onready var inventory_menu: CanvasLayer = %InventoryMenu
@onready var settings_menu: CanvasLayer = %SettingsMenu

var _return_to_pause_after_inventory := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.hide()

	pause_menu.resume_requested.connect(close_all)
	pause_menu.inventory_requested.connect(_open_inventory_from_pause)
	pause_menu.settings_requested.connect(open_settings)
	pause_menu.save_requested.connect(save_game)
	pause_menu.abandon_requested.connect(abandon_game)
	inventory_menu.close_requested.connect(_on_inventory_close_requested)
	settings_menu.close_requested.connect(_on_settings_close_requested)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause_menu"):
		_toggle_pause_menu()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		_toggle_inventory()
		get_viewport().set_input_as_handled()


func open_pause_menu() -> void:
	inventory_menu.hide()
	settings_menu.hide()
	pause_menu.show()
	_set_ui_mode(true)
	get_tree().paused = true
	_focus_menu(pause_menu)


func open_inventory(inventory_override: Node = null) -> void:
	_return_to_pause_after_inventory = false
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
	_return_to_pause_after_inventory = false
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.show()
	_set_ui_mode(true)
	get_tree().paused = true
	_focus_menu(settings_menu)


func close_all() -> void:
	_return_to_pause_after_inventory = false
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.hide()
	if inventory_menu.has_method("set_inventory_override"):
		inventory_menu.call("set_inventory_override", null)
	get_tree().paused = false
	_set_ui_mode(false)


func abandon_game() -> void:
	_return_to_pause_after_inventory = false
	get_tree().paused = false
	_set_ui_mode(true)
	get_tree().change_scene_to_file(main_menu_scene_path)


func save_game() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("save_current_game"):
		save_manager.call("save_current_game")


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
		_set_ui_mode(false)


func _on_settings_close_requested() -> void:
	open_pause_menu()


func _set_ui_mode(enabled: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled or not _should_capture_mouse_after_ui() else Input.MOUSE_MODE_CAPTURED


func _focus_menu(menu: Node) -> void:
	if menu.has_method("focus_first"):
		menu.call_deferred("focus_first")


func _should_capture_mouse_after_ui() -> bool:
	var audio_manager := get_node_or_null("/root/AudioManager")
	if audio_manager != null and audio_manager.has_method("get_settings"):
		var settings: Dictionary = audio_manager.call("get_settings")
		return str(settings.get("input_mode", "keyboard")) != "joystick"
	return true
