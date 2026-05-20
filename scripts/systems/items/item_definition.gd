extends Resource
class_name ItemDefinition

const ItemAction := preload("res://scripts/systems/items/actions/item_action.gd")
const MeleeItemAction := preload("res://scripts/systems/items/actions/melee_item_action.gd")
const ThrowItemAction := preload("res://scripts/systems/items/actions/throw_item_action.gd")
const ConsumeItemAction := preload("res://scripts/systems/items/actions/consume_item_action.gd")

enum Kind {
	MISC,
	CURRENCY,
	WEAPON,
	TOOL,
	LIGHT,
	FOOD,
	POTION,
	KEY,
	MATERIAL,
	ARMOR
}

@export var id: StringName
@export var display_name := ""
@export_multiline var description := ""
@export var kind: Kind = Kind.MISC

@export_group("Presentation")
@export var icon: Texture2D
@export var world_scene: PackedScene
@export var held_scene: PackedScene
@export var generate_icon_from_world_scene := true

@export_group("Inventory")
@export_range(0.0, 1000.0, 0.01, "or_greater") var weight_kg := 0.0
@export_range(1, 999, 1, "or_greater") var stack_limit := 1
@export var buy_price := 0
@export var sell_price := 0

@export_group("Equipment")
@export var default_equipment_slot: StringName
@export var is_mining_tool := false
@export var weapon_damage := 0
@export var defense_bonus := 0
@export var durability_max := 0.0
@export var key_id: StringName

@export_group("Held Transform")
@export var held_position := Vector3.ZERO
@export var held_rotation_degrees := Vector3.ZERO
@export var held_scale := Vector3.ONE
@export var actions: Array[Resource] = []

@export_group("Use")
@export var hp_restore := 0.0
@export var hunger_restore := 0.0
@export var energy_restore := 0.0
@export var oxygen_bonus_seconds := 0.0
@export var attack_bonus := 0
@export var defense_buff := 0
@export var effect_duration_seconds := 0.0


func can_stack() -> bool:
	return stack_limit > 1


func is_key_for(lock_id: StringName) -> bool:
	return kind == Kind.KEY and (key_id == lock_id or id == lock_id)


func has_world_scene() -> bool:
	return world_scene != null


func should_generate_icon() -> bool:
	return generate_icon_from_world_scene and world_scene != null


func get_display_name() -> String:
	var localization := _get_localization_manager()
	if localization != null and localization.has_method("item_name"):
		return str(localization.call("item_name", self, display_name))
	return display_name


func get_description() -> String:
	var localization := _get_localization_manager()
	if localization != null and localization.has_method("item_description"):
		return str(localization.call("item_description", self, description))
	return description


func create_world_instance(amount := 1, durability := -1.0) -> Node:
	if world_scene == null:
		return null

	var instance := world_scene.instantiate()
	if instance.has_method("setup"):
		instance.call("setup", self, amount, durability)
	return instance


func create_held_instance(amount := 1, durability := -1.0) -> Node3D:
	var source_scene := held_scene if held_scene != null else world_scene
	if source_scene == null:
		return null

	var instance := source_scene.instantiate() as Node3D
	if instance == null:
		return null
	if instance.has_method("setup"):
		instance.call("setup", self, amount, durability)
	return instance


func get_default_equipment_slot() -> StringName:
	if default_equipment_slot != &"":
		return default_equipment_slot
	if kind == Kind.LIGHT:
		return &"left_hand"
	return &"right_hand"


func get_action_for_trigger(trigger: StringName) -> Resource:
	for action in actions:
		if action == null:
			continue
		if action.get("trigger") == trigger:
			return action
	return _create_default_action(trigger)


func _create_default_action(trigger: StringName) -> Resource:
	if trigger == ItemAction.TRIGGER_THROW:
		return ThrowItemAction.new()

	if trigger == ItemAction.TRIGGER_PRIMARY:
		if kind == Kind.WEAPON or kind == Kind.TOOL:
			var slash := MeleeItemAction.new()
			slash.display_name = "Slash"
			slash.animation_name = _get_default_primary_animation()
			return slash
		if kind == Kind.FOOD or kind == Kind.POTION:
			return ConsumeItemAction.new()

	if trigger == ItemAction.TRIGGER_SECONDARY and (kind == Kind.WEAPON or kind == Kind.TOOL):
		var thrust := MeleeItemAction.new()
		thrust.trigger = ItemAction.TRIGGER_SECONDARY
		thrust.display_name = "Thrust"
		thrust.animation_name = _get_default_secondary_animation()
		thrust.range = 2.2
		thrust.damage_multiplier = 1.15
		return thrust

	return null


func _get_default_primary_animation() -> StringName:
	if kind == Kind.TOOL:
		if is_mining_tool:
			return &"mining"
		var item_id := String(id).to_lower()
		if item_id.contains("axe"):
			return &"chopping"
		return &"picking"

	if kind == Kind.WEAPON:
		var item_id := String(id).to_lower()
		if item_id.contains("staff"):
			return &"staff_attack"
		if item_id.contains("sword"):
			return &"sword_attack"
	return &"sword_attack"


func _get_default_secondary_animation() -> StringName:
	if kind == Kind.WEAPON:
		var item_id := String(id).to_lower()
		if item_id.contains("staff"):
			return &"staff_attack"
		return &"sword_slash_vertical"
	if kind == Kind.TOOL:
		return _get_default_primary_animation()
	return &""


func _get_localization_manager() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("LocalizationManager")
