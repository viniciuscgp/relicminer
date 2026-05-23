extends CanvasLayer

@export var player_path: NodePath = NodePath("..")
@export var update_interval := 0.15
@export_group("World Time")
@export var show_world_time := true
@export var environment_path: NodePath
@export var show_weather_id := true

var _stats: Node
var _inventory: Node
var _environment: Node
var _localization_manager: Node
var _audio_manager: Node
var _elapsed := 0.0

var _time_panel: PanelContainer
var _time_label: Label
var _weather_label: Label
var _level_label: Label
var _hp_label: Label
var _energy_label: Label
var _hunger_label: Label
var _oxygen_label: Label
var _weight_label: Label
var _hp_bar: ProgressBar
var _energy_bar: ProgressBar
var _hunger_bar: ProgressBar
var _oxygen_bar: ProgressBar


func _ready() -> void:
	_audio_manager = get_node_or_null("/root/AudioManager")
	if _audio_manager != null and _audio_manager.has_signal("settings_changed"):
		_audio_manager.connect("settings_changed", _on_settings_changed)
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)
	_apply_saved_settings()
	_build_ui()
	_resolve_player_links()
	_resolve_environment()
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < update_interval:
		return

	_elapsed = 0.0
	_refresh()


func _resolve_player_links() -> void:
	var player := get_node_or_null(player_path)
	if player == null:
		player = get_parent()

	if player == null:
		return

	_stats = player.get_node_or_null("PlayerStats")
	_inventory = player.get_node_or_null("Inventory")

	if _stats != null and _stats.has_signal("changed"):
		_stats.connect("changed", _refresh)
	if _inventory != null and _inventory.has_signal("changed"):
		_inventory.connect("changed", _refresh)


func _resolve_environment() -> void:
	if not environment_path.is_empty():
		_environment = get_node_or_null(environment_path)
	if _environment == null:
		_environment = _find_environment(get_tree().current_scene)
	if _environment != null and _environment.has_signal("hour_changed"):
		_environment.connect("hour_changed", _on_environment_hour_changed)
	if _environment != null and _environment.has_signal("weather_changed"):
		_environment.connect("weather_changed", _on_environment_weather_changed)


func _find_environment(node: Node) -> Node:
	if node == null:
		return null
	if node.get("current_hour") != null and node.has_method("get_current_weather_id"):
		return node
	for child in node.get_children():
		var result := _find_environment(child)
		if result != null:
			return result
	return null


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	_time_panel = PanelContainer.new()
	_time_panel.name = "WorldTimePanel"
	_time_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_panel.custom_minimum_size = Vector2(164.0, 48.0)
	_time_panel.offset_left = 16.0
	_time_panel.offset_top = 184.0
	_time_panel.offset_right = 180.0
	_time_panel.offset_bottom = 232.0
	_time_panel.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(_time_panel)

	var time_margin := MarginContainer.new()
	time_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_margin.add_theme_constant_override("margin_left", 10)
	time_margin.add_theme_constant_override("margin_top", 8)
	time_margin.add_theme_constant_override("margin_right", 10)
	time_margin.add_theme_constant_override("margin_bottom", 8)
	_time_panel.add_child(time_margin)

	var time_rows := VBoxContainer.new()
	time_rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_rows.add_theme_constant_override("separation", 2)
	time_margin.add_child(time_rows)

	_time_label = Label.new()
	_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_time_label.add_theme_font_size_override("font_size", 14)
	time_rows.add_child(_time_label)

	_weather_label = Label.new()
	_weather_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weather_label.add_theme_font_size_override("font_size", 11)
	time_rows.add_child(_weather_label)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.custom_minimum_size = Vector2(315.0, 154.0)
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 331.0
	panel.offset_bottom = 170.0
	panel.add_theme_stylebox_override("panel", _make_panel_style())
	root.add_child(panel)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 6)
	margin.add_child(rows)

	_level_label = Label.new()
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_label.add_theme_font_size_override("font_size", 15)
	rows.add_child(_level_label)

	_hp_bar = _add_meter(rows, "HP", Color(0.78, 0.16, 0.14))
	_hp_label = _hp_bar.get_meta("label") as Label
	_energy_bar = _add_meter(rows, "ui.hud.energy", Color(0.9, 0.68, 0.18))
	_energy_label = _energy_bar.get_meta("label") as Label
	_hunger_bar = _add_meter(rows, "ui.hud.hunger", Color(0.33, 0.72, 0.33))
	_hunger_label = _hunger_bar.get_meta("label") as Label
	_oxygen_bar = _add_meter(rows, "ui.hud.breath", Color(0.23, 0.57, 0.86))
	_oxygen_label = _oxygen_bar.get_meta("label") as Label

	_weight_label = Label.new()
	_weight_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_weight_label.add_theme_font_size_override("font_size", 12)
	rows.add_child(_weight_label)


