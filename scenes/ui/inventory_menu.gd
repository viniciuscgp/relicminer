extends CanvasLayer

signal close_requested

const ItemIconRenderer := preload("res://scripts/systems/items/item_icon_renderer.gd")

const KIND_KEYS := {
	0: "item.kind.misc",
	1: "item.kind.currency",
	2: "item.kind.weapon",
	3: "item.kind.tool",
	4: "item.kind.light",
	5: "item.kind.food",
	6: "item.kind.potion",
	7: "item.kind.key",
	8: "item.kind.material",
	9: "item.kind.armor",
}
const KIND_FOOD := 5
const KIND_POTION := 6

@export var actor_path: NodePath = NodePath("../..")
@export var visible_slot_count := 30
@export var slot_columns := 5
@export var slot_size := Vector2(72, 64)

@onready var title_label: Label = %TitleLabel
@onready var weight_label: Label = %WeightLabel
@onready var weight_help_label: Label = %WeightHelpLabel
@onready var equipment_title: Label = %EquipmentTitle
@onready var inventory_title: Label = %InventoryTitle
@onready var head_label: Label = %HeadLabel
@onready var right_hand_label: Label = %RightHandLabel
@onready var torso_label: Label = %TorsoLabel
@onready var left_hand_label: Label = %LeftHandLabel
@onready var legs_label: Label = %LegsLabel
@onready var accessory_label: Label = %AccessoryLabel
@onready var feet_label: Label = %FeetLabel
@onready var accessory_2_label: Label = %Accessory2Label
@onready var slot_grid: GridContainer = %SlotGrid
@onready var empty_label: Label = %EmptyLabel
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_detail_label: Label = %ItemDetailLabel
@onready var close_button: Button = %CloseButton

var _inventory: Node
var _actor_inventory: Node
var _inventory_override: Node
var _inventory_dropper: Node
var _equipment: Node
var _stats: Node
var _slot_style: StyleBox
var _slot_focus_style: StyleBox
var _slot_selected_style: StyleBox
var _slot_buttons: Array[Button] = []
var _selected_index := -1
var _localization_manager: Node
var _equipment_icon_rects := {}
var _equipment_empty_icons := {}
var _equipment_slot_labels := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	_localization_manager = get_node_or_null("/root/LocalizationManager")
	if _localization_manager != null and _localization_manager.has_signal("language_changed"):
		_localization_manager.connect("language_changed", _on_language_changed)
	_prepare_slot_styles()
	close_button.pressed.connect(_on_close_pressed)
	close_button.focus_mode = Control.FOCUS_ALL
	_prepare_equipment_labels()
	_resolve_actor_links()
	_apply_localization()
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


func set_inventory_override(inventory: Node = null) -> void:
	_inventory_override = inventory
	_set_active_inventory(_inventory_override if _inventory_override != null else _actor_inventory)
	if is_node_ready():
		refresh()


func refresh() -> void:
	var preferred_index := _selected_index
	_clear_slots()

	if _inventory == null:
		title_label.text = _text("ui.inventory.inventory")
		weight_label.text = ""
		weight_help_label.text = ""
		empty_label.show()
		empty_label.text = _text("ui.inventory.missing")
		_select_slot(-1)
		return

	title_label.text = _get_inventory_display_name()
	_update_weight()
	_update_equipment_labels()

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


func _resolve_actor_links() -> void:
	var actor := get_node_or_null(actor_path)
	if actor == null:
		actor = get_parent()
	if actor == null:
		return

	_actor_inventory = actor.get_node_or_null("Inventory")
	_set_active_inventory(_inventory_override if _inventory_override != null else _actor_inventory)
	_inventory_dropper = actor.get_node_or_null("InventoryDropper")
	_equipment = actor.get_node_or_null("Equipment")
	_stats = actor.get_node_or_null("PlayerStats")

	if _equipment != null and _equipment.has_signal("changed"):
		_equipment.connect("changed", _update_equipment_labels)
	if _stats != null and _stats.has_signal("changed"):
		_stats.connect("changed", _update_weight)


