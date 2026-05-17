extends CharacterBody3D
class_name EnemyBase

signal died(enemy: Node)
signal loot_opened(actor_inventory: Node, enemy_inventory: Node)
signal loot_open_failed(reason: String)

@export var stats_path: NodePath = NodePath("CombatStats")
@export var inventory_path: NodePath = NodePath("Inventory")
@export var loot_after_death := true
@export var disable_collision_on_death := true

@onready var stats: Node = get_node_or_null(stats_path)
@onready var inventory: Node = get_node_or_null(inventory_path)


func _ready() -> void:
	if stats != null and stats.has_signal("died"):
		stats.connect("died", _on_stats_died)


func get_stats() -> Node:
	return stats


func get_inventory() -> Node:
	return inventory


func is_dead() -> bool:
	return stats != null and stats.has_method("is_dead") and bool(stats.call("is_dead"))


func take_damage(raw_damage: float) -> float:
	if stats == null or not stats.has_method("take_damage"):
		return 0.0
	return float(stats.call("take_damage", raw_damage))


func can_open_loot(actor_inventory: Node = null) -> bool:
	if not loot_after_death or not is_dead() or inventory == null:
		return false
	if not inventory.has_method("is_accessible"):
		return false
	return bool(inventory.call("is_accessible", actor_inventory))


func open_loot(actor_inventory: Node = null) -> bool:
	if inventory == null:
		loot_open_failed.emit("Este inimigo nao possui inventario.")
		return false

	if not loot_after_death or not is_dead():
		loot_open_failed.emit("Ainda nao e possivel vasculhar este inimigo.")
		return false

	if not inventory.has_method("unlock_with"):
		loot_open_failed.emit("Este inventario nao pode ser aberto.")
		return false

	if not bool(inventory.call("unlock_with", actor_inventory)):
		loot_open_failed.emit("Trancado.")
		return false

	loot_opened.emit(actor_inventory, inventory)
	return true


func _on_stats_died() -> void:
	if disable_collision_on_death:
		for child in get_children():
			if child is CollisionShape3D:
				child.disabled = true
	died.emit(self)
