@tool
extends VBoxContainer


const RIVER_MARKER_SCENE := "res://scenes/components/river_marker.tscn"
const LAKE_MARKER_SCENE := "res://scenes/components/lake_marker.tscn"
const GENERATED_ROOT_NAME := "GeneratedWater"
const SURVEY_RIVER_NAME := "SurveyRiver"
const DEFAULT_SURVEY_FILE := "res://river_survey.json"
const DEFAULT_SURFACE_MATERIAL := preload("res://addons/relic_road_tools/water_surface.tres")
const DEFAULT_VOLUME_MATERIAL := preload("res://addons/relic_road_tools/water_volume.tres")


var editor_plugin: EditorPlugin
var curve_step_spin: SpinBox
var smooth_passes_spin: SpinBox
var surface_offset_spin: SpinBox
var survey_path_edit: LineEdit
var surface_picker: EditorResourcePicker
var volume_picker: EditorResourcePicker
var bake_button: Button
var bake_survey_button: Button
var clear_button: Button
var status_label: Label
var bake_warnings: Array[String] = []


func _init() -> void:
	name = "Water Baker"
	custom_minimum_size = Vector2(300, 0)

	var title := Label.new()
	title.text = "Water Baker"
	title.tooltip_text = "Generates river and lake meshes from visible RiverMarker and LakeMarker nodes."
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	curve_step_spin = _add_spin("Curve Step", 0.5, 30.0, 0.5, 4.0, "m", "Distance between sampled river curve points. Lower values follow curves better.")
	smooth_passes_spin = _add_spin("Smooth Passes", 0.0, 5.0, 1.0, 2.0, "", "Rounds river and lake corners. Higher values are smoother but pull the water edge inward.")
	surface_offset_spin = _add_spin("Surface Offset", -100.0, 100.0, 0.1, 0.0, "m", "Adds height to marker origins when generating the water surface.")
	survey_path_edit = _add_path_edit("Survey File", DEFAULT_SURVEY_FILE, "River survey file recorded by the player sensor.")
	surface_picker = _add_material_picker("Surface", DEFAULT_SURFACE_MATERIAL, "Material used by the visible water surface.")
	volume_picker = _add_material_picker("Volume", DEFAULT_VOLUME_MATERIAL, "Material used by generated sides and bottom volume.")

	bake_button = Button.new()
	bake_button.text = "Bake Water"
	bake_button.tooltip_text = "Generates normal Godot meshes and Area3D water volumes from visible markers."
	bake_button.pressed.connect(_on_bake_pressed)
	add_child(bake_button)

	bake_survey_button = Button.new()
	bake_survey_button.text = "Bake Survey File"
	bake_survey_button.tooltip_text = "Generates a river mesh from the survey samples recorded by the player."
	bake_survey_button.pressed.connect(_on_bake_survey_pressed)
	add_child(bake_survey_button)

	clear_button = Button.new()
	clear_button.text = "Clear Generated Water"
	clear_button.tooltip_text = "Removes the GeneratedWater node created by this tool."
	clear_button.pressed.connect(_on_clear_pressed)
	add_child(clear_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Use RiverMarker edge pairs for rivers and LakeMarker outlines for lakes."
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

	var river_routes := _collect_marker_routes(root, true)
	var lake_routes := _collect_marker_routes(root, false)
	if river_routes.is_empty() and lake_routes.is_empty():
		_set_status("No visible river or lake marker routes found.", true)
		return

	var generated_root := _get_or_create_generated_root(root)
	_clear_marker_generated_water(generated_root)

	var surface_material := _get_picker_material(surface_picker, DEFAULT_SURFACE_MATERIAL)
	var volume_material := _get_picker_material(volume_picker, DEFAULT_VOLUME_MATERIAL)
	var curve_step := float(curve_step_spin.value)
	var smooth_passes := int(smooth_passes_spin.value)
	var surface_offset := float(surface_offset_spin.value)
	var river_count := 0
	var lake_count := 0
	var invalid_count := 0
	bake_warnings.clear()

	for route in river_routes:
		if _bake_river(generated_root, route, surface_material, volume_material, curve_step, smooth_passes, surface_offset):
			river_count += 1
		else:
			invalid_count += 1

	for route in lake_routes:
		if _bake_lake(generated_root, route, surface_material, volume_material, smooth_passes, surface_offset):
			lake_count += 1
		else:
			invalid_count += 1

	if river_count == 0 and lake_count == 0:
		if invalid_count == 0:
			_set_status("No water generated. Check marker counts and order.", true)
		return

	EditorInterface.mark_scene_as_unsaved()
	var message := "Generated %d river(s) and %d lake(s)." % [river_count, lake_count]
	if not bake_warnings.is_empty():
		message += " " + " ".join(bake_warnings)
	_set_status(message, false)


func _on_bake_survey_pressed() -> void:
	var root: Node = editor_plugin.get_scene_root()
	if not root:
		_set_status("No edited scene is open.", true)
		return

	var samples := _read_survey_samples(survey_path_edit.text.strip_edges())
	if samples.size() < 2:
		_set_status("Survey file needs at least 2 valid samples.", true)
		return

	var generated_root := _get_or_create_generated_root(root)
	_clear_named_child(generated_root, SURVEY_RIVER_NAME)

	var surface_material := _get_picker_material(surface_picker, DEFAULT_SURFACE_MATERIAL)
	var volume_material := _get_picker_material(volume_picker, DEFAULT_VOLUME_MATERIAL)
	var smooth_passes := int(smooth_passes_spin.value)
	if _bake_survey_river(generated_root, _smooth_river_sections(samples, smooth_passes), surface_material, volume_material):
		EditorInterface.mark_scene_as_unsaved()
		_set_status("Generated survey river from %d sample(s)." % samples.size(), false)
	else:
		_set_status("Survey river could not be generated.", true)


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


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()


func _clear_marker_generated_water(node: Node) -> void:
	for child in node.get_children():
		if child.name == SURVEY_RIVER_NAME:
			continue
		child.free()


func _clear_named_child(node: Node, child_name: String) -> void:
	var child := node.get_node_or_null(child_name)
	if child:
		child.free()


func _collect_marker_routes(root: Node, river: bool) -> Array:
	var routes: Array = []
	_collect_marker_routes_recursive(root, root, river, routes)
	return routes


func _collect_marker_routes_recursive(root: Node, node: Node, river: bool, routes: Array) -> void:
	if node != root and not _is_visible_node(node):
		return
	if _is_marker(node, river):
		return

	var route := _collect_direct_markers(node, river)
	var minimum := 2 if river else 3
	if route.size() >= minimum:
		routes.append({
			"name": node.name,
			"markers": route,
		})

	for child in node.get_children():
		_collect_marker_routes_recursive(root, child, river, routes)


func _collect_direct_markers(node: Node, river: bool) -> Array:
	var markers: Array = []
	for child in node.get_children():
		if _is_marker(child, river) and _is_visible_node(child):
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


func _is_marker(node: Node, river: bool) -> bool:
	if river:
		return node.name.begins_with("RiverMarker") or node.scene_file_path == RIVER_MARKER_SCENE
	return node.name.begins_with("LakeMarker") or node.scene_file_path == LAKE_MARKER_SCENE


func _is_visible_node(node: Node) -> bool:
	if node.has_method("is_visible_in_tree"):
		return bool(node.call("is_visible_in_tree"))
	for property in node.get_property_list():
		if String(property.name) == "visible":
			return bool(node.get("visible"))
	return true


func _bake_river(parent: Node, route: Dictionary, surface_material: Material, volume_material: Material, curve_step: float, smooth_passes: int, global_surface_offset: float) -> bool:
	var markers: Array = (route["markers"] as Array).duplicate()
	if markers.size() < 4:
		_set_status("River %s found %d RiverMarker node(s), but needs at least 4: two edge pairs." % [String(route["name"]), markers.size()], true)
		return false
	if markers.size() % 2 != 0:
		var skip_index := _choose_unpaired_river_marker_to_skip(markers, global_surface_offset)
		var skipped_marker: Node = markers[skip_index]
		markers.remove_at(skip_index)
		var warning := "River %s had an odd marker count; skipped %s for this bake." % [String(route["name"]), skipped_marker.name]
		bake_warnings.append(warning)
		push_warning("WaterBaker: " + warning)

	var samples := _sample_river_edge_pairs(markers, curve_step, smooth_passes, global_surface_offset)
	if samples.size() < 2:
		return false

	var body := Node3D.new()
	body.name = _safe_node_name(String(route["name"]))
	parent.add_child(body)
	body.owner = editor_plugin.get_scene_root()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WaterMesh"
	mesh_instance.mesh = _build_river_edge_mesh(samples, surface_material, volume_material)
	body.add_child(mesh_instance)
	mesh_instance.owner = editor_plugin.get_scene_root()

	var area := Area3D.new()
	area.name = "WaterArea"
	body.add_child(area)
	area.owner = editor_plugin.get_scene_root()
	_add_river_edge_collision_prisms(area, samples)
	return true


func _bake_survey_river(parent: Node, samples: Array, surface_material: Material, volume_material: Material) -> bool:
	if samples.size() < 2:
		return false

	var body := Node3D.new()
	body.name = SURVEY_RIVER_NAME
	parent.add_child(body)
	body.owner = editor_plugin.get_scene_root()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "WaterMesh"
	mesh_instance.mesh = _build_river_edge_mesh(samples, surface_material, volume_material)
	body.add_child(mesh_instance)
	mesh_instance.owner = editor_plugin.get_scene_root()

	var area := Area3D.new()
	area.name = "WaterArea"
	body.add_child(area)
	area.owner = editor_plugin.get_scene_root()
	_add_river_edge_collision_prisms(area, samples)
	return true


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


func _sample_river_edge_pairs(markers: Array, sample_step: float, smooth_passes: int, global_surface_offset: float) -> Array:
	var profiles: Array = []
	for marker in markers:
		profiles.append(_get_marker_water_profile(marker, global_surface_offset, 2.0))

	var sections := _build_river_edge_sections(profiles)
	_order_river_sections(sections)
	_optimize_river_section_order(sections)
	_orient_river_sections(sections)
	sections = _smooth_river_sections(sections, smooth_passes)

	var samples: Array = []
	for segment in range(sections.size() - 1):
		var left1: Vector3 = sections[segment]["left"]
		var left2: Vector3 = sections[segment + 1]["left"]
		var right1: Vector3 = sections[segment]["right"]
		var right2: Vector3 = sections[segment + 1]["right"]
		var center1: Vector3 = sections[segment]["center"]
		var center2: Vector3 = sections[segment + 1]["center"]
		var distance := center1.distance_to(center2)
		var steps := maxi(2, ceili(distance / maxf(sample_step, 0.25)))

		for step in range(steps):
			var t := float(step) / float(steps)
			var left := left1.lerp(left2, t)
			var right := right1.lerp(right2, t)
			samples.append({
				"left": left,
				"right": right,
				"center": (left + right) * 0.5,
				"depth": lerpf(float(sections[segment]["depth"]), float(sections[segment + 1]["depth"]), t),
			})

	samples.append(sections[-1])
	return samples


func _choose_unpaired_river_marker_to_skip(markers: Array, global_surface_offset: float) -> int:
	var best_index := 0
	var best_score := INF
	for skip_index in markers.size():
		var profiles: Array = []
		for marker_index in markers.size():
			if marker_index == skip_index:
				continue
			profiles.append(_get_marker_water_profile(markers[marker_index], global_surface_offset, 2.0))

		var sections := _build_river_edge_sections(profiles)
		_order_river_sections(sections)
		_optimize_river_section_order(sections)
		_orient_river_sections(sections)
		var score := _score_river_sections(sections)
		if score < best_score:
			best_score = score
			best_index = skip_index
	return best_index


func _score_river_sections(sections: Array) -> float:
	if sections.size() < 2:
		return INF

	var score := 0.0
	for section in sections:
		var left: Vector3 = section["left"]
		var right: Vector3 = section["right"]
		score += _flat_distance_squared(left, right) * 0.25

	for index in range(sections.size() - 1):
		var current_center: Vector3 = sections[index]["center"]
		var next_center: Vector3 = sections[index + 1]["center"]
		score += _flat_distance_squared(current_center, next_center)

		var left_a: Vector3 = sections[index]["left"]
		var right_a: Vector3 = sections[index]["right"]
		var left_b: Vector3 = sections[index + 1]["left"]
		var right_b: Vector3 = sections[index + 1]["right"]
		score += maxf(0.0, _flat_distance_squared(left_a, left_b) - _flat_distance_squared(current_center, next_center)) * 0.15
		score += maxf(0.0, _flat_distance_squared(right_a, right_b) - _flat_distance_squared(current_center, next_center)) * 0.15

	return score


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


func _build_river_edge_sections(profiles: Array) -> Array:
	var candidates: Array = []
	for a in profiles.size():
		for b in range(a + 1, profiles.size()):
			var a_position: Vector3 = profiles[a]["position"]
			var b_position: Vector3 = profiles[b]["position"]
			candidates.append({
				"a": a,
				"b": b,
				"distance": _flat_distance_squared(a_position, b_position),
			})
	candidates.sort_custom(_compare_pair_candidate)

	var used := {}
	var sections: Array = []
	for candidate in candidates:
		var a_index: int = candidate["a"]
		var b_index: int = candidate["b"]
		if used.has(a_index) or used.has(b_index):
			continue

		used[a_index] = true
		used[b_index] = true
		var left: Vector3 = profiles[a_index]["position"]
		var right: Vector3 = profiles[b_index]["position"]
		var surface_y := (left.y + right.y) * 0.5
		left.y = surface_y
		right.y = surface_y
		sections.append({
			"left": left,
			"right": right,
			"center": (left + right) * 0.5,
			"depth": maxf((float(profiles[a_index]["depth"]) + float(profiles[b_index]["depth"])) * 0.5, 0.1),
		})

	return sections


func _compare_pair_candidate(a: Dictionary, b: Dictionary) -> bool:
	return float(a["distance"]) < float(b["distance"])


func _order_river_sections(sections: Array) -> void:
	if sections.size() < 3:
		return

	var start_index := _find_farthest_section_endpoint(sections)
	var ordered: Array = [sections[start_index]]
	var used := {start_index: true}

	while ordered.size() < sections.size():
		var last_center: Vector3 = ordered[-1]["center"]
		var best_index := -1
		var best_distance := INF
		for index in sections.size():
			if used.has(index):
				continue
			var center: Vector3 = sections[index]["center"]
			var distance := _flat_distance_squared(last_center, center)
			if distance < best_distance:
				best_distance = distance
				best_index = index
		if best_index < 0:
			break
		used[best_index] = true
		ordered.append(sections[best_index])

	sections.clear()
	sections.append_array(ordered)


func _find_farthest_section_endpoint(sections: Array) -> int:
	var best_a := 0
	var best_distance := -1.0
	for a in sections.size():
		var a_center: Vector3 = sections[a]["center"]
		for b in range(a + 1, sections.size()):
			var b_center: Vector3 = sections[b]["center"]
			var distance := _flat_distance_squared(a_center, b_center)
			if distance > best_distance:
				best_distance = distance
				best_a = a
	return best_a


func _optimize_river_section_order(sections: Array) -> void:
	if sections.size() < 4:
		return

	var improved := true
	var max_passes := 24
	var pass_index := 0
	while improved and pass_index < max_passes:
		improved = false
		pass_index += 1
		for a in range(0, sections.size() - 3):
			for b in range(a + 2, sections.size() - 1):
				var current_cost := _section_link_cost(sections[a], sections[a + 1]) + _section_link_cost(sections[b], sections[b + 1])
				var swapped_cost := _section_link_cost(sections[a], sections[b]) + _section_link_cost(sections[a + 1], sections[b + 1])
				if swapped_cost + 0.001 < current_cost:
					_reverse_sections(sections, a + 1, b)
					improved = true


func _section_link_cost(a: Dictionary, b: Dictionary) -> float:
	var a_center: Vector3 = a["center"]
	var b_center: Vector3 = b["center"]
	return _flat_distance_squared(a_center, b_center)


func _reverse_sections(sections: Array, start: int, end: int) -> void:
	while start < end:
		var temp: Variant = sections[start]
		sections[start] = sections[end]
		sections[end] = temp
		start += 1
		end -= 1


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


func _build_river_edge_mesh(samples: Array, surface_material: Material, volume_material: Material) -> ArrayMesh:
	var left_top: Array[Vector3] = []
	var right_top: Array[Vector3] = []
	var left_bottom: Array[Vector3] = []
	var right_bottom: Array[Vector3] = []

	for index in samples.size():
		var depth := float(samples[index]["depth"])
		left_top.append(samples[index]["left"])
		right_top.append(samples[index]["right"])
		left_bottom.append(left_top[-1] - Vector3(0.0, depth, 0.0))
		right_bottom.append(right_top[-1] - Vector3(0.0, depth, 0.0))

	var surface_vertices := PackedVector3Array()
	var surface_uvs := PackedVector2Array()
	var surface_indices := PackedInt32Array()
	var length_u := 0.0
	for index in samples.size():
		if index > 0:
			length_u += (samples[index]["center"] as Vector3).distance_to(samples[index - 1]["center"])
		surface_vertices.append(left_top[index])
		surface_vertices.append(right_top[index])
		surface_uvs.append(Vector2(length_u * 0.05, 0.0))
		surface_uvs.append(Vector2(length_u * 0.05, 1.0))

	for index in range(samples.size() - 1):
		var base := index * 2
		surface_indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))

	var volume_vertices := PackedVector3Array()
	var volume_uvs := PackedVector2Array()
	var volume_indices := PackedInt32Array()
	_add_river_volume_faces(volume_vertices, volume_uvs, volume_indices, left_top, left_bottom)
	_add_river_volume_faces(volume_vertices, volume_uvs, volume_indices, right_bottom, right_top)
	_add_river_volume_faces(volume_vertices, volume_uvs, volume_indices, left_bottom, right_bottom)
	_add_river_cap(volume_vertices, volume_uvs, volume_indices, left_top[0], right_top[0], right_bottom[0], left_bottom[0])
	_add_river_cap(volume_vertices, volume_uvs, volume_indices, right_top[-1], left_top[-1], left_bottom[-1], right_bottom[-1])

	var mesh := ArrayMesh.new()
	_add_mesh_surface(mesh, surface_vertices, surface_uvs, surface_indices, surface_material)
	_add_mesh_surface(mesh, volume_vertices, volume_uvs, volume_indices, volume_material)
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


