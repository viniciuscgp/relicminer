extends Node3D


## NodePath used to locate the world environment node.
@export var world_environment_path: NodePath
## NodePath used to locate the target node.
@export var target_path: NodePath
## Physics layers used by water collision mask.
@export_flags_3d_physics var water_collision_mask := 1
## Configures water area group.
@export var water_area_group := "water_volume"
## Name used for water area.
@export var water_area_name := "WaterArea"
## Configures check interval.
@export var check_interval := 0.1
## Speed value used for transition.
@export var transition_speed := 4.0
## Configures max water results.
@export var max_water_results := 16
## Radius used for probe.
@export var probe_radius := 0.6
## Radius used for vertical probe.
@export var vertical_probe_radius := 0.35
## Color used for underwater fog.
@export var underwater_fog_color := Color(0.03, 0.22, 0.28, 1.0)
## Density used for underwater fog.
@export_range(0.0, 1.0, 0.01) var underwater_fog_density := 0.12
## Configures underwater fog sky affect.
@export_range(0.0, 1.0, 0.01) var underwater_fog_sky_affect := 0.65


var _world_environment: WorldEnvironment
var _target: Node3D
var _original_environment: Environment
var _runtime_environment: Environment
var _original_fog_enabled := false
var _original_fog_color := Color.WHITE
var _original_fog_density := 0.0
var _original_fog_sky_affect := 0.0
var _underwater := false
var _blend := 0.0
var _check_timer := 0.0


func _ready() -> void:
	_world_environment = _resolve_world_environment()
	_target = _resolve_target()
	if not _world_environment:
		push_warning("UnderwaterEnvironment: no WorldEnvironment found.")
		return

	_original_environment = _world_environment.environment
	_runtime_environment = _original_environment.duplicate(true) if _original_environment else Environment.new()
	_world_environment.environment = _runtime_environment
	_capture_original_fog()
	_apply_underwater_blend(0.0)


func _exit_tree() -> void:
	if _world_environment and _world_environment.environment == _runtime_environment:
		_world_environment.environment = _original_environment


func _process(delta: float) -> void:
	if not _runtime_environment or not _target:
		return

	if _world_environment.environment != _runtime_environment:
		_original_environment = _world_environment.environment
		_runtime_environment = _original_environment.duplicate(true) if _original_environment else Environment.new()
		_world_environment.environment = _runtime_environment
		_capture_original_fog()

	_check_timer -= delta
	if _check_timer <= 0.0:
		_check_timer = maxf(check_interval, 0.02)
		_underwater = _is_position_inside_water(_target.global_position)

	var target_blend := 1.0 if _underwater else 0.0
	_blend = move_toward(_blend, target_blend, transition_speed * delta)
	if _blend <= 0.001 and not _underwater:
		_capture_original_fog()
	_apply_underwater_blend(_blend)


func is_underwater() -> bool:
	return _underwater


func is_position_inside_water(position: Vector3) -> bool:
	return _is_position_inside_water(position)


func is_water_at_point(position: Vector3) -> bool:
	return _is_probe_inside_water(position)


func _resolve_target() -> Node3D:
	if not target_path.is_empty():
		var node := get_node_or_null(target_path) as Node3D
		if node:
			return node
	return self


func _resolve_world_environment() -> WorldEnvironment:
	if not world_environment_path.is_empty():
		var node := get_node_or_null(world_environment_path) as WorldEnvironment
		if node:
			return node
	return _find_world_environment(get_tree().current_scene)


func _find_world_environment(node: Node) -> WorldEnvironment:
	if not node:
		return null
	if node is WorldEnvironment:
		return node
	for child in node.get_children():
		var result := _find_world_environment(child)
		if result:
			return result
	return null


func _capture_original_fog() -> void:
	_original_fog_enabled = bool(_runtime_environment.get("fog_enabled"))
	_original_fog_color = _runtime_environment.get("fog_light_color")
	_original_fog_density = float(_runtime_environment.get("fog_density"))
	_original_fog_sky_affect = float(_runtime_environment.get("fog_sky_affect"))


func _apply_underwater_blend(weight: float) -> void:
	var t := clampf(weight, 0.0, 1.0)
	_runtime_environment.set("fog_enabled", _original_fog_enabled or t > 0.001)
	_runtime_environment.set("fog_light_color", _original_fog_color.lerp(underwater_fog_color, t))
	_runtime_environment.set("fog_density", lerpf(_original_fog_density, underwater_fog_density, t))
	_runtime_environment.set("fog_sky_affect", lerpf(_original_fog_sky_affect, underwater_fog_sky_affect, t))


func _is_position_inside_water(position: Vector3) -> bool:
	for probe_position in _get_probe_positions(position):
		if _is_probe_inside_water(probe_position):
			return true
	return false


func _get_probe_positions(position: Vector3) -> Array[Vector3]:
	var radius := maxf(probe_radius, 0.0)
	var vertical_radius := maxf(vertical_probe_radius, 0.0)
	var positions: Array[Vector3] = [position]
	if radius > 0.0:
		positions.append(position + Vector3(radius, 0.0, 0.0))
		positions.append(position - Vector3(radius, 0.0, 0.0))
		positions.append(position + Vector3(0.0, 0.0, radius))
		positions.append(position - Vector3(0.0, 0.0, radius))
	if vertical_radius > 0.0:
		positions.append(position + Vector3.UP * vertical_radius)
		positions.append(position - Vector3.UP * vertical_radius)
	return positions


func _is_probe_inside_water(position: Vector3) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = position
	query.collision_mask = water_collision_mask
	query.collide_with_areas = true
	query.collide_with_bodies = false

	var hits := get_world_3d().direct_space_state.intersect_point(query, max_water_results)
	for hit in hits:
		var collider: Object = hit.get("collider")
		if _is_water_collider(collider):
			return true
	return false


func _is_water_collider(collider: Object) -> bool:
	if not collider is Area3D:
		return false
	var area := collider as Area3D
	return area.is_in_group(water_area_group) or area.name == water_area_name
