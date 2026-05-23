extends MeshInstance3D
class_name CloudLayer

## Raio da cupula de nuvens ao redor da camera.
@export_range(100.0, 4000.0, 10.0) var size := 1800.0
## Quanto o centro da cupula fica abaixo da camera. Ajuda a nuvem preencher o ceu sem cortar no horizonte.
@export_range(0.0, 600.0, 1.0) var height := 180.0
## Quando ativo, a cupula segue a posicao da camera para parecer que o ceu cobre o mundo inteiro.
@export var follow_camera := true
## Multiplicador geral do movimento das nuvens. Baixe para nuvens quase paradas.
@export_range(0.0, 1.0, 0.001) var drift_speed_multiplier := 0.035
## Variacao lenta do vento. Faz as nuvens alternarem entre quase paradas e um drift suave.
@export_range(0.0, 1.0, 0.001) var slow_drift_variation := 0.45
## Velocidade da variacao lenta do vento. Menor significa ciclos mais longos.
@export_range(0.0, 0.2, 0.001) var slow_drift_variation_speed := 0.018
## Opacidade maxima das nuvens no pico de cobertura.
@export_range(0.0, 1.0, 0.01) var max_opacity := 0.92
## Opacidade minima quando existe alguma cobertura. Evita que nuvens sorteadas baixas fiquem invisiveis.
@export_range(0.0, 1.0, 0.01) var min_visible_opacity := 0.22
## Controla a suavidade das bordas das nuvens na cupula procedural.
@export_range(0.05, 1.0, 0.01) var visibility_threshold_max := 0.45
## Quanto as nuvens ficam mais cinzas durante noite/clima escuro.
@export_range(0.0, 1.0, 0.01) var night_shadow_strength := 0.78

const DOME_RINGS := 28
const DOME_SEGMENTS := 112
const NOISE_TEXTURE_SIZE := Vector2i(512, 256)

var _material: ShaderMaterial
var _coverage := 0.0
var _opacity := 0.0
var _cloud_color := Color.WHITE
var _wind_offset := Vector2.ZERO
var _wind_direction := Vector2.RIGHT
var _wind_speed := 0.0
var _drift_time := 0.0


func apply_runtime_settings(settings: Dictionary) -> void:
	var should_rebuild := false

	if settings.has("size") and not is_equal_approx(size, float(settings.get("size"))):
		size = float(settings.get("size"))
		should_rebuild = true
	if settings.has("height"):
		height = float(settings.get("height"))
	if settings.has("drift_speed_multiplier"):
		drift_speed_multiplier = float(settings.get("drift_speed_multiplier"))
	if settings.has("slow_drift_variation"):
		slow_drift_variation = float(settings.get("slow_drift_variation"))
	if settings.has("slow_drift_variation_speed"):
		slow_drift_variation_speed = float(settings.get("slow_drift_variation_speed"))
	if settings.has("max_opacity"):
		max_opacity = float(settings.get("max_opacity"))
	if settings.has("min_visible_opacity"):
		min_visible_opacity = float(settings.get("min_visible_opacity"))
	if settings.has("visibility_threshold_max"):
		visibility_threshold_max = float(settings.get("visibility_threshold_max"))
	if settings.has("night_shadow_strength"):
		night_shadow_strength = float(settings.get("night_shadow_strength"))

	if should_rebuild and is_node_ready():
		_build_layer()
	else:
		_update_shader_parameters()


func _ready() -> void:
	_build_layer()


func _process(delta: float) -> void:
	_drift_time += delta
	var drift_variation := lerpf(1.0 - slow_drift_variation, 1.0, (sin(_drift_time * TAU * slow_drift_variation_speed) + 1.0) * 0.5)
	var drift_speed := _wind_speed * drift_speed_multiplier * drift_variation
	_wind_offset += _wind_direction.normalized() * drift_speed * delta

	if follow_camera:
		var camera := get_viewport().get_camera_3d()
		if camera != null:
			global_position = Vector3(camera.global_position.x, camera.global_position.y - height, camera.global_position.z)
	_update_shader_parameters()


func set_weather(coverage: float, wind_direction: Vector2, wind_speed: float, day_factor: float) -> void:
	_coverage = clampf(coverage, 0.0, 1.0)
	_wind_direction = wind_direction if wind_direction.length_squared() > 0.001 else Vector2.RIGHT
	_wind_speed = maxf(wind_speed, 0.0)
	visible = _coverage > 0.015

	_opacity = 0.0 if _coverage <= 0.015 else lerpf(min_visible_opacity, max_opacity, _coverage)
	var shade := lerpf(1.0 - night_shadow_strength, 1.0, clampf(day_factor, 0.0, 1.0))
	_cloud_color = Color(shade, shade, shade, 1.0)
	_update_shader_parameters()


