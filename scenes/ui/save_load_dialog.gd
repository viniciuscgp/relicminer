extends CanvasLayer

signal save_confirmed(save_name: String)
signal load_confirmed(entry: Dictionary)
signal delete_requested(entry: Dictionary)
signal cancelled
signal result_closed

const MODE_SAVE := &"save"
const MODE_LOAD := &"load"
const MESSAGE_RESULT := &"result"
const MESSAGE_DELETE := &"delete"

## Delay in seconds between save slot moves while a joystick stick is held.
@export_range(0.05, 0.6, 0.01) var joystick_navigation_delay := 0.22

@onready var _root: Control = %Root
@onready var _title_label: Label = %Title
@onready var _list_title_label: Label = %ListTitle
@onready var _save_list_scroll: ScrollContainer = %SaveListScroll
@onready var _save_list: VBoxContainer = %SaveList
@onready var _slot_button_template: Button = %SlotButtonTemplate
@onready var _empty_label: Label = %EmptyLabel
@onready var _preview_title_label: Label = %PreviewTitle
@onready var _preview_rect: TextureRect = %PreviewRect
@onready var _details_label: Label = %DetailsLabel
@onready var _name_row: HBoxContainer = %NameRow
@onready var _name_label: Label = %NameLabel
@onready var _name_edit: LineEdit = %NameEdit
@onready var _delete_button: Button = %DeleteButton
@onready var _primary_button: Button = %PrimaryButton
@onready var _cancel_button: Button = %CancelButton
@onready var _message_root: Control = %MessageRoot
@onready var _message_title_label: Label = %MessageTitle
@onready var _message_label: Label = %MessageLabel
@onready var _message_ok_button: Button = %MessageOkButton
@onready var _message_cancel_button: Button = %MessageCancelButton

var _mode := MODE_SAVE
var _entries: Array[Dictionary] = []
var _slot_buttons: Array[Button] = []
var _pending_snapshot: Image
var _selected_index := -1
var _message_action := StringName()
var _localization_manager: Node
var _joy_nav_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 35
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)

	_slot_button_template.hide()
	_message_root.hide()
	_primary_button.pressed.connect(_on_primary_pressed)
	_cancel_button.pressed.connect(_on_cancel_pressed)
	_delete_button.pressed.connect(_on_delete_pressed)
	_name_edit.text_submitted.connect(_on_name_submitted)
	_message_ok_button.pressed.connect(_on_message_ok_pressed)
	_message_cancel_button.pressed.connect(_on_message_cancel_pressed)
	hide()


func _process(delta: float) -> void:
	if _joy_nav_timer > 0.0:
		_joy_nav_timer = maxf(0.0, _joy_nav_timer - delta)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _message_root.visible:
			_on_message_cancel_pressed()
		elif _root.visible:
			_on_cancel_pressed()
		return

	if not _root.visible or _message_root.visible:
		return
	if not (event is InputEventJoypadMotion or event is InputEventJoypadButton):
		return

	var direction := 0
	if event.is_action_pressed("ui_down"):
		direction = 1
	elif event.is_action_pressed("ui_up"):
		direction = -1
	if direction == 0:
		return

	get_viewport().set_input_as_handled()
	if _joy_nav_timer > 0.0:
		return
	_move_selection(direction)
	_joy_nav_timer = joystick_navigation_delay


func open_save(entries: Array[Dictionary], suggested_save_name: String, pending_snapshot: Image) -> void:
	_mode = MODE_SAVE
	_pending_snapshot = pending_snapshot
	_name_edit.text = suggested_save_name
	_open(entries, false)
	_show_pending_snapshot()
	_name_edit.call_deferred("grab_focus")
	_name_edit.call_deferred("select_all")


func open_load(entries: Array[Dictionary]) -> void:
	_mode = MODE_LOAD
	_pending_snapshot = null
	_open(entries, false)
	if _selected_index >= 0:
		_focus_selected_slot()
	else:
		_cancel_button.call_deferred("grab_focus")


func refresh_entries(entries: Array[Dictionary], use_selected_name := false) -> void:
	_set_entries(entries)
	if _entries.is_empty():
		_selected_index = -1
	else:
		_selected_index = clampi(_selected_index, 0, _entries.size() - 1)
		if _selected_index < 0:
			_selected_index = 0
	_update_selection(use_selected_name)
	_update_action_buttons()
	_configure_focus()


func show_result(title: String, message: String, failed: bool) -> void:
	show()
	_root.hide()
	_show_message(title, message, MESSAGE_RESULT, false, failed)


func focus_first() -> void:
	if _mode == MODE_SAVE:
		_name_edit.grab_focus()
	elif _selected_index >= 0:
		_focus_selected_slot()
	else:
		_cancel_button.grab_focus()


