@tool
extends VBoxContainer


const LAKE_MARKER_SCENE := "res://scenes/editor_tools/lake_marker.tscn"
const GENERATED_ROOT_NAME := "GeneratedWater"
const SURVEY_RIVER_PREFIX := "SurveyRiver_"
const WATER_AREA_GROUP := "water_volume"
const DEFAULT_SURVEY_DIRECTORY := "res://surveys/rivers"
const DEFAULT_SURFACE_MATERIAL := preload("res://addons/relic_road_tools/water_surface.tres")


var editor_plugin: EditorPlugin
var smooth_passes_spin: SpinBox
var surface_offset_spin: SpinBox
var survey_edge_inset_spin: SpinBox
var survey_height_offset_spin: SpinBox
var lake_height_offset_spin: SpinBox
var lake_min_depth_spin: SpinBox
var survey_max_edge_jump_spin: SpinBox
var survey_directory_edit: LineEdit
var surface_picker: EditorResourcePicker
var bake_button: Button
var bake_all_surveys_button: Button
var clear_button: Button
var status_label: Label
var bake_warnings: Array[String] = []


func _init() -> void:
	name = "Water Baker"
	custom_minimum_size = Vector2(300, 0)

	var title := Label.new()
	title.text = "Water Baker"
	title.tooltip_text = "Gera lagoas a partir de marcadores visiveis e rios a partir de arquivos de scan."
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	smooth_passes_spin = _add_spin("Suavizacao", 0.0, 5.0, 1.0, 2.0, "", "Suaviza cantos de rios e lagoas. Valores maiores arredondam mais, mas podem puxar a borda para dentro.")
	surface_offset_spin = _add_spin("Altura Global", -100.0, 100.0, 0.1, 0.0, "m", "Soma uma altura global na superficie gerada a partir dos marcadores.")
	survey_edge_inset_spin = _add_spin("Recuo Scan", 0.0, 12.0, 0.25, 1.5, "m", "Puxa as bordas dos rios escaneados para dentro da vala para evitar agua exatamente em cima da margem.")
	survey_height_offset_spin = _add_spin("Altura Scan", -5.0, 5.0, 0.1, -2.0, "m", "Ajusta somente a altura dos rios gerados por scan. Use valores negativos para abaixar a agua.")
	lake_height_offset_spin = _add_spin("Altura Lagoa", -5.0, 5.0, 0.1, -2.0, "m", "Ajusta somente a altura das lagoas feitas com LakeMarker. Use valores negativos para abaixar a superficie.")
	lake_min_depth_spin = _add_spin("Prof. Lagoa", 0.1, 100.0, 0.1, 12.1, "m", "Profundidade minima do volume da lagoa usado para detectar camera, player, peixes e efeito submerso.")
	survey_max_edge_jump_spin = _add_spin("Salto Max.", 0.0, 80.0, 1.0, 16.0, "m", "Limita saltos bruscos da margem detectada pelo scan. Use 0 para desativar.")
	survey_directory_edit = _add_path_edit("Pasta Scans", DEFAULT_SURVEY_DIRECTORY, "Pasta com os arquivos JSON dos trechos de rio gravados pelo sensor.")
	surface_picker = _add_material_picker("Superficie", DEFAULT_SURFACE_MATERIAL, "Material usado pela superficie visivel da agua.")

	bake_button = Button.new()
	bake_button.text = "Gerar Marcadores"
	bake_button.tooltip_text = "Gera lagoas por LakeMarker, criando mesh e volumes Area3D."
	bake_button.pressed.connect(_on_bake_pressed)
	add_child(bake_button)

	bake_all_surveys_button = Button.new()
	bake_all_surveys_button.text = "Gerar Scans"
	bake_all_surveys_button.tooltip_text = "Gera um trecho de rio para cada arquivo JSON na pasta de scans."
	bake_all_surveys_button.pressed.connect(_on_bake_all_surveys_pressed)
	add_child(bake_all_surveys_button)

	clear_button = Button.new()
	clear_button.text = "Remover Agua Gerada"
	clear_button.tooltip_text = "Remove o node GeneratedWater criado por esta ferramenta."
	clear_button.pressed.connect(_on_clear_pressed)
	add_child(clear_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Use LakeMarker para lagoas e arquivos de scan para rios."
	add_child(status_label)


func _add_spin(label_text: String, minimum: float, maximum: float, step: float, value: float, suffix: String, hint: String) -> SpinBox:
	var row := HBoxContainer.new()
	row.tooltip_text = hint
	add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 92
	label.tooltip_text = hint
	row.add_child(label)

	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = step
	spin.value = value
	spin.suffix = suffix
	spin.tooltip_text = hint
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spin)
	return spin