func _build_layer() -> void:
	mesh = _build_dome_mesh()
	_material = _build_cloud_material()
	material_override = _material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_weather(0.0, Vector2.RIGHT, 0.0, 1.0)


func _build_dome_mesh() -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var radius := maxf(size, 1.0)

	for ring in range(DOME_RINGS + 1):
		var v := float(ring) / float(DOME_RINGS)
		var theta := v * PI * 0.5
		var horizontal_radius := cos(theta) * radius
		var y := sin(theta) * radius
		for segment in range(DOME_SEGMENTS + 1):
			var u := float(segment) / float(DOME_SEGMENTS)
			var angle := u * TAU
			vertices.append(Vector3(cos(angle) * horizontal_radius, y, sin(angle) * horizontal_radius))
			uvs.append(Vector2(u, v))

	for ring in range(DOME_RINGS):
		for segment in range(DOME_SEGMENTS):
			var i0 := ring * (DOME_SEGMENTS + 1) + segment
			var i1 := i0 + 1
			var i2 := i0 + DOME_SEGMENTS + 1
			var i3 := i2 + 1
			indices.append(i0)
			indices.append(i2)
			indices.append(i1)
			indices.append(i1)
			indices.append(i2)
			indices.append(i3)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var dome_mesh := ArrayMesh.new()
	dome_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return dome_mesh


func _build_cloud_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;

uniform sampler2D cloud_noise : repeat_enable, filter_linear_mipmap;
uniform vec4 cloud_color : source_color = vec4(1.0);
uniform vec2 wind_offset = vec2(0.0);
uniform float coverage = 0.0;
uniform float opacity = 0.0;
uniform float softness = 0.18;
uniform float contrast = 1.18;

void fragment() {
	vec2 uv = UV;
	vec2 lower_uv = vec2(uv.x * 1.22, uv.y * 0.68 + 0.10) + wind_offset * vec2(0.34, 0.16);
	vec2 upper_uv = vec2(uv.x * 2.35 + 0.31, uv.y * 1.38 + 0.27) - wind_offset * vec2(0.18, 0.11);
	vec2 detail_uv = vec2(uv.x * 6.40 + 0.53, uv.y * 3.20 + 0.19) + wind_offset * vec2(0.08, -0.05);

	float lower = texture(cloud_noise, lower_uv).r;
	float upper = texture(cloud_noise, upper_uv).r;
	float detail = texture(cloud_noise, detail_uv).r;
	float cloud = lower * 0.58 + upper * 0.30 + detail * 0.12;
	cloud = pow(cloud, contrast);

	float clamped_coverage = clamp(coverage, 0.0, 1.0);
	float threshold = mix(0.68, 0.22, clamped_coverage);
	float mask = smoothstep(threshold, threshold + softness, cloud);
	float horizon_fade = smoothstep(0.015, 0.13, uv.y);
	float zenith_fade = 1.0 - smoothstep(0.96, 1.0, uv.y) * 0.12;
	float alpha = mask * horizon_fade * zenith_fade * opacity;

	float light_variation = mix(0.82, 1.16, cloud);
	ALBEDO = cloud_color.rgb * light_variation;
	ALPHA = alpha;
}
"""

	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("cloud_noise", _build_noise_texture())
	return material


func _build_noise_texture() -> Texture2D:
	var noise := FastNoiseLite.new()
	noise.seed = 90843
	noise.frequency = 4.2
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.15
	noise.fractal_gain = 0.48

	var image := Image.create(NOISE_TEXTURE_SIZE.x, NOISE_TEXTURE_SIZE.y, false, Image.FORMAT_L8)
	for y in range(NOISE_TEXTURE_SIZE.y):
		for x in range(NOISE_TEXTURE_SIZE.x):
			var value := noise.get_noise_2d(float(x) / float(NOISE_TEXTURE_SIZE.x), float(y) / float(NOISE_TEXTURE_SIZE.y))
			value = clampf(value * 0.5 + 0.5, 0.0, 1.0)
			image.set_pixel(x, y, Color(value, value, value, 1.0))
	return ImageTexture.create_from_image(image)


func _update_shader_parameters() -> void:
	if _material == null:
		return

	var wind_uv := _wind_offset / maxf(size, 1.0)
	_material.set_shader_parameter("wind_offset", wind_uv)
	_material.set_shader_parameter("coverage", _coverage)
	_material.set_shader_parameter("opacity", _opacity)
	_material.set_shader_parameter("cloud_color", _cloud_color)
	_material.set_shader_parameter("softness", lerpf(0.24, 0.10, clampf(_coverage, 0.0, 1.0)))
