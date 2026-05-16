extends Node3D


@export var output_path := "res://river_survey.json"
@export var sample_distance := 4.0
@export var max_bank_distance := 80.0
@export var surface_height_offset := 1.0
@export var auto_detect_surface_height := true
@export var max_surface_scan_height := 8.0
@export var surface_scan_step := 0.25
@export var minimum_depth := 0.5
@export var down_ray_height := 20.0
@export var down_ray_depth := 120.0
@export_flags_3d_physics var collision_mask := 1


var recording := false
var samples: Array[Dictionary] = []
var last_sample_position := Vector3.INF


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_river_survey"):
		if recording:
			_stop_recording()
		else:
			_start_recording()
		get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
	if not recording:
		return

	var player := get_parent() as Node3D
	if not player:
		return

	if samples.is_empty() or _flat_distance(player.global_position, last_sample_position) >= sample_distance:
		_record_sample(player)


func _start_recording() -> void:
	recording = true
	samples.clear()
	last_sample_position = Vector3.INF
	print("RiverSurveyRecorder: recording started.")


func _stop_recording() -> void:
	recording = false
	_save_samples()


func _record_sample(player: Node3D) -> void:
	var direction := _get_motion_direction(player)
	if direction.is_zero_approx():
		return

	var side := Vector3(-direction.z, 0.0, direction.x).normalized()
	var player_position := player.global_position
	var excludes := _get_excludes(player)
	var space_state := get_world_3d().direct_space_state

	var bottom_from := player_position + Vector3.UP * down_ray_height
	var bottom_to := player_position - Vector3.UP * down_ray_depth
	var bottom_hit := _raycast(space_state, bottom_from, bottom_to, excludes)
	var bottom_y := player_position.y
	if not bottom_hit.is_empty():
		bottom_y = (bottom_hit["position"] as Vector3).y

	var surface_profile := _find_surface_profile(space_state, player_position, side, excludes)
	var surface_origin: Vector3 = surface_profile["center"]
	var left: Vector3 = surface_profile["left"]
	var right: Vector3 = surface_profile["right"]
	var depth := maxf(surface_origin.y - bottom_y, minimum_depth)

	samples.append({
		"center": _vector_to_array(surface_origin),
		"left": _vector_to_array(left),
		"right": _vector_to_array(right),
		"bottom_y": bottom_y,
		"surface_y": surface_origin.y,
		"depth": depth,
	})
	last_sample_position = player_position
	print("RiverSurveyRecorder: sample %d recorded." % samples.size())


func _find_surface_profile(space_state: PhysicsDirectSpaceState3D, player_position: Vector3, side: Vector3, excludes: Array[RID]) -> Dictionary:
	if not auto_detect_surface_height:
		var fixed_origin := Vector3(player_position.x, player_position.y + surface_height_offset, player_position.z)
		return _make_surface_profile(space_state, fixed_origin, side, excludes)

	var start_y := player_position.y + surface_height_offset
	var end_y := player_position.y + max_surface_scan_height
	var step := maxf(surface_scan_step, 0.05)
	var best_profile := {}
	var y := start_y

	while y <= end_y + 0.001:
		var origin := Vector3(player_position.x, y, player_position.z)
		var profile := _make_surface_profile(space_state, origin, side, excludes)
		if bool(profile["has_left"]) and bool(profile["has_right"]):
			best_profile = profile
		elif not best_profile.is_empty():
			break
		y += step

	if best_profile.is_empty():
		var fallback_origin := Vector3(player_position.x, start_y, player_position.z)
		best_profile = _make_surface_profile(space_state, fallback_origin, side, excludes)

	return best_profile


func _make_surface_profile(space_state: PhysicsDirectSpaceState3D, origin: Vector3, side: Vector3, excludes: Array[RID]) -> Dictionary:
	var left_hit := _raycast(space_state, origin, origin + side * max_bank_distance, excludes)
	var right_hit := _raycast(space_state, origin, origin - side * max_bank_distance, excludes)
	return {
		"center": origin,
		"left": _edge_position(left_hit, origin + side * max_bank_distance, origin.y),
		"right": _edge_position(right_hit, origin - side * max_bank_distance, origin.y),
		"has_left": not left_hit.is_empty(),
		"has_right": not right_hit.is_empty(),
	}


func _save_samples() -> void:
	var file := FileAccess.open(output_path, FileAccess.WRITE)
	if not file:
		push_error("RiverSurveyRecorder: could not write %s." % output_path)
		return

	var payload := {
		"version": 1,
		"sample_distance": sample_distance,
		"samples": samples,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	print("RiverSurveyRecorder: saved %d sample(s) to %s." % [samples.size(), output_path])


func _get_motion_direction(player: Node3D) -> Vector3:
	var direction := Vector3.ZERO
	if player is CharacterBody3D:
		direction = (player as CharacterBody3D).velocity
		direction.y = 0.0

	if direction.length_squared() <= 0.01:
		direction = -player.global_transform.basis.z
		direction.y = 0.0

	return direction.normalized()


func _raycast(space_state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3, excludes: Array[RID]) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = collision_mask
	query.exclude = excludes
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return space_state.intersect_ray(query)


func _edge_position(hit: Dictionary, fallback: Vector3, surface_y: float) -> Vector3:
	var position := fallback
	if not hit.is_empty():
		position = hit["position"]
	position.y = surface_y
	return position


func _get_excludes(player: Node3D) -> Array[RID]:
	if player is CollisionObject3D:
		return [(player as CollisionObject3D).get_rid()]
	return []


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]


func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta_x := a.x - b.x
	var delta_z := a.z - b.z
	return sqrt(delta_x * delta_x + delta_z * delta_z)
