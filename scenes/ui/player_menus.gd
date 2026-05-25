extends Node

## Controls whether pause when inventory open is enabled.
@export var pause_when_inventory_open := true
## Scene file path used for main menu scene.
@export_file("*.tscn") var main_menu_scene_path := "res://scenes/ui/main_menu.tscn"

@onready var pause_menu: CanvasLayer = %PauseMenu
@onready var inventory_menu: CanvasLayer = %InventoryMenu
@onready var settings_menu: CanvasLayer = %SettingsMenu

const SAVE_DIALOG_MODE_SAVE := &"save"
const SAVE_DIALOG_MODE_LOAD := &"load"

var _return_to_pause_after_inventory := false
var _open_container: Node
var _save_load_dialog: ConfirmationDialog
var _save_slot_list: ItemList
var _save_name_row: HBoxContainer
var _save_name_edit: LineEdit
var _save_preview_rect: TextureRect
var _save_details_label: Label
var _save_result_dialog: AcceptDialog
var _save_entries: Array[Dictionary] = []
var _save_load_mode := SAVE_DIALOG_MODE_SAVE
var _pending_save_snapshot: Image
var _localization_manager: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	pause_menu.hide()
	inventory_menu.hide()
	settings_menu.hide()

	pause_menu.resume_requested.connect(close_all)
	pause_menu.inventory_requested.connect(_open_inventory_from_pause)
	pause_menu.settings_requested.connect(open_settings)
	pause_menu.save_requested.connect(save_game)
	pause_menu.load_requested.connect(load_game)
	pause_menu.abandon_requested.connect(abandon_game)
	inventory_menu.close_requested.connect(_on_inventory_close_requested)
	settings_menu.close_requested.connect(_on_settings_close_requested)
	_build_save_dialogs()


func _input(event: InputEvent) -> void:
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
	_open_save_load_dialog(SAVE_DIALOG_MODE_SAVE)


func load_game() -> void:
	_open_save_load_dialog(SAVE_DIALOG_MODE_LOAD)


func _build_save_dialogs() -> void:
	_save_load_dialog = ConfirmationDialog.new()
	_save_load_dialog.name = "SaveLoadDialog"
	_save_load_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_load_dialog.exclusive = true
	_save_load_dialog.confirmed.connect(_on_save_load_confirmed)
	add_child(_save_load_dialog)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	_save_load_dialog.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(scroll)

	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)

	var list_column := VBoxContainer.new()
	list_column.custom_minimum_size = Vector2(230.0, 0.0)
	list_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_column.add_theme_constant_override("separation", 8)
	content.add_child(list_column)

	var list_label := Label.new()
	list_label.text = _text("ui.save_dialog.existing_saves")
	list_column.add_child(list_label)

	_save_slot_list = ItemList.new()
	_save_slot_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_save_slot_list.select_mode = ItemList.SELECT_SINGLE
	_save_slot_list.item_selected.connect(_on_save_slot_selected)
	_save_slot_list.item_activated.connect(_on_save_slot_activated)
	list_column.add_child(_save_slot_list)

	var details_column := VBoxContainer.new()
	details_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details_column.add_theme_constant_override("separation", 10)
	content.add_child(details_column)

	_save_preview_rect = TextureRect.new()
	_save_preview_rect.custom_minimum_size = Vector2(360.0, 202.0)
	_save_preview_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_save_preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_save_preview_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_column.add_child(_save_preview_rect)

	_save_details_label = Label.new()
	_save_details_label.custom_minimum_size = Vector2(0.0, 54.0)
	_save_details_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details_column.add_child(_save_details_label)

	_save_name_row = HBoxContainer.new()
	_save_name_row.add_theme_constant_override("separation", 8)
	details_column.add_child(_save_name_row)

	var name_label := Label.new()
	name_label.text = _text("ui.save_dialog.name_label")
	name_label.custom_minimum_size = Vector2(92.0, 0.0)
	_save_name_row.add_child(name_label)

	_save_name_edit = LineEdit.new()
	_save_name_edit.placeholder_text = _text("ui.save_dialog.name_placeholder")
	_save_name_edit.select_all_on_focus = true
	_save_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_name_edit.text_submitted.connect(_on_save_name_submitted)
	_save_name_row.add_child(_save_name_edit)

	_save_result_dialog = AcceptDialog.new()
	_save_result_dialog.name = "SaveResultDialog"
	_save_result_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_save_result_dialog.exclusive = true
	add_child(_save_result_dialog)


