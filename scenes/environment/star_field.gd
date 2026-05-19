extends Node3D
class_name StarField

## Quantidade de estrelas geradas no ceu. Mais estrelas custam mais instancias no MultiMesh.
@export_range(32, 2000, 1) var star_count := 450
## Distancia das estrelas ao redor da camera. Deve ser grande o bastante para ficar no fundo.
@export_range(40.0, 2000.0, 1.0) var radius := 360.0
## Tamanho visual de cada estrela.
@export_range(0.01, 2.0, 0.01) var star_size := 0.18
## Cor base das estrelas antes da transparencia calculada por noite/nuvens/chuva.
@export var star_color := Color(0.88, 0.94, 1.0, 1.0)
## Quando ativo, o campo de estrelas segue a camera para parecer distante/infinito.
@export var follow_camera := true

var _stars: MultiMeshInstance3D
var _material: StandardMaterial3D
var _visibility := 0.0


func _ready() -> void:
	_build_stars()
	set_visibility(0.0)


func _process(_delta: float) -> void:
	if not follow_camera:
		return

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		global_position = camera.global_position


func set_visibility(value: float) -> void:
	_visibility = clampf(value, 0.0, 1.0)
	visible = _visibility > 0.01
	if _material != null:
		var color := star_color
		color.a = _visibility
		_material.albedo_color = color


func _build_stars() -> void:
	_stars = MultiMeshInstance3D.new()
	_stars.name = "Stars"
	add_child(_stars)

	var mesh := SphereMesh.new()
	mesh.radius = star_size
	mesh.height = star_size * 2.0
	mesh.radial_segments = 6
	mesh.rings = 3

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.albedo_color = star_color
	mesh.material = _material

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.instance_count = star_count
	multimesh.mesh = mesh

	var random := RandomNumberGenerator.new()
	random.seed = 74097
	for index in range(star_count):
		var direction := _random_upper_direction(random)
		var distance := radius * random.randf_range(0.82, 1.0)
		var transform := Transform3D(Basis(), direction * distance)
		var scale := random.randf_range(0.65, 1.35)
		transform.basis = transform.basis.scaled(Vector3.ONE * scale)
		multimesh.set_instance_transform(index, transform)

	_stars.multimesh = multimesh


func _random_upper_direction(random: RandomNumberGenerator) -> Vector3:
	var angle := random.randf_range(0.0, TAU)
	var height := random.randf_range(0.15, 1.0)
	var ring_radius := sqrt(maxf(0.0, 1.0 - height * height))
	return Vector3(cos(angle) * ring_radius, height, sin(angle) * ring_radius).normalized()
