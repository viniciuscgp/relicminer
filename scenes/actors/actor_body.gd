extends CharacterBody3D
class_name ActorBody

@export var inventory_path: NodePath = NodePath("Inventory")
@export var stats_path: NodePath = NodePath("PlayerStats")
@export var combat_stats_path: NodePath = NodePath("CombatStats")
@export var inventory_dropper_path: NodePath = NodePath("InventoryDropper")
@export var interactor_path: NodePath = NodePath("Interactor")
@export var rigid_body_pusher_path: NodePath = NodePath("RigidBodyPusher")
@export var equipment_path: NodePath = NodePath("Equipment")
@export var animation_controller_path: NodePath = NodePath("AnimationController")

@onready var inventory: Node = get_node_or_null(inventory_path)
@onready var stats: Node = get_node_or_null(stats_path)
@onready var combat_stats: Node = get_node_or_null(combat_stats_path)
@onready var inventory_dropper: Node = get_node_or_null(inventory_dropper_path)
@onready var interactor: Node = get_node_or_null(interactor_path)
@onready var rigid_body_pusher: Node = get_node_or_null(rigid_body_pusher_path)
@onready var equipment: Node = get_node_or_null(equipment_path)
@onready var animation_controller: Node = get_node_or_null(animation_controller_path)


func get_inventory() -> Node:
	return inventory


func get_stats() -> Node:
	if stats != null:
		return stats
	return combat_stats


func get_combat_stats() -> Node:
	if combat_stats != null:
		return combat_stats
	return stats


func get_equipment() -> Node:
	return equipment


func get_animation_controller() -> Node:
	return animation_controller


func can_move() -> bool:
	return stats == null or not stats.has_method("is_over_absolute_weight") or not bool(stats.call("is_over_absolute_weight"))


func get_movement_speed_multiplier() -> float:
	if stats != null and stats.has_method("get_speed_multiplier"):
		return float(stats.call("get_speed_multiplier"))
	return 1.0


func process_survival(delta: float, moving: bool, swimming: bool, underwater: bool) -> void:
	if stats != null and stats.has_method("process_survival"):
		stats.call("process_survival", delta, moving, swimming, underwater)


func play_action_animation(animation_name: StringName) -> bool:
	if animation_controller == null or not animation_controller.has_method("play_action_animation"):
		return false
	return bool(animation_controller.call("play_action_animation", animation_name))


func set_locomotion_animation(moving: bool, running: bool, jumping: bool, swimming: bool) -> void:
	if animation_controller == null or not animation_controller.has_method("set_locomotion_state"):
		return
	animation_controller.call("set_locomotion_state", moving, running, jumping, swimming)


func interact() -> bool:
	if interactor == null or not interactor.has_method("interact"):
		return false
	return bool(interactor.call("interact"))


func push_rigid_body_collisions(move_direction: Vector3) -> void:
	if rigid_body_pusher != null and rigid_body_pusher.has_method("push_collisions"):
		rigid_body_pusher.call("push_collisions", self, move_direction)


func use_equipped_primary() -> bool:
	if equipment == null or not equipment.has_method("use_primary"):
		return false
	return bool(equipment.call("use_primary"))


func use_equipped_secondary() -> bool:
	if equipment == null or not equipment.has_method("use_secondary"):
		return false
	return bool(equipment.call("use_secondary"))


func throw_equipped() -> bool:
	if equipment == null or not equipment.has_method("throw_equipped"):
		return false
	return bool(equipment.call("throw_equipped"))


func drop_stack(stack: Resource, amount := 1) -> bool:
	if inventory_dropper == null or not inventory_dropper.has_method("drop_stack"):
		return false
	return bool(inventory_dropper.call("drop_stack", stack, amount))


func drop_item(item: Resource, amount := 1, durability := -1.0) -> bool:
	if inventory_dropper == null or not inventory_dropper.has_method("drop_item"):
		return false
	return bool(inventory_dropper.call("drop_item", item, amount, durability))


func take_damage(raw_damage: float) -> float:
	var damage_target := get_combat_stats()
	if damage_target == null or not damage_target.has_method("take_damage"):
		return 0.0
	return float(damage_target.call("take_damage", raw_damage))
