extends Node3D
class_name EnvironmentController

const WeatherProfileScript := preload("res://scenes/environment/weather_profile.gd")

signal hour_changed(hour: float)
signal weather_changed(weather_id: StringName)

@export_group("Time")
## Hora atual do mundo em formato 0-24. Exemplo: 6 amanhecer, 12 meio-dia, 20 noite.
@export_range(0.0, 24.0, 0.01) var current_hour := 14.0:
	set(value):
		current_hour = fposmod(float(value), 24.0)
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
@export_range(0.0, 1.0, 0.001) var night_ambient_energy := 0.16
## Quanto clima/nuvem/chuva reduzem a luz ambiente durante a noite. Menor faz Night Ambient Energy responder mais diretamente.
@export_range(0.0, 1.0, 0.01) var night_ambient_weather_influence := 0.25
## Intensidade maxima da lua em noite limpa. Mantem alguma leitura sem competir com tochas.
@export_range(0.0, 2.0, 0.01) var night_moon_energy := 0.34
## Cor da luz ambiente noturna. Azul escuro costuma preservar a sensacao de noite.
@export var night_ambient_color := Color(0.045, 0.055, 0.105, 1.0)

@export_group("Day Lighting")
## Luz ambiente base durante o dia antes dos multiplicadores de clima.
@export_range(0.0, 2.0, 0.01) var day_ambient_energy := 0.72
## Intensidade maxima do sol ao meio-dia em clima limpo.
@export_range(0.0, 8.0, 0.01) var day_sun_energy := 2.15
## Cor da luz ambiente diurna.
@export var day_ambient_color := Color(0.62, 0.68, 0.76, 1.0)

@export_group("Day Night Timing")
## Hora em que o ceu comeca a clarear antes do amanhecer.
@export_range(0.0, 24.0, 0.01) var dawn_start_hour := 5.0
## Hora em que a luz do dia fica completa.
@export_range(0.0, 24.0, 0.01) var day_start_hour := 7.0
## Hora em que o dia comeca a virar entardecer.
@export_range(0.0, 24.0, 0.01) var sunset_start_hour := 17.4
## Hora em que a noite comeca a entrar visualmente.
@export_range(0.0, 24.0, 0.01) var night_start_hour := 21.1
## Hora em que a noite fica completa.
@export_range(0.0, 24.0, 0.01) var full_night_hour := 22.5
## Luz ambiente extra durante amanhecer/entardecer para evitar queda brusca de exposicao.
@export_range(0.0, 1.0, 0.001) var twilight_ambient_boost := 0.18
## Energia minima do ceu durante amanhecer/entardecer.
@export_range(0.0, 2.0, 0.01) var twilight_sky_energy := 0.58
## Quanto o crepusculo colore o topo do ceu. Menor deixa a faixa quente mais proxima do horizonte.
@export_range(0.0, 1.0, 0.01) var twilight_top_tint_strength := 0.12
## Quanto o crepusculo colore a linha do horizonte.
@export_range(0.0, 1.0, 0.01) var twilight_horizon_tint_strength := 0.62
## Energia minima do ceu durante a noite completa.
@export_range(0.0, 1.0, 0.01) var night_sky_energy_floor := 0.24
## Hora em que as primeiras estrelas comecam a aparecer no entardecer.
@export_range(0.0, 24.0, 0.01) var stars_start_hour := 18.5
## Visibilidade inicial das primeiras estrelas ao chegar em Stars Start Hour.
@export_range(0.0, 1.0, 0.01) var stars_initial_visibility := 0.14
## Hora em que o campo de estrelas chega na visibilidade maxima.
@export_range(0.0, 24.0, 0.01) var stars_full_hour := 22.0
## Hora em que as estrelas comecam a sumir no amanhecer.
@export_range(0.0, 24.0, 0.01) var stars_fade_out_start_hour := 4.8
## Hora em que as estrelas somem completamente.
@export_range(0.0, 24.0, 0.01) var stars_hidden_hour := 6.4

@export_group("Celestial Shared")
## Distancia visual do sol e da lua em relacao a camera. Deve ficar alem do mundo jogavel para nao parecer um objeto proximo.
@export_range(50.0, 5000.0, 1.0) var celestial_visual_distance := 3200.0
## Altura minima acima do horizonte para o sol/lua aparecerem totalmente. Evita o astro atravessar montanhas no nascer/por do sol.
@export_range(0.0, 0.5, 0.001) var celestial_horizon_fade_height := 0.095

