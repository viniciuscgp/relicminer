extends Node3D
class_name RainController

@export_group("Rain")
## Quantidade maxima de gotas quando a chuva esta em intensidade 1.0.
@export_range(0, 20000, 1) var max_particles := 3200
## Largura/profundidade da area local onde as gotas sao emitidas ao redor da camera.
@export_range(10.0, 220.0, 1.0) var rain_area_size := 70.0
## Altura usada para posicionar o emissor de chuva acima da camera.
@export_range(8.0, 80.0, 1.0) var rain_height := 34.0
## Quando ativo, o emissor segue a camera e simula chuva ao redor do jogador.
@export var follow_camera := true

@export_group("Lightning")
## Ativa flashes e raio visual quando o perfil de clima tiver Lightning Activity acima de 0.
@export var lightning_enabled := true
## Menor intervalo possivel entre relampagos, antes da escala por intensidade da tempestade.
@export_range(0.5, 120.0, 0.1) var lightning_min_interval := 4.0
## Maior intervalo possivel entre relampagos, antes da escala por intensidade da tempestade.
@export_range(0.5, 180.0, 0.1) var lightning_max_interval := 12.0
## Duracao visual do flash em segundos.
@export_range(0.03, 2.0, 0.01) var lightning_flash_duration := 0.28
## Alpha maximo do flash na tela. Aumente se o relampago ainda estiver dificil de ver.
@export_range(0.0, 1.0, 0.01) var lightning_flash_alpha := 0.36
## Energia da luz temporaria criada pelo relampago.
@export_range(0.0, 80.0, 0.1) var lightning_light_energy := 18.0
## Distancia do raio visual em frente a camera.
@export_range(20.0, 800.0, 1.0) var lightning_bolt_distance := 180.0
## Altura visual do raio.
@export_range(10.0, 300.0, 1.0) var lightning_bolt_height := 95.0
## Largura do traço do raio.
@export_range(0.1, 12.0, 0.1) var lightning_bolt_width := 2.6
## Cor usada no flash, luz e raio.
@export var lightning_color := Color(0.64, 0.74, 1.0, 1.0)

var _particles: GPUParticles3D
var _material: ParticleProcessMaterial
var _mesh_material: StandardMaterial3D
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _flash_light: OmniLight3D
var _bolt_mesh: MeshInstance3D
var _bolt_material: StandardMaterial3D
var _intensity := 0.0
var _lightning_activity := 0.0
var _lightning_timer := 0.0
var _flash_time_left := 0.0
var _flash_total_time := 0.0
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	_build_particles()
	_build_lightning_visuals()
	set_weather(0.0, 0.0)


func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if follow_camera and camera != null:
		global_position = camera.global_position + Vector3.UP * rain_height * 0.45
	_update_lightning(delta, camera)


func set_intensity(value: float) -> void:
	set_weather(value, _lightning_activity)


func set_weather(rain_intensity: float, lightning_activity: float) -> void:
	var previous_storm := _get_storm_strength()
	_intensity = clampf(rain_intensity, 0.0, 1.0)
	_lightning_activity = clampf(lightning_activity, 0.0, 1.0)
	if _particles == null:
		return

	_particles.emitting = _intensity > 0.01
	_particles.amount_ratio = _intensity
	if _mesh_material != null:
		var color := Color(0.58, 0.68, 0.82, lerpf(0.0, 0.48, _intensity))
		_mesh_material.albedo_color = color
	if previous_storm <= 0.01 and _get_storm_strength() > 0.01:
		_schedule_next_lightning(true)


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


