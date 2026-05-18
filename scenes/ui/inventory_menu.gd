extends CanvasLayer

signal close_requested

const KIND_NAMES := {
	0: "Comum",
	1: "Moeda",
	2: "Arma",
	3: "Ferramenta",
	4: "Luz",
	5: "Comida",
	6: "Pocao",
	7: "Chave",
	8: "Material",
	9: "Armadura",
}

@export var player_path: NodePath = NodePath("../..")
@export var visible_slot_count := 30
@export var slot_columns := 5
@export var slot_size := Vector2(68, 54)

@onready var title_label: Label = %TitleLabel
@onready var weight_label: Label = %WeightLabel
@onready var weight_help_label: Label = %WeightHelpLabel
@onready var slot_grid: GridContainer = %SlotGrid
@onready var empty_label: Label = %EmptyLabel
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_detail_label: Label = %ItemDetailLabel
@onready var close_button: Button = %CloseButton

var _inventory: Node
var _stats: Node
var _slot_style: StyleBox
var _slot_focus_style: StyleBox
var _slot_selected_style: StyleBox
var _slot_buttons: Array[Button] = []
var _selected_index := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_prepare_slot_styles()
	close_button.pressed.connect(_on_close_pressed)
	close_button.focus_mode = Control.FOCUS_ALL
	_resolve_player_links()
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("use_item"):
		_use_selected_item()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item"):
		_drop_selected_item()
		get_viewport().set_input_as_handled()


func focus_first() -> void:
	var first_slot := _find_first_focus_slot()
	if first_slot != null:
		first_slot.grab_focus()
		return
	close_button.grab_focus()


func refresh() -> void:
	var preferred_index := _selected_index
	_clear_slots()

	if _inventory == null:
		title_label.text = "Inventario"
		weight_label.text = ""
		weight_help_label.text = ""
		empty_label.show()
		empty_label.text = "Inventario nao encontrado."
		_select_slot(-1)
		return

	title_label.text = str(_inventory.get("display_name"))
	_update_weight()

	var slots: Array = _inventory.get("slots")
	empty_label.visible = slots.is_empty()
	var slot_count: int = max(visible_slot_count, int(_inventory.get("capacity_slots")))
	slot_grid.columns = max(1, slot_columns)
	for index in range(slot_count):
		var stack: Resource = slots[index] if index < slots.size() else null
		var slot := _make_slot(stack, index)
		_slot_buttons.append(slot)
		slot_grid.add_child(slot)

	if preferred_index < 0 or preferred_index >= slot_count:
		preferred_index = _find_first_non_empty_index()
	if preferred_index < 0 and slot_count > 0:
		preferred_index = 0
	_select_slot(preferred_index)
	_configure_slot_focus()


func _resolve_player_links() -> void:
	var player := get_node_or_null(player_path)
	if player == null:
		player = get_parent()
	if player == null:
		return

	_inventory = player.get_node_or_null("Inventory")
	_stats = player.get_node_or_null("PlayerStats")

	if _inventory != null and _inventory.has_signal("changed"):
		_inventory.connect("changed", refresh)
	if _stats != null and _stats.has_signal("changed"):
		_stats.connect("changed", _update_weight)


func _update_weight() -> void:
	if _stats != null and _stats.has_method("get_carried_weight_kg"):
		var carried := float(_stats.call("get_carried_weight_kg"))
		var maximum := float(_stats.call("get_absolute_weight_kg"))
		weight_label.text = "Peso %.0f/%.0f" % [carried, maximum]
		weight_help_label.text = "Peso atual: %.1f/%.1f" % [carried, maximum]
		return

	if _inventory != null and _inventory.has_method("get_total_weight"):
		var carried := float(_inventory.call("get_total_weight"))
		weight_label.text = "Peso %.1f kg" % carried
		weight_help_label.text = "Peso atual: %.1f kg" % carried


func _clear_slots() -> void:
	_slot_buttons.clear()
	for child in slot_grid.get_children():
		child.free()


