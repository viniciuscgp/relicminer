extends Node
class_name CombatStatsComponent

signal changed
signal health_changed(current: float, maximum: float)
signal died

@export_group("Identity")
## Name shown to players and editor tools in the Identity settings.
@export var display_name := "Enemy"

@export_group("Stats")
## Configures level in the Stats settings.
@export_range(1, 100, 1, "or_greater") var level := 1
## Configures base max HP in the Stats settings.
@export var base_max_hp := 30.0
## Configures HP per level in the Stats settings.
@export var hp_per_level := 4.0
## Configures base attack in the Stats settings.
@export var base_attack := 4
## Configures attack per level in the Stats settings.
@export var attack_per_level := 1
## Configures base defense in the Stats settings.
@export var base_defense := 0
## Configures defense per level in the Stats settings.
@export var defense_per_level := 0
## Configures XP reward in the Stats settings.
@export var xp_reward := 10

var current_hp := 0.0
var dead := false


func _ready() -> void:
	reset()


func reset() -> void:
	dead = false
	current_hp = get_max_hp()
	_emit_health()


func get_max_hp() -> float:
	return base_max_hp + float(max(0, level - 1)) * hp_per_level


func get_attack() -> int:
	return base_attack + max(0, level - 1) * attack_per_level


func get_defense() -> int:
	return base_defense + max(0, level - 1) * defense_per_level


func calculate_damage(raw_damage: float) -> float:
	if raw_damage <= 0.0:
		return 0.0
	return maxf(1.0, raw_damage - float(get_defense()))


func take_damage(raw_damage: float) -> float:
	if dead:
		return 0.0

	var damage := calculate_damage(raw_damage)
	if damage <= 0.0:
		return 0.0

	current_hp = maxf(0.0, current_hp - damage)
	_emit_health()

	if current_hp <= 0.0:
		dead = true
		died.emit()

	return damage


func heal(amount: float) -> void:
	if dead or amount <= 0.0:
		return

	current_hp = minf(get_max_hp(), current_hp + amount)
	_emit_health()


func is_dead() -> bool:
	return dead


func _emit_health() -> void:
	health_changed.emit(current_hp, get_max_hp())
	changed.emit()