func _open_save_load_dialog(mode: StringName) -> void:
	if _save_load_dialog == null or _save_name_edit == null:
		_build_save_dialogs()
	_save_load_mode = mode
	var is_load := _save_load_mode == SAVE_DIALOG_MODE_LOAD
	_save_load_dialog.title = _text("ui.save_dialog.load_title" if is_load else "ui.save_dialog.title")
	_save_load_dialog.get_ok_button().text = _text("ui.save_dialog.load_confirm" if is_load else "ui.save_dialog.confirm")
	var cancel_button := _save_load_dialog.get_cancel_button()
	if cancel_button != null:
		cancel_button.text = _text("ui.save_dialog.cancel")
	if _save_name_row != null:
		_save_name_row.visible = not is_load

	if is_load:
		_pending_save_snapshot = null
	else:
		_pending_save_snapshot = await _capture_save_snapshot()

	_refresh_save_entries(false)
	_save_load_dialog.get_ok_button().disabled = is_load and _save_entries.is_empty()
	if not is_load:
		var save_manager := get_node_or_null("/root/SaveManager")
		if save_manager != null and save_manager.has_method("suggest_save_name"):
			_save_name_edit.text = str(save_manager.call("suggest_save_name"))
		else:
			_save_name_edit.text = _fallback_save_name()
		_show_pending_save_snapshot()

	_save_load_dialog.popup_centered(_get_save_dialog_size())
	if is_load:
		_save_slot_list.call_deferred("grab_focus")
	else:
		_save_name_edit.call_deferred("grab_focus")
		_save_name_edit.call_deferred("select_all")


func _on_save_name_submitted(_new_text: String) -> void:
	if _save_load_mode == SAVE_DIALOG_MODE_SAVE:
		if _save_load_dialog != null:
			_save_load_dialog.hide()
		_confirm_save_game()


func _on_save_load_confirmed() -> void:
	if _save_load_mode == SAVE_DIALOG_MODE_LOAD:
		_confirm_load_game()
		return
	_confirm_save_game()


func _confirm_save_game() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("save_current_game"):
		_show_save_result(_text("ui.save_dialog.failed_no_manager"), true)
		return

	var save_name := _save_name_edit.text.strip_edges() if _save_name_edit != null else ""
	if save_name.is_empty():
		if save_manager.has_method("suggest_save_name"):
			save_name = str(save_manager.call("suggest_save_name"))
		else:
			save_name = _fallback_save_name()

	var snapshot := _pending_save_snapshot
	if snapshot == null:
		snapshot = await _capture_save_snapshot()
	var saved := bool(save_manager.call("save_current_game", save_name, snapshot))
	if saved:
		var message: String = _text("ui.save_dialog.saved", [save_name])
		_show_save_result(message, false)
		_pending_save_snapshot = null
		return

	_show_save_result(_text("ui.save_dialog.failed"), true)


func _confirm_load_game() -> void:
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager == null or not save_manager.has_method("load_game_scene_from_path"):
		_show_save_result(_text("ui.save_dialog.failed_no_manager"), true)
		return

	var entry := _get_selected_save_entry()
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
	pause_menu.show()
	_show_save_result(_text("ui.save_dialog.load_failed"), true)


