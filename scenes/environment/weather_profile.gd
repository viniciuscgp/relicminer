extends Resource
class_name WeatherProfile

## Identificador usado pelo EnvironmentController para ativar este clima por codigo.
@export var id: StringName = &"clear"
## Nome legivel do clima para editor, debug ou UI futura.
@export var display_name := "Clear"

@export_group("Sky")
## Cobertura de nuvens de 0 a 1. Valores altos escurecem o dia, escondem estrelas e reduzem sol/lua.
@export_range(0.0, 1.0, 0.01) var cloud_coverage := 0.0
## Intensidade da chuva de 0 a 1. Controla particulas de chuva, neblina e escurecimento do ceu.
@export_range(0.0, 1.0, 0.01) var rain_intensity := 0.0
## Neblina base adicionada por este clima. Chuva e nuvens podem somar mais neblina por cima.
@export_range(0.0, 1.0, 0.01) var fog_density := 0.0
## Multiplicador de cor aplicado ao ceu. Use para clima mais frio, cinza ou quente.
@export var sky_tint := Color(1.0, 1.0, 1.0, 1.0)

@export_group("Lighting")
## Multiplica a intensidade do sol neste clima. Nublado e chuva geralmente usam valores menores.
@export_range(0.0, 2.0, 0.01) var sun_energy_multiplier := 1.0
## Multiplica a intensidade da lua neste clima. Nuvens densas reduzem a leitura noturna.
@export_range(0.0, 2.0, 0.01) var moon_energy_multiplier := 1.0
## Multiplica a luz ambiente neste clima. Use baixo para chuva pesada ou tempestade.
@export_range(0.0, 2.0, 0.01) var ambient_energy_multiplier := 1.0
## Multiplica a visibilidade das estrelas. Ainda e afetado por noite, nuvens e chuva.
@export_range(0.0, 1.0, 0.01) var star_visibility_multiplier := 1.0

@export_group("Motion")
## Direcao do vento usada para mover nuvens e futuramente chuva/folhagem.
@export var wind_direction := Vector2(1.0, 0.25)
## Velocidade do vento usada pelos efeitos visuais deste clima.
@export_range(0.0, 10.0, 0.01) var wind_speed := 0.7
