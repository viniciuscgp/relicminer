extends CanvasLayer

signal close_requested

@export var player_path: NodePath = NodePath("../..")
@export var visible_slot_count := 30

@onready var title_label: Label = %TitleLabel
@onready var weight_label: Label = %WeightLabel
@onready var weight_help_label: Label = %WeightHelpLabel
@onready var slot_grid: GridContainer = %SlotGrid
@onready var empty_label: Label = %EmptyLabel
@onready var close_button: Button = %CloseButton

var _inventory: Node
var _stats: Node
var _slot_style: StyleBox


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_slot_style = _find_slot_style()
	close_button.pressed.connect(_on_close_pressed)
	close_button.focus_mode = Control.FOCUS_ALL
	_resolve_player_links()
	refresh()


func focus_first() -> void:
	close_button.grab_focus()


func refresh() -> void:
	_clear_slots()

	if _inventory == null:
		title_label.text = "Inventario"
		weight_label.text = ""
		weight_help_label.text = ""
		empty_label.show()
		empty_label.text = "Inventario nao encontrado."
		return

	title_label.text = str(_inventory.get("display_name"))
	_update_weight()

	var slots: Array = _inventory.get("slots")
	empty_label.visible = slots.is_empty()
	var slot_count: int = max(visible_slot_count, int(_inventory.get("capacity_slots")))
	for index in range(slot_count):
		var stack: Resource = slots[index] if index < slots.size() else null
		slot_grid.add_child(_make_slot(stack))


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
		weight_help_label.text = "Peso atual: %.1f/%.1f\nSe o peso exceder o limite maximo, voce nao conseguira andar ate descartar itens." % [carried, maximum]
		return

	if _inventory != null and _inventory.has_method("get_total_weight"):
		var carried := float(_inventory.call("get_total_weight"))
		weight_label.text = "Peso %.1f kg" % carried
		weight_help_label.text = "Peso atual: %.1f kg" % carried


func _clear_slots() -> void:
	for child in slot_grid.get_children():
		child.free()


func _make_slot(stack: Resource) -> Control:
	var slot := PanelContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(96, 78)
	if _slot_style != null:
		slot.add_theme_stylebox_override("panel", _slot_style)

	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 4)
	slot.add_child(margin)

	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	name_label.text = _get_item_name(item)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 11)
	content.add_child(name_label)

	var amount_label := Label.new()
	amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	amount_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	amount_label.text = "x%d" % amount
	amount_label.add_theme_font_size_override("font_size", 13)
	content.add_child(amount_label)

	return slot


func _get_item_name(item: Resource) -> String:
	if item == null:
		return "Item"

	var display_name := str(item.get("display_name"))
	if not display_name.is_empty():
		return display_name
	return str(item.get("id"))


func _on_close_pressed() -> void:
	close_requested.emit()


func _find_slot_style() -> StyleBox:
	var equipment_slot := get_node_or_null("Root/Center/Panel/Margin/Content/Body/EquipmentPanel/EquipmentMargin/EquipmentContent/EquipmentGrid/HeadSlot") as PanelContainer
	if equipment_slot == null:
		return null
	return equipment_slot.get_theme_stylebox("panel").duplicate()