@export_group("Sun Visual")
## Tamanho visual do disco do sol no ceu.
@export_range(1.0, 300.0, 0.5) var sun_visual_size := 137.0
## Cor emissiva do disco do sol. Use tons amarelados para evitar um sol branco/frio.
@export var sun_visual_color := Color(1.0, 0.76, 0.32, 1.0)
## Intensidade emissiva do sol visual. Valores maiores alimentam o glow/bloom do Environment.
@export_range(0.0, 20.0, 0.1) var sun_emission_energy := 7.0

@export_group("Sun Halo And Flare")
## Tamanho do brilho suave ao redor do sol. Maior cria o halo claro visto em ceus HDR.
@export_range(1.0, 1200.0, 1.0) var sun_halo_size := 520.0
## Forca do halo do sol. Afeta o brilho suave mesmo quando a camera nao olha direto para ele.
@export_range(0.0, 6.0, 0.01) var sun_halo_intensity := 1.25
## Tamanho do flare frontal do sol quando a camera olha perto dele.
@export_range(1.0, 1600.0, 1.0) var sun_flare_size := 820.0
## Forca do flare frontal do sol. Aumente se quiser mais estouro de luz.
@export_range(0.0, 8.0, 0.01) var sun_flare_intensity := 2.7
## Quanto a camera precisa apontar para o sol antes do flare aparecer. Maior deixa o flare mais raro.
@export_range(0.0, 1.0, 0.01) var sun_flare_alignment_start := 0.58

@export_group("Moon Visual")
## Tamanho visual do disco da lua no ceu.
@export_range(1.0, 300.0, 0.5) var moon_visual_size := 99.0
## Cor emissiva do disco da lua.
@export var moon_visual_color := Color(0.45, 0.56, 0.82, 0.82)
## Intensidade emissiva da lua visual.
@export_range(0.0, 20.0, 0.1) var moon_emission_energy := 0.75
## Hora em que a lua comeca a ficar visivel ao subir no horizonte.
@export_range(0.0, 24.0, 0.01) var moon_visible_start_hour := 18.25
## Hora em que a lua chega na visibilidade maxima.
@export_range(0.0, 24.0, 0.01) var moon_full_visibility_hour := 21.0
## Hora em que a lua comeca a sumir no amanhecer.
@export_range(0.0, 24.0, 0.01) var moon_fade_out_start_hour := 5.0
## Hora em que a lua some completamente.
@export_range(0.0, 24.0, 0.01) var moon_hidden_hour := 6.5

@export_group("Glow")
## Ativa bloom/glow no WorldEnvironment para o sol e outros materiais emissivos brilharem.
@export var glow_enabled := true
## Intensidade base do glow. Aumente se o sol ainda parecer sem brilho.
@export_range(0.0, 2.0, 0.01) var glow_intensity := 0.38
## Alcance/forca visual do glow. Aumente para halos maiores.
@export_range(0.0, 2.0, 0.01) var glow_strength := 0.88

@export_group("Color Grading")
## Exposicao do tonemapper. Valores maiores clareiam altas luzes e alimentam o aspecto HDR.
@export_range(0.1, 4.0, 0.01) var tonemap_exposure := 1.08
## Branco maximo do tonemapper. Valores maiores preservam detalhes em areas muito claras.
@export_range(0.1, 16.0, 0.1) var tonemap_white := 5.8
## Ativa ajuste final de cor/contraste do WorldEnvironment.
@export var adjustment_enabled := true
## Brilho final da imagem. Normalmente fica perto de 1.
@export_range(0.0, 2.0, 0.01) var adjustment_brightness := 1.0
## Contraste final. Aumentar cria pretos mais presentes, como o HDR de referencia.
@export_range(0.0, 2.0, 0.01) var adjustment_contrast := 1.1
## Saturacao final. Aumente pouco para nao deixar o mundo artificial.
@export_range(0.0, 2.0, 0.01) var adjustment_saturation := 1.04

