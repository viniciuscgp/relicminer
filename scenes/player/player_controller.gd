extends Node
class_name PlayerController

@export var actor_path: NodePath = NodePath("..")
@export var camera_pivot_path: NodePath = NodePath("../CameraPivot")
@export var camera_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D")
@export var underwater_environment_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D/UnderwaterEnvironment")

@export var speed := 15.0
@export_range(0.1, 1.0, 0.05) var walk_speed_multiplier := 0.45
@export_range(0.1, 1.0, 0.05) var backward_speed_multiplier := 0.55
@export var minimum_run_energy := 0.0
@export var run_resume_energy := 12.0
@export_range(0.0, 1.0, 0.05) var run_animation_min_energy_ratio := 0.2
@export var jump_velocity := 7.0
@export var mouse_sensitivity := 0.0025
@export var gamepad_look_sensitivity := 3.0
@export_range(10.0, 89.0, 1.0) var max_look_angle_degrees := 65.0
@export_range(0.0, 60.0, 0.5) var look_smoothing := 18.0
@export_range(0.0, 30.0, 0.5) var turn_smoothing := 14.0
@export var acceleration := 18.0
@export var friction := 22.0
@export_group("Swimming")
@export var swim_speed_multiplier := 0.55
@export var swim_vertical_friction := 10.0
@export_range(0.0, 20.0, 0.1, "or_greater") var swim_up_speed := 8.0
@export_range(0.0, 80.0, 0.5, "or_greater") var swim_up_acceleration := 32.0
@export var swim_probe_height := 0.75
@export var swim_probe_radius := 0.25
@export var breath_probe_height := 1.15

@onready var actor = get_node_or_null(actor_path)
@onready var camera_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
@onready var camera: Node3D = get_node_or_null(camera_path) as Node3D
@onready var underwater_environment: Node = get_node_or_null(underwater_environment_path)

var _camera_pitch := 0.0
var _target_camera_pitch := 0.0
var _camera_yaw := 0.0
var _target_camera_yaw := 0.0
var _audio_manager: Node
var _run_exhausted := false


func _ready() -> void:
	_audio_manager = get_node_or_null("/root/AudioManager")
	if _audio_manager != null and _audio_manager.has_signal("settings_changed"):
		_audio_manager.connect("settings_changed", _on_settings_changed)
	if camera_pivot != null:
		_camera_pitch = camera_pivot.rotation.x
		_target_camera_pitch = _camera_pitch
		_camera_yaw = _get_camera_global_yaw()
		_target_camera_yaw = _camera_yaw
	_apply_mouse_capture_mode()


func _process(delta: float) -> void:
	_apply_camera_rotation(delta)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_add_camera_yaw(-event.relative.x * mouse_sensitivity)
		_add_camera_pitch(-event.relative.y * mouse_sensitivity)