func _set_active_inventory(inventory: Node) -> void:
	var refresh_callable := Callable(self, "refresh")
	if _inventory != null and _inventory.has_signal("changed"):
		if _inventory.is_connected("changed", refresh_callable):
			_inventory.disconnect("changed", refresh_callable)

	_inventory = inventory
	if _inventory != null and _inventory.has_signal("changed"):
		if not _inventory.is_connected("changed", refresh_callable):
			_inventory.connect("changed", refresh_callable)


func _update_weight() -> void:
	if _stats != null and _stats.has_method("get_carried_weight_kg"):
		var carried := float(_stats.call("get_carried_weight_kg"))
		var maximum := float(_stats.call("get_absolute_weight_kg"))
		weight_label.text = "%s %.1f/%.1f kg" % [_text("ui.inventory.weight"), carried, maximum]
		weight_help_label.text = "%s: %.1f/%.1f" % [_text("ui.inventory.current_weight"), carried, maximum]
		return

	if _inventory != null and _inventory.has_method("get_total_weight"):
		var carried := float(_inventory.call("get_total_weight"))
		weight_label.text = "%s %.1f kg" % [_text("ui.inventory.weight"), carried]
		weight_help_label.text = "%s: %.1f kg" % [_text("ui.inventory.current_weight"), carried]


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
	slot.gui_input.connect(_on_slot_gui_input.bind(index, slot))

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
	var icon_rect := TextureRect.new()
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_rect.custom_minimum_size = Vector2(0, 34)
	icon_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture = ItemIconRenderer.get_icon_or_fallback(item)
	content.add_child(icon_rect)
	_load_slot_icon(item, icon_rect)

	var name_label := Label.new()
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.custom_minimum_size = Vector2(0, 14)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = _get_item_name(item)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.clip_text = true
	name_label.max_lines_visible = 1
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 8)
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


func _load_slot_icon(item: Resource, icon_rect: TextureRect) -> void:
	if item == null:
		return

	var texture: Texture2D = await ItemIconRenderer.bake_icon_async(item)
	if not is_instance_valid(icon_rect):
		return
	icon_rect.texture = texture


func _on_slot_pressed(index: int, slot: Button) -> void:
	slot.grab_focus()
	_select_slot(index)


func _on_slot_gui_input(event: InputEvent, index: int, slot: Button) -> void:
	var mouse_event := event as InputEventMouseButton
	if mouse_event == null or not mouse_event.pressed or not mouse_event.double_click:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return

	slot.grab_focus()
	_select_slot(index)
	_use_selected_item()
	slot.accept_event()


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
		item_name_label.text = _text("ui.inventory.empty_slot")
		item_detail_label.text = _text("ui.inventory.no_item")
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

	if item.has_method("get_display_name"):
		return str(item.call("get_display_name"))

	var display_name := str(item.get("display_name"))
	if not display_name.is_empty():
		return display_name
	return str(item.get("id"))


func _build_item_details(stack: Resource, item: Resource) -> String:
	if item == null:
		return _text("ui.inventory.unknown_item")

	var lines: Array[String] = []
	var description := _get_item_description(item)
	if not description.is_empty():
		lines.append(description)

	var amount := int(stack.get("amount"))
	var unit_weight := float(item.get("weight_kg"))
	lines.append("%s: %s" % [_text("ui.inventory.type"), _get_kind_name(item)])
	lines.append("%s: %d" % [_text("ui.inventory.amount"), amount])
	lines.append(_text("ui.inventory.weight_line", [unit_weight, unit_weight * amount]))

	var buy_price := int(item.get("buy_price"))
	var sell_price := int(item.get("sell_price"))
	if buy_price > 0 or sell_price > 0:
		lines.append(_text("ui.inventory.value_line", [buy_price, sell_price]))

	if stack.has_method("has_durability") and bool(stack.call("has_durability")):
		var current := float(stack.call("get_durability"))
		var maximum := float(item.get("durability_max"))
		lines.append("%s: %.0f/%.0f" % [_text("ui.inventory.durability"), current, maximum])

	var item_id := str(item.get("id"))
	if not item_id.is_empty():
		lines.append("%s: %s" % [_text("ui.inventory.id"), item_id])
	return "\n".join(lines)


