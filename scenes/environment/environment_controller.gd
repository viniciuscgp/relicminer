extends Node3D
class_name EnvironmentController

const WeatherProfileScript := preload("res://scenes/environment/weather_profile.gd")

signal hour_changed(hour: float)
signal weather_changed(weather_id: StringName)

@export_group("Time")
## Hora atual do mundo em formato 0-24. Exemplo: 6 amanhecer, 12 meio-dia, 20 noite.
@export_range(0.0, 24.0, 0.01) var current_hour := 14.0
## Quando ativo, o relogio do mundo avanca automaticamente a cada frame.
@export var auto_advance_time := true
## Quantos segundos de jogo passam por segundo real. 60 significa 1 minuto de jogo por segundo real.
@export_range(0.0, 7200.0, 1.0, "or_greater") var time_scale := 60.0

@export_group("Weather")
## Lista de perfis de clima que o controlador pode usar e sortear automaticamente.
@export var weather_profiles: Array[Resource] = []
## ID do clima inicial. Deve bater com o campo id de um WeatherProfile.
@export var initial_weather_id: StringName = &"clear"
## Quando ativo, o sistema troca o clima sozinho depois de algumas horas de jogo.
@export var auto_weather := true
## Duracao, em horas de jogo, da mistura visual entre um clima e outro.
@export_range(0.05, 24.0, 0.05) var weather_transition_hours := 0.35
## Tempo minimo, em horas de jogo, que um clima fica ativo antes de poder trocar.
@export_range(0.25, 72.0, 0.25) var min_weather_duration_hours := 5.0
## Tempo maximo, em horas de jogo, que um clima fica ativo antes de poder trocar.
@export_range(0.25, 72.0, 0.25) var max_weather_duration_hours := 14.0

@export_group("Scene")
## Caminho para o WorldEnvironment que recebe ceu, luz ambiente e neblina dinamicos.
@export var world_environment_path: NodePath = NodePath("WorldEnvironment")
## Materiais de agua que recebem brilho noturno da lua.
@export var water_materials: Array[Material] = []
## Caminho para a luz direcional usada como sol.
@export var sun_light_path: NodePath = NodePath("SunLight")
## Caminho para a luz direcional usada como lua durante a noite.
@export var moon_light_path: NodePath = NodePath("MoonLight")
## Caminho para a camada visual de nuvens.
@export var cloud_layer_path: NodePath = NodePath("CloudLayer")
## Caminho para o campo de estrelas visivel durante a noite.
@export var star_field_path: NodePath = NodePath("StarField")
## Caminho para o controlador de chuva/particulas.
@export var rain_controller_path: NodePath = NodePath("RainController")

@export_group("Night Darkness")
## Luz ambiente minima durante a noite. Menor deixa tochas mais importantes; maior deixa a noite mais legivel.
@export_range(0.0, 1.0, 0.001) var night_ambient_energy := 0.095
## Luz ambiente base durante o dia antes dos multiplicadores de clima.
@export_range(0.0, 2.0, 0.01) var day_ambient_energy := 0.72
## Intensidade maxima do sol ao meio-dia em clima limpo.
@export_range(0.0, 8.0, 0.01) var day_sun_energy := 2.15
## Intensidade maxima da lua em noite limpa. Mantem alguma leitura sem competir com tochas.
@export_range(0.0, 2.0, 0.01) var night_moon_energy := 0.22
## Cor da luz ambiente noturna. Azul escuro costuma preservar a sensacao de noite.
@export var night_ambient_color := Color(0.025, 0.035, 0.075, 1.0)
## Cor da luz ambiente diurna.
@export var day_ambient_color := Color(0.62, 0.68, 0.76, 1.0)