func _add_meter(parent: Control, title: String, color: Color) -> ProgressBar:
	var row := VBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)

	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = _meter_title(title)
	label.set_meta("title_key", title)
	label.add_theme_font_size_override("font_size", 12)
	row.add_child(label)

	var bar := ProgressBar.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.custom_minimum_size = Vector2(0.0, 9.0)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", _make_bar_style(Color(0.02, 0.025, 0.03, 0.9)))
	bar.add_theme_stylebox_override("fill", _make_bar_style(color))
	bar.set_meta("label", label)
	row.add_child(bar)
	return bar


func _make_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.04, 0.045, 0.84)
	style.border_color = Color(0.62, 0.5, 0.34, 0.65)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	return style


func _make_bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	return style


func _refresh() -> void:
	_update_world_time()
	if _stats == null:
		_level_label.text = "%s --" % _text("ui.hud.level")
		return

	_level_label.text = "%s %d  XP %d/%d" % [_text("ui.hud.level"), _stats.level, _stats.xp, int(_stats.call("get_xp_required_for_next_level"))]
	_set_meter(_hp_bar, _hp_label, "HP", _stats.current_hp, float(_stats.call("get_max_hp")))
	_set_meter(_energy_bar, _energy_label, "ui.hud.energy", _stats.current_energy, float(_stats.call("get_max_energy")))
	_set_meter(_hunger_bar, _hunger_label, "ui.hud.hunger", _stats.current_hunger, _stats.max_hunger)
	_set_meter(_oxygen_bar, _oxygen_label, "ui.hud.breath", _stats.current_oxygen, float(_stats.call("get_max_oxygen")))

	var carried: float = float(_stats.call("get_carried_weight_kg"))
	_weight_label.text = "%s %.1f/%.1f kg" % [_text("ui.hud.weight"), carried, float(_stats.call("get_absolute_weight_kg"))]


func _update_world_time() -> void:
	if _time_panel == null:
		return

	_time_panel.visible = show_world_time and _environment != null
	if not _time_panel.visible:
		return

	var hour := float(_environment.get("current_hour"))
	_time_label.text = "%s %s" % [_text("ui.hud.time"), _format_world_time(hour)]
	_weather_label.visible = show_weather_id
	if show_weather_id:
		var weather_id := ""
		if _environment.has_method("get_current_weather_id"):
			weather_id = str(_environment.call("get_current_weather_id"))
		_weather_label.text = "%s %s" % [_text("ui.hud.weather"), weather_id.capitalize()]


func _format_world_time(hour: float) -> String:
	var wrapped := fposmod(hour, 24.0)
	var total_minutes := int(round(wrapped * 60.0)) % (24 * 60)
	var hours := int(total_minutes / 60)
	var minutes := total_minutes % 60
	return "%02d:%02d" % [hours, minutes]


func _set_meter(bar: ProgressBar, label: Label, title: String, value: float, maximum: float) -> void:
	bar.max_value = maxf(1.0, maximum)
	bar.value = clampf(value, 0.0, bar.max_value)
	label.text = "%s %.0f/%.0f" % [_meter_title(title), value, maximum]


func _meter_title(title: String) -> String:
	if title.begins_with("ui."):
		return _text(title)
	return title


func _on_language_changed(_language: String) -> void:
	_refresh()


func _on_environment_hour_changed(_hour: float) -> void:
	_update_world_time()


func _on_environment_weather_changed(_weather_id: StringName) -> void:
	_update_world_time()


func _on_settings_changed() -> void:
	_apply_saved_settings()
	_update_world_time()


func _apply_saved_settings() -> void:
	if _audio_manager != null and _audio_manager.has_method("get_settings"):
		var settings: Dictionary = _audio_manager.call("get_settings")
		show_world_time = bool(settings.get("hud_show_world_time", show_world_time))


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