func _get_kind_name(item: Resource) -> String:
	var kind := int(item.get("kind"))
	return _text(KIND_KEYS.get(kind, "item.kind.misc"))


func _use_selected_item() -> void:
	if not _is_actor_inventory_active():
		return

	var stack := _get_stack_at(_selected_index)
	if stack == null or bool(stack.call("is_empty")):
		return
	var item: Resource = stack.get("item")
	if item == null:
		return

	if _is_direct_use_item(item):
		_consume_selected_item()
		return

	if _equipment != null and _equipment.has_method("equip_stack"):
		if bool(_equipment.call("equip_stack", stack)):
			_update_equipment_labels()
			return


func _drop_selected_item() -> void:
	if not _is_actor_inventory_active():
		return

	var stack := _get_stack_at(_selected_index)
	if stack == null or bool(stack.call("is_empty")):
		return

	if _inventory_dropper == null or not _inventory_dropper.has_method("drop_stack"):
		return

	if bool(_inventory_dropper.call("drop_stack", stack, 1)):
		call_deferred("_refresh_after_item_change")


func _consume_selected_item() -> void:
	var stack := _get_stack_at(_selected_index)
	if stack == null or bool(stack.call("is_empty")):
		return

	var item: Resource = stack.get("item")
	if item == null or _inventory == null or not _inventory.has_method("remove_item"):
		return

	var removed := int(_inventory.call("remove_item", item.get("id"), 1))
	if removed > 0:
		_apply_consumable_effects(item)
		call_deferred("_refresh_after_item_change")


func _is_direct_use_item(item: Resource) -> bool:
	if item == null:
		return false

	var kind := int(item.get("kind"))
	return kind == KIND_FOOD or kind == KIND_POTION


func _is_actor_inventory_active() -> bool:
	return _inventory != null and _inventory == _actor_inventory


func _apply_consumable_effects(item: Resource) -> void:
	if item == null or _stats == null:
		return

	var hp_restore := float(item.get("hp_restore"))
	var hunger_restore := float(item.get("hunger_restore"))
	if hp_restore > 0.0 and _stats.has_method("heal"):
		_stats.call("heal", hp_restore)
	if hunger_restore > 0.0 and _stats.has_method("restore_hunger"):
		_stats.call("restore_hunger", hunger_restore)


func _refresh_after_item_change() -> void:
	refresh()
	focus_first()


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


func _prepare_equipment_labels() -> void:
	_prepare_equipment_slot(head_label, &"head")
	_prepare_equipment_slot(right_hand_label, &"right_hand")
	_prepare_equipment_slot(torso_label, &"torso")
	_prepare_equipment_slot(left_hand_label, &"left_hand")
	_prepare_equipment_slot(legs_label, &"legs")
	_prepare_equipment_slot(accessory_label, &"accessory")
	_prepare_equipment_slot(feet_label, &"feet")
	_prepare_equipment_slot(accessory_2_label, &"accessory_2")


func _prepare_equipment_slot(label: Label, slot: StringName) -> void:
	if label == null:
		return

	var panel := label.get_parent() as PanelContainer
	if panel == null:
		return

	panel.custom_minimum_size = Vector2(96, 72)

	if panel.has_node("SlotMargin"):
		_equipment_slot_labels[slot] = label
		_equipment_icon_rects[slot] = panel.get_node("SlotMargin/SlotContent/IconBox/ItemIcon")
		_equipment_empty_icons[slot] = panel.get_node("SlotMargin/SlotContent/IconBox/EmptyIcon")
		return

	panel.remove_child(label)

	var margin := MarginContainer.new()
	margin.name = "SlotMargin"
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 5)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var content := VBoxContainer.new()
	content.name = "SlotContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 2)
	margin.add_child(content)

	var icon_box := CenterContainer.new()
	icon_box.name = "IconBox"
	icon_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_box.custom_minimum_size = Vector2(0, 38)
	icon_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	icon_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(icon_box)

	var item_icon := TextureRect.new()
	item_icon.name = "ItemIcon"
	item_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item_icon.custom_minimum_size = Vector2(36, 36)
	item_icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	item_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	item_icon.visible = false
	icon_box.add_child(item_icon)

	var empty_icon := Label.new()
	empty_icon.name = "EmptyIcon"
	empty_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	empty_icon.text = "<>"
	empty_icon.modulate = Color(0.42, 0.36, 0.25, 0.9)
	empty_icon.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_icon.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty_icon.add_theme_font_size_override("font_size", 16)
	icon_box.add_child(empty_icon)

	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.custom_minimum_size = Vector2(0, 20)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.clip_text = true
	label.max_lines_visible = 2
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 9)
	content.add_child(label)

	_equipment_slot_labels[slot] = label
	_equipment_icon_rects[slot] = item_icon
	_equipment_empty_icons[slot] = empty_icon