func _refresh_save_entries(use_selected_name: bool) -> void:
	_save_entries.clear()
	_save_slot_list.clear()
	var save_manager := get_node_or_null("/root/SaveManager")
	if save_manager != null and save_manager.has_method("get_save_entries"):
		var entries: Variant = save_manager.call("get_save_entries")
		if entries is Array:
			for entry in entries:
				if entry is Dictionary:
					_save_entries.append(entry)

	if _save_entries.is_empty():
		_save_slot_list.add_item(_text("ui.save_dialog.no_saves"))
		_save_slot_list.set_item_disabled(0, true)
		if _save_load_mode == SAVE_DIALOG_MODE_SAVE:
			_show_pending_save_snapshot()
		else:
			_save_preview_rect.texture = null
			_save_details_label.text = _text("ui.save_dialog.no_saves")
		return

	for entry in _save_entries:
		var save_name := str(entry.get("save_name", ""))
		var label := save_name
		var date_text := _format_save_date(int(entry.get("saved_at_unix_time", 0)))
		if not date_text.is_empty():
			label += " - %s" % date_text
		var index := _save_slot_list.add_item(label)
		_save_slot_list.set_item_metadata(index, entry)

	_save_slot_list.select(0)
	_update_selected_save_preview(0, use_selected_name)


func _on_save_slot_selected(index: int) -> void:
	_update_selected_save_preview(index, true)


func _on_save_slot_activated(index: int) -> void:
	_update_selected_save_preview(index, true)
	if _save_load_mode == SAVE_DIALOG_MODE_LOAD:
		if _save_load_dialog != null:
			_save_load_dialog.hide()
		_confirm_load_game()


func _update_selected_save_preview(index: int, use_selected_name: bool) -> void:
	if index < 0 or index >= _save_slot_list.get_item_count():
		return
	var metadata: Variant = _save_slot_list.get_item_metadata(index)
	if not metadata is Dictionary:
		return

	var entry := metadata as Dictionary
	if use_selected_name and _save_load_mode == SAVE_DIALOG_MODE_SAVE and _save_name_edit != null:
		_save_name_edit.text = str(entry.get("save_name", ""))
		_show_pending_save_snapshot()
		return

	var snapshot_path := str(entry.get("snapshot_path", ""))
	_save_preview_rect.texture = _load_save_preview_texture(snapshot_path)

	var lines: Array[String] = []
	lines.append("%s: %s" % [_text("ui.save_dialog.name"), str(entry.get("save_name", ""))])
	lines.append("%s: %s" % [_text("ui.save_dialog.date"), _format_save_date(int(entry.get("saved_at_unix_time", 0)))])
	if _save_preview_rect.texture == null:
		lines.append(_text("ui.save_dialog.no_snapshot"))
	_save_details_label.text = "\n".join(lines)


func _get_selected_save_entry() -> Dictionary:
	if _save_slot_list == null:
		return {}
	var selected := _save_slot_list.get_selected_items()
	if selected.is_empty():
		return {}
	var metadata: Variant = _save_slot_list.get_item_metadata(selected[0])
	if metadata is Dictionary:
		return metadata
	return {}


func _load_save_preview_texture(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


func _show_pending_save_snapshot() -> void:
	if _pending_save_snapshot != null:
		_save_preview_rect.texture = ImageTexture.create_from_image(_pending_save_snapshot)
	else:
		_save_preview_rect.texture = null
	_save_details_label.text = _text("ui.save_dialog.current_snapshot")


func _capture_save_snapshot() -> Image:
	var pause_was_visible := pause_menu.visible
	if _save_load_dialog != null:
		_save_load_dialog.hide()
	if pause_was_visible:
		pause_menu.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if pause_was_visible:
		pause_menu.show()
	return image


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


func _get_save_dialog_size() -> Vector2i:
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var available_width: float = max(120.0, viewport_size.x - 40.0)
	var available_height: float = max(140.0, viewport_size.y - 120.0)
	var width := int(min(760.0, available_width))
	var height := int(min(420.0, available_height))
	return Vector2i(width, height)


func _show_save_result(message: String, failed: bool) -> void:
	if _save_result_dialog == null:
		_build_save_dialogs()
	var failed_title_key := "ui.save_dialog.load_failed_title" if _save_load_mode == SAVE_DIALOG_MODE_LOAD else "ui.save_dialog.failed_title"
	_save_result_dialog.title = _text(failed_title_key if failed else "ui.save_dialog.saved_title")
	_save_result_dialog.dialog_text = message
	_save_result_dialog.get_ok_button().text = _text("ui.save_dialog.close")
	_save_result_dialog.popup_centered()


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