func _add_path_edit(label_text: String, value: String, hint: String) -> LineEdit:
	var row := HBoxContainer.new()
	row.tooltip_text = hint
	add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 92
	label.tooltip_text = hint
	row.add_child(label)

	var edit := LineEdit.new()
	edit.text = value
	edit.tooltip_text = hint
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	return edit


func _add_material_picker(label_text: String, default_material: Material, hint: String) -> EditorResourcePicker:
	var row := HBoxContainer.new()
	row.tooltip_text = hint
	add_child(row)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 92
	label.tooltip_text = hint
	row.add_child(label)

	var picker := EditorResourcePicker.new()
	picker.base_type = "Material"
	picker.edited_resource = default_material
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.tooltip_text = hint
	row.add_child(picker)
	return picker


func _on_bake_pressed() -> void:
	var root: Node = editor_plugin.get_scene_root()
	if not root:
		_set_status("No edited scene is open.", true)
		return

	var lake_routes := _collect_marker_routes(root)
	if lake_routes.is_empty():
		_set_status("Nenhuma rota visivel de LakeMarker encontrada.", true)
		return

	var generated_root := _get_or_create_generated_root(root)
	_clear_marker_generated_water(generated_root)

	var surface_material := _get_picker_material(surface_picker, DEFAULT_SURFACE_MATERIAL)
	var smooth_passes := int(smooth_passes_spin.value)
	var surface_offset := float(surface_offset_spin.value)
	var lake_height_offset := float(lake_height_offset_spin.value)
	var lake_min_depth := float(lake_min_depth_spin.value)
	var lake_count := 0
	var invalid_count := 0
	bake_warnings.clear()

	for route in lake_routes:
		if _bake_lake(generated_root, route, surface_material, smooth_passes, surface_offset + lake_height_offset, lake_min_depth):
			lake_count += 1
		else:
			invalid_count += 1

	if lake_count == 0:
		if invalid_count == 0:
			_set_status("Nenhuma lagoa gerada. Verifique quantidade e ordem dos marcadores.", true)
		return

	EditorInterface.mark_scene_as_unsaved()
	var message := "Gerou %d lagoa(s)." % lake_count
	if not bake_warnings.is_empty():
		message += " " + " ".join(bake_warnings)
	_set_status(message, false)


func _on_bake_all_surveys_pressed() -> void:
	var root: Node = editor_plugin.get_scene_root()
	if not root:
		_set_status("No edited scene is open.", true)
		return

	var survey_paths := _collect_survey_files(survey_directory_edit.text.strip_edges())
	if survey_paths.is_empty():
		_set_status("No survey JSON files found.", true)
		return

	var generated_root := _get_or_create_generated_root(root)
	_clear_survey_generated_water(generated_root)

	var surface_material := _get_picker_material(surface_picker, DEFAULT_SURFACE_MATERIAL)
	var smooth_passes := int(smooth_passes_spin.value)
	var edge_inset := float(survey_edge_inset_spin.value)
	var survey_height_offset := float(survey_height_offset_spin.value)
	var max_edge_jump := float(survey_max_edge_jump_spin.value)
	var generated_count := 0
	var invalid_count := 0
	for survey_path in survey_paths:
		var samples := _read_survey_samples(survey_path)
		if samples.size() < 2:
			invalid_count += 1
			continue
		var prepared_samples := _prepare_survey_samples(samples, edge_inset, survey_height_offset, max_edge_jump)
		if _bake_survey_river(generated_root, _survey_node_name_from_path(survey_path), _smooth_river_sections(prepared_samples, smooth_passes), surface_material):
			generated_count += 1
		else:
			invalid_count += 1

	if generated_count == 0:
		_set_status("No survey rivers generated. Check JSON files.", true)
		return

	EditorInterface.mark_scene_as_unsaved()
	var message := "Generated %d survey river(s)." % generated_count
	if invalid_count > 0:
		message += " Ignored %d invalid file(s)." % invalid_count
	_set_status(message, false)


