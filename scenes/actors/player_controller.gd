extends Node
class_name PlayerController

@export var actor_path: NodePath = NodePath("..")
@export var camera_pivot_path: NodePath = NodePath("../CameraPivot")
@export var underwater_environment_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D/UnderwaterEnvironment")

@export var speed := 15.0
@export var jump_velocity := 14.5
@export var mouse_sensitivity := 0.0025
@export var gamepad_look_sensitivity := 3.0
@export_range(10.0, 89.0, 1.0) var max_look_angle_degrees := 65.0
@export_range(0.0, 60.0, 0.5) var look_smoothing := 18.0
@export var acceleration := 18.0
@export var friction := 22.0

@onready var actor = get_node_or_null(actor_path)
@onready var camera_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
@onready var underwater_environment: Node = get_node_or_null(underwater_environment_path)

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
		actor.rotate_y(-event.relative.x * mouse_sensitivity)
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

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if actor == null:
		return

	if not actor.is_on_floor():
		actor.velocity += actor.get_gravity() * delta

	if Input.is_action_just_pressed("jump") and actor.is_on_floor() and actor.can_move():
		actor.velocity.y = jump_velocity

	var look_axis := Input.get_axis("look_left", "look_right")
	if not is_zero_approx(look_axis):
		actor.rotate_y(-look_axis * gamepad_look_sensitivity * delta)

	var look_vertical_axis := Input.get_axis("look_up", "look_down")
	if not is_zero_approx(look_vertical_axis):
		_add_camera_pitch(-look_vertical_axis * gamepad_look_sensitivity * delta)

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (actor.global_transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var moving: bool = direction != Vector3.ZERO

	actor.process_survival(delta, moving, false, _is_underwater())
	var speed_multiplier: float = actor.get_movement_speed_multiplier()

	if moving and actor.can_move():
		var target_speed: float = speed * speed_multiplier
		actor.velocity.x = move_toward(actor.velocity.x, direction.x * target_speed, acceleration * delta)
		actor.velocity.z = move_toward(actor.velocity.z, direction.z * target_speed, acceleration * delta)
	else:
		actor.velocity.x = move_toward(actor.velocity.x, 0, friction * delta)
		actor.velocity.z = move_toward(actor.velocity.z, 0, friction * delta)

	actor.move_and_slide()
	actor.push_rigid_body_collisions(direction)


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