func _open(entries: Array[Dictionary], use_selected_name: bool) -> void:
	show()
	_root.show()
	_message_root.hide()
	_selected_index = -1
	_apply_localization()
	_name_row.visible = _mode == MODE_SAVE
	_set_entries(entries)
	if not _entries.is_empty():
		_selected_index = 0
	_update_selection(use_selected_name)
	_update_action_buttons()
	_configure_focus()


func _set_entries(entries: Array[Dictionary]) -> void:
	_entries.clear()
	for entry in entries:
		_entries.append(entry.duplicate(true))

	for child in _save_list.get_children():
		if child == _slot_button_template or child == _empty_label:
			continue
		_save_list.remove_child(child)
		child.queue_free()
	_slot_buttons.clear()

	_empty_label.visible = _entries.is_empty()
	for index in range(_entries.size()):
		var entry := _entries[index]
		var button := _slot_button_template.duplicate() as Button
		button.name = "SaveSlot%d" % index
		button.unique_name_in_owner = false
		button.visible = true
		button.disabled = false
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.text = _get_slot_label(entry)
		button.set_meta("entry", entry)
		button.pressed.connect(_select_entry.bind(index, true))
		button.focus_entered.connect(_select_entry.bind(index, false))
		_save_list.add_child(button)
		_slot_buttons.append(button)


func _get_slot_label(entry: Dictionary) -> String:
	var save_name := str(entry.get("save_name", "")).strip_edges()
	if save_name.is_empty():
		save_name = _text("ui.save_dialog.unknown_save")
	var date_text := _format_save_date(int(entry.get("saved_at_unix_time", 0)))
	if date_text.is_empty():
		return save_name
	return "%s\n%s" % [save_name, date_text]


func _select_entry(index: int, use_selected_name: bool) -> void:
	if index < 0 or index >= _entries.size():
		return
	_selected_index = index
	_update_selection(use_selected_name)
	_update_action_buttons()


func _update_selection(use_selected_name: bool) -> void:
	for index in range(_slot_buttons.size()):
		_slot_buttons[index].button_pressed = index == _selected_index

	if _mode == MODE_SAVE:
		if use_selected_name and _selected_index >= 0:
			_name_edit.text = str(_entries[_selected_index].get("save_name", ""))
		_show_pending_snapshot()
		return

	if _selected_index < 0 or _selected_index >= _entries.size():
		_preview_rect.texture = null
		_details_label.text = _text("ui.save_dialog.no_saves")
		return

	var entry := _entries[_selected_index]
	_preview_rect.texture = _load_save_preview_texture(str(entry.get("snapshot_path", "")))
	var lines: Array[String] = []
	lines.append(str(entry.get("save_name", "")))
	lines.append(_format_save_date(int(entry.get("saved_at_unix_time", 0))))
	if _preview_rect.texture == null:
		lines.append(_text("ui.save_dialog.no_snapshot"))
	_details_label.text = "\n".join(lines)
	_focus_selected_slot()


func _show_pending_snapshot() -> void:
	if _pending_snapshot != null:
		_preview_rect.texture = ImageTexture.create_from_image(_pending_snapshot)
	else:
		_preview_rect.texture = null
	_details_label.text = _text("ui.save_dialog.current_snapshot")


func _update_action_buttons() -> void:
	var has_selection := _selected_index >= 0 and _selected_index < _entries.size()
	_primary_button.disabled = _mode == MODE_LOAD and not has_selection
	_delete_button.disabled = not has_selection


func _configure_focus() -> void:
	_name_edit.focus_mode = Control.FOCUS_ALL
	_primary_button.focus_mode = Control.FOCUS_ALL
	_delete_button.focus_mode = Control.FOCUS_ALL
	_cancel_button.focus_mode = Control.FOCUS_ALL

	for index in range(_slot_buttons.size()):
		var button := _slot_buttons[index]
		button.focus_neighbor_top = _slot_buttons[maxi(index - 1, 0)].get_path()
		button.focus_neighbor_bottom = _slot_buttons[mini(index + 1, _slot_buttons.size() - 1)].get_path()
		button.focus_neighbor_right = _primary_button.get_path()

	if not _slot_buttons.is_empty():
		_primary_button.focus_neighbor_left = _slot_buttons[_selected_index if _selected_index >= 0 else 0].get_path()
		_delete_button.focus_neighbor_left = _slot_buttons[_selected_index if _selected_index >= 0 else 0].get_path()
		_cancel_button.focus_neighbor_left = _slot_buttons[_selected_index if _selected_index >= 0 else 0].get_path()

	_name_edit.focus_neighbor_bottom = _primary_button.get_path()
	_primary_button.focus_neighbor_top = _name_edit.get_path() if _mode == MODE_SAVE else _primary_button.get_path()
	_primary_button.focus_neighbor_left = _delete_button.get_path()
	_primary_button.focus_neighbor_right = _cancel_button.get_path()
	_delete_button.focus_neighbor_right = _primary_button.get_path()
	_cancel_button.focus_neighbor_left = _primary_button.get_path()