@export_group("HDR Look")
## Ativa uma camada de pos-processamento sobre o 3D, abaixo do HUD, para controlar pretos e cor.
@export var hdr_post_process_enabled := true
## Camada do pos-processamento. Deve ficar acima do mundo 3D e abaixo do HUD.
@export_range(-10, 20, 1) var hdr_post_process_layer := 1
## Ponto de preto. Aumente para deixar sombras e areas escuras mais pretas sem apagar luzes fortes.
@export_range(0.0, 0.35, 0.001) var hdr_black_point := 0.08
## Potencia das sombras. Valores acima de 1 escurecem medios tons e sombras.
@export_range(0.25, 3.0, 0.01) var hdr_shadow_power := 1.24
## Exposicao visual depois do render. Aumente para recuperar luz se o preto ficar pesado demais.
@export_range(0.25, 3.0, 0.01) var hdr_post_exposure := 1.08
## Contraste do pos-processamento. Trabalha junto com o ponto de preto.
@export_range(0.0, 3.0, 0.01) var hdr_post_contrast := 1.22
## Saturacao do pos-processamento. Controla a potencia geral da cor.
@export_range(0.0, 3.0, 0.01) var hdr_post_saturation := 1.14
## Gamma final. Acima de 1 clareia medios tons; abaixo de 1 escurece.
@export_range(0.2, 3.0, 0.01) var hdr_gamma := 1.0
## Quanto o HDR escurecedor e reduzido durante a noite. 0 mantem o HDR igual; 1 aplica todo o alivio noturno.
@export_range(0.0, 1.0, 0.01) var hdr_night_relief := 0.75
## Ponto de preto usado no pico da noite.
@export_range(0.0, 0.35, 0.001) var hdr_night_black_point := 0.018
## Potencia de sombras usada no pico da noite. Menor deixa medios tons e sombras mais legiveis.
@export_range(0.25, 3.0, 0.01) var hdr_night_shadow_power := 0.78
## Exposicao do pos-processo no pico da noite.
@export_range(0.25, 3.0, 0.01) var hdr_night_post_exposure := 1.28
## Contraste do pos-processo no pico da noite.
@export_range(0.0, 3.0, 0.01) var hdr_night_post_contrast := 0.82
## Gamma do pos-processo no pico da noite.
@export_range(0.2, 3.0, 0.01) var hdr_night_gamma := 1.32
## Vinheta do pos-processo no pico da noite.
@export_range(0.0, 1.0, 0.01) var hdr_night_vignette_strength := 0.08
## Potencia por canal. Valores abaixo de 1 intensificam o canal; acima de 1 seguram o canal.
@export var hdr_color_power := Color(1.0, 1.0, 1.0, 1.0)
## Cor multiplicativa opcional para dar direcao artistica ao mundo.
@export var hdr_tint_color := Color(1.0, 0.96, 0.9, 1.0)
## Forca da cor multiplicativa. 0 desliga, 1 aplica totalmente.
@export_range(0.0, 1.0, 0.01) var hdr_tint_strength := 0.08
## Escurecimento nas bordas da tela. Ajuda a dar leitura de lente/camera.
@export_range(0.0, 1.0, 0.01) var hdr_vignette_strength := 0.18
## Raio da vinheta. Maior deixa a vinheta mais perto da borda.
@export_range(0.1, 1.4, 0.01) var hdr_vignette_radius := 0.78

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
var _sun_halo: MeshInstance3D
var _sun_flare: MeshInstance3D
var _sun_visual_material: StandardMaterial3D
var _moon_visual_material: StandardMaterial3D
var _sun_halo_material: ShaderMaterial
var _sun_flare_material: ShaderMaterial
var _hdr_post_layer: CanvasLayer
var _hdr_post_rect: ColorRect
var _hdr_post_material: ShaderMaterial
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
	_ensure_hdr_post_process()
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
	_resize_hdr_post_rect()
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


func get_environment_save_data() -> Dictionary:
	return {
		"current_hour": current_hour,
		"source_weather_id": str(_source_weather.get("id")) if _source_weather != null else "",
		"target_weather_id": str(_target_weather.get("id")) if _target_weather != null else "",
		"weather_blend": _weather_blend,
		"weather_timer_hours": _weather_timer_hours,
	}


func apply_environment_save_data(data: Dictionary) -> void:
	if data.has("current_hour"):
		current_hour = fposmod(float(data.get("current_hour", current_hour)), 24.0)

	var target_weather_id := StringName(str(data.get("target_weather_id", data.get("weather_id", initial_weather_id))))
	var source_weather_id := StringName(str(data.get("source_weather_id", target_weather_id)))
	_target_weather = _find_weather(target_weather_id)
	if _target_weather == null:
		_target_weather = _get_fallback_weather()

	_source_weather = _find_weather(source_weather_id)
	if _source_weather == null:
		_source_weather = _target_weather

	_weather_blend = clampf(float(data.get("weather_blend", 1.0)), 0.0, 1.0)
	if is_equal_approx(_weather_blend, 1.0):
		_source_weather = _target_weather
	_weather_timer_hours = maxf(float(data.get("weather_timer_hours", _weather_timer_hours)), 0.0)
	if is_zero_approx(_weather_timer_hours):
		_schedule_next_weather()

	_apply_environment(0.0)
	_emit_hour_if_needed()
	weather_changed.emit(get_current_weather_id())


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

	var next_profile := _pick_weighted_weather(options)
	change_weather(next_profile.get("id"))


