extends CharacterBody3D


@export var speed := 15.0
@export var jump_velocity := 14.5
@export var mouse_sensitivity := 0.0025
@export var gamepad_look_sensitivity := 3.0
@export var acceleration := 18.0
@export var friction := 22.0

@onready var stats: Node = get_node_or_null("PlayerStats")
@onready var underwater_environment: Node = get_node_or_null("CameraPivot/SpringArm3D/Camera3D/UnderwaterEnvironment")


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)

	if event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor() and _can_move():
		velocity.y = jump_velocity

	var look_axis := Input.get_axis("look_left", "look_right")
	if not is_zero_approx(look_axis):
		rotate_y(-look_axis * gamepad_look_sensitivity * delta)

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


func _can_move() -> bool:
	return stats == null or not bool(stats.call("is_over_absolute_weight"))


func _is_underwater() -> bool:
	if underwater_environment == null or not underwater_environment.has_method("is_underwater"):
		return false
	return bool(underwater_environment.call("is_underwater"))
