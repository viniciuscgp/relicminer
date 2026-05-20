extends MeshInstance3D
class_name CloudLayer

## Area horizontal coberta pelos agrupamentos de nuvens ao redor da camera.
@export_range(100.0, 4000.0, 10.0) var size := 1800.0
## Altura das nuvens acima da camera quando follow_camera esta ativo.
@export_range(10.0, 600.0, 1.0) var height := 260.0
## Quando ativo, a camada segue a camera para parecer que o ceu cobre o mundo inteiro.
@export var follow_camera := true
## Quantidade de massas de nuvem grandes.
@export_range(1, 80, 1) var cloud_cluster_count := 18
## Quantidade media de puffs por massa de nuvem.
@export_range(1, 24, 1) var puffs_per_cluster := 9
## Tamanho minimo de cada puff individual.
@export_range(4.0, 180.0, 1.0) var min_puff_size := 26.0
## Tamanho maximo de cada puff individual.
@export_range(4.0, 240.0, 1.0) var max_puff_size := 78.0
## Largura media de cada massa de nuvem.
@export_range(10.0, 360.0, 1.0) var cluster_spread := 95.0
## Multiplicador geral do movimento das nuvens. Baixe para nuvens quase paradas.
@export_range(0.0, 1.0, 0.001) var drift_speed_multiplier := 0.035
## Variação lenta do vento. Faz as nuvens alternarem entre quase paradas e um drift suave.
@export_range(0.0, 1.0, 0.001) var slow_drift_variation := 0.45
## Velocidade da variação lenta do vento. Menor significa ciclos mais longos.
@export_range(0.0, 0.2, 0.001) var slow_drift_variation_speed := 0.018

var _material: ShaderMaterial
var _puffs: Array[MeshInstance3D] = []
var _base_positions: Array[Vector3] = []
var _puff_scales: Array[Vector3] = []
var _coverage := 0.0
var _wind_offset := Vector2.ZERO
var _wind_direction := Vector2.RIGHT
var _wind_speed := 0.0
var _drift_time := 0.0


func _ready() -> void:
	_build_layer()


func _process(delta: float) -> void:
	_drift_time += delta
	var drift_variation := lerpf(1.0 - slow_drift_variation, 1.0, (sin(_drift_time * TAU * slow_drift_variation_speed) + 1.0) * 0.5)
	var drift_speed := _wind_speed * drift_speed_multiplier * drift_variation
	_wind_offset += _wind_direction.normalized() * drift_speed * delta

	if not follow_camera:
		_update_puffs(null)
		return

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = Vector3(camera.global_position.x, camera.global_position.y + height, camera.global_position.z)
	_update_puffs(camera)


func set_weather(coverage: float, wind_direction: Vector2, wind_speed: float, day_factor: float) -> void:
	_coverage = clampf(coverage, 0.0, 1.0)
	_wind_direction = wind_direction if wind_direction.length_squared() > 0.001 else Vector2.RIGHT
	_wind_speed = maxf(wind_speed, 0.0)
	visible = _coverage > 0.015
	if _material == null:
		return

	var alpha := lerpf(0.0, 0.92, smoothstep(0.0, 1.0, _coverage))
	var shade := lerpf(0.22, 1.0, clampf(day_factor, 0.0, 1.0))
	_material.set_shader_parameter("opacity", alpha)
	_material.set_shader_parameter("cloud_color", Color(shade, shade, shade, 1.0))


func _build_layer() -> void:
	mesh = null

	var noise := FastNoiseLite.new()
	noise.seed = 90843
	noise.frequency = 0.085
	noise.fractal_octaves = 4

	var noise_texture := NoiseTexture2D.new()
	noise_texture.width = 512
	noise_texture.height = 512
	noise_texture.noise = noise
	noise_texture.seamless = true

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D cloud_noise;
uniform float opacity = 0.0;
uniform vec4 cloud_color : source_color = vec4(1.0);

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	float distance_from_center = length(centered);
	float noise_a = texture(cloud_noise, UV * 1.6).r;
	float noise_b = texture(cloud_noise, UV * 4.4 + vec2(0.37, 0.19)).r;
	float broken_edge = mix(noise_a, noise_b, 0.45);
	float dome = smoothstep(1.0, 0.12, distance_from_center);
	float soft_edge = smoothstep(1.08, 0.58 + broken_edge * 0.24, distance_from_center);
	float alpha = dome * soft_edge * opacity;
	ALBEDO = cloud_color.rgb;
	ALPHA = alpha;
}
"""

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("cloud_noise", noise_texture)
	_build_puffs()
	set_weather(0.0, Vector2.RIGHT, 0.0, 1.0)


func _build_puffs() -> void:
	for child in get_children():
		child.queue_free()
	_puffs.clear()
	_base_positions.clear()
	_puff_scales.clear()

	var random := RandomNumberGenerator.new()
	random.seed = 119923
	var puff_mesh := QuadMesh.new()
	puff_mesh.size = Vector2.ONE

	for _cluster_index in range(cloud_cluster_count):
		var cluster_center := Vector3(
			random.randf_range(-size * 0.5, size * 0.5),
			random.randf_range(-height * 0.18, height * 0.16),
			random.randf_range(-size * 0.5, size * 0.5)
		)
		var cluster_width := cluster_spread * random.randf_range(0.72, 1.45)
		var puff_count: int = max(1, puffs_per_cluster + random.randi_range(-3, 4))
		for _puff_index in range(puff_count):
			var puff := MeshInstance3D.new()
			puff.mesh = puff_mesh
			puff.material_override = _material
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(puff)
			var local_position := cluster_center + Vector3(
				random.randf_range(-cluster_width, cluster_width),
				random.randf_range(-cluster_width * 0.18, cluster_width * 0.28),
				random.randf_range(-cluster_width * 0.45, cluster_width * 0.45)
			)
			var scale_x := random.randf_range(min_puff_size, max_puff_size)
			var scale_y := scale_x * random.randf_range(0.42, 0.72)
			var puff_scale := Vector3(scale_x, scale_y, 1.0)
			puff.scale = puff_scale
			_puffs.append(puff)
			_base_positions.append(local_position)
			_puff_scales.append(puff_scale)


func _update_puffs(camera: Camera3D) -> void:
	var wind := Vector3(_wind_offset.x, 0.0, _wind_offset.y)
	for index in range(_puffs.size()):
		var puff := _puffs[index]
		puff.position = _wrap_cloud_position(_base_positions[index] + wind)
		if camera != null:
			puff.global_transform.basis = camera.global_transform.basis
			puff.scale = _puff_scales[index]


func _wrap_cloud_position(position: Vector3) -> Vector3:
	var half_size := size * 0.5
	position.x = wrapf(position.x, -half_size, half_size)
	position.z = wrapf(position.z, -half_size, half_size)
	return position