func _schedule_next_weather() -> void:
	_weather_timer_hours = _random.randf_range(min_weather_duration_hours, max_weather_duration_hours)


func _pick_weighted_weather(options: Array[Resource]) -> Resource:
	var total_weight := 0.0
	for profile in options:
		total_weight += _get_weather_auto_weight(profile)

	if total_weight <= 0.0:
		return options[_random.randi_range(0, options.size() - 1)]

	var roll := _random.randf_range(0.0, total_weight)
	var accumulated := 0.0
	for profile in options:
		accumulated += _get_weather_auto_weight(profile)
		if roll <= accumulated:
			return profile

	return options[options.size() - 1]


func _get_weather_auto_weight(profile: Resource) -> float:
	if profile == null:
		return 0.0
	return maxf(0.0, float(profile.get("auto_weather_weight")))


func _apply_environment(delta: float) -> void:
	_refresh_runtime_environment()
	if _runtime_environment == null:
		return

	var sun_elevation := sin((current_hour / 24.0) * TAU - PI * 0.5)
	var cycle := _get_day_night_cycle()
	var day_factor := float(cycle.get("day", 1.0))
	var night_factor := float(cycle.get("night", 0.0))
	var twilight_factor := float(cycle.get("twilight", 0.0))
	_configure_glow()
	_configure_hdr_post_process(night_factor)
	var cloud_coverage := _weather_float("cloud_coverage", 0.0)
	var rain_intensity := _weather_float("rain_intensity", 0.0)
	var fog_density := _weather_float("fog_density", 0.0)
	var sun_multiplier := _weather_float("sun_energy_multiplier", 1.0)
	var moon_multiplier := _weather_float("moon_energy_multiplier", 1.0)
	var ambient_multiplier := _weather_float("ambient_energy_multiplier", 1.0)
	var star_multiplier := _weather_float("star_visibility_multiplier", 1.0)
	var lightning_activity := _weather_float("lightning_activity", 0.0)
	var wind_direction := _weather_vector2("wind_direction", Vector2.RIGHT)
	var wind_speed := _weather_float("wind_speed", 0.0)

	_apply_sky(day_factor, twilight_factor, night_factor, cloud_coverage, rain_intensity)
	_apply_lights(day_factor, night_factor, cloud_coverage, rain_intensity, sun_multiplier, moon_multiplier)
	_apply_ambient(day_factor, twilight_factor, night_factor, cloud_coverage, rain_intensity, ambient_multiplier)
	_apply_fog(day_factor, fog_density, rain_intensity, cloud_coverage)
	_apply_water_reflection(night_factor, cloud_coverage, rain_intensity)
	_apply_visual_systems(day_factor, night_factor, cloud_coverage, rain_intensity, star_multiplier, lightning_activity, wind_direction, wind_speed)
	_rotate_celestial_lights(delta)
	_update_celestial_visuals(day_factor, night_factor, cloud_coverage, rain_intensity)


