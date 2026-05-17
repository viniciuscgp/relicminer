extends Resource
class_name ItemDefinition

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

@export_group("Inventory")
@export_range(0.0, 1000.0, 0.01, "or_greater") var weight_kg := 0.0
@export_range(1, 999, 1, "or_greater") var stack_limit := 1
@export var buy_price := 0
@export var sell_price := 0

@export_group("Equipment")
@export var weapon_damage := 0
@export var defense_bonus := 0
@export var durability_max := 0.0
@export var key_id: StringName

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