func _unhandled_input(event: InputEvent) -> void:
	if actor == null:
		return

	if not get_tree().paused and event.is_action_pressed("interact"):
		if actor.has_method("interact") and bool(actor.call("interact")):
			get_viewport().set_input_as_handled()
			return

	if not get_tree().paused and event.is_action_pressed("use_item"):
		if actor.has_method("use_equipped_primary") and bool(actor.call("use_equipped_primary")):
			get_viewport().set_input_as_handled()
			return

	if not get_tree().paused and event.is_action_pressed("secondary_item_action"):
		if actor.has_method("use_equipped_secondary") and bool(actor.call("use_equipped_secondary")):
			get_viewport().set_input_as_handled()
			return

	if not get_tree().paused and event.is_action_pressed("drop_item"):
		if actor.has_method("throw_equipped") and bool(actor.call("throw_equipped")):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.pressed and _should_capture_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if actor == null:
		return

	var head_underwater := _is_head_underwater()
	var swimming := _is_swimming()

	if swimming:
		actor.velocity.y = move_toward(actor.velocity.y, 0.0, swim_vertical_friction * delta)
	elif not actor.is_on_floor():
		actor.velocity += actor.get_gravity() * delta

	if not swimming and Input.is_action_just_pressed("jump") and actor.is_on_floor() and actor.can_move():
		actor.velocity.y = jump_velocity

	var look_axis := Input.get_axis("look_left", "look_right")
	if not is_zero_approx(look_axis):
		_add_camera_yaw(-look_axis * gamepad_look_sensitivity * delta)

	var look_vertical_axis := Input.get_axis("look_up", "look_down")
	if not is_zero_approx(look_vertical_axis):
		_add_camera_pitch(-look_vertical_axis * gamepad_look_sensitivity * delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _get_camera_relative_direction(input_dir, swimming)
	var moving: bool = direction != Vector3.ZERO
	var moving_backward := moving and input_dir.y > 0.1
	var can_move: bool = actor.can_move()
	var wants_to_run := _wants_to_run(moving, moving_backward)
	var running := can_move and not swimming and _can_run(wants_to_run)

	actor.process_survival(delta, moving and can_move, swimming, head_underwater, running)
	_update_run_exhaustion(wants_to_run)
	var speed_multiplier: float = actor.get_movement_speed_multiplier()
	var movement_speed_multiplier := swim_speed_multiplier if swimming else _get_movement_speed_multiplier(running)

	if swimming and can_move:
		_turn_actor_toward_camera(delta)

	if moving and can_move:
		if not swimming:
			_turn_actor_for_movement(input_dir, direction, delta)
		var direction_speed_multiplier := backward_speed_multiplier if moving_backward else 1.0
		var target_speed: float = speed * movement_speed_multiplier * speed_multiplier * direction_speed_multiplier
		actor.velocity.x = move_toward(actor.velocity.x, direction.x * target_speed, acceleration * delta)
		if swimming:
			actor.velocity.y = move_toward(actor.velocity.y, direction.y * target_speed, acceleration * delta)
		actor.velocity.z = move_toward(actor.velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		actor.velocity.x = move_toward(actor.velocity.x, 0, friction * delta)
		if swimming:
			actor.velocity.y = move_toward(actor.velocity.y, 0, swim_vertical_friction * delta)
		actor.velocity.z = move_toward(actor.velocity.z, 0, friction * delta)

	if swimming and Input.is_action_pressed("jump") and can_move:
		actor.velocity.y = move_toward(actor.velocity.y, swim_up_speed, swim_up_acceleration * delta)

	actor.move_and_slide()
	actor.push_rigid_body_collisions(direction)

	if actor.has_method("set_locomotion_animation"):
		var horizontal_speed := Vector2(actor.velocity.x, actor.velocity.z).length()
		var is_swim_ascending := swimming and Input.is_action_pressed("jump") and can_move
		var is_moving: bool = (moving or is_swim_ascending if swimming else horizontal_speed > 0.1) and can_move
		var swim_drift := swimming and head_underwater and not moving and not is_swim_ascending and can_move
		var should_play_running := is_moving and running and _get_energy_ratio() > run_animation_min_energy_ratio
		actor.call("set_locomotion_animation", is_moving, should_play_running, not actor.is_on_floor() and not swimming, swimming, moving_backward, swim_drift)


func _add_camera_yaw(amount: float) -> void:
	_target_camera_yaw = wrapf(_target_camera_yaw + amount, -PI, PI)


func _add_camera_pitch(amount: float) -> void:
	if camera_pivot == null:
		return

	var max_angle := deg_to_rad(max_look_angle_degrees)
	_target_camera_pitch = clampf(
		_target_camera_pitch + amount,
		-max_angle,
		max_angle
	)


func _apply_camera_rotation(delta: float) -> void:
	if camera_pivot == null:
		return

	if look_smoothing <= 0.0:
		_camera_pitch = _target_camera_pitch
		_camera_yaw = _target_camera_yaw
	else:
		var weight := 1.0 - exp(-look_smoothing * delta)
		_camera_pitch = lerpf(_camera_pitch, _target_camera_pitch, weight)
		_camera_yaw = lerp_angle(_camera_yaw, _target_camera_yaw, weight)

	camera_pivot.rotation.x = _camera_pitch
	camera_pivot.rotation.y = _camera_yaw - _get_actor_global_yaw()


func _get_camera_relative_direction(input_dir: Vector2, include_pitch := false) -> Vector3:
	if input_dir == Vector2.ZERO:
		return Vector3.ZERO
	if include_pitch:
		return _get_camera_swim_direction(input_dir)

	var yaw_basis := Basis(Vector3.UP, _camera_yaw)
	var forward: Vector3 = -yaw_basis.z
	var right: Vector3 = yaw_basis.x
	forward.y = 0.0
	right.y = 0.0
	forward = forward.normalized()
	right = right.normalized()
	return (right * input_dir.x - forward * input_dir.y).normalized()


func _get_camera_swim_direction(input_dir: Vector2) -> Vector3:
	var basis := camera.global_transform.basis if camera != null else Basis(Vector3.UP, _camera_yaw)
	var forward: Vector3 = -basis.z
	var right: Vector3 = basis.x
	return (right * input_dir.x - forward * input_dir.y).normalized()


func _turn_actor_for_movement(input_dir: Vector2, direction: Vector3, delta: float) -> void:
	if actor == null or direction == Vector3.ZERO:
		return

	var facing_direction := -direction if input_dir.y > 0.1 else direction

	var target_yaw := atan2(-facing_direction.x, -facing_direction.z)
	var weight := 1.0 if turn_smoothing <= 0.0 else 1.0 - exp(-turn_smoothing * delta)
	actor.rotation.y = lerp_angle(actor.rotation.y, target_yaw, weight)


func _turn_actor_toward_camera(delta: float) -> void:
	if actor == null:
		return
	var target_yaw := _get_camera_global_yaw()
	var weight := 1.0 if turn_smoothing <= 0.0 else 1.0 - exp(-turn_smoothing * delta)
	actor.rotation.y = lerp_angle(actor.rotation.y, target_yaw, weight)


func _wants_to_run(moving: bool, moving_backward: bool) -> bool:
	return moving and not moving_backward and InputMap.has_action("run") and Input.is_action_pressed("run")


func _can_run(wants_to_run: bool) -> bool:
	if not wants_to_run:
		_run_exhausted = false
		return false

	var current_energy := _get_current_energy()
	if _run_exhausted:
		if current_energy < run_resume_energy:
			return false
		_run_exhausted = false

	return current_energy > minimum_run_energy


func _get_movement_speed_multiplier(running: bool) -> float:
	if not running:
		return walk_speed_multiplier

	var energy_ratio := _get_energy_ratio()
	return lerpf(walk_speed_multiplier, 1.0, energy_ratio)


func _update_run_exhaustion(wants_to_run: bool) -> void:
	if not wants_to_run:
		_run_exhausted = false
		return
	if _get_current_energy() <= minimum_run_energy:
		_run_exhausted = true


func _get_current_energy() -> float:
	var stats: Node = _get_actor_stats()
	if stats == null:
		return INF

	var current_energy: Variant = stats.get("current_energy")
	if current_energy == null:
		return INF
	return float(current_energy)


func _get_energy_ratio() -> float:
	var stats: Node = _get_actor_stats()
	if stats == null:
		return 1.0

	var current_energy: Variant = stats.get("current_energy")
	if current_energy == null:
		return 1.0

	var max_energy := 0.0
	if stats.has_method("get_max_energy"):
		max_energy = float(stats.call("get_max_energy"))
	else:
		var base_max_energy: Variant = stats.get("base_max_energy")
		if base_max_energy != null:
			max_energy = float(base_max_energy)

	if max_energy <= 0.0:
		return 1.0
	return clampf(float(current_energy) / max_energy, 0.0, 1.0)


func _get_actor_stats() -> Node:
	if actor == null or not actor.has_method("get_stats"):
		return null
	return actor.call("get_stats") as Node


func _get_camera_global_yaw() -> float:
	if camera_pivot == null:
		return _get_actor_global_yaw()
	return camera_pivot.global_rotation.y


func _get_actor_global_yaw() -> float:
	if actor == null or not actor is Node3D:
		return 0.0
	return (actor as Node3D).global_rotation.y


func _is_underwater() -> bool:
	if underwater_environment == null or not underwater_environment.has_method("is_underwater"):
		return false
	return bool(underwater_environment.call("is_underwater"))


func _is_head_underwater() -> bool:
	if actor == null or not actor is Node3D or underwater_environment == null:
		return _is_underwater()
	if not underwater_environment.has_method("is_water_at_point"):
		return _is_underwater()

	var actor_node := actor as Node3D
	return bool(underwater_environment.call("is_water_at_point", actor_node.global_position + Vector3.UP * breath_probe_height))


func _is_swimming() -> bool:
	if actor == null or not actor is Node3D or underwater_environment == null:
		return false
	if not underwater_environment.has_method("is_water_at_point"):
		return _is_underwater()

	var actor_node := actor as Node3D
	var probe_origin: Vector3 = actor_node.global_position + Vector3.UP * swim_probe_height
	for probe_position in _get_swim_probe_positions(probe_origin):
		if bool(underwater_environment.call("is_water_at_point", probe_position)):
			return true
	return false


func _get_swim_probe_positions(origin: Vector3) -> Array[Vector3]:
	var radius := maxf(swim_probe_radius, 0.0)
	var positions: Array[Vector3] = [origin]
	if radius <= 0.0:
		return positions

	positions.append(origin + Vector3(radius, 0.0, 0.0))
	positions.append(origin - Vector3(radius, 0.0, 0.0))
	positions.append(origin + Vector3(0.0, 0.0, radius))
	positions.append(origin - Vector3(0.0, 0.0, radius))
	return positions


func _on_settings_changed() -> void:
	_apply_mouse_capture_mode()


func _apply_mouse_capture_mode() -> void:
	if _should_capture_mouse():
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _should_capture_mouse() -> bool:
	if get_tree().paused:
		return false
	if _audio_manager != null and _audio_manager.has_method("get_settings"):
		var settings: Dictionary = _audio_manager.call("get_settings")
		return str(settings.get("input_mode", "keyboard")) != "joystick"
	return true