@export_group("Celestial Visuals")
## Distancia visual do sol e da lua em relacao a camera. Nao afeta a luz, apenas onde os discos aparecem no ceu.
@export_range(50.0, 2000.0, 1.0) var celestial_visual_distance := 420.0
## Tamanho visual do disco do sol no ceu.
@export_range(1.0, 120.0, 0.5) var sun_visual_size := 18.0
## Tamanho visual do disco da lua no ceu.
@export_range(1.0, 120.0, 0.5) var moon_visual_size := 13.0
## Cor emissiva do disco do sol. Use tons amarelados para evitar um sol branco/frio.
@export var sun_visual_color := Color(1.0, 0.76, 0.32, 1.0)
## Cor emissiva do disco da lua.
@export var moon_visual_color := Color(0.72, 0.82, 1.0, 1.0)
## Intensidade emissiva do sol visual. Valores maiores alimentam o glow/bloom do Environment.
@export_range(0.0, 20.0, 0.1) var sun_emission_energy := 7.0
## Intensidade emissiva da lua visual. Deve ser menor que o sol para nao clarear demais a noite.
@export_range(0.0, 20.0, 0.1) var moon_emission_energy := 1.7

@export_group("Glow")
## Ativa bloom/glow no WorldEnvironment para o sol e outros materiais emissivos brilharem.
@export var glow_enabled := true
## Intensidade base do glow. Aumente se o sol ainda parecer sem brilho.
@export_range(0.0, 2.0, 0.01) var glow_intensity := 0.28
## Alcance/forca visual do glow. Aumente para halos maiores.
@export_range(0.0, 2.0, 0.01) var glow_strength := 0.72

@export_group("Shadow Quality")
## Distancia maxima das sombras do sol. Valores menores deixam a sombra menos serrilhada perto do player.
@export_range(16.0, 256.0, 1.0) var sun_shadow_distance := 72.0
## Distancia maxima das sombras da lua. Normalmente pode ser menor que a do sol.
@export_range(16.0, 256.0, 1.0) var moon_shadow_distance := 48.0
## Suavizacao das sombras direcionais. Valores maiores reduzem serrilhado, mas deixam bordas mais macias.
@export_range(0.0, 10.0, 0.1) var directional_shadow_blur := 4.0
## Bias da sombra direcional. Aumente se aparecer acne; diminua se a sombra desgrudar demais.
@export_range(0.0, 0.2, 0.001) var directional_shadow_bias := 0.025
## Bias normal da sombra direcional. Ajuda a reduzir artefatos em terrenos inclinados.
@export_range(0.0, 5.0, 0.01) var directional_shadow_normal_bias := 1.15

var _world_environment: WorldEnvironment
var _sun_light: DirectionalLight3D
var _moon_light: DirectionalLight3D
var _cloud_layer: Node
var _star_field: Node
var _rain_controller: Node
var _sun_visual: MeshInstance3D
var _moon_visual: MeshInstance3D
var _sun_visual_material: StandardMaterial3D
var _moon_visual_material: StandardMaterial3D
var _runtime_environment: Environment
var _sky_material: ProceduralSkyMaterial
var _source_weather: Resource
var _target_weather: Resource
var _weather_blend := 1.0
var _weather_timer_hours := 0.0
var _previous_reported_hour := -1
var _random := RandomNumberGenerator.new()


func _ready() -> void:
	_random.randomize()
	_resolve_nodes()
	_refresh_runtime_environment()
	_ensure_celestial_visuals()
	_configure_shadow_quality()
	_target_weather = _find_weather(initial_weather_id)
	if _target_weather == null:
		_target_weather = _get_fallback_weather()
	_source_weather = _target_weather
	_weather_blend = 1.0
	_schedule_next_weather()
	_apply_environment(0.0)
	_emit_hour_if_needed()


func _process(delta: float) -> void:
	var delta_hours := 0.0
	if auto_advance_time and time_scale > 0.0:
		delta_hours = delta * time_scale / 3600.0
		current_hour = fposmod(current_hour + delta_hours, 24.0)

	_update_weather(delta_hours)
	_apply_environment(delta)
	_emit_hour_if_needed()


func set_hour(hour: float) -> void:
	current_hour = fposmod(hour, 24.0)
	_apply_environment(0.0)
	_emit_hour_if_needed()


func change_weather(weather_id: StringName, immediate := false) -> bool:
	var profile := _find_weather(weather_id)
	if profile == null:
		return false

	_source_weather = _get_active_weather_snapshot()
	_target_weather = profile
	_weather_blend = 1.0 if immediate else 0.0
	_schedule_next_weather()
	weather_changed.emit(weather_id)
	return true


