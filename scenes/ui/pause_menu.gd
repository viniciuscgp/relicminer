extends CanvasLayer

signal resume_requested
signal inventory_requested
signal settings_requested
signal save_requested
signal abandon_requested

@onready var resume_button: Button = %ResumeButton
@onready var inventory_button: Button = %InventoryButton
@onready var settings_button: Button = %SettingsButton
@onready var save_button: Button = %SaveButton
@onready var abandon_button: Button = %AbandonButton
@onready var title_label: Label = %Title

var _localization_manager: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)
	resume_button.pressed.connect(_on_resume_pressed)
	inventory_button.pressed.connect(_on_inventory_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	save_button.pressed.connect(_on_save_pressed)
	abandon_button.pressed.connect(_on_abandon_pressed)
	_configure_focus()
	_apply_localization()


func focus_first() -> void:
	resume_button.grab_focus()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_inventory_pressed() -> void:
	inventory_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_save_pressed() -> void:
	save_requested.emit()


func _on_abandon_pressed() -> void:
	abandon_requested.emit()


func _configure_focus() -> void:
	resume_button.focus_mode = Control.FOCUS_ALL
	inventory_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL
	save_button.focus_mode = Control.FOCUS_ALL
	abandon_button.focus_mode = Control.FOCUS_ALL
	resume_button.focus_neighbor_top = abandon_button.get_path()
	resume_button.focus_neighbor_bottom = inventory_button.get_path()
	inventory_button.focus_neighbor_top = resume_button.get_path()
	inventory_button.focus_neighbor_bottom = settings_button.get_path()
	settings_button.focus_neighbor_top = inventory_button.get_path()
	settings_button.focus_neighbor_bottom = save_button.get_path()
	save_button.focus_neighbor_top = settings_button.get_path()
	save_button.focus_neighbor_bottom = abandon_button.get_path()
	abandon_button.focus_neighbor_top = save_button.get_path()
	abandon_button.focus_neighbor_bottom = resume_button.get_path()


func _apply_localization() -> void:
	title_label.text = _text("ui.pause.title")
	resume_button.text = _text("ui.pause.resume")
	inventory_button.text = _text("ui.pause.inventory")
	settings_button.text = _text("ui.pause.settings")
	save_button.text = _text("ui.pause.save")
	abandon_button.text = _text("ui.pause.abandon")


func _on_language_changed(_language: String) -> void:
	_apply_localization()


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
