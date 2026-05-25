extends Node

signal changed
signal health_changed(current: float, maximum: float)
signal energy_changed(current: float, maximum: float)
signal hunger_changed(current: float, maximum: float)
signal oxygen_changed(current: float, maximum: float)
signal level_changed(level: int)
signal died
signal message_requested(text: String)

## NodePath used to locate the inventory node.
@export var inventory_path: NodePath

@export_group("Level")
## Configures level in the Level settings.
@export_range(1, 100, 1, "or_greater") var level := 1
## Configures XP in the Level settings.
@export var xp := 0

@export_group("Base Stats")
## Configures base max HP in the Base Stats settings.
@export var base_max_hp     := 100.0
## Configures base attack in the Base Stats settings.
@export var base_attack     := 5
## Configures base defense in the Base Stats settings.
@export var base_defense    := 1
## Energy or light intensity used for base max in the Base Stats settings.
@export var base_max_energy := 100.0
## Configures max hunger in the Base Stats settings.
@export var max_hunger      := 100.0
## Duration in seconds for base oxygen in the Base Stats settings.
@export var base_oxygen_seconds     := 10.0
## Weight value used for base comfort weight kg in the Base Stats settings.
@export var base_comfort_weight_kg  := 22.0
## Weight value used for base absolute weight kg in the Base Stats settings.
@export var base_absolute_weight_kg := 32.0

@export_group("Survival Rates")
## Configures hunger drain per second in the Survival Rates settings.
@export var hunger_drain_per_second         := 0.015
## Multiplier applied to moving hunger in the Survival Rates settings.
@export var moving_hunger_multiplier        := 3.0
## Multiplier applied to swimming hunger in the Survival Rates settings.
@export var swimming_hunger_multiplier      := 4.0
## Configures hunger damage per second in the Survival Rates settings.
@export var hunger_damage_per_second        := 1.0
## Configures energy recovery per second in the Survival Rates settings.
@export var energy_recovery_per_second      := 18.0
## Configures moving energy cost per second in the Survival Rates settings.
@export var moving_energy_cost_per_second   := 0.0
## Configures running energy cost per second in the Survival Rates settings.
@export var running_energy_cost_per_second  := 14.0
## Configures swimming energy cost per second in the Survival Rates settings.
@export var swimming_energy_cost_per_second := 8.0
## Duration in seconds for drowning damage first in the Survival Rates settings.
@export var drowning_damage_first_seconds   := 5.0
## Duration in seconds for drowning damage late in the Survival Rates settings.
@export var drowning_damage_late_seconds    := 10.0

var current_hp     := 0.0
var current_energy := 0.0
var current_hunger := 0.0
var current_oxygen := 0.0
var extra_oxygen_seconds := 0.0
var attack_bonus  := 0
var defense_bonus := 0

var _inventory: Node
var _drowning_time := 0.0


func _ready() -> void:
	_inventory = get_node_or_null(inventory_path)
	if _inventory != null and _inventory.has_signal("changed"):
		_inventory.connect("changed", _emit_all)

	current_hp = get_max_hp()
	current_energy = get_max_energy()
	current_hunger = max_hunger
	current_oxygen = get_max_oxygen()
	_emit_all()


func get_save_data() -> Dictionary:
	return {
		"level": level,
		"xp": xp,
		"current_hp": current_hp,
		"current_energy": current_energy,
		"current_hunger": current_hunger,
		"current_oxygen": current_oxygen,
		"extra_oxygen_seconds": extra_oxygen_seconds,
		"attack_bonus": attack_bonus,
		"defense_bonus": defense_bonus,
		"drowning_time": _drowning_time,
	}


func apply_save_data(data: Dictionary) -> void:
	level = max(1, int(data.get("level", level)))
	xp = max(0, int(data.get("xp", xp)))
	extra_oxygen_seconds = maxf(0.0, float(data.get("extra_oxygen_seconds", extra_oxygen_seconds)))
	attack_bonus = int(data.get("attack_bonus", attack_bonus))
	defense_bonus = int(data.get("defense_bonus", defense_bonus))
	current_hp = clampf(float(data.get("current_hp", current_hp)), 0.0, get_max_hp())
	current_energy = clampf(float(data.get("current_energy", current_energy)), 0.0, get_max_energy())
	current_hunger = clampf(float(data.get("current_hunger", current_hunger)), 0.0, max_hunger)
	current_oxygen = clampf(float(data.get("current_oxygen", current_oxygen)), 0.0, get_max_oxygen())
	_drowning_time = maxf(0.0, float(data.get("drowning_time", _drowning_time)))
	_emit_all()


func process_survival(delta: float, moving: bool, swimming: bool, underwater: bool, running := false) -> void:
	_update_hunger(delta, moving, swimming)
	_update_energy(delta, moving, swimming, running)
	_update_oxygen(delta, underwater)
	_emit_all()


func get_xp_required_for_next_level() -> int:
	var level_index := level - 1
	return 100 + level_index * 80 + level_index * level_index * 20