func _on_clear_pressed() -> void:
	var root: Node = editor_plugin.get_scene_root()
	if not root:
		_set_status("No edited scene is open.", true)
		return

	var generated_root := root.get_node_or_null(GENERATED_ROOT_NAME)
	if not generated_root:
		_set_status("No GeneratedWater node found.", true)
		return

	generated_root.queue_free()
	EditorInterface.mark_scene_as_unsaved()
	_set_status("Generated water removed.", false)


func _set_status(message: String, is_error: bool) -> void:
	status_label.text = message
	if is_error:
		push_error(message)
	else:
		print("WaterBaker: ", message)


func _get_picker_material(picker: EditorResourcePicker, fallback: Material) -> Material:
	if picker and picker.edited_resource is Material:
		return picker.edited_resource
	return fallback


func _get_or_create_generated_root(root: Node) -> Node3D:
	var generated_root := root.get_node_or_null(GENERATED_ROOT_NAME) as Node3D
	if generated_root:
		return generated_root

	generated_root = Node3D.new()
	generated_root.name = GENERATED_ROOT_NAME
	root.add_child(generated_root)
	generated_root.owner = root
	return generated_root


func _configure_water_area(area: Area3D) -> void:
	area.monitoring = true
	area.monitorable = true
	area.add_to_group(WATER_AREA_GROUP, true)


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()


func _clear_marker_generated_water(node: Node) -> void:
	for child in node.get_children():
		if String(child.name).begins_with(SURVEY_RIVER_PREFIX):
			continue
		child.free()


func _clear_survey_generated_water(node: Node) -> void:
	for child in node.get_children():
		if String(child.name).begins_with(SURVEY_RIVER_PREFIX):
			child.free()


func _clear_named_child(node: Node, child_name: String) -> void:
	var child := node.get_node_or_null(child_name)
	if child:
		child.free()


func _collect_marker_routes(root: Node) -> Array:
	var routes: Array = []
	_collect_marker_routes_recursive(root, root, routes)
	return routes


func _collect_marker_routes_recursive(root: Node, node: Node, routes: Array) -> void:
	if node != root and not _is_visible_node(node):
		return
	if _is_marker(node):
		return

	var route := _collect_direct_markers(node)
	if route.size() >= 3:
		routes.append({
			"name": node.name,
			"markers": route,
		})

	for child in node.get_children():
		_collect_marker_routes_recursive(root, child, routes)


func _collect_direct_markers(node: Node) -> Array:
	var markers: Array = []
	for child in node.get_children():
		if _is_marker(child) and _is_visible_node(child):
			markers.append(child)
	markers.sort_custom(_compare_marker_order)
	return markers


func _compare_marker_order(a: Node, b: Node) -> bool:
	var a_index := _marker_order_index(a.name)
	var b_index := _marker_order_index(b.name)
	if a_index == b_index:
		return String(a.name).naturalnocasecmp_to(String(b.name)) < 0
	return a_index < b_index


func _marker_order_index(marker_name: StringName) -> int:
	var text := String(marker_name)
	var digits := ""
	for index in range(text.length() - 1, -1, -1):
		var character := text[index]
		if character < "0" or character > "9":
			break
		digits = character + digits
	if digits.is_empty():
		return 1
	return int(digits)


func _is_marker(node: Node) -> bool:
	return node.name.begins_with("LakeMarker") or node.scene_file_path == LAKE_MARKER_SCENE


func _is_visible_node(node: Node) -> bool:
	if node.has_method("is_visible_in_tree"):
		return bool(node.call("is_visible_in_tree"))
	for property in node.get_property_list():
		if String(property.name) == "visible":
			return bool(node.get("visible"))
	return true


