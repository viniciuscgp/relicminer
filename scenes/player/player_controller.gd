extends Node
class_name PlayerController

@export_group("Node References")
## Node do personagem controlado. Normalmente aponta para o CharacterBody3D pai.
@export var actor_path: NodePath = NodePath("..")
## Pivot vertical/horizontal da camera usado para mirar e suavizar a rotacao.
@export var camera_pivot_path: NodePath = NodePath("../CameraPivot")
## Camera principal usada para calcular direcao relativa de movimento e mira.
@export var camera_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D")
## Ambiente subaquatico ligado/desligado quando a camera entra na agua.
@export var underwater_environment_path: NodePath = NodePath("../CameraPivot/SpringArm3D/Camera3D/UnderwaterEnvironment")
## Caminho fallback do esqueleto do personagem. Quando ha Male/Female, o esqueleto ativo e resolvido via PlayerAnimation.
@export var skeleton_path: NodePath = NodePath("../visual/PlayerAnimation/Armature/Skeleton3D")
## Probe usado como fallback para detectar se a cabeca esta submersa.
@export var breath_probe_path: NodePath = NodePath("../visual/PlayerAnimation/Armature/Skeleton3D/BreathProbeAttachment/BreathProbe")

@export_group("Ground Movement")
## Velocidade base do personagem em metros por segundo antes de multiplicadores.
@export var speed := 15.0
## Multiplicador aplicado quando o jogador caminha em vez de correr.
@export_range(0.1, 1.0, 0.05) var walk_speed_multiplier := 0.45
## Multiplicador aplicado quando o jogador se move para tras.
@export_range(0.1, 1.0, 0.05) var backward_speed_multiplier := 0.55
## Forca inicial do pulo aplicada no eixo Y.
@export var jump_velocity := 7.0
## Taxa de aceleracao ao entrar em movimento.
@export var acceleration := 18.0
## Taxa de desaceleracao quando nao ha input de movimento.
@export var friction := 22.0

@export_group("Running")
## Energia minima necessaria para iniciar ou manter corrida.
@export var minimum_run_energy := 0.0
## Energia necessaria para voltar a correr depois de exaustao.
@export var run_resume_energy := 12.0
## Razao minima de energia para permitir animacao de corrida; abaixo disso a locomocao usa walk.
@export_range(0.0, 1.0, 0.05) var run_animation_min_energy_ratio := 0.2

@export_group("Camera Look")
## Sensibilidade do mouse para girar a camera.
@export var mouse_sensitivity := 0.0025
## Sensibilidade do analogico/gamepad para girar a camera.
@export var gamepad_look_sensitivity := 3.0
## Angulo vertical maximo da camera em graus, para cima e para baixo.
@export_range(10.0, 89.0, 1.0) var max_look_angle_degrees := 65.0
## Suavizacao da rotacao da camera. Maior valor responde mais rapido.
@export_range(0.0, 60.0, 0.5) var look_smoothing := 18.0

@export_group("Body Rotation")
## Suavizacao da rotacao do personagem em direcao ao movimento/camera. Maior valor responde mais rapido.
@export_range(0.0, 30.0, 0.5) var turn_smoothing := 14.0

@export_group("Swimming")
## Multiplicador da velocidade base enquanto o personagem esta nadando.
@export var swim_speed_multiplier := 0.55
## Atrito vertical aplicado na agua para reduzir subida/descida involuntaria.
@export var swim_vertical_friction := 10.0
## Velocidade vertical alvo ao segurar pulo enquanto submerso.
@export_range(0.0, 20.0, 0.1, "or_greater") var swim_up_speed := 8.0
## Aceleracao usada para atingir a velocidade vertical de subida.
@export_range(0.0, 80.0, 0.5, "or_greater") var swim_up_acceleration := 32.0
## Velocidade vertical minima para manter animacao de saida da agua.
@export_range(0.0, 10.0, 0.1, "or_greater") var swim_exit_animation_min_up_speed := 1.0
## Altura do probe usado para detectar superficie/volume de agua ao redor do corpo.
@export var swim_probe_height := 1.0
## Raio do probe de natacao usado em consultas fisicas.
@export var swim_probe_radius := 0.25
## Altura inicial do probe que verifica apoio no fundo enquanto em agua rasa.
@export var swim_floor_probe_start_height := 0.2
## Distancia vertical do probe que verifica se ha chao sob o personagem na agua.
@export var swim_floor_probe_distance := 0.6
## Altura fallback do ponto de respiracao quando breath_probe_path nao resolve um node.
@export var breath_probe_height := 2.55
## Ossos que podem ser testados contra a superficie para detectar natacao de superficie.
@export var surface_swim_bone_names: Array[StringName] = [&"L_Clavicle", &"R_Clavicle"]
## Quantidade minima de ossos acima/fora da agua para considerar natacao de superficie.
@export_range(1, 8, 1) var surface_swim_required_bone_hits := 1

@onready var actor = get_node_or_null(actor_path)
@onready var camera_pivot: Node3D = get_node_or_null(camera_pivot_path) as Node3D
@onready var camera: Node3D = get_node_or_null(camera_path) as Node3D
@onready var underwater_environment: Node = get_node_or_null(underwater_environment_path)
@onready var skeleton: Skeleton3D = get_node_or_null(skeleton_path) as Skeleton3D
@onready var breath_probe: Node3D = get_node_or_null(breath_probe_path) as Node3D

var _camera_pitch := 0.0
var _target_camera_pitch := 0.0
var _camera_yaw := 0.0
var _target_camera_yaw := 0.0
var _audio_manager: Node
var _run_exhausted := false