func get_current_weather_id() -> StringName:
	var weather := _target_weather if _target_weather != null else _source_weather
	if weather == null:
		return &""
	return weather.get("id")


func _resolve_nodes() -> void:
	_world_environment = get_node_or_null(world_environment_path) as WorldEnvironment
	_sun_light = get_node_or_null(sun_light_path) as DirectionalLight3D
	_moon_light = get_node_or_null(moon_light_path) as DirectionalLight3D
	_cloud_layer = get_node_or_null(cloud_layer_path)
	_star_field = get_node_or_null(star_field_path)
	_rain_controller = get_node_or_null(rain_controller_path)


func _refresh_runtime_environment() -> void:
	if _world_environment == null:
		return

	if _world_environment.environment == null:
		_world_environment.environment = Environment.new()

	if _runtime_environment == _world_environment.environment:
		return

	_runtime_environment = _world_environment.environment
	if _runtime_environment.sky == null:
		_runtime_environment.sky = Sky.new()
	if not _runtime_environment.sky.sky_material is ProceduralSkyMaterial:
		_runtime_environment.sky.sky_material = ProceduralSkyMaterial.new()
	_sky_material = _runtime_environment.sky.sky_material as ProceduralSkyMaterial
	_configure_glow()


func _update_weather(delta_hours: float) -> void:
	if _target_weather == null:
		return

	if _weather_blend < 1.0:
		var transition := maxf(weather_transition_hours, 0.01)
		_weather_blend = minf(1.0, _weather_blend + delta_hours / transition)
		if is_equal_approx(_weather_blend, 1.0):
			_source_weather = _target_weather
		return

	if not auto_weather:
		return

	_weather_timer_hours -= delta_hours
	if _weather_timer_hours <= 0.0:
		_pick_next_weather()


func _pick_next_weather() -> void:
	var options: Array[Resource] = []
	for profile in weather_profiles:
		if profile == null:
			continue
		if _target_weather != null and profile.get("id") == _target_weather.get("id"):
			continue
		options.append(profile)

	if options.is_empty():
		_schedule_next_weather()
		return

	var next_index := _random.randi_range(0, options.size() - 1)
	var next_profile := options[next_index]
	change_weather(next_profile.get("id"))


func _schedule_next_weather() -> void:
	_weather_timer_hours = _random.randf_range(min_weather_duration_hours, max_weather_duration_hours)


func _apply_environment(delta: float) -> void:
	_refresh_runtime_environment()
	if _runtime_environment == null:
		return

	_configure_glow()
	var sun_elevation := sin((current_hour / 24.0) * TAU - PI * 0.5)
	var day_factor := smoothstep(-0.08, 0.24, sun_elevation)
	var night_factor := 1.0 - smoothstep(-0.18, 0.05, sun_elevation)
	var twilight_factor := _get_twilight_factor(sun_elevation)
	var cloud_coverage := _weather_float("cloud_coverage", 0.0)
	var rain_intensity := _weather_float("rain_intensity", 0.0)
	var fog_density := _weather_float("fog_density", 0.0)
	var sun_multiplier := _weather_float("sun_energy_multiplier", 1.0)
	var moon_multiplier := _weather_float("moon_energy_multiplier", 1.0)
	var ambient_multiplier := _weather_float("ambient_energy_multiplier", 1.0)
	var star_multiplier := _weather_float("star_visibility_multiplier", 1.0)
	var wind_direction := _weather_vector2("wind_direction", Vector2.RIGHT)
	var wind_speed := _weather_float("wind_speed", 0.0)

	_apply_sky(day_factor, twilight_factor, night_factor, cloud_coverage, rain_intensity)
	_apply_lights(day_factor, night_factor, cloud_coverage, rain_intensity, sun_multiplier, moon_multiplier)
	_apply_ambient(day_factor, night_factor, cloud_coverage, rain_intensity, ambient_multiplier)
	_apply_fog(day_factor, fog_density, rain_intensity, cloud_coverage)
	_apply_water_reflection(night_factor, cloud_coverage, rain_intensity)
	_apply_visual_systems(day_factor, night_factor, cloud_coverage, rain_intensity, star_multiplier, wind_direction, wind_speed)
	_rotate_celestial_lights(delta)
	_update_celestial_visuals(day_factor, night_factor, cloud_coverage, rain_intensity)