func _bake_survey_river(parent: Node, node_name: String, samples: Array, surface_material: Material) -> bool:
	if samples.size() < 2:
		return false

	var body := Node3D.new()
	body.name = node_name
	parent.add_child(body)
	body.owner = editor_plugin.get_scene_root()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WaterMesh"
	mesh_instance.mesh = _build_river_edge_mesh(samples, surface_material)
	body.add_child(mesh_instance)
	mesh_instance.owner = editor_plugin.get_scene_root()

	var area := Area3D.new()
	area.name = "WaterArea"
	_configure_water_area(area)
	body.add_child(area)
	area.owner = editor_plugin.get_scene_root()
	_add_river_edge_collision_prisms(area, samples)
	return true


func _collect_survey_files(directory_path: String) -> Array[String]:
	var survey_paths: Array[String] = []
	if directory_path.is_empty():
		_set_status("Survey directory path is empty.", true)
		return survey_paths

	var directory := DirAccess.open(directory_path)
	if not directory:
		_set_status("Survey directory not found: %s" % directory_path, true)
		return survey_paths

	directory.list_dir_begin()
	var file_name := directory.get_next()
	while not file_name.is_empty():
		if not directory.current_is_dir() and file_name.get_extension().to_lower() == "json":
			survey_paths.append(directory_path.path_join(file_name))
		file_name = directory.get_next()
	directory.list_dir_end()
	survey_paths.sort()
	return survey_paths


func _survey_node_name_from_path(path: String) -> String:
	var base_name := path.get_file().get_basename()
	if base_name.is_empty():
		base_name = "survey_river"
	return _safe_node_name(SURVEY_RIVER_PREFIX + base_name)


func _read_survey_samples(path: String) -> Array:
	if path.is_empty():
		_set_status("Survey file path is empty.", true)
		return []
	if not FileAccess.file_exists(path):
		_set_status("Survey file not found: %s" % path, true)
		return []

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		_set_status("Could not read survey file: %s" % path, true)
		return []

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_set_status("Survey file is not valid JSON data.", true)
		return []

	var raw_samples: Variant = parsed.get("samples", [])
	if not raw_samples is Array:
		_set_status("Survey file does not contain a samples array.", true)
		return []

	var samples: Array = []
	for index in raw_samples.size():
		var raw_sample: Variant = raw_samples[index]
		if not raw_sample is Dictionary:
			continue
		if not raw_sample.has("left") or not raw_sample.has("right"):
			continue

		var left := _parse_vector3(raw_sample["left"], Vector3.ZERO)
		var right := _parse_vector3(raw_sample["right"], Vector3.ZERO)
		var center := _parse_vector3(raw_sample.get("center", []), (left + right) * 0.5)
		var surface_y := (left.y + right.y) * 0.5
		left.y = surface_y
		right.y = surface_y
		center.y = surface_y
		samples.append({
			"left": left,
			"right": right,
			"center": center,
			"depth": maxf(float(raw_sample.get("depth", 2.0)), 0.1),
		})
	return samples


func _parse_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback


func _prepare_survey_samples(samples: Array, edge_inset: float, height_offset: float, max_edge_jump: float) -> Array:
	var prepared := samples.duplicate(true)
	_orient_river_sections(prepared)
	if max_edge_jump > 0.0:
		_clamp_survey_edge_jumps(prepared, max_edge_jump)
	if edge_inset > 0.0:
		_inset_survey_edges(prepared, edge_inset)
	if not is_zero_approx(height_offset):
		_offset_survey_height(prepared, height_offset)
	return prepared


func _clamp_survey_edge_jumps(samples: Array, max_edge_jump: float) -> void:
	if samples.size() < 2:
		return

	for index in range(1, samples.size()):
		var previous: Dictionary = samples[index - 1]
		var current: Dictionary = samples[index]
		var previous_center: Vector3 = previous["center"]
		var current_center: Vector3 = current["center"]
		var center_delta := current_center - previous_center
		center_delta.y = 0.0
		var allowed_jump := maxf(max_edge_jump, _flat_distance(previous_center, current_center) * 3.0)

		var previous_left: Vector3 = previous["left"]
		var previous_right: Vector3 = previous["right"]
		var current_left: Vector3 = current["left"]
		var current_right: Vector3 = current["right"]
		if _flat_distance(previous_left, current_left) > allowed_jump:
			current_left = previous_left + center_delta
			current_left.y = (current["left"] as Vector3).y
			current["left"] = current_left
		if _flat_distance(previous_right, current_right) > allowed_jump:
			current_right = previous_right + center_delta
			current_right.y = (current["right"] as Vector3).y
			current["right"] = current_right
		current["center"] = ((current["left"] as Vector3) + (current["right"] as Vector3)) * 0.5