func _move_selection(direction: int) -> void:
	if _entries.is_empty():
		return
	if _selected_index < 0:
		_selected_index = 0
	else:
		_selected_index = clampi(_selected_index + direction, 0, _entries.size() - 1)
	_update_selection(_mode == MODE_SAVE)
	_focus_selected_slot()


func _focus_selected_slot() -> void:
	if _selected_index < 0 or _selected_index >= _slot_buttons.size():
		return
	var button := _slot_buttons[_selected_index]
	button.grab_focus()
	if _save_list_scroll.has_method("ensure_control_visible"):
		_save_list_scroll.call_deferred("ensure_control_visible", button)


func _on_primary_pressed() -> void:
	if _mode == MODE_SAVE:
		_root.hide()
		save_confirmed.emit(_name_edit.text.strip_edges())
		return

	var entry := _get_selected_entry()
	if entry.is_empty():
		return
	_root.hide()
	hide()
	load_confirmed.emit(entry)


func _on_cancel_pressed() -> void:
	hide()
	cancelled.emit()


func _on_delete_pressed() -> void:
	var entry := _get_selected_entry()
	if entry.is_empty():
		return
	var save_name := str(entry.get("save_name", ""))
	_show_message(
		_text("ui.save_dialog.delete_title"),
		_text("ui.save_dialog.delete_message", [save_name]),
		MESSAGE_DELETE,
		true,
		true
	)


func _on_name_submitted(_new_text: String) -> void:
	if _mode == MODE_SAVE:
		_on_primary_pressed()


func _on_message_ok_pressed() -> void:
	if _message_action == MESSAGE_DELETE:
		_message_root.hide()
		delete_requested.emit(_get_selected_entry())
		focus_first()
		return

	_message_root.hide()
	hide()
	result_closed.emit()


func _on_message_cancel_pressed() -> void:
	if _message_action == MESSAGE_RESULT:
		_on_message_ok_pressed()
		return
	_message_root.hide()
	focus_first()


func _show_message(title: String, message: String, action: StringName, show_cancel: bool, failed: bool) -> void:
	_message_action = action
	_message_title_label.text = title
	_message_title_label.add_theme_color_override("font_color", Color(0.92, 0.32, 0.24, 1.0) if failed else Color(0.94, 0.74, 0.42, 1.0))
	_message_label.text = message
	_message_cancel_button.visible = show_cancel
	_message_ok_button.text = _text("ui.save_dialog.delete_confirm" if action == MESSAGE_DELETE else "ui.save_dialog.close")
	_message_cancel_button.text = _text("ui.save_dialog.cancel")
	_message_root.show()
	_message_ok_button.call_deferred("grab_focus")


func _get_selected_entry() -> Dictionary:
	if _selected_index < 0 or _selected_index >= _entries.size():
		return {}
	return _entries[_selected_index].duplicate(true)


func _load_save_preview_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _format_save_date(unix_time: int) -> String:
	if unix_time <= 0:
		return _text("ui.save_dialog.unknown_date")
	var datetime := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [
		int(datetime.get("year", 0)),
		int(datetime.get("month", 0)),
		int(datetime.get("day", 0)),
		int(datetime.get("hour", 0)),
		int(datetime.get("minute", 0)),
	]


func _apply_localization() -> void:
	_title_label.text = _text("ui.save_dialog.load_title" if _mode == MODE_LOAD else "ui.save_dialog.title")
	_list_title_label.text = _text("ui.save_dialog.existing_saves")
	_preview_title_label.text = _text("ui.save_dialog.preview")
	_empty_label.text = _text("ui.save_dialog.no_saves")
	_name_label.text = _text("ui.save_dialog.name_label")
	_name_edit.placeholder_text = _text("ui.save_dialog.name_placeholder")
	_primary_button.text = _text("ui.save_dialog.load_confirm" if _mode == MODE_LOAD else "ui.save_dialog.confirm")
	_delete_button.text = _text("ui.save_dialog.delete")
	_cancel_button.text = _text("ui.save_dialog.cancel")


func _on_language_changed(_language: String) -> void:
	var entries := _entries.duplicate(true)
	_apply_localization()
	refresh_entries(entries, false)


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
