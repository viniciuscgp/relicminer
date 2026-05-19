extends MeshInstance3D
class_name CloudLayer

## Tamanho do plano de nuvens em metros. Maior cobre mais area ao redor da camera.
@export_range(100.0, 4000.0, 10.0) var size := 1600.0
## Altura das nuvens acima da camera quando follow_camera esta ativo.
@export_range(10.0, 600.0, 1.0) var height := 180.0
## Quando ativo, a camada segue a camera para parecer que o ceu cobre o mundo inteiro.
@export var follow_camera := true

var _material: ShaderMaterial
var _coverage := 0.0
var _wind_offset := Vector2.ZERO
var _wind_direction := Vector2.RIGHT
var _wind_speed := 0.0


func _ready() -> void:
	_build_layer()


func _process(delta: float) -> void:
	_wind_offset += _wind_direction.normalized() * _wind_speed * delta * 0.003
	if _material != null:
		_material.set_shader_parameter("wind_offset", _wind_offset)

	if not follow_camera:
		return

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = Vector3(camera.global_position.x, camera.global_position.y + height, camera.global_position.z)


func set_weather(coverage: float, wind_direction: Vector2, wind_speed: float, day_factor: float) -> void:
	_coverage = clampf(coverage, 0.0, 1.0)
	_wind_direction = wind_direction if wind_direction.length_squared() > 0.001 else Vector2.RIGHT
	_wind_speed = maxf(wind_speed, 0.0)
	visible = _coverage > 0.02
	if _material == null:
		return

	var alpha := lerpf(0.0, 0.88, _coverage)
	var shade := lerpf(0.16, 0.92, clampf(day_factor, 0.0, 1.0))
	_material.set_shader_parameter("coverage", _coverage)
	_material.set_shader_parameter("opacity", alpha)
	_material.set_shader_parameter("cloud_color", Color(shade, shade, shade, 1.0))


func _build_layer() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(size, size)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	mesh = plane
	rotation_degrees.x = 180.0

	var noise := FastNoiseLite.new()
	noise.seed = 90843
	noise.frequency = 0.024
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
uniform float coverage = 0.0;
uniform float opacity = 0.0;
uniform vec2 wind_offset = vec2(0.0);
uniform vec4 cloud_color : source_color = vec4(1.0);

void fragment() {
	vec2 cloud_uv = UV * 3.0 + wind_offset;
	float base_noise = texture(cloud_noise, cloud_uv).r;
	float detail_noise = texture(cloud_noise, cloud_uv * 2.7 + vec2(0.31, 0.17)).r;
	float cloud = mix(base_noise, detail_noise, 0.35);
	float threshold = mix(0.78, 0.28, coverage);
	float alpha = smoothstep(threshold, threshold + 0.18, cloud) * opacity;
	ALBEDO = cloud_color.rgb;
	ALPHA = alpha;
}
"""

	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("cloud_noise", noise_texture)
	material_override = _material
	set_weather(0.0, Vector2.RIGHT, 0.0, 1.0)