func _apply_localization() -> void:
	equipment_title.text = _text("ui.inventory.equipment")
	inventory_title.text = _text("ui.inventory.inventory")
	empty_label.text = _text("ui.inventory.empty")
	_update_equipment_labels()


func _update_equipment_labels() -> void:
	_update_equipment_slot(&"head", "ui.inventory.head")
	_update_equipment_slot(&"right_hand", "ui.inventory.right_hand")
	_update_equipment_slot(&"torso", "ui.inventory.torso")
	_update_equipment_slot(&"left_hand", "ui.inventory.left_hand")
	_update_equipment_slot(&"legs", "ui.inventory.legs")
	_update_equipment_slot(&"accessory", "ui.inventory.accessory")
	_update_equipment_slot(&"feet", "ui.inventory.feet")
	_update_equipment_slot(&"accessory_2", "ui.inventory.accessory")


func _update_equipment_slot(slot: StringName, label_key: String) -> void:
	var label := _equipment_slot_labels.get(slot) as Label
	if label != null:
		label.text = _text(label_key)

	var icon_rect := _equipment_icon_rects.get(slot) as TextureRect
	var empty_icon := _equipment_empty_icons.get(slot) as Label
	if icon_rect == null or empty_icon == null:
		return

	var item := _get_equipped_item_for_slot(slot)
	if item == null:
		icon_rect.texture = null
		icon_rect.hide()
		empty_icon.show()
		if label != null:
			label.tooltip_text = _text(label_key)
		return

	icon_rect.texture = ItemIconRenderer.get_icon_or_fallback(item)
	icon_rect.show()
	empty_icon.hide()
	if label != null:
		label.tooltip_text = "%s: %s" % [_text(label_key), _get_item_name(item)]
	_load_equipment_icon(slot, item)


func _get_equipped_item_for_slot(slot: StringName) -> Resource:
	if _equipment == null or not _equipment.has_method("get_equipped_item"):
		return null
	return _equipment.call("get_equipped_item", slot) as Resource


func _load_equipment_icon(slot: StringName, item: Resource) -> void:
	if item == null:
		return

	var texture: Texture2D = await ItemIconRenderer.bake_icon_async(item)
	var current_item := _get_equipped_item_for_slot(slot)
	if current_item != item:
		return

	var icon_rect := _equipment_icon_rects.get(slot) as TextureRect
	if icon_rect == null or not is_instance_valid(icon_rect):
		return
	icon_rect.texture = texture


func _on_language_changed(_language: String) -> void:
	_apply_localization()
	refresh()


func _get_inventory_display_name() -> String:
	var display_name := str(_inventory.get("display_name"))
	if display_name == "Mochila":
		return _text("ui.inventory.backpack")
	if display_name == "Bau":
		return _text("ui.inventory.chest")
	if display_name == "Inventario do inimigo":
		return _text("ui.inventory.enemy_inventory")
	if display_name == "Inventory":
		return _text("ui.inventory.inventory")
	return display_name


func _get_item_description(item: Resource) -> String:
	if item.has_method("get_description"):
		return str(item.call("get_description"))
	return str(item.get("description"))


func _text(key: String, args: Array = []) -> String:
	if _localization_manager != null and _localization_manager.has_method("text"):
		return str(_localization_manager.call("text", key, args))
	return key