func _inset_survey_edges(samples: Array, edge_inset: float) -> void:
	for sample in samples:
		var left: Vector3 = sample["left"]
		var right: Vector3 = sample["right"]
		var width := _flat_distance(left, right)
		if width <= 0.01:
			continue
		var midpoint := (left + right) * 0.5
		var weight := clampf(edge_inset / width, 0.0, 0.45)
		sample["left"] = left.lerp(midpoint, weight)
		sample["right"] = right.lerp(midpoint, weight)
		sample["center"] = ((sample["left"] as Vector3) + (sample["right"] as Vector3)) * 0.5


func _offset_survey_height(samples: Array, height_offset: float) -> void:
	for sample in samples:
		var left: Vector3 = sample["left"]
		var right: Vector3 = sample["right"]
		var center: Vector3 = sample["center"]
		left.y += height_offset
		right.y += height_offset
		center.y += height_offset
		sample["left"] = left
		sample["right"] = right
		sample["center"] = center
		sample["depth"] = maxf(float(sample["depth"]) + height_offset, 0.1)


func _smooth_river_sections(sections: Array, smooth_passes: int) -> Array:
	var smoothed := sections.duplicate(true)
	for _pass_index in range(clampi(smooth_passes, 0, 5)):
		if smoothed.size() < 3:
			break

		var next_sections: Array = [smoothed[0]]
		for index in range(smoothed.size() - 1):
			var a: Dictionary = smoothed[index]
			var b: Dictionary = smoothed[index + 1]
			next_sections.append(_lerp_river_section(a, b, 0.25))
			next_sections.append(_lerp_river_section(a, b, 0.75))
		next_sections.append(smoothed[-1])
		smoothed = next_sections
	return smoothed


func _lerp_river_section(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var left_a: Vector3 = a["left"]
	var left_b: Vector3 = b["left"]
	var right_a: Vector3 = a["right"]
	var right_b: Vector3 = b["right"]
	var left := left_a.lerp(left_b, weight)
	var right := right_a.lerp(right_b, weight)
	return {
		"left": left,
		"right": right,
		"center": (left + right) * 0.5,
		"depth": lerpf(float(a["depth"]), float(b["depth"]), weight),
	}


func _orient_river_sections(sections: Array) -> void:
	if sections.size() < 2:
		return

	for index in range(1, sections.size()):
		var previous_left: Vector3 = sections[index - 1]["left"]
		var previous_right: Vector3 = sections[index - 1]["right"]
		var current_left: Vector3 = sections[index]["left"]
		var current_right: Vector3 = sections[index]["right"]
		var keep_cost := previous_left.distance_squared_to(current_left) + previous_right.distance_squared_to(current_right)
		var swap_cost := previous_left.distance_squared_to(current_right) + previous_right.distance_squared_to(current_left)
		if swap_cost < keep_cost:
			sections[index]["left"] = current_right
			sections[index]["right"] = current_left


func _flat_distance_squared(a: Vector3, b: Vector3) -> float:
	var delta_x := a.x - b.x
	var delta_z := a.z - b.z
	return delta_x * delta_x + delta_z * delta_z


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return sqrt(_flat_distance_squared(a, b))


func _build_river_edge_mesh(samples: Array, surface_material: Material) -> ArrayMesh:
	var surface_vertices := PackedVector3Array()
	var surface_uvs := PackedVector2Array()
	var surface_indices := PackedInt32Array()
	var length_u := 0.0
	for index in samples.size():
		if index > 0:
			length_u += (samples[index]["center"] as Vector3).distance_to(samples[index - 1]["center"])
		surface_vertices.append(samples[index]["left"])
		surface_vertices.append(samples[index]["right"])
		surface_uvs.append(Vector2(length_u * 0.05, 0.0))
		surface_uvs.append(Vector2(length_u * 0.05, 1.0))

	for index in range(samples.size() - 1):
		var base := index * 2
		surface_indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))

	var mesh := ArrayMesh.new()
	_add_mesh_surface(mesh, surface_vertices, surface_uvs, surface_indices, surface_material)
	return mesh