func _apply_sky(day_factor: float, twilight_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float) -> void:
	if _sky_material == null:
		return

	var day_top := Color(0.16, 0.42, 0.82, 1.0)
	var day_horizon := Color(0.62, 0.76, 0.88, 1.0)
	var night_top := Color(0.012, 0.018, 0.04, 1.0)
	var night_horizon := Color(0.025, 0.03, 0.065, 1.0)
	var dusk_top := Color(0.15, 0.08, 0.18, 1.0)
	var dusk_horizon := Color(0.9, 0.38, 0.16, 1.0)
	var storm_tint := Color(0.22, 0.24, 0.28, 1.0)
	var weather_tint: Color = _weather_color("sky_tint", Color.WHITE)
	var overcast := clampf(cloud_coverage * 0.65 + rain_intensity * 0.55, 0.0, 1.0)

	var top := night_top.lerp(day_top, day_factor)
	var horizon := night_horizon.lerp(day_horizon, day_factor)
	top = top.lerp(dusk_top, twilight_factor * 0.7)
	horizon = horizon.lerp(dusk_horizon, twilight_factor)
	top = top.lerp(storm_tint, overcast)
	horizon = horizon.lerp(storm_tint.lightened(0.08), overcast)
	top = _multiply_color(top, weather_tint)
	horizon = _multiply_color(horizon, weather_tint)

	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_bottom_color = top.darkened(0.35)
	_sky_material.ground_horizon_color = horizon.darkened(0.18)
	_sky_material.sky_energy_multiplier = lerpf(0.16, 1.0, day_factor) * lerpf(1.0, 0.42, overcast)
	_sky_material.sun_angle_max = 0.0


func _apply_lights(day_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float, sun_multiplier: float, moon_multiplier: float) -> void:
	var weather_shadow := clampf(1.0 - cloud_coverage * 0.72 - rain_intensity * 0.35, 0.12, 1.0)
	if _sun_light != null:
		_sun_light.light_energy = day_sun_energy * day_factor * weather_shadow * sun_multiplier
		_sun_light.light_color = Color(1.0, 0.78, 0.46, 1.0).lerp(Color(1.0, 0.9, 0.72, 1.0), day_factor)
		_sun_light.shadow_enabled = _sun_light.light_energy > 0.03

	if _moon_light != null:
		_moon_light.light_energy = night_moon_energy * night_factor * lerpf(1.0, 0.22, cloud_coverage) * lerpf(1.0, 0.05, rain_intensity) * moon_multiplier
		_moon_light.light_color = Color(0.42, 0.52, 0.78, 1.0)
		_moon_light.shadow_enabled = _moon_light.light_energy > 0.02


func _apply_ambient(day_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float, ambient_multiplier: float) -> void:
	var overcast := clampf(cloud_coverage * 0.5 + rain_intensity * 0.4, 0.0, 1.0)
	var ambient_color := night_ambient_color.lerp(day_ambient_color, day_factor)
	ambient_color = ambient_color.lerp(Color(0.19, 0.22, 0.27, 1.0), overcast)
	var ambient_energy := lerpf(night_ambient_energy, day_ambient_energy, day_factor)
	ambient_energy *= lerpf(1.0, 0.42, overcast) * ambient_multiplier
	if night_factor > 0.5:
		ambient_energy = minf(ambient_energy, night_ambient_energy * lerpf(1.0, 2.4, 1.0 - night_factor))

	_runtime_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_runtime_environment.ambient_light_color = ambient_color
	_runtime_environment.ambient_light_energy = ambient_energy
	_runtime_environment.ambient_light_sky_contribution = lerpf(0.02, 0.42, day_factor) * lerpf(1.0, 0.35, overcast)