func _add_river_volume_faces(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a_points: Array[Vector3], b_points: Array[Vector3]) -> void:
	var start := vertices.size()
	for index in a_points.size():
		vertices.append(a_points[index])
		vertices.append(b_points[index])
		uvs.append(Vector2(index, 0.0))
		uvs.append(Vector2(index, 1.0))

	for index in range(a_points.size() - 1):
		var base := start + index * 2
		indices.append_array(PackedInt32Array([base, base + 2, base + 1, base + 1, base + 2, base + 3]))


func _add_river_cap(vertices: PackedVector3Array, uvs: PackedVector2Array, indices: PackedInt32Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	var base := vertices.size()
	vertices.append_array(PackedVector3Array([a, b, c, d]))
	uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]))
	indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))


func _bake_lake(parent: Node, route: Dictionary, surface_material: Material, volume_material: Material, smooth_passes: int, global_surface_offset: float) -> bool:
	var markers: Array = route["markers"]
	if markers.size() < 3:
		return false

	var profiles: Array = []
	for marker in markers:
		var water_profile := _get_marker_water_profile(marker, global_surface_offset, 3.0)
		profiles.append({
			"position": water_profile["position"],
			"depth": water_profile["depth"],
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
	mesh_instance.mesh = _build_lake_mesh(top_points, bottom_points, triangles, surface_material, volume_material)
	body.add_child(mesh_instance)
	mesh_instance.owner = editor_plugin.get_scene_root()

	var area := Area3D.new()
	area.name = "WaterArea"
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


func _build_lake_mesh(top_points: Array[Vector3], bottom_points: Array[Vector3], triangles: PackedInt32Array, surface_material: Material, volume_material: Material) -> ArrayMesh:
	var surface_vertices := PackedVector3Array()
	var surface_uvs := PackedVector2Array()
	var surface_indices := PackedInt32Array()
	for point in top_points:
		surface_vertices.append(point)
		surface_uvs.append(Vector2(point.x, point.z) * 0.05)
	surface_indices = triangles

	var volume_vertices := PackedVector3Array()
	var volume_uvs := PackedVector2Array()
	var volume_indices := PackedInt32Array()
	for point in bottom_points:
		volume_vertices.append(point)
		volume_uvs.append(Vector2(point.x, point.z) * 0.05)
	for index in range(0, triangles.size(), 3):
		volume_indices.append_array(PackedInt32Array([triangles[index + 2], triangles[index + 1], triangles[index]]))

	for index in top_points.size():
		var next := (index + 1) % top_points.size()
		var base := volume_vertices.size()
		volume_vertices.append_array(PackedVector3Array([top_points[index], top_points[next], bottom_points[next], bottom_points[index]]))
		volume_uvs.append_array(PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]))
		volume_indices.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))

	var mesh := ArrayMesh.new()
	_add_mesh_surface(mesh, surface_vertices, surface_uvs, surface_indices, surface_material)
	_add_mesh_surface(mesh, volume_vertices, volume_uvs, volume_indices, volume_material)
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
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


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