func _add_river_edge_collision_prisms(area: Area3D, samples: Array) -> void:
	for index in range(samples.size() - 1):
		var left_a: Vector3 = samples[index]["left"]
		var right_a: Vector3 = samples[index]["right"]
		var left_b: Vector3 = samples[index + 1]["left"]
		var right_b: Vector3 = samples[index + 1]["right"]
		var depth := (float(samples[index]["depth"]) + float(samples[index + 1]["depth"])) * 0.5
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([
			left_a, right_a, right_b, left_b,
			left_a - Vector3(0.0, depth, 0.0),
			right_a - Vector3(0.0, depth, 0.0),
			right_b - Vector3(0.0, depth, 0.0),
			left_b - Vector3(0.0, depth, 0.0),
		])

		var collision := CollisionShape3D.new()
		collision.name = "WaterSegmentCollision"
		collision.shape = shape
		area.add_child(collision)
		collision.owner = editor_plugin.get_scene_root()


func _bake_lake(parent: Node, route: Dictionary, surface_material: Material, smooth_passes: int, global_surface_offset: float, minimum_depth: float) -> bool:
	var markers: Array = route["markers"]
	if markers.size() < 3:
		return false

	var profiles: Array = []
	for marker in markers:
		var water_profile := _get_marker_water_profile(marker, global_surface_offset, 3.0)
		profiles.append({
			"position": water_profile["position"],
			"depth": maxf(float(water_profile["depth"]), minimum_depth),
		})
	_order_lake_profiles_around_center(profiles)
	_remove_duplicate_lake_profiles(profiles)
	profiles = _smooth_lake_profiles(profiles, smooth_passes)
	_remove_duplicate_lake_profiles(profiles)
	if profiles.size() < 3:
		_set_status("Lake %s needs at least 3 unique LakeMarker positions." % String(route["name"]), true)
		return false

	var polygon := PackedVector2Array()
	var top_points: Array[Vector3] = []
	var bottom_points: Array[Vector3] = []
	for profile in profiles:
		var top: Vector3 = profile["position"]
		var depth: float = profile["depth"]
		top_points.append(top)
		bottom_points.append(top - Vector3(0.0, depth, 0.0))
		polygon.append(Vector2(top.x, top.z))

	var triangles := Geometry2D.triangulate_polygon(polygon)
	if triangles.is_empty():
		_set_status("Lake %s could not be triangulated." % String(route["name"]), true)
		return false

	var body := Node3D.new()
	body.name = _safe_node_name(String(route["name"]))
	parent.add_child(body)
	body.owner = editor_plugin.get_scene_root()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WaterMesh"
	mesh_instance.mesh = _build_lake_mesh(top_points, triangles, surface_material)
	body.add_child(mesh_instance)
	mesh_instance.owner = editor_plugin.get_scene_root()

	var area := Area3D.new()
	area.name = "WaterArea"
	_configure_water_area(area)
	body.add_child(area)
	area.owner = editor_plugin.get_scene_root()
	_add_lake_collision_prisms(area, top_points, bottom_points, triangles)
	return true


func _order_lake_profiles_around_center(profiles: Array) -> void:
	var center := Vector2.ZERO
	for profile in profiles:
		var position: Vector3 = profile["position"]
		center += Vector2(position.x, position.z)
	center /= float(profiles.size())

	for profile in profiles:
		var position: Vector3 = profile["position"]
		profile["angle"] = atan2(position.z - center.y, position.x - center.x)

	profiles.sort_custom(_compare_lake_profile_angle)


func _compare_lake_profile_angle(a: Dictionary, b: Dictionary) -> bool:
	return float(a["angle"]) < float(b["angle"])