func _make_slot(stack: Resource, index: int) -> Button:
	var slot := Button.new()
	slot.focus_mode = Control.FOCUS_ALL
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	slot.custom_minimum_size = slot_size
	slot.text = ""
	if _slot_style != null:
		slot.add_theme_stylebox_override("normal", _slot_style)
		slot.add_theme_stylebox_override("hover", _slot_style)
		slot.add_theme_stylebox_override("pressed", _slot_style)
	if _slot_focus_style != null:
		slot.add_theme_stylebox_override("focus", _slot_focus_style)
	slot.focus_entered.connect(_select_slot.bind(index))
	slot.pressed.connect(_on_slot_pressed.bind(index, slot))

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 4)
	slot.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 1)
	margin.add_child(content)

	if stack == null or bool(stack.call("is_empty")):
		var empty := Label.new()
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE
		empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
		empty.text = "<>"
		empty.modulate = Color(0.32, 0.27, 0.18, 0.8)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		content.add_child(empty)
		return slot

	var item: Resource = stack.get("item")
	var amount := int(stack.get("amount"))
	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.custom_minimum_size = Vector2(0, 30)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = _get_item_name(item)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.clip_text = true
	name_label.max_lines_visible = 2
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	content.add_child(name_label)

	var amount_label := Label.new()
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount_label.text = "x%d" % amount
	amount_label.add_theme_font_size_override("font_size", 11)
	content.add_child(amount_label)

	return slot


func _on_slot_pressed(index: int, slot: Button) -> void:
	slot.grab_focus()
	_select_slot(index)


func _configure_slot_focus() -> void:
	if _slot_buttons.is_empty():
		return

	var columns: int = max(1, slot_grid.columns)
	for index in range(_slot_buttons.size()):
		var slot := _slot_buttons[index]
		var row: int = floori(float(index) / float(columns))
		var col: int = index % columns
		var last_row: int = floori(float(_slot_buttons.size() - 1) / float(columns))
		var right_index: int = mini(index + 1, _slot_buttons.size() - 1)
		var left_index: int = maxi(index - 1, 0)
		var down_index: int = mini(index + columns, _slot_buttons.size() - 1)
		var up_index: int = maxi(index - columns, 0)

		slot.focus_neighbor_right = _slot_buttons[right_index].get_path()

		if col == 0:
			slot.focus_neighbor_left = slot.get_path()
		else:
			slot.focus_neighbor_left = _slot_buttons[left_index].get_path()

		slot.focus_neighbor_bottom = _slot_buttons[down_index].get_path()

		if row == 0:
			slot.focus_neighbor_top = close_button.get_path()
		else:
			slot.focus_neighbor_top = _slot_buttons[up_index].get_path()

	var selected_index: int = clampi(_selected_index, 0, _slot_buttons.size() - 1)
	close_button.focus_neighbor_bottom = _slot_buttons[selected_index].get_path()


func _select_slot(index: int) -> void:
	_selected_index = index
	_update_slot_selection_styles()

	var stack := _get_stack_at(index)
	if stack == null or bool(stack.call("is_empty")):
		item_name_label.text = "Espaco vazio"
		item_detail_label.text = "Nenhum item neste slot."
		return

	var item: Resource = stack.get("item")
	item_name_label.text = _get_item_name(item)
	item_detail_label.text = _build_item_details(stack, item)


func _update_slot_selection_styles() -> void:
	for index in range(_slot_buttons.size()):
		var selected := index == _selected_index
		_apply_slot_style(_slot_buttons[index], selected)


func _apply_slot_style(slot: Button, selected: bool) -> void:
	var style := _slot_selected_style if selected and _slot_selected_style != null else _slot_style
	if style == null:
		return

	slot.add_theme_stylebox_override("normal", style)
	slot.add_theme_stylebox_override("hover", style)
	slot.add_theme_stylebox_override("pressed", style)


func _get_stack_at(index: int) -> Resource:
	if _inventory == null or index < 0:
		return null

	var slots: Array = _inventory.get("slots")
	if index >= slots.size():
		return null
	return slots[index]