func add_xp(amount: int) -> void:
	if amount <= 0:
		return

	xp += amount
	while xp >= get_xp_required_for_next_level():
		xp -= get_xp_required_for_next_level()
		_level_up()
	changed.emit()


func take_damage(amount: float) -> void:
	if amount <= 0.0 or current_hp <= 0.0:
		return

	current_hp = maxf(0.0, current_hp - amount)
	health_changed.emit(current_hp, get_max_hp())
	changed.emit()

	if current_hp <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	current_hp = minf(get_max_hp(), current_hp + amount)
	health_changed.emit(current_hp, get_max_hp())
	changed.emit()


func restore_hunger(amount: float) -> void:
	if amount <= 0.0:
		return
	current_hunger = minf(max_hunger, current_hunger + amount)
	hunger_changed.emit(current_hunger, max_hunger)
	changed.emit()


func spend_energy(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if current_energy < amount:
		return false
	current_energy -= amount
	energy_changed.emit(current_energy, get_max_energy())
	changed.emit()
	return true


func has_energy(amount: float) -> bool:
	return amount <= 0.0 or current_energy >= amount


func get_max_hp() -> float:
	return base_max_hp + float(level - 1) * 5.0


func get_max_energy() -> float:
	return base_max_energy + float(level - 1) * 3.0


func get_attack() -> int:
	return base_attack + int(floor(float(level) / 2.0)) + attack_bonus


func get_defense() -> int:
	return base_defense + int(floor(float(level - 1) / 4.0)) + defense_bonus


func get_comfort_weight_kg() -> float:
	return base_comfort_weight_kg + floor(float(level - 1) / 3.0)


func get_absolute_weight_kg() -> float:
	return base_absolute_weight_kg + floor(float(level - 1) / 3.0)


func get_max_oxygen() -> float:
	return base_oxygen_seconds + extra_oxygen_seconds


func get_carried_weight_kg() -> float:
	if _inventory == null:
		return 0.0
	return float(_inventory.call("get_total_weight"))


func is_over_absolute_weight() -> bool:
	return get_carried_weight_kg() > get_absolute_weight_kg()


func get_weight_speed_multiplier() -> float:
	var carried := get_carried_weight_kg()
	var comfort := get_comfort_weight_kg()
	var absolute := get_absolute_weight_kg()

	if carried > absolute:
		return 0.0
	if carried <= comfort * 0.7:
		return 1.0
	if carried <= comfort:
		return 0.9
	return 0.65


func get_hunger_speed_multiplier() -> float:
	if current_hunger > 30.0:
		return 1.0
	if current_hunger > 0.0:
		return 0.85
	return 0.65


func get_speed_multiplier() -> float:
	return get_weight_speed_multiplier() * get_hunger_speed_multiplier()


func calculate_damage(weapon_damage: int, target_defense: int) -> int:
	return max(1, get_attack() + weapon_damage - target_defense)


func _level_up() -> void:
	level += 1
	current_hp = get_max_hp()
	current_energy = get_max_energy()
	level_changed.emit(level)


func _update_hunger(delta: float, moving: bool, swimming: bool) -> void:
	var multiplier := 1.0
	if moving:
		multiplier = moving_hunger_multiplier
	if swimming:
		multiplier = swimming_hunger_multiplier

	current_hunger = maxf(0.0, current_hunger - hunger_drain_per_second * multiplier * delta)
	if current_hunger <= 0.0:
		take_damage(hunger_damage_per_second * delta)


func _update_energy(delta: float, moving: bool, swimming: bool, running := false) -> void:
	var cost := moving_energy_cost_per_second if moving else 0.0
	if running:
		cost += running_energy_cost_per_second
	if swimming:
		cost += swimming_energy_cost_per_second

	if cost > 0.0:
		current_energy = maxf(0.0, current_energy - cost * delta)
	else:
		var hunger_factor := 1.0
		if current_hunger <= 30.0:
			hunger_factor = 0.35
		elif current_hunger <= 60.0:
			hunger_factor = 0.7
		current_energy = minf(get_max_energy(), current_energy + energy_recovery_per_second * hunger_factor * delta)


func _update_oxygen(delta: float, underwater: bool) -> void:
	if underwater:
		current_oxygen = maxf(0.0, current_oxygen - delta)
		if current_oxygen <= 0.0:
			_drowning_time += delta
			var damage_rate := drowning_damage_first_seconds if _drowning_time <= 3.0 else drowning_damage_late_seconds
			take_damage(damage_rate * delta)
	else:
		_drowning_time = 0.0
		current_oxygen = minf(get_max_oxygen(), current_oxygen + delta * 4.0)


func _emit_all() -> void:
	health_changed.emit(current_hp, get_max_hp())
	energy_changed.emit(current_energy, get_max_energy())
	hunger_changed.emit(current_hunger, max_hunger)
	oxygen_changed.emit(current_oxygen, get_max_oxygen())
	changed.emit()