func _apply_sky(day_factor: float, twilight_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float) -> void:
	if _sky_material == null:
		return

	var day_top := Color(0.16, 0.42, 0.82, 1.0)
	var day_horizon := Color(0.62, 0.76, 0.88, 1.0)
	var night_top := Color(0.012, 0.018, 0.04, 1.0)
	var night_horizon := Color(0.025, 0.03, 0.065, 1.0)
	var dusk_top := Color(0.08, 0.08, 0.15, 1.0)
	var dusk_horizon := Color(0.9, 0.42, 0.18, 1.0)
	var storm_tint := Color(0.22, 0.24, 0.28, 1.0)
	var weather_tint: Color = _weather_color("sky_tint", Color.WHITE)
	var overcast := clampf(cloud_coverage * 0.65 + rain_intensity * 0.55, 0.0, 1.0)

	var top := night_top.lerp(day_top, day_factor)
	var horizon := night_horizon.lerp(day_horizon, day_factor)
	top = top.lerp(dusk_top, twilight_factor * twilight_top_tint_strength)
	horizon = horizon.lerp(dusk_horizon, twilight_factor * twilight_horizon_tint_strength)
	top = top.lerp(storm_tint, overcast)
	horizon = horizon.lerp(storm_tint.lightened(0.08), overcast)
	top = _multiply_color(top, weather_tint)
	horizon = _multiply_color(horizon, weather_tint)

	_sky_material.sky_top_color = top
	_sky_material.sky_horizon_color = horizon
	_sky_material.ground_bottom_color = top.darkened(0.35)
	_sky_material.ground_horizon_color = horizon.darkened(0.18)
	var sky_energy := lerpf(night_sky_energy_floor, 1.0, day_factor)
	sky_energy = maxf(sky_energy, twilight_sky_energy * twilight_factor)
	_sky_material.sky_energy_multiplier = sky_energy * lerpf(1.0, 0.42, overcast)
	_sky_material.sun_angle_max = 0.0


func _apply_lights(day_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float, sun_multiplier: float, moon_multiplier: float) -> void:
	var weather_shadow := clampf(1.0 - cloud_coverage * 0.72 - rain_intensity * 0.35, 0.12, 1.0)
	if _sun_light != null:
		_sun_light.light_energy = day_sun_energy * day_factor * weather_shadow * sun_multiplier
		_sun_light.light_color = Color(1.0, 0.78, 0.46, 1.0).lerp(Color(1.0, 0.9, 0.72, 1.0), day_factor)
		_sun_light.shadow_enabled = _sun_light.light_energy > 0.03

	if _moon_light != null:
		var moon_light_factor := maxf(night_factor, _get_moon_time_visibility() * 0.65)
		_moon_light.light_energy = night_moon_energy * moon_light_factor * lerpf(1.0, 0.22, cloud_coverage) * lerpf(1.0, 0.05, rain_intensity) * moon_multiplier
		_moon_light.light_color = Color(0.42, 0.52, 0.78, 1.0)
		_moon_light.shadow_enabled = _moon_light.light_energy > 0.02


func _apply_ambient(day_factor: float, twilight_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float, ambient_multiplier: float) -> void:
	var overcast := clampf(cloud_coverage * 0.5 + rain_intensity * 0.4, 0.0, 1.0)
	var ambient_color := night_ambient_color.lerp(day_ambient_color, day_factor)
	ambient_color = ambient_color.lerp(Color(0.19, 0.22, 0.27, 1.0), overcast)
	var ambient_energy := lerpf(night_ambient_energy, day_ambient_energy, day_factor)
	var weather_multiplier := lerpf(1.0, 0.42, overcast) * ambient_multiplier
	var weather_influence := lerpf(night_ambient_weather_influence, 1.0, day_factor)
	ambient_energy *= lerpf(1.0, weather_multiplier, weather_influence)
	ambient_energy = maxf(ambient_energy, night_ambient_energy + twilight_ambient_boost * twilight_factor)

	_runtime_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_runtime_environment.ambient_light_color = ambient_color
	_runtime_environment.ambient_light_energy = ambient_energy
	_runtime_environment.ambient_light_sky_contribution = lerpf(0.08, 0.42, day_factor) * lerpf(1.0, 0.35, overcast)


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


func _apply_visual_systems(day_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float, star_multiplier: float, lightning_activity: float, wind_direction: Vector2, wind_speed: float) -> void:
	if _cloud_layer != null and _cloud_layer.has_method("set_weather"):
		_cloud_layer.call("set_weather", cloud_coverage, wind_direction, wind_speed, day_factor)

	if _rain_controller != null:
		if _rain_controller.has_method("set_weather"):
			_rain_controller.call("set_weather", rain_intensity, lightning_activity)
		elif _rain_controller.has_method("set_intensity"):
			_rain_controller.call("set_intensity", rain_intensity)

	if _star_field != null and _star_field.has_method("set_visibility"):
		var star_time_visibility := _get_star_time_visibility()
		var star_visibility := star_time_visibility * pow(1.0 - cloud_coverage, 1.8) * (1.0 - rain_intensity) * star_multiplier
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
	if _sun_halo == null:
		_sun_halo = _create_sun_effect_visual("SunHalo", sun_halo_size, Color(1.0, 0.76, 0.32, 0.72), 2.8)
	if _sun_flare == null:
		_sun_flare = _create_sun_effect_visual("SunFlare", sun_flare_size, Color(1.0, 0.88, 0.54, 0.82), 4.4)
	_sun_visual_material = _sun_visual.get_active_material(0) as StandardMaterial3D
	_moon_visual_material = _moon_visual.get_active_material(0) as StandardMaterial3D
	_sun_halo_material = _sun_halo.get_active_material(0) as ShaderMaterial
	_sun_flare_material = _sun_flare.get_active_material(0) as ShaderMaterial


