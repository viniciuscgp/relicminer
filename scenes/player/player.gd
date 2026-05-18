extends CharacterBody3D


@export var speed := 15.0
@export var jump_velocity := 14.5
@export var mouse_sensitivity := 0.0025
@export var gamepad_look_sensitivity := 3.0
@export_range(10.0, 89.0, 1.0) var max_look_angle_degrees := 65.0
@export_range(0.0, 60.0, 0.5) var look_smoothing := 18.0
@export var acceleration := 18.0
@export var friction := 22.0
@export var interaction_distance := 3.0
@export var interaction_radius := 1.45
@export var rigid_body_push_speed := 1.25

@onready var stats: Node = get_node_or_null("PlayerStats")
@onready var inventory: Node = get_node_or_null("Inventory")
@onready var camera_pivot: Node3D = get_node_or_null("CameraPivot")
@onready var camera: Camera3D = get_node_or_null("CameraPivot/SpringArm3D/Camera3D")
@onready var underwater_environment: Node = get_node_or_null("CameraPivot/SpringArm3D/Camera3D/UnderwaterEnvironment")

var _camera_pitch := 0.0
var _target_camera_pitch := 0.0


func _ready() -> void:
	if camera_pivot != null:
		_camera_pitch = camera_pivot.rotation.x
		_target_camera_pitch = _camera_pitch
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_apply_camera_pitch(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		_add_camera_pitch(-event.relative.y * mouse_sensitivity)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and not get_tree().paused:
		_try_interact()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and _can_move():
		velocity.y = jump_velocity

	var look_axis := Input.get_axis("look_left", "look_right")
	if not is_zero_approx(look_axis):
		rotate_y(-look_axis * gamepad_look_sensitivity * delta)

	var look_vertical_axis := Input.get_axis("look_up", "look_down")
	if not is_zero_approx(look_vertical_axis):
		_add_camera_pitch(-look_vertical_axis * gamepad_look_sensitivity * delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()

	var moving := direction != Vector3.ZERO
	var speed_multiplier := 1.0
	if stats != null:
		stats.call("process_survival", delta, moving, false, _is_underwater())
		speed_multiplier = float(stats.call("get_speed_multiplier"))

	if moving and _can_move():
		var target_speed := speed * speed_multiplier
		velocity.x = move_toward(velocity.x, direction.x * target_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)
	move_and_slide()
	_push_rigid_body_collisions(direction)


func _can_move() -> bool:
	return stats == null or not bool(stats.call("is_over_absolute_weight"))


func _push_rigid_body_collisions(move_direction: Vector3) -> void:
	for index in range(get_slide_collision_count()):
		var collision := get_slide_collision(index)
		var body := collision.get_collider() as RigidBody3D
		if body == null or body.freeze:
			continue

		var push_direction := -collision.get_normal()
		push_direction.y = 0.0
		if push_direction.length_squared() < 0.001:
			push_direction = move_direction
		push_direction.y = 0.0
		if push_direction.length_squared() < 0.001:
			continue

		push_direction = push_direction.normalized()
		var mass_factor := clampf(1.0 / maxf(body.mass, 0.1), 0.15, 1.0)
		body.apply_central_impulse(push_direction * rigid_body_push_speed * mass_factor)


func _try_interact() -> void:
	var target := _get_interaction_target()
	if target == null:
		return

	if target.has_method("try_pickup"):
		target.call("try_pickup", inventory)
		return

	if target.has_method("open"):
		target.call("open", inventory)
		return

	if target.has_method("open_loot"):
		target.call("open_loot", inventory)
		return


func _get_interaction_target() -> Node:
	var space_state := get_world_3d().direct_space_state
	var origin := global_position + Vector3.UP * 0.9
	var direction := -global_transform.basis.z.normalized()

	if camera != null:
		origin = camera.global_position
		direction = -camera.global_transform.basis.z.normalized()

	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * interaction_distance)
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true

	var hit := space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider := hit.get("collider") as Node
		var target := _find_interactable(collider)
		if target != null:
			return target

	return _get_nearby_interaction_target(space_state)


func _get_nearby_interaction_target(space_state: PhysicsDirectSpaceState3D) -> Node:
	var shape := SphereShape3D.new()
	shape.radius = interaction_radius

	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), global_position + Vector3.UP * 0.75)
	query.exclude = [get_rid()]
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
		var distance := global_position.distance_squared_to(target_3d.global_position)
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


func _add_camera_pitch(amount: float) -> void:
	if camera_pivot == null:
		return

	var max_angle := deg_to_rad(max_look_angle_degrees)
	_target_camera_pitch = clampf(
		_target_camera_pitch + amount,
		-max_angle,
		max_angle
	)


func _apply_camera_pitch(delta: float) -> void:
	if camera_pivot == null:
		return

	if look_smoothing <= 0.0:
		_camera_pitch = _target_camera_pitch
	else:
		var weight := 1.0 - exp(-look_smoothing * delta)
		_camera_pitch = lerpf(_camera_pitch, _target_camera_pitch, weight)

	camera_pivot.rotation.x = _camera_pitch


func _is_underwater() -> bool:
	if underwater_environment == null or not underwater_environment.has_method("is_underwater"):
		return false
	return bool(underwater_environment.call("is_underwater"))