func _apply_fog(day_factor: float, fog_density: float, rain_intensity: float, cloud_coverage: float) -> void:
	var density := fog_density + rain_intensity * 0.018 + cloud_coverage * 0.004
	_runtime_environment.fog_enabled = density > 0.001
	_runtime_environment.fog_light_color = Color(0.03, 0.04, 0.07, 1.0).lerp(Color(0.62, 0.68, 0.72, 1.0), day_factor)
	_runtime_environment.fog_light_energy = lerpf(0.02, 0.22, day_factor)
	_runtime_environment.fog_density = density
	_runtime_environment.fog_sky_affect = clampf(0.2 + cloud_coverage * 0.45 + rain_intensity * 0.35, 0.0, 1.0)


func _apply_water_reflection(night_factor: float, cloud_coverage: float, rain_intensity: float) -> void:
	var visibility := night_factor * clampf(1.0 - cloud_coverage * 0.55 - rain_intensity * 0.7, 0.0, 1.0)
	var strength := visibility * 0.42
	for material in water_materials:
		var shader_material := material as ShaderMaterial
		if shader_material == null:
			continue
		shader_material.set_shader_parameter("moon_reflection_strength", strength)
		shader_material.set_shader_parameter("moon_reflection_color", Color(0.5, 0.62, 1.0, 1.0))


func _apply_visual_systems(day_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float, star_multiplier: float, wind_direction: Vector2, wind_speed: float) -> void:
	if _cloud_layer != null and _cloud_layer.has_method("set_weather"):
		_cloud_layer.call("set_weather", cloud_coverage, wind_direction, wind_speed, day_factor)

	if _rain_controller != null and _rain_controller.has_method("set_intensity"):
		_rain_controller.call("set_intensity", rain_intensity)

	if _star_field != null and _star_field.has_method("set_visibility"):
		var star_visibility := night_factor * pow(1.0 - cloud_coverage, 1.8) * (1.0 - rain_intensity) * star_multiplier
		_star_field.call("set_visibility", star_visibility)


func _rotate_celestial_lights(_delta: float) -> void:
	var angle := 90.0 - (current_hour / 24.0) * 360.0
	if _sun_light != null:
		_sun_light.rotation_degrees = Vector3(angle, -35.0, 0.0)
	if _moon_light != null:
		_moon_light.rotation_degrees = Vector3(angle + 180.0, -35.0, 0.0)


func _ensure_celestial_visuals() -> void:
	if _sun_visual == null:
		_sun_visual = _create_celestial_visual("SunVisual", sun_visual_size, sun_visual_color)
	if _moon_visual == null:
		_moon_visual = _create_celestial_visual("MoonVisual", moon_visual_size, moon_visual_color)
	_sun_visual_material = _sun_visual.get_active_material(0) as StandardMaterial3D
	_moon_visual_material = _moon_visual.get_active_material(0) as StandardMaterial3D


func _create_celestial_visual(node_name: String, size: float, color: Color) -> MeshInstance3D:
	var visual := get_node_or_null(node_name) as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = node_name
		add_child(visual)

	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mesh.radial_segments = 32
	mesh.rings = 16
	visual.mesh = mesh
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = false
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = sun_emission_energy if node_name == "SunVisual" else moon_emission_energy
	visual.material_override = material
	return visual


