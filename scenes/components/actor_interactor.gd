extends Node
class_name ActorInteractor

@export var actor_path: NodePath = NodePath("..")
@export var aim_source_path: NodePath
@export var interaction_distance := 3.0
@export var interaction_radius := 1.45

@onready var actor: Node = get_node_or_null(actor_path)
@onready var aim_source: Node3D = get_node_or_null(aim_source_path) as Node3D


func interact() -> bool:
	var target := get_interaction_target()
	if target == null:
		return false

	if target.has_method("try_pickup"):
		target.call("try_pickup", _get_actor_inventory())
		return true

	if target.has_method("open"):
		target.call("open", _get_actor_inventory())
		return true

	if target.has_method("open_loot"):
		target.call("open_loot", _get_actor_inventory())
		return true

	return false


func get_interaction_target() -> Node:
	if actor == null:
		return null

	var actor_3d := actor as Node3D
	if actor_3d == null:
		return null

	var space_state: PhysicsDirectSpaceState3D = actor_3d.get_world_3d().direct_space_state
	var origin: Vector3 = actor_3d.global_position + Vector3.UP * 0.9
	var direction: Vector3 = -actor_3d.global_transform.basis.z.normalized()

	if aim_source != null:
		origin = aim_source.global_position
		direction = -aim_source.global_transform.basis.z.normalized()

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * interaction_distance)
	query.exclude = [actor_3d.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit: Dictionary = space_state.intersect_ray(query)
	if not hit.is_empty():
		var target := _find_interactable(hit.get("collider") as Node)
		if target != null:
			return target

	return _get_nearby_interaction_target(space_state)


func _get_nearby_interaction_target(space_state: PhysicsDirectSpaceState3D) -> Node:
	var shape := SphereShape3D.new()
	shape.radius = interaction_radius

	var actor_3d := actor as Node3D
	if actor_3d == null:
		return null

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), actor_3d.global_position + Vector3.UP * 0.75)
	query.exclude = [actor_3d.get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hits := space_state.intersect_shape(query, 16)
	var closest: Node = null
	var closest_distance := INF
	for hit in hits:
		var target := _find_interactable(hit.get("collider") as Node)
		if target == null:
			continue
		var target_3d := target as Node3D
		if target_3d == null:
			continue
		var distance: float = actor_3d.global_position.distance_squared_to(target_3d.global_position)
		if distance < closest_distance:
			closest = target
			closest_distance = distance
	return closest


func _find_interactable(node: Node) -> Node:
	var current := node
	while current != null:
		if current.has_method("try_pickup") or current.has_method("open") or current.has_method("open_loot"):
			return current
		current = current.get_parent()
	return null


func _get_actor_inventory() -> Node:
	if actor == null or not actor.has_method("get_inventory"):
		return null
	return actor.call("get_inventory") as Node