func _create_celestial_visual(node_name: String, size: float, color: Color) -> MeshInstance3D:
	var visual := get_node_or_null(node_name) as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = node_name
		visual.visible = false
		add_child(visual)
	else:
		visual.visible = false

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
	var hidden_color := color
	hidden_color.a = 0.0
	material.albedo_color = hidden_color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 0.0
	visual.material_override = material
	return visual


func _create_sun_effect_visual(node_name: String, size: float, color: Color, falloff_power: float) -> MeshInstance3D:
	var visual := get_node_or_null(node_name) as MeshInstance3D
	if visual == null:
		visual = MeshInstance3D.new()
		visual.name = node_name
		visual.visible = false
		add_child(visual)
	else:
		visual.visible = false

	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	visual.mesh = mesh
	visual.scale = Vector3(size, size, 1.0)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;

uniform vec4 effect_color : source_color = vec4(1.0);
uniform float intensity = 0.0;
uniform float falloff_power = 3.0;

void fragment() {
	vec2 centered = UV * 2.0 - vec2(1.0);
	float distance_from_center = length(centered);
	float radial = pow(max(0.0, 1.0 - distance_from_center), falloff_power);
	float core = pow(max(0.0, 1.0 - distance_from_center * 2.2), 1.4);
	float alpha = (radial + core * 0.35) * intensity * effect_color.a;
	ALBEDO = effect_color.rgb;
	EMISSION = effect_color.rgb * intensity * 2.2;
	ALPHA = alpha;
}
"""
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("effect_color", color)
	material.set_shader_parameter("intensity", 0.0)
	material.set_shader_parameter("falloff_power", falloff_power)
	visual.material_override = material
	return visual


func _update_celestial_visuals(day_factor: float, night_factor: float, cloud_coverage: float, rain_intensity: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var weather_visibility := clampf(1.0 - cloud_coverage * 0.65 - rain_intensity * 0.9, 0.0, 1.0)
	_update_single_celestial_visual(_sun_visual, _sun_visual_material, _sun_light, day_factor * weather_visibility, sun_visual_color, sun_emission_energy, sun_visual_size)
	_update_single_celestial_visual(_moon_visual, _moon_visual_material, _moon_light, _get_moon_time_visibility() * weather_visibility, moon_visual_color, moon_emission_energy, moon_visual_size)
	_update_sun_effects(camera, day_factor * weather_visibility)


func _update_single_celestial_visual(visual: MeshInstance3D, material: StandardMaterial3D, light: DirectionalLight3D, visibility: float, color: Color, emission_energy: float, visual_size: float) -> void:
	if visual == null or light == null:
		return

	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return

	var sky_direction := _get_light_sky_direction(light)
	var horizon_visibility := smoothstep(0.0, celestial_horizon_fade_height, sky_direction.y)
	var alpha := clampf(visibility * horizon_visibility, 0.0, 1.0)
	if material != null:
		var visible_color := color
		visible_color.a = alpha
		material.albedo_color = visible_color
		material.emission = color
		material.emission_energy_multiplier = emission_energy if alpha > 0.01 else 0.0
	visual.visible = alpha > 0.01
	visual.global_position = camera.global_position + sky_direction * celestial_visual_distance
	visual.scale = Vector3.ONE * (visual_size / maxf(visual.get_aabb().size.y, 0.001))


func _update_sun_effects(camera: Camera3D, visibility: float) -> void:
	if _sun_light == null:
		return

	var sky_direction := _get_light_sky_direction(_sun_light)
	var horizon_visibility := smoothstep(0.0, celestial_horizon_fade_height, sky_direction.y)
	var alpha := clampf(visibility * horizon_visibility, 0.0, 1.0)
	var camera_forward := -camera.global_transform.basis.z.normalized()
	var alignment := clampf(camera_forward.dot(sky_direction), 0.0, 1.0)
	var flare_visibility := alpha * smoothstep(sun_flare_alignment_start, 0.98, alignment)
	_update_sun_effect_visual(_sun_halo, _sun_halo_material, camera, sky_direction, sun_halo_size, alpha * sun_halo_intensity)
	_update_sun_effect_visual(_sun_flare, _sun_flare_material, camera, sky_direction, sun_flare_size, flare_visibility * sun_flare_intensity)


func _update_sun_effect_visual(visual: MeshInstance3D, material: ShaderMaterial, camera: Camera3D, sky_direction: Vector3, visual_size: float, intensity: float) -> void:
	if visual == null:
		return

	var clamped_intensity := clampf(intensity, 0.0, 8.0)
	if material != null:
		material.set_shader_parameter("intensity", clamped_intensity)
	visual.visible = clamped_intensity > 0.01
	visual.global_position = camera.global_position + sky_direction * (celestial_visual_distance * 0.96)
	visual.global_transform.basis = camera.global_transform.basis
	visual.scale = Vector3(visual_size, visual_size, 1.0)


func _ensure_hdr_post_process() -> void:
	_hdr_post_layer = get_node_or_null("HDRPostProcess") as CanvasLayer
	if _hdr_post_layer == null:
		_hdr_post_layer = CanvasLayer.new()
		_hdr_post_layer.name = "HDRPostProcess"
		add_child(_hdr_post_layer)

	_hdr_post_rect = _hdr_post_layer.get_node_or_null("Grade") as ColorRect
	if _hdr_post_rect == null:
		_hdr_post_rect = ColorRect.new()
		_hdr_post_rect.name = "Grade"
		_hdr_post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hdr_post_layer.add_child(_hdr_post_rect)
	_hdr_post_rect.color = Color.WHITE
	_resize_hdr_post_rect()

	if _hdr_post_material == null:
		var shader := Shader.new()
		shader.code = """
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float black_point = 0.08;
uniform float shadow_power = 1.24;
uniform float post_exposure = 1.08;
uniform float post_contrast = 1.22;
uniform float post_saturation = 1.14;
uniform float grade_gamma = 1.0;
uniform vec3 color_power = vec3(1.0);
uniform vec4 tint_color : source_color = vec4(1.0, 0.96, 0.9, 1.0);
uniform float tint_strength = 0.08;
uniform float vignette_strength = 0.18;
uniform float vignette_radius = 0.78;