func _update_celestial_visuals(day_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var weather_visibility := clampf(1.0 - cloud_coverage * 0.65 - rain_intensity * 0.9, 0.0, 1.0)
	_update_single_celestial_visual(_sun_visual, _sun_visual_material, _sun_light, day_factor * weather_visibility, sun_visual_color, sun_emission_energy)
	_update_single_celestial_visual(_moon_visual, _moon_visual_material, _moon_light, night_factor * weather_visibility, moon_visual_color, moon_emission_energy)


func _update_single_celestial_visual(visual: MeshInstance3D, material: StandardMaterial3D, light: DirectionalLight3D, visibility: float, color: Color, emission_energy: float) -> void:
	if visual == null or light == null:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var alpha := clampf(visibility, 0.0, 1.0)
	visual.visible = alpha > 0.01
	visual.global_position = camera.global_position + _get_light_sky_direction(light) * celestial_visual_distance
	if material != null:
		var visible_color := color
		visible_color.a = alpha
		material.albedo_color = visible_color
		material.emission = color
		material.emission_energy_multiplier = emission_energy * alpha


func _get_light_sky_direction(light: DirectionalLight3D) -> Vector3:
	return light.global_transform.basis.z.normalized()


func _configure_shadow_quality() -> void:
	_configure_directional_shadow(_sun_light, sun_shadow_distance)
	_configure_directional_shadow(_moon_light, moon_shadow_distance)


func _configure_glow() -> void:
	if _runtime_environment == null:
		return

	_runtime_environment.glow_enabled = glow_enabled
	_runtime_environment.glow_intensity = glow_intensity
	_runtime_environment.glow_strength = glow_strength


func _configure_directional_shadow(light: DirectionalLight3D, distance: float) -> void:
	if light == null:
		return

	light.shadow_blur = directional_shadow_blur
	light.shadow_bias = directional_shadow_bias
	light.shadow_normal_bias = directional_shadow_normal_bias
	light.directional_shadow_blend_splits = true
	light.directional_shadow_max_distance = distance


func _get_twilight_factor(sun_elevation: float) -> float:
	var below := 1.0 - smoothstep(-0.24, -0.02, sun_elevation)
	var above := 1.0 - smoothstep(0.16, 0.32, sun_elevation)
	return clampf(below * above, 0.0, 1.0)


func _find_weather(weather_id: StringName) -> Resource:
	for profile in weather_profiles:
		if profile != null and profile.get("id") == weather_id:
			return profile
	return null


func _get_fallback_weather() -> Resource:
	if not weather_profiles.is_empty():
		return weather_profiles[0]

	var profile: Resource = WeatherProfileScript.new()
	profile.id = &"clear"
	profile.display_name = "Clear"
	return profile


func _get_active_weather_snapshot() -> Resource:
	var profile: Resource = WeatherProfileScript.new()
	profile.id = get_current_weather_id()
	profile.cloud_coverage = _weather_float("cloud_coverage", 0.0)
	profile.rain_intensity = _weather_float("rain_intensity", 0.0)
	profile.fog_density = _weather_float("fog_density", 0.0)
	profile.sky_tint = _weather_color("sky_tint", Color.WHITE)
	profile.sun_energy_multiplier = _weather_float("sun_energy_multiplier", 1.0)
	profile.moon_energy_multiplier = _weather_float("moon_energy_multiplier", 1.0)
	profile.ambient_energy_multiplier = _weather_float("ambient_energy_multiplier", 1.0)
	profile.star_visibility_multiplier = _weather_float("star_visibility_multiplier", 1.0)
	profile.wind_direction = _weather_vector2("wind_direction", Vector2.RIGHT)
	profile.wind_speed = _weather_float("wind_speed", 0.0)
	return profile


func _weather_float(property: StringName, default_value: float) -> float:
	var source_value := default_value
	var target_value := default_value
	if _source_weather != null:
		source_value = float(_source_weather.get(property))
	if _target_weather != null:
		target_value = float(_target_weather.get(property))
	return lerpf(source_value, target_value, _weather_blend)


func _weather_color(property: StringName, default_value: Color) -> Color:
	var source_value := default_value
	var target_value := default_value
	if _source_weather != null:
		source_value = _source_weather.get(property)
	if _target_weather != null:
		target_value = _target_weather.get(property)
	return source_value.lerp(target_value, _weather_blend)


func _weather_vector2(property: StringName, default_value: Vector2) -> Vector2:
	var source_value := default_value
	var target_value := default_value
	if _source_weather != null:
		source_value = _source_weather.get(property)
	if _target_weather != null:
		target_value = _target_weather.get(property)
	return source_value.lerp(target_value, _weather_blend)


func _multiply_color(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)


func _emit_hour_if_needed() -> void:
	var hour_int := int(floor(current_hour))
	if hour_int == _previous_reported_hour:
		return
	_previous_reported_hour = hour_int
	hour_changed.emit(current_hour)