func _ready() -> void:
	refresh_character_nodes()
	_audio_manager = get_node_or_null("/root/AudioManager")
	if _audio_manager != null and _audio_manager.has_signal("settings_changed"):
		_audio_manager.connect("settings_changed", _on_settings_changed)
	if camera_pivot != null:
		_camera_pitch = camera_pivot.rotation.x
		_target_camera_pitch = _camera_pitch
		_camera_yaw = _get_camera_global_yaw()
		_target_camera_yaw = _camera_yaw
	_apply_mouse_capture_mode()


func refresh_character_nodes() -> void:
	skeleton = null
	breath_probe = null

	var actor := get_node_or_null(actor_path)
	if actor != null:
		var player_animation := actor.get_node_or_null("visual/PlayerAnimation")
		if player_animation != null and player_animation.has_method("get_active_skeleton"):
			skeleton = player_animation.call("get_active_skeleton") as Skeleton3D

	if skeleton == null:
		skeleton = get_node_or_null(skeleton_path) as Skeleton3D
	if breath_probe == null:
		breath_probe = get_node_or_null(breath_probe_path) as Node3D
	if breath_probe == null and skeleton != null:
		breath_probe = skeleton.get_node_or_null("BreathProbeAttachment/BreathProbe") as Node3D


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
	var has_water_footing := _has_water_footing()

	if swimming:
		actor.velocity.y = move_toward(actor.velocity.y, 0.0, swim_vertical_friction * delta)
	elif not actor.is_on_floor():
		actor.velocity += actor.get_gravity() * delta

	if (not swimming or has_water_footing) and Input.is_action_just_pressed("jump") and actor.is_on_floor() and actor.can_move():
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

	if swimming and head_underwater and Input.is_action_pressed("jump") and can_move:
		actor.velocity.y = move_toward(actor.velocity.y, swim_up_speed, swim_up_acceleration * delta)
	elif swimming and not head_underwater and not has_water_footing and Input.is_action_pressed("jump") and can_move:
		actor.velocity.y = minf(actor.velocity.y, 0.0)

	actor.move_and_slide()
	actor.push_rigid_body_collisions(direction)

	if actor.has_method("set_locomotion_animation"):
		var animation_head_underwater := _is_head_underwater()
		var animation_swimming := _is_swimming()
		if _is_exiting_water_for_animation(animation_head_underwater):
			animation_swimming = false
		var horizontal_speed := Vector2(actor.velocity.x, actor.velocity.z).length()
		var is_swim_ascending := animation_swimming and animation_head_underwater and Input.is_action_pressed("jump") and can_move
		var is_moving: bool = (moving or is_swim_ascending if animation_swimming else horizontal_speed > 0.1) and can_move
		var swim_drift := animation_swimming and animation_head_underwater and not moving and not is_swim_ascending and can_move
		var should_play_running := is_moving and running and _get_energy_ratio() > run_animation_min_energy_ratio
		actor.call("set_locomotion_animation", is_moving, should_play_running, not actor.is_on_floor() and not animation_swimming, animation_swimming, moving_backward, swim_drift, horizontal_speed)


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

	return bool(underwater_environment.call("is_water_at_point", _get_breath_probe_position()))


func _is_swimming() -> bool:
	if actor == null or not actor is Node3D or underwater_environment == null:
		return false
	if not underwater_environment.has_method("is_water_at_point"):
		return _is_underwater()
	if _is_head_underwater():
		return true
	return _is_surface_swim_depth()


func _is_body_in_water() -> bool:
	var actor_node := actor as Node3D
	var probe_origin: Vector3 = actor_node.global_position + Vector3.UP * swim_probe_height
	for probe_position in _get_swim_probe_positions(probe_origin):
		if bool(underwater_environment.call("is_water_at_point", probe_position)):
			return true
	return false


func _is_surface_swim_depth() -> bool:
	if skeleton == null or surface_swim_bone_names.is_empty():
		return _is_body_in_water() and not _has_water_footing()

	var required_hits: int = clampi(surface_swim_required_bone_hits, 1, surface_swim_bone_names.size())
	var hits := 0
	for bone_name in surface_swim_bone_names:
		if _is_bone_in_water(bone_name):
			hits += 1
			if hits >= required_hits:
				return true
	return false


func _is_bone_in_water(bone_name: StringName) -> bool:
	var bone_position: Variant = _get_bone_global_position(bone_name)
	if not bone_position is Vector3:
		return false
	return bool(underwater_environment.call("is_water_at_point", bone_position))


func _get_bone_global_position(bone_name: StringName) -> Variant:
	if skeleton == null or bone_name == &"":
		return null
	var bone_index := skeleton.find_bone(String(bone_name))
	if bone_index < 0:
		return null
	return skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin


func _get_breath_probe_position() -> Vector3:
	if breath_probe != null:
		return breath_probe.global_position
	if actor != null and actor is Node3D:
		return (actor as Node3D).global_position + Vector3.UP * breath_probe_height
	return Vector3.ZERO


func _is_exiting_water_for_animation(head_underwater: bool) -> bool:
	return not head_underwater and Input.is_action_pressed("jump") and actor != null and actor.velocity.y > swim_exit_animation_min_up_speed


func _has_water_footing() -> bool:
	if actor == null or not actor is Node3D:
		return false
	if actor.has_method("is_on_floor") and bool(actor.call("is_on_floor")):
		return true
	if swim_floor_probe_distance <= 0.0:
		return false

	var actor_node := actor as Node3D
	var start := actor_node.global_position + Vector3.UP * maxf(swim_floor_probe_start_height, 0.0)
	var end := actor_node.global_position + Vector3.DOWN * swim_floor_probe_distance
	var query := PhysicsRayQueryParameters3D.create(start, end)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	if actor_node is CollisionObject3D:
		query.exclude = [(actor_node as CollisionObject3D).get_rid()]

	return not actor_node.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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
