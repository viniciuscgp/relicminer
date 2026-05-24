extends CanvasLayer

@export var player_path: NodePath = NodePath("..")
@export var update_interval := 0.15
@export var underwater_environment_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D/UnderwaterEnvironment")
@export_group("World Time")
@export var show_world_time := true
@export var environment_path: NodePath
@export var clock_margin := Vector2(56.0, 56.0)

var _stats: Node
var _inventory: Node
var _environment: Node
var _underwater_environment: Node
var _localization_manager: Node
var _audio_manager: Node
var _elapsed := 0.0

var _clock: Node2D
var _hp_label: Label
var _energy_label: Label
var _hunger_label: Label
var _hp_bar: Range
var _energy_bar: Range
var _hunger_bar: Range


func _ready() -> void:
	_audio_manager = get_node_or_null("/root/AudioManager")
	if _audio_manager != null and _audio_manager.has_signal("settings_changed"):
		_audio_manager.connect("settings_changed", _on_settings_changed)
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)
	_apply_saved_settings()
	_resolve_clock()
	_resolve_status_ui()
	_resolve_player_links()
	_resolve_environment()
	_refresh()


func _process(delta: float) -> void:
	_position_clock()
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
	_underwater_environment = get_node_or_null(underwater_environment_path)
	if _underwater_environment == null:
		_underwater_environment = player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D/UnderwaterEnvironment")

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


func _resolve_clock() -> void:
	_clock = get_node_or_null("Clock") as Node2D


func _resolve_status_ui() -> void:
	_hp_label = _get_status_caption("HP")
	_hp_bar = _get_status_value("HP")
	_hunger_label = _get_status_caption("Hunger")
	_hunger_bar = _get_status_value("Hunger")
	_energy_label = _get_status_caption("Energy")
	_energy_bar = _get_status_value("Energy")
	_configure_status_bar(_hp_bar, Color(0.78, 0.12, 0.1, 0.82))
	_configure_status_bar(_hunger_bar, Color(0.24, 0.68, 0.24, 0.82))
	_configure_status_bar(_energy_bar, Color(0.95, 0.68, 0.16, 0.82))


func _get_status_caption(status_name: String) -> Label:
	return get_node_or_null("%s/Caption" % status_name) as Label


func _get_status_value(status_name: String) -> Range:
	var value := get_node_or_null("%s/Value" % status_name) as Range
	if value == null:
		value = get_node_or_null("%s/value" % status_name) as Range
	return value


func _configure_status_bar(bar: Range, color: Color) -> void:
	if bar == null:
		return

	bar.min_value = 0.0
	bar.max_value = 100.0
	bar.value = 100.0
	bar.set_meta("fill_color", color)

	var texture_bar := bar as TextureProgressBar
	if texture_bar != null:
		texture_bar.texture_progress = _make_status_fill_texture()
		texture_bar.tint_progress = color

	var control := bar as Control
	if control == null:
		return

	var fill_parent := control.get_parent()
	if fill_parent == null:
		return

	var fill := fill_parent.get_node_or_null("%sRuntimeFill" % control.name) as ColorRect
	if fill == null:
		fill = ColorRect.new()
		fill.name = "%sRuntimeFill" % control.name
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fill.set_anchors_preset(Control.PRESET_TOP_LEFT)
		fill_parent.add_child(fill)
	fill.color = color
	fill.z_index = control.z_index + 1
	fill.position = control.position
	fill.size = control.size


func _make_status_fill_texture() -> Texture2D:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	return ImageTexture.create_from_image(image)


func _refresh() -> void:
	_update_world_time()
	if _stats == null:
		_set_meter(_hp_bar, _hp_label, "HP", 0.0, 1.0)
		_set_meter(_energy_bar, _energy_label, "ui.hud.energy", 0.0, 1.0)
		_set_meter(_hunger_bar, _hunger_label, "ui.hud.hunger", 0.0, 1.0)
		return

	_set_meter(_hp_bar, _hp_label, "HP", _stats.current_hp, float(_stats.call("get_max_hp")))
	_set_meter(_energy_bar, _energy_label, "ui.hud.energy", _stats.current_energy, float(_stats.call("get_max_energy")))
	_set_meter(_hunger_bar, _hunger_label, "ui.hud.hunger", _stats.current_hunger, _stats.max_hunger)


func _update_world_time() -> void:
	if _clock == null:
		return

	_clock.visible = show_world_time and _environment != null
	if not _clock.visible:
		return

	var hour := float(_environment.get("current_hour"))
	if _clock.has_method("set_current_hour"):
		_clock.call("set_current_hour", hour)
	_position_clock()


func _position_clock() -> void:
	if _clock == null:
		return

	var viewport_size := get_viewport().get_visible_rect().size
	_clock.position = Vector2(viewport_size.x - clock_margin.x, viewport_size.y - clock_margin.y)


func _set_meter(bar: Range, label: Label, title: String, value: float, maximum: float) -> void:
	if bar != null:
		bar.max_value = maxf(1.0, maximum)
		bar.value = clampf(value, 0.0, bar.max_value)
		_update_status_fill(bar)
	if label == null:
		return
	label.text = _meter_title(title)


func _update_status_fill(bar: Range) -> void:
	var control := bar as Control
	if control == null:
		return

	var fill_parent := control.get_parent()
	if fill_parent == null:
		return

	var fill := fill_parent.get_node_or_null("%sRuntimeFill" % control.name) as ColorRect
	if fill == null:
		return

	var ratio := 0.0
	if bar.max_value > bar.min_value:
		ratio = clampf((bar.value - bar.min_value) / (bar.max_value - bar.min_value), 0.0, 1.0)
	fill.position = control.position
	fill.size = Vector2(control.size.x * ratio, control.size.y)


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