func _find_first_non_empty_index() -> int:
	if _inventory == null:
		return -1

	var slots: Array = _inventory.get("slots")
	for index in range(slots.size()):
		var stack: Resource = slots[index]
		if stack != null and not bool(stack.call("is_empty")):
			return index
	return -1


func _find_first_focus_slot() -> Button:
	var non_empty_index := _find_first_non_empty_index()
	if non_empty_index >= 0 and non_empty_index < _slot_buttons.size():
		return _slot_buttons[non_empty_index]

	if not _slot_buttons.is_empty():
		return _slot_buttons[0]
	return null


func _get_item_name(item: Resource) -> String:
	if item == null:
		return "Item"

	var display_name := str(item.get("display_name"))
	if not display_name.is_empty():
		return display_name
	return str(item.get("id"))


func _build_item_details(stack: Resource, item: Resource) -> String:
	if item == null:
		return "Item sem definicao."

	var lines: Array[String] = []
	var description := str(item.get("description"))
	if not description.is_empty():
		lines.append(description)

	var amount := int(stack.get("amount"))
	var unit_weight := float(item.get("weight_kg"))
	lines.append("Tipo: %s" % _get_kind_name(item))
	lines.append("Quantidade: %d" % amount)
	lines.append("Peso: %.2f kg cada | %.2f kg total" % [unit_weight, unit_weight * amount])

	var buy_price := int(item.get("buy_price"))
	var sell_price := int(item.get("sell_price"))
	if buy_price > 0 or sell_price > 0:
		lines.append("Valor: compra %d | venda %d" % [buy_price, sell_price])

	if stack.has_method("has_durability") and bool(stack.call("has_durability")):
		var current := float(stack.call("get_durability"))
		var maximum := float(item.get("durability_max"))
		lines.append("Durabilidade: %.0f/%.0f" % [current, maximum])

	var item_id := str(item.get("id"))
	if not item_id.is_empty():
		lines.append("ID: %s" % item_id)
	return "\n".join(lines)


func _get_kind_name(item: Resource) -> String:
	var kind := int(item.get("kind"))
	return KIND_NAMES.get(kind, "Item")


func _use_selected_item() -> void:
	_consume_selected_item()


func _drop_selected_item() -> void:
	_consume_selected_item()


func _consume_selected_item() -> void:
	var stack := _get_stack_at(_selected_index)
	if stack == null or bool(stack.call("is_empty")):
		return

	var item: Resource = stack.get("item")
	if item == null or _inventory == null or not _inventory.has_method("remove_item"):
		return

	var removed := int(_inventory.call("remove_item", item.get("id"), 1))
	if removed > 0:
		call_deferred("focus_first")


func _on_close_pressed() -> void:
	close_requested.emit()


func _prepare_slot_styles() -> void:
	var equipment_slot := get_node_or_null("Root/Center/Panel/Margin/Content/Body/EquipmentPanel/EquipmentMargin/EquipmentContent/EquipmentGrid/HeadSlot") as PanelContainer
	if equipment_slot == null:
		return

	_slot_style = equipment_slot.get_theme_stylebox("panel").duplicate()
	_slot_focus_style = _slot_style.duplicate()
	if _slot_focus_style is StyleBoxFlat:
		_slot_focus_style.border_color = Color(0.95, 0.68, 0.22, 1.0)
		_slot_focus_style.border_width_left = 2
		_slot_focus_style.border_width_top = 2
		_slot_focus_style.border_width_right = 2
		_slot_focus_style.border_width_bottom = 2
	_slot_selected_style = _slot_style.duplicate()
	if _slot_selected_style is StyleBoxFlat:
		_slot_selected_style.bg_color = Color(0.08, 0.055, 0.025, 0.98)
		_slot_selected_style.border_color = Color(0.95, 0.68, 0.22, 1.0)
		_slot_selected_style.border_width_left = 2
		_slot_selected_style.border_width_top = 2
		_slot_selected_style.border_width_right = 2
		_slot_selected_style.border_width_bottom = 2
