extends "res://scripts/systems/items/actions/item_action.gd"
class_name MeleeItemAction

@export var animation_name: StringName = &""
@export var damage_multiplier := 1.0
@export var range := 1.7
@export var impact_impulse := 3.0


func _init() -> void:
	trigger = TRIGGER_PRIMARY
	display_name = "Attack"


func execute(actor: Node, equipment: Node, stack: Resource, _slot: StringName, _held_instance: Node3D) -> bool:
	if actor == null or equipment == null or stack == null or bool(stack.call("is_empty")):
		return false

	if animation_name != &"" and actor.has_method("play_action_animation"):
		actor.call("play_action_animation", animation_name)

	var item: Resource = stack.get("item")
	var damage := _calculate_damage(actor, item)
	var hit := _get_hit(actor, equipment)
	if hit.is_empty():
		return true

	var collider := hit.get("collider") as Node
	var target := _find_damage_target(collider)
	if target != null and target.has_method("take_damage"):
		target.call("take_damage", damage)

	var body := collider as RigidBody3D
	if body != null:
		var direction: Vector3 = equipment.call("get_aim_direction")
		body.apply_central_impulse(direction.normalized() * impact_impulse)

	return true


func _calculate_damage(actor: Node, item: Resource) -> float:
	var weapon_damage := 1
	if item != null:
		weapon_damage = max(1, int(item.get("weapon_damage")))

	var stats: Node = actor.call("get_stats") if actor.has_method("get_stats") else null
	if stats != null and stats.has_method("calculate_damage"):
		return float(stats.call("calculate_damage", weapon_damage, 0)) * damage_multiplier
	return float(weapon_damage) * damage_multiplier


func _get_hit(actor: Node, equipment: Node) -> Dictionary:
	if not (actor is Node3D):
		return {}

	var actor_3d := actor as Node3D
	var space_state := actor_3d.get_world_3d().direct_space_state
	var origin: Vector3 = equipment.call("get_aim_origin")
	var direction: Vector3 = equipment.call("get_aim_direction")
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction.normalized() * range)
	query.exclude = [actor_3d.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)


func _find_damage_target(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_method("take_damage"):
			return current
		current = current.get_parent()
	return null
