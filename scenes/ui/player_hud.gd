extends CanvasLayer

@export var player_path: NodePath = NodePath("..")
@export var update_interval := 0.15

var _stats: Node
var _inventory: Node
var _elapsed := 0.0

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
	_build_ui()
	_resolve_player_links()
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


func _build_ui() -> void:
	var root := Control.new()
	root.name = "Root"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

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
	_energy_bar = _add_meter(rows, "Energia", Color(0.9, 0.68, 0.18))
	_energy_label = _energy_bar.get_meta("label") as Label
	_hunger_bar = _add_meter(rows, "Fome", Color(0.33, 0.72, 0.33))
	_hunger_label = _hunger_bar.get_meta("label") as Label
	_oxygen_bar = _add_meter(rows, "Folego", Color(0.23, 0.57, 0.86))
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
	label.text = title
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
	if _stats == null:
		_level_label.text = "Level --"
		return

	_level_label.text = "Level %d  XP %d/%d" % [_stats.level, _stats.xp, int(_stats.call("get_xp_required_for_next_level"))]
	_set_meter(_hp_bar, _hp_label, "HP", _stats.current_hp, float(_stats.call("get_max_hp")))
	_set_meter(_energy_bar, _energy_label, "Energia", _stats.current_energy, float(_stats.call("get_max_energy")))
	_set_meter(_hunger_bar, _hunger_label, "Fome", _stats.current_hunger, _stats.max_hunger)
	_set_meter(_oxygen_bar, _oxygen_label, "Folego", _stats.current_oxygen, float(_stats.call("get_max_oxygen")))

	var carried: float = float(_stats.call("get_carried_weight_kg"))
	_weight_label.text = "Peso %.1f/%.1f kg" % [carried, float(_stats.call("get_absolute_weight_kg"))]


func _set_meter(bar: ProgressBar, label: Label, title: String, value: float, maximum: float) -> void:
	bar.max_value = maxf(1.0, maximum)
	bar.value = clampf(value, 0.0, bar.max_value)
	label.text = "%s %.0f/%.0f" % [title, value, maximum]
