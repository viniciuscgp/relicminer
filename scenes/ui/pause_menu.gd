extends CanvasLayer

signal resume_requested
signal inventory_requested
signal settings_requested
signal abandon_requested

@onready var resume_button: Button = %ResumeButton
@onready var inventory_button: Button = %InventoryButton
@onready var settings_button: Button = %SettingsButton
@onready var abandon_button: Button = %AbandonButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	resume_button.pressed.connect(_on_resume_pressed)
	inventory_button.pressed.connect(_on_inventory_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	abandon_button.pressed.connect(_on_abandon_pressed)
	_configure_focus()


func focus_first() -> void:
	resume_button.grab_focus()


func _on_resume_pressed() -> void:
	resume_requested.emit()


func _on_inventory_pressed() -> void:
	inventory_requested.emit()


func _on_settings_pressed() -> void:
	settings_requested.emit()


func _on_abandon_pressed() -> void:
	abandon_requested.emit()


func _configure_focus() -> void:
	resume_button.focus_mode = Control.FOCUS_ALL
	inventory_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL
	abandon_button.focus_mode = Control.FOCUS_ALL
	resume_button.focus_neighbor_top = abandon_button.get_path()
	resume_button.focus_neighbor_bottom = inventory_button.get_path()
	inventory_button.focus_neighbor_top = resume_button.get_path()
	inventory_button.focus_neighbor_bottom = settings_button.get_path()
	settings_button.focus_neighbor_top = inventory_button.get_path()
	settings_button.focus_neighbor_bottom = abandon_button.get_path()
	abandon_button.focus_neighbor_top = settings_button.get_path()
	abandon_button.focus_neighbor_bottom = resume_button.get_path()