void fragment() {
	vec3 color = texture(screen_texture, SCREEN_UV).rgb;
	color *= post_exposure;

	float black_range = max(0.001, 1.0 - black_point);
	color = max((color - vec3(black_point)) / black_range, vec3(0.0));
	color = pow(color, vec3(shadow_power));

	color = (color - vec3(0.5)) * post_contrast + vec3(0.5);
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, post_saturation);

	color = pow(max(color, vec3(0.0)), max(color_power, vec3(0.001)));
	color = mix(color, color * tint_color.rgb, tint_strength);
	color = pow(max(color, vec3(0.0)), vec3(1.0 / max(grade_gamma, 0.001)));

	float edge = smoothstep(vignette_radius, 0.98, distance(UV, vec2(0.5)));
	color *= 1.0 - edge * vignette_strength;
	COLOR = vec4(max(color, vec3(0.0)), 1.0);
}
"""
		_hdr_post_material = ShaderMaterial.new()
		_hdr_post_material.shader = shader
		_hdr_post_rect.material = _hdr_post_material
	else:
		_hdr_post_rect.material = _hdr_post_material

	_configure_hdr_post_process()


func _configure_hdr_post_process(night_factor := 0.0) -> void:
	if _hdr_post_layer == null or _hdr_post_rect == null:
		return

	_hdr_post_layer.layer = hdr_post_process_layer
	_hdr_post_rect.visible = hdr_post_process_enabled
	_resize_hdr_post_rect()
	if _hdr_post_material == null:
		return

	var night_mix := clampf(night_factor * hdr_night_relief, 0.0, 1.0)
	var black_point := lerpf(hdr_black_point, hdr_night_black_point, night_mix)
	var shadow_power := lerpf(hdr_shadow_power, hdr_night_shadow_power, night_mix)
	var post_exposure := lerpf(hdr_post_exposure, hdr_night_post_exposure, night_mix)
	var post_contrast := lerpf(hdr_post_contrast, hdr_night_post_contrast, night_mix)
	var grade_gamma := lerpf(hdr_gamma, hdr_night_gamma, night_mix)
	var vignette_strength := lerpf(hdr_vignette_strength, hdr_night_vignette_strength, night_mix)

	_hdr_post_material.set_shader_parameter("black_point", black_point)
	_hdr_post_material.set_shader_parameter("shadow_power", shadow_power)
	_hdr_post_material.set_shader_parameter("post_exposure", post_exposure)
	_hdr_post_material.set_shader_parameter("post_contrast", post_contrast)
	_hdr_post_material.set_shader_parameter("post_saturation", hdr_post_saturation)
	_hdr_post_material.set_shader_parameter("grade_gamma", grade_gamma)
	_hdr_post_material.set_shader_parameter("color_power", Vector3(hdr_color_power.r, hdr_color_power.g, hdr_color_power.b))
	_hdr_post_material.set_shader_parameter("tint_color", hdr_tint_color)
	_hdr_post_material.set_shader_parameter("tint_strength", hdr_tint_strength)
	_hdr_post_material.set_shader_parameter("vignette_strength", vignette_strength)
	_hdr_post_material.set_shader_parameter("vignette_radius", hdr_vignette_radius)


func _resize_hdr_post_rect() -> void:
	if _hdr_post_rect == null:
		return

	_hdr_post_rect.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_hdr_post_rect.position = Vector2.ZERO
	_hdr_post_rect.size = get_viewport().get_visible_rect().size


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
	_runtime_environment.tonemap_exposure = tonemap_exposure
	_runtime_environment.tonemap_white = tonemap_white
	_runtime_environment.adjustment_enabled = adjustment_enabled
	_runtime_environment.adjustment_brightness = adjustment_brightness
	_runtime_environment.adjustment_contrast = adjustment_contrast
	_runtime_environment.adjustment_saturation = adjustment_saturation


func _configure_directional_shadow(light: DirectionalLight3D, distance: float) -> void:
	if light == null:
		return

	light.shadow_blur = directional_shadow_blur
	light.shadow_bias = directional_shadow_bias
	light.shadow_normal_bias = directional_shadow_normal_bias
	light.directional_shadow_blend_splits = true
	light.directional_shadow_max_distance = distance


func _get_day_night_cycle() -> Dictionary:
	var hour := current_hour
	var day_rise := smoothstep(dawn_start_hour, day_start_hour, hour)
	var day_set := 1.0 - smoothstep(sunset_start_hour, night_start_hour, hour)
	var day_factor := clampf(minf(day_rise, day_set), 0.0, 1.0)
	var night_factor := _get_night_factor(hour)
	var twilight_factor := maxf(
		_get_interval_peak_factor(hour, dawn_start_hour, day_start_hour),
		_get_interval_peak_factor(hour, sunset_start_hour, full_night_hour)
	)

	return {
		"day": day_factor,
		"night": night_factor,
		"twilight": twilight_factor,
	}


func _get_night_factor(hour: float) -> float:
	if hour >= full_night_hour or hour < dawn_start_hour:
		return 1.0
	if hour < day_start_hour:
		return 1.0 - smoothstep(dawn_start_hour, day_start_hour, hour)
	if hour >= night_start_hour:
		return smoothstep(night_start_hour, full_night_hour, hour)
	return 0.0


func _get_star_time_visibility() -> float:
	var hour := current_hour
	if hour >= stars_start_hour:
		var appear := smoothstep(stars_start_hour, stars_full_hour, hour)
		return lerpf(stars_initial_visibility, 1.0, appear)

	if hour < stars_fade_out_start_hour:
		return 1.0

	if hour < stars_hidden_hour:
		return 1.0 - smoothstep(stars_fade_out_start_hour, stars_hidden_hour, hour)

	return 0.0


func _get_moon_time_visibility() -> float:
	var hour := current_hour
	if hour >= moon_visible_start_hour:
		return smoothstep(moon_visible_start_hour, moon_full_visibility_hour, hour)

	if hour < moon_fade_out_start_hour:
		return 1.0

	if hour < moon_hidden_hour:
		return 1.0 - smoothstep(moon_fade_out_start_hour, moon_hidden_hour, hour)

	return 0.0


func _get_interval_peak_factor(hour: float, start_hour: float, end_hour: float) -> float:
	if hour < start_hour or hour > end_hour or is_equal_approx(start_hour, end_hour):
		return 0.0

	var t := clampf(inverse_lerp(start_hour, end_hour, hour), 0.0, 1.0)
	return sin(t * PI)


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
	profile.lightning_activity = _weather_float("lightning_activity", 0.0)
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
