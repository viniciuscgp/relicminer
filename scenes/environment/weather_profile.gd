extends Resource
class_name WeatherProfile

## Identificador usado pelo EnvironmentController para ativar este clima por codigo.
@export var id: StringName = &"clear"
## Nome legivel do clima para editor, debug ou UI futura.
@export var display_name := "Clear"

@export_group("Selection")
## Peso usado no sorteio automatico de clima. 0 impede este clima de ser escolhido automaticamente.
@export_range(0.0, 100.0, 0.1, "or_greater") var auto_weather_weight := 1.0

@export_group("Sky")
## Cobertura maxima de nuvens de 0 a 1. Ao iniciar este clima, o jogo sorteia o valor real entre 0 e este valor.
@export_range(0.0, 1.0, 0.01) var cloud_coverage := 0.0
## Intensidade maxima de chuva de 0 a 1. Ao iniciar este clima, o jogo sorteia o valor real entre 0 e este valor.
@export_range(0.0, 1.0, 0.01) var rain_intensity := 0.0
## Neblina maxima adicionada por este clima. Ao iniciar este clima, o jogo sorteia o valor real entre 0 e este valor.
@export_range(0.0, 1.0, 0.01) var fog_density := 0.0
## Multiplicador de cor aplicado ao ceu. Use para clima mais frio, cinza ou quente.
@export var sky_tint := Color(1.0, 1.0, 1.0, 1.0)

@export_group("Lighting")
## Multiplicador maximo da intensidade do sol neste clima. Ao iniciar este clima, o jogo sorteia entre 0 e este valor.
@export_range(0.0, 2.0, 0.01) var sun_energy_multiplier := 1.0
## Multiplicador maximo da intensidade da lua neste clima. Ao iniciar este clima, o jogo sorteia entre 0 e este valor.
@export_range(0.0, 2.0, 0.01) var moon_energy_multiplier := 1.0
## Multiplicador maximo da luz ambiente neste clima. Ao iniciar este clima, o jogo sorteia entre 0 e este valor.
@export_range(0.0, 2.0, 0.01) var ambient_energy_multiplier := 1.0
## Multiplicador maximo da visibilidade das estrelas. Ao iniciar este clima, o jogo sorteia entre 0 e este valor.
@export_range(0.0, 1.0, 0.01) var star_visibility_multiplier := 1.0

@export_group("Storm")
## Frequencia/forca maxima dos relampagos neste clima. Ao iniciar este clima, o jogo sorteia entre 0 e este valor.
@export_range(0.0, 1.0, 0.01) var lightning_activity := 0.0

@export_group("Motion")
## Direcao do vento usada para mover nuvens e futuramente chuva/folhagem.
@export var wind_direction := Vector2(1.0, 0.25)
## Velocidade maxima do vento usada pelos efeitos visuais deste clima. Ao iniciar este clima, o jogo sorteia entre 0 e este valor.
@export_range(0.0, 10.0, 0.01) var wind_speed := 0.7