func _build_lightning_visuals() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "LightningFlashLayer"
	_flash_layer.layer = 2
	add_child(_flash_layer)

	_flash_rect = ColorRect.new()
	_flash_rect.name = "LightningFlash"
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(lightning_color.r, lightning_color.g, lightning_color.b, 0.0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_layer.add_child(_flash_rect)

	_flash_light = OmniLight3D.new()
	_flash_light.name = "LightningLight"
	_flash_light.light_color = lightning_color
	_flash_light.light_energy = 0.0
	_flash_light.omni_range = 280.0
	_flash_light.shadow_enabled = false
	add_child(_flash_light)

	_bolt_material = StandardMaterial3D.new()
	_bolt_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bolt_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_bolt_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_bolt_material.albedo_color = Color(lightning_color.r, lightning_color.g, lightning_color.b, 0.0)
	_bolt_material.emission_enabled = true
	_bolt_material.emission = lightning_color
	_bolt_material.emission_energy_multiplier = 8.0

	_bolt_mesh = MeshInstance3D.new()
	_bolt_mesh.name = "LightningBolt"
	_bolt_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt_mesh.visible = false
	_bolt_mesh.material_override = _bolt_material
	add_child(_bolt_mesh)


func _update_lightning(delta: float, camera: Camera3D) -> void:
	_resize_flash_rect()
	_fade_lightning(delta)
	if not lightning_enabled:
		return

	var storm_strength := _get_storm_strength()
	if storm_strength <= 0.01:
		_lightning_timer = 0.0
		return

	if _lightning_timer <= 0.0:
		_schedule_next_lightning(true)
		return

	_lightning_timer -= delta
	if _lightning_timer <= 0.0:
		_trigger_lightning(camera, storm_strength)
		_schedule_next_lightning(false)


func _fade_lightning(delta: float) -> void:
	if _flash_time_left > 0.0:
		_flash_time_left = maxf(0.0, _flash_time_left - delta)
	var flash_ratio := 0.0
	if _flash_total_time > 0.0:
		flash_ratio = clampf(_flash_time_left / _flash_total_time, 0.0, 1.0)
	flash_ratio = pow(flash_ratio, 1.7)

	if _flash_rect != null:
		_flash_rect.color = Color(lightning_color.r, lightning_color.g, lightning_color.b, lightning_flash_alpha * flash_ratio)
	if _flash_light != null:
		_flash_light.light_color = lightning_color
		_flash_light.light_energy = lightning_light_energy * flash_ratio
	if _bolt_material != null:
		_bolt_material.albedo_color = Color(lightning_color.r, lightning_color.g, lightning_color.b, flash_ratio)
		_bolt_material.emission_energy_multiplier = lerpf(0.0, 8.0, flash_ratio)
	if _bolt_mesh != null:
		_bolt_mesh.visible = flash_ratio > 0.03


func _resize_flash_rect() -> void:
	if _flash_rect == null:
		return

	_flash_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_flash_rect.position = Vector2.ZERO
	_flash_rect.size = get_viewport().get_visible_rect().size


func _trigger_lightning(camera: Camera3D, storm_strength: float) -> void:
	_flash_total_time = lightning_flash_duration
	_flash_time_left = lightning_flash_duration
	if camera == null:
		return

	var forward := -camera.global_transform.basis.z.normalized()
	var right := camera.global_transform.basis.x.normalized()
	var up := camera.global_transform.basis.y.normalized()
	var lateral := right * _random.randf_range(-70.0, 70.0)
	var center := camera.global_position + forward * lightning_bolt_distance + up * _random.randf_range(30.0, 70.0) + lateral

	if _flash_light != null:
		_flash_light.global_position = center
	if _bolt_mesh != null:
		_bolt_mesh.global_transform = Transform3D(camera.global_transform.basis, center)
		_bolt_mesh.mesh = _create_lightning_bolt_mesh(storm_strength)


func _create_lightning_bolt_mesh(storm_strength: float) -> ArrayMesh:
	var segment_count := 7
	var height := lightning_bolt_height * lerpf(0.75, 1.15, storm_strength)
	var half_height := height * 0.5
	var width := lightning_bolt_width * lerpf(0.8, 1.35, storm_strength)
	var points: Array[Vector2] = []
	for index in range(segment_count + 1):
		var t := float(index) / float(segment_count)
		var jitter := 0.0 if index == 0 or index == segment_count else _random.randf_range(-16.0, 16.0)
		points.append(Vector2(jitter, half_height - height * t))

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	for index in range(segment_count):
		var a := points[index]
		var b := points[index + 1]
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x) * width
		var base := vertices.size()
		vertices.append(Vector3(a.x - normal.x, a.y - normal.y, 0.0))
		vertices.append(Vector3(a.x + normal.x, a.y + normal.y, 0.0))
		vertices.append(Vector3(b.x + normal.x, b.y + normal.y, 0.0))
		vertices.append(Vector3(b.x - normal.x, b.y - normal.y, 0.0))
		indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _schedule_next_lightning(initial := false) -> void:
	var storm_strength := maxf(_get_storm_strength(), 0.2)
	if initial:
		_lightning_timer = _random.randf_range(1.0, 3.0)
	else:
		_lightning_timer = _random.randf_range(lightning_min_interval, lightning_max_interval) / storm_strength


func _get_storm_strength() -> float:
	return clampf(_intensity * _lightning_activity, 0.0, 1.0)