func _remove_duplicate_lake_profiles(profiles: Array) -> void:
	var index := profiles.size() - 1
	while index >= 0:
		var current: Vector3 = profiles[index]["position"]
		var previous: Vector3 = profiles[(index - 1 + profiles.size()) % profiles.size()]["position"]
		if _flat_distance_squared(current, previous) <= 0.01:
			profiles.remove_at(index)
		index -= 1


func _smooth_lake_profiles(profiles: Array, smooth_passes: int) -> Array:
	var smoothed := profiles.duplicate(true)
	for _pass_index in range(clampi(smooth_passes, 0, 5)):
		if smoothed.size() < 3:
			break

		var next_profiles: Array = []
		for index in smoothed.size():
			var a: Dictionary = smoothed[index]
			var b: Dictionary = smoothed[(index + 1) % smoothed.size()]
			next_profiles.append(_lerp_lake_profile(a, b, 0.25))
			next_profiles.append(_lerp_lake_profile(a, b, 0.75))
		smoothed = next_profiles
	return smoothed


func _lerp_lake_profile(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
	var position_a: Vector3 = a["position"]
	var position_b: Vector3 = b["position"]
	return {
		"position": position_a.lerp(position_b, weight),
		"depth": lerpf(float(a["depth"]), float(b["depth"]), weight),
	}


func _build_lake_mesh(top_points: Array[Vector3], triangles: PackedInt32Array, surface_material: Material) -> ArrayMesh:
	var surface_vertices := PackedVector3Array()
	var surface_uvs := PackedVector2Array()
	var surface_indices := PackedInt32Array()
	for point in top_points:
		surface_vertices.append(point)
		surface_uvs.append(Vector2(point.x, point.z) * 0.05)
	surface_indices = triangles

	var mesh := ArrayMesh.new()
	_add_mesh_surface(mesh, surface_vertices, surface_uvs, surface_indices, surface_material)
	return mesh


func _add_lake_collision_prisms(area: Area3D, top_points: Array[Vector3], bottom_points: Array[Vector3], triangles: PackedInt32Array) -> void:
	for index in range(0, triangles.size(), 3):
		var a := int(triangles[index])
		var b := int(triangles[index + 1])
		var c := int(triangles[index + 2])
		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([
			top_points[a], top_points[b], top_points[c],
			bottom_points[a], bottom_points[b], bottom_points[c],
		])

		var collision := CollisionShape3D.new()
		collision.name = "WaterTriangleCollision"
		collision.shape = shape
		area.add_child(collision)
		collision.owner = editor_plugin.get_scene_root()


func _add_mesh_surface(mesh: ArrayMesh, vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, material: Material) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_NORMAL] = _make_surface_normals(vertices.size())
	arrays[Mesh.ARRAY_TANGENT] = _make_surface_tangents(vertices.size())
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


func _make_surface_normals(vertex_count: int) -> PackedVector3Array:
	var normals := PackedVector3Array()
	for _index in vertex_count:
		normals.append(Vector3.UP)
	return normals


func _make_surface_tangents(vertex_count: int) -> PackedFloat32Array:
	var tangents := PackedFloat32Array()
	for _index in vertex_count:
		tangents.append_array(PackedFloat32Array([1.0, 0.0, 0.0, 1.0]))
	return tangents


func _catmull_rom_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return (
		p1 * 2.0
		+ (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p3 - p0 + (p1 - p2) * 3.0) * t3
	) * 0.5


func _get_float_property(node: Node, property_name: String, fallback: float) -> float:
	for property in node.get_property_list():
		if String(property.name) == property_name:
			return float(node.get(property_name))
	return fallback


func _get_marker_water_profile(marker: Node3D, global_surface_offset: float, default_depth: float) -> Dictionary:
	var fallback_depth := _get_float_property(marker, "depth", default_depth)
	var marker_surface_offset := _get_float_property(marker, "surface_offset", 0.0)
	var total_offset := global_surface_offset + marker_surface_offset
	return {
		"position": marker.global_position + Vector3(0.0, total_offset, 0.0),
		"depth": fallback_depth,
	}


func _safe_node_name(value: String) -> String:
	var safe := value.strip_edges()
	if safe.is_empty():
		return "WaterBody"
	return safe.replace("/", "_").replace("\\", "_").replace(":", "_")
