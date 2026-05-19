extends Node3D
class_name RainController

## Quantidade maxima de gotas quando a chuva esta em intensidade 1.0.
@export_range(0, 20000, 1) var max_particles := 3200
## Largura/profundidade da area local onde as gotas sao emitidas ao redor da camera.
@export_range(10.0, 220.0, 1.0) var rain_area_size := 70.0
## Altura usada para posicionar o emissor de chuva acima da camera.
@export_range(8.0, 80.0, 1.0) var rain_height := 34.0
## Quando ativo, o emissor segue a camera e simula chuva ao redor do jogador.
@export var follow_camera := true

var _particles: GPUParticles3D
var _material: ParticleProcessMaterial
var _mesh_material: StandardMaterial3D
var _intensity := 0.0


func _ready() -> void:
	_build_particles()
	set_intensity(0.0)


func _process(_delta: float) -> void:
	if not follow_camera:
		return

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position + Vector3.UP * rain_height * 0.45


func set_intensity(value: float) -> void:
	_intensity = clampf(value, 0.0, 1.0)
	if _particles == null:
		return

	_particles.emitting = _intensity > 0.01
	_particles.amount_ratio = _intensity
	if _mesh_material != null:
		var color := Color(0.58, 0.68, 0.82, lerpf(0.0, 0.48, _intensity))
		_mesh_material.albedo_color = color


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.name = "RainParticles"
	_particles.amount = max_particles
	_particles.lifetime = 1.1
	_particles.preprocess = 0.6
	_particles.visibility_aabb = AABB(Vector3(-rain_area_size, -rain_height, -rain_area_size), Vector3(rain_area_size * 2.0, rain_height * 2.0, rain_area_size * 2.0))
	add_child(_particles)

	_material = ParticleProcessMaterial.new()
	_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_material.emission_box_extents = Vector3(rain_area_size * 0.5, 1.0, rain_area_size * 0.5)
	_material.direction = Vector3(0.12, -1.0, 0.04).normalized()
	_material.spread = 5.0
	_material.gravity = Vector3(0.0, -44.0, 0.0)
	_material.initial_velocity_min = 18.0
	_material.initial_velocity_max = 26.0
	_material.scale_min = 0.65
	_material.scale_max = 1.25
	_particles.process_material = _material

	var streak := QuadMesh.new()
	streak.size = Vector2(0.035, 1.35)
	_mesh_material = StandardMaterial3D.new()
	_mesh_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh_material.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_mesh_material.albedo_color = Color(0.58, 0.68, 0.82, 0.0)
	streak.material = _mesh_material
	_particles.draw_pass_1 = streak
