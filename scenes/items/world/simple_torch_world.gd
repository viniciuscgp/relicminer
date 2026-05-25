extends "res://scenes/items/item_world_base.gd"
class_name SimpleTorchWorld

@export_group("Torch Light")
## Energy or light intensity used for base light in the Torch Light settings.
@export_range(0.0, 10.0, 0.01) var base_light_energy := 3.05
## Energy or light intensity used for flicker in the Torch Light settings.
@export_range(0.0, 5.0, 0.01) var flicker_energy := 0.65
## Configures light range in the Torch Light settings.
@export_range(0.0, 20.0, 0.01) var light_range := 8.2
## Speed value used for flicker in the Torch Light settings.
@export_range(0.1, 30.0, 0.1) var flicker_speed := 11.0
## Controls whether cast torch shadows is enabled in the Torch Light settings.
@export var cast_torch_shadows := false
## Controls whether lit is enabled in the Torch Light settings.
@export var lit := true

@export_group("Flame")
## Energy or light intensity used for flame emission in the Flame settings.
@export_range(0.0, 5.0, 0.01) var flame_emission_energy := 3.5
## Configures flame scale flicker in the Flame settings.
@export_range(0.0, 1.0, 0.01) var flame_scale_flicker := 0.18
## Configures ember particles in the Flame settings.
@export_range(0, 256, 1) var ember_particles := 42

@onready var light: OmniLight3D = get_node_or_null("Visual/OmniLight3D") as OmniLight3D
@onready var flame: Node3D = get_node_or_null("Visual/FlamePlaceholder") as Node3D
@onready var outer_flame: Node3D = get_node_or_null("Visual/OuterFlame") as Node3D

var _flame_material: StandardMaterial3D
var _outer_flame_material: StandardMaterial3D
var _particles: GPUParticles3D
var _time_offset := 0.0
var _base_flame_scale := Vector3.ONE
var _base_outer_flame_scale := Vector3.ONE


func _ready() -> void:
	super._ready()
	_time_offset = randf() * TAU
	if flame != null:
		_base_flame_scale = flame.scale
		_flame_material = flame.get("material_override") as StandardMaterial3D
	if outer_flame != null:
		_base_outer_flame_scale = outer_flame.scale
		_outer_flame_material = outer_flame.get("material_override") as StandardMaterial3D
	_setup_light()
	_setup_particles()
	_apply_lit_state()


func _process(delta: float) -> void:
	if not lit or light == null:
		return

	_time_offset += delta * flicker_speed
	var wave := sin(_time_offset) * 0.55 + sin(_time_offset * 2.37) * 0.3 + sin(_time_offset * 5.11) * 0.15
	var normalized := clampf((wave + 1.0) * 0.5, 0.0, 1.0)
	light.light_energy = base_light_energy + flicker_energy * normalized
	if flame != null:
		var scale_multiplier := 1.0 + flame_scale_flicker * (normalized - 0.5)
		flame.scale = _base_flame_scale * scale_multiplier
	if outer_flame != null:
		var outer_scale_multiplier := 1.0 + flame_scale_flicker * 1.4 * (0.5 - normalized)
		outer_flame.scale = _base_outer_flame_scale * outer_scale_multiplier
	if _flame_material != null:
		_flame_material.emission_energy_multiplier = flame_emission_energy + normalized * 0.8
	if _outer_flame_material != null:
		_outer_flame_material.emission_energy_multiplier = flame_emission_energy * 0.55 + normalized * 0.45


func toggle_light() -> void:
	lit = not lit
	_apply_lit_state()


func _setup_light() -> void:
	if light == null:
		return

	light.light_color = Color(1.0, 0.52, 0.22, 1.0)
	light.light_energy = base_light_energy
	light.omni_range = light_range
	light.shadow_enabled = cast_torch_shadows
	light.shadow_bias = 0.03
	light.shadow_normal_bias = 1.0


func _setup_particles() -> void:
	if flame == null:
		return

	_particles = get_node_or_null("Visual/FlameParticles") as GPUParticles3D
	if _particles == null:
		_particles = GPUParticles3D.new()
		_particles.name = "FlameParticles"
		_particles.position = flame.position
		get_node("Visual").add_child(_particles)

	_particles.amount = ember_particles
	_particles.lifetime = 0.72
	_particles.preprocess = 0.2
	_particles.visibility_aabb = AABB(Vector3(-0.35, -0.1, -0.35), Vector3(0.7, 1.0, 0.7))

	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = 0.055
	process_material.direction = Vector3.UP
	process_material.spread = 22.0
	process_material.gravity = Vector3(0.0, 0.8, 0.0)
	process_material.initial_velocity_min = 0.22
	process_material.initial_velocity_max = 0.62
	process_material.angular_velocity_min = -40.0
	process_material.angular_velocity_max = 40.0
	process_material.scale_min = 0.018
	process_material.scale_max = 0.055
	_particles.process_material = process_material

	var ember_mesh := SphereMesh.new()
	ember_mesh.radius = 0.028
	ember_mesh.height = 0.052
	ember_mesh.radial_segments = 6
	ember_mesh.rings = 3

	var ember_material := StandardMaterial3D.new()
	ember_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_material.albedo_color = Color(1.0, 0.38, 0.07, 0.78)
	ember_material.emission_enabled = true
	ember_material.emission = Color(1.0, 0.26, 0.03, 1.0)
	ember_material.emission_energy_multiplier = 2.4
	ember_mesh.material = ember_material
	_particles.draw_pass_1 = ember_mesh


func _apply_lit_state() -> void:
	if light != null:
		light.visible = lit
	if flame != null:
		flame.visible = lit
	if outer_flame != null:
		outer_flame.visible = lit
	if _particles != null:
		_particles.visible = lit
		_particles.emitting = lit
