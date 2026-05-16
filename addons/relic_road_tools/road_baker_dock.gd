@tool
extends VBoxContainer


const STREET_MAKER_SCENE := "res://scenes/components/street_maker.tscn"
const TERRAIN_HEIGHT := 0
const TERRAIN_CONTROL := 1
const NO_TEXTURE_ID := -1
const LAST_BAKE_BACKUP_FILE := "user://relic_road_tools_last_bake.dat"


var editor_plugin: EditorPlugin

var width_spin: SpinBox
var depth_spin: SpinBox
var falloff_spin: SpinBox
var sample_step_spin: SpinBox
var write_step_spin: SpinBox
var texture_cutoff_spin: SpinBox
var texture_option: OptionButton
var refresh_textures_button: Button
var save_check: CheckBox
var status_label: Label
var bake_button: Button
var save_button: Button
var remove_button: Button


func _init() -> void:
	name = "Road Baker"
	custom_minimum_size = Vector2(260, 0)

	var title := Label.new()
	title.text = "Road Baker"
	title.tooltip_text = "Bakes road relief and optional Terrain3D texture paint from StreetMaker nodes."
	title.add_theme_font_size_override("font_size", 16)
	add_child(title)

	width_spin = _add_spin("Width", 2.0, 80.0, 0.5, 18.0, "m", "Total road width in meters before the side falloff starts.")
	depth_spin = _add_spin("Depth", 0.0, 5.0, 0.05, 0.25, "m", "How much the road center is lowered into the terrain. Use small values while testing.")
	falloff_spin = _add_spin("Falloff", 0.0, 40.0, 0.5, 8.0, "m", "Soft shoulder width outside the road. Higher values blend the relief and texture more gradually.")
	sample_step_spin = _add_spin("Curve Step", 0.5, 20.0, 0.5, 4.0, "m", "Distance between curve samples. Lower values follow tight curves better but bake slower.")
	write_step_spin = _add_spin("Write Step", 0.5, 8.0, 0.5, 1.0, "m", "Terrain write spacing. Lower values are denser; the plugin clamps this to Terrain3D vertex spacing when needed.")
	texture_cutoff_spin = _add_spin("Texture Cutoff", 0.0, 0.95, 0.05, 0.25, "", "Minimum falloff strength required to paint texture. Higher values trim noisy side spikes while keeping terrain relief smooth.")

	_add_texture_picker()

	save_check = CheckBox.new()
	save_check.text = "Save terrain_data immediately"
	save_check.button_pressed = false
	save_check.tooltip_text = "When enabled, writes Terrain3D .res files right after baking. Keep off while testing so Ctrl+Z can undo."
	add_child(save_check)

	bake_button = Button.new()
	bake_button.text = "Bake Road Relief"
	bake_button.tooltip_text = "Applies the road relief and optional texture paint as one Undo/Redo action."
	bake_button.pressed.connect(_on_bake_pressed)
	add_child(bake_button)

	remove_button = Button.new()
	remove_button.text = "Remove Last Bake"
	remove_button.tooltip_text = "Restores the terrain height and texture values saved before the last bake, even after terrain_data was saved."
	remove_button.pressed.connect(_on_remove_last_bake_pressed)
	add_child(remove_button)

	save_button = Button.new()
	save_button.text = "Save Terrain Data Now"
	save_button.tooltip_text = "Saves the current Terrain3D data directory after you approve the result."
	save_button.pressed.connect(_on_save_pressed)
	add_child(save_button)

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.text = "Only visible StreetMaker nodes are used. Each bake stores one removable backup."
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


func _add_texture_picker() -> void:
	var hint := "Terrain3D texture to paint on the road. Uses overlay/blend paint and disables autoshader on painted cells."
	var row := HBoxContainer.new()
	row.tooltip_text = hint
	add_child(row)

	var label := Label.new()
	label.text = "Texture"
	label.custom_minimum_size.x = 92
	label.tooltip_text = hint
	row.add_child(label)

	texture_option = OptionButton.new()
	texture_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texture_option.tooltip_text = hint
	row.add_child(texture_option)

	refresh_textures_button = Button.new()
	refresh_textures_button.text = "Refresh"
	refresh_textures_button.tooltip_text = "Reloads the texture list from the Terrain3D node in the open scene."
	refresh_textures_button.pressed.connect(_refresh_texture_options)
	row.add_child(refresh_textures_button)

	_refresh_texture_options()


func _on_bake_pressed() -> void:
	var root: Node = editor_plugin.get_scene_root()
	if not root:
		_set_status("No edited scene is open.", true)
		return

	var terrain: Node = _find_first_by_class(root, "Terrain3D")
	if not terrain:
		_set_status("No Terrain3D node found in the open scene.", true)
		return
	if not terrain.data:
		_set_status("Terrain3D has no data resource.", true)
		return
	_refresh_texture_options(terrain)
	var texture_id := _get_selected_texture_id()
	if texture_id == NO_TEXTURE_ID:
		_set_status("Select a Terrain3D texture before baking.", true)
		return

	var routes: Array[Array] = _collect_routes(root)
	if routes.is_empty():
		_set_status("No route with at least 2 StreetMaker nodes found.", true)
		return

	var result: Dictionary = _bake_routes(
		terrain,
		routes,
		float(width_spin.value),
		float(depth_spin.value),
		float(falloff_spin.value),
		float(sample_step_spin.value),
		float(write_step_spin.value),
		texture_id,
		float(texture_cutoff_spin.value)
	)

	if result.height_changes.is_empty() and result.control_changes.is_empty():
		_set_status("No terrain changes were needed.", true)
		return

	if not _write_last_bake_backup(root, result.height_changes, result.control_changes):
		return

	_commit_bake(terrain, result.height_changes, result.control_changes)

	if save_check.button_pressed:
		if not _save_terrain_data(terrain):
			return

	EditorInterface.mark_scene_as_unsaved()
	var save_text := "saved immediately" if save_check.button_pressed else "not saved; Ctrl+Z can undo"
	_set_status(
		"Baked %d route(s), %d samples, %d height writes, %d texture writes (%s). Remove Last Bake can revert it."
		% [routes.size(), result.samples, result.height_writes, result.texture_writes, save_text],
		false
	)


func _on_save_pressed() -> void:
	var root: Node = editor_plugin.get_scene_root()
	if not root:
		_set_status("No edited scene is open.", true)
		return

	var terrain: Node = _find_first_by_class(root, "Terrain3D")
	if not terrain or not terrain.data:
		_set_status("No Terrain3D data found in the open scene.", true)
		return

	if _save_terrain_data(terrain):
		_set_status("Terrain data saved.", false)


func _on_remove_last_bake_pressed() -> void:
	var root: Node = editor_plugin.get_scene_root()
	if not root:
		_set_status("No edited scene is open.", true)
		return

	var terrain: Node = _find_first_by_class(root, "Terrain3D")
	if not terrain or not terrain.data:
		_set_status("No Terrain3D data found in the open scene.", true)
		return

	var backup := _read_last_bake_backup()
	if backup.is_empty():
		return

	var backup_scene_path := String(backup.get("scene_path", ""))
	if not backup_scene_path.is_empty() and not root.scene_file_path.is_empty() and backup_scene_path != root.scene_file_path:
		_set_status("Last bake backup belongs to another scene: %s" % backup_scene_path, true)
		return

	var height_changes: Array = backup.get("height_changes", [])
	var control_changes: Array = backup.get("control_changes", [])
	if height_changes.is_empty() and control_changes.is_empty():
		_set_status("Last bake backup has no changes to remove.", true)
		return

	_commit_remove_last_bake(terrain, height_changes, control_changes)

	if save_check.button_pressed:
		if not _save_terrain_data(terrain):
			return

	EditorInterface.mark_scene_as_unsaved()
	var save_text := "saved immediately" if save_check.button_pressed else "not saved; Ctrl+Z can reapply"
	_set_status(
		"Removed last bake, restored %d height values and %d texture values (%s)."
		% [height_changes.size(), control_changes.size(), save_text],
		false
	)


func _set_status(message: String, is_error: bool) -> void:
	status_label.text = message
	if is_error:
		push_error(message)
	else:
		print("RoadBaker: ", message)


func _save_terrain_data(terrain: Node) -> bool:
	var directory: String = terrain.data_directory
	if directory.is_empty():
		_set_status("Terrain3D data_directory is empty. Save manually.", true)
		return false
	terrain.data.save_directory(directory)
	return true


func _write_last_bake_backup(root: Node, height_changes: Array, control_changes: Array) -> bool:
	var backup := {
		"version": 1,
		"scene_path": root.scene_file_path,
		"height_changes": height_changes,
		"control_changes": control_changes,
		"created_unix_time": Time.get_unix_time_from_system(),
	}

	var file := FileAccess.open(LAST_BAKE_BACKUP_FILE, FileAccess.WRITE)
	if not file:
		_set_status("Could not write last bake backup: %s" % error_string(FileAccess.get_open_error()), true)
		return false

	file.store_var(backup, true)
	return true


func _read_last_bake_backup() -> Dictionary:
	if not FileAccess.file_exists(LAST_BAKE_BACKUP_FILE):
		_set_status("No last bake backup found.", true)
		return {}

	var file := FileAccess.open(LAST_BAKE_BACKUP_FILE, FileAccess.READ)
	if not file:
		_set_status("Could not read last bake backup: %s" % error_string(FileAccess.get_open_error()), true)
		return {}

	var value: Variant = file.get_var(true)
	if not value is Dictionary:
		_set_status("Last bake backup is invalid.", true)
		return {}

	return value


func _refresh_texture_options(terrain: Node = null) -> void:
	if not texture_option:
		return

	var selected_id := _get_selected_texture_id()
	texture_option.clear()

	if not terrain:
		var root: Node = editor_plugin.get_scene_root() if editor_plugin else null
		terrain = _find_first_by_class(root, "Terrain3D") if root else null

	if terrain and terrain.assets:
		var texture_count: int = terrain.assets.get_texture_count()
		for index in texture_count:
			var texture: Terrain3DTextureAsset = terrain.assets.get_texture(index)
			if not texture:
				continue
			var texture_id := int(texture.id)
			var texture_name := texture.name
			if texture_name.is_empty():
				texture_name = texture.get_name()
			if texture_name.is_empty():
				texture_name = "Texture %d" % texture_id
			texture_option.add_item("%d - %s" % [texture_id, texture_name], texture_id)

	if texture_option.item_count == 0:
		texture_option.add_item("No Terrain3D textures found", NO_TEXTURE_ID)

	_select_texture_id(selected_id)


func _get_selected_texture_id() -> int:
	if not texture_option or texture_option.selected < 0:
		return NO_TEXTURE_ID
	return texture_option.get_item_id(texture_option.selected)


func _select_texture_id(texture_id: int) -> void:
	for index in texture_option.item_count:
		if texture_option.get_item_id(index) == texture_id:
			texture_option.select(index)
			return
	texture_option.select(0)


func _find_first_by_class(node: Node, cls_name: String) -> Node:
	if node.is_class(cls_name):
		return node
	for child in node.get_children():
		var found := _find_first_by_class(child, cls_name)
		if found:
			return found
	return null


func _collect_routes(root: Node) -> Array[Array]:
	var routes: Array[Array] = []
	_collect_routes_recursive(root, routes)
	return routes


func _collect_routes_recursive(node: Node, routes: Array[Array]) -> void:
	if node != editor_plugin.get_scene_root() and not _is_marker_visible(node):
		return
	if _is_street_maker(node):
		return

	var direct_route := _collect_street_makers_under(node, false)
	if direct_route.size() >= 2:
		routes.append(direct_route)

	for child in node.get_children():
		_collect_routes_recursive(child, routes)


func _collect_street_makers_under(node: Node, recursive: bool) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for child in node.get_children():
		if _is_street_maker(child):
			if _is_marker_visible(child):
				points.append(child.global_position)
		elif recursive:
			points.append_array(_collect_street_makers_under(child, true))
	return points


func _is_street_maker(node: Node) -> bool:
	if node.name.begins_with("StreetMaker"):
		return true
	if node.scene_file_path == STREET_MAKER_SCENE:
		return true
	return false


func _is_marker_visible(node: Node) -> bool:
	if node.has_method("is_visible_in_tree"):
		return node.call("is_visible_in_tree")
	return _has_bool_property_enabled(node, "visible")


func _has_bool_property_enabled(node: Node, property_name: String) -> bool:
	for property in node.get_property_list():
		if String(property.name) == property_name:
			return bool(node.get(property_name))
	return true


func _bake_routes(terrain: Node, routes: Array[Array], width: float, depth: float, falloff: float, sample_step: float, write_step: float, texture_id: int, texture_cutoff: float) -> Dictionary:
	var inner_radius := width * 0.5
	var influence_radius := inner_radius + falloff
	var grid_step: float = _get_grid_step(terrain, write_step)
	var height_changes_by_key: Dictionary = {}
	var control_changes_by_key: Dictionary = {}
	var samples := 0

	for route in routes:
		var curve_points: Array[Vector3] = _sample_catmull_rom(route, sample_step)
		var route_result := _bake_route_grid(terrain, curve_points, inner_radius, influence_radius, depth, falloff, grid_step, texture_id, texture_cutoff)
		samples += int(route_result.samples)
		for change in route_result.height_changes:
			var key: Vector2i = change["key"]
			if not height_changes_by_key.has(key) or float(change["new_height"]) < float(height_changes_by_key[key]["new_height"]):
				height_changes_by_key[key] = change
		for change in route_result.control_changes:
			var key: Vector2i = change["key"]
			if not control_changes_by_key.has(key) or float(change["weight"]) > float(control_changes_by_key[key]["weight"]):
				control_changes_by_key[key] = change

	var height_changes := height_changes_by_key.values()
	var control_changes := control_changes_by_key.values()

	return {
		"samples": samples,
		"height_writes": height_changes.size(),
		"texture_writes": control_changes.size(),
		"height_changes": height_changes,
		"control_changes": control_changes,
	}


func _bake_route_grid(terrain: Node, points: Array[Vector3], inner_radius: float, influence_radius: float, depth: float, falloff: float, grid_step: float, texture_id: int, texture_cutoff: float) -> Dictionary:
	if points.size() < 2:
		return {
			"samples": 0,
			"height_writes": 0,
			"texture_writes": 0,
			"height_changes": [],
			"control_changes": [],
		}

	var cells: Dictionary = {}
	var origin: Vector3 = terrain.global_position
	var samples := 0

	for index in range(points.size() - 1):
		var a: Vector3 = points[index]
		var b: Vector3 = points[index + 1]
		if _flat_distance(a, b) <= 0.001:
			continue

		var min_x := _snap_down(minf(a.x, b.x) - influence_radius, origin.x, grid_step)
		var max_x := _snap_up(maxf(a.x, b.x) + influence_radius, origin.x, grid_step)
		var min_z := _snap_down(minf(a.z, b.z) - influence_radius, origin.z, grid_step)
		var max_z := _snap_up(maxf(a.z, b.z) + influence_radius, origin.z, grid_step)

		var x := min_x
		while x <= max_x:
			var z := min_z
			while z <= max_z:
				var sample_pos := Vector3(x, 0.0, z)
				if terrain.data.has_regionp(sample_pos):
					var closest := _closest_point_on_segment_xz(sample_pos, a, b)
					var distance := _flat_distance(sample_pos, closest)
					if distance <= influence_radius:
						var key := Vector2i(roundi((x - origin.x) / grid_step), roundi((z - origin.z) / grid_step))
						if not cells.has(key) or distance < float(cells[key]["distance"]):
							cells[key] = {
								"key": key,
								"position": sample_pos,
								"distance": distance,
								"center_height": terrain.data.get_height(closest),
							}
				z += grid_step
			x += grid_step
		samples += 1

	var height_writes := 0
	var texture_writes := 0
	var height_changes: Array = []
	var control_changes: Array = []
	for cell in cells.values():
		var distance: float = cell["distance"]
		var weight := _road_weight(distance, inner_radius, falloff)
		if weight <= 0.0:
			continue

		var sample_pos: Vector3 = cell["position"]
		var current_height: float = terrain.data.get_height(sample_pos)
		var target_height: float = float(cell["center_height"]) - depth
		var blended_height := lerpf(current_height, target_height, weight)
		var new_height := minf(current_height, blended_height)
		if not is_equal_approx(current_height, new_height):
			height_changes.append({
				"key": cell["key"],
				"position": sample_pos,
				"old_height": current_height,
				"new_height": new_height,
			})
			height_writes += 1

		if texture_id != NO_TEXTURE_ID:
			var texture_weight := _texture_weight(weight, texture_cutoff)
			if texture_weight <= 0.0:
				continue
			var old_base_id: int = terrain.data.get_control_base_id(sample_pos)
			var old_overlay_id: int = terrain.data.get_control_overlay_id(sample_pos)
			var old_blend: float = terrain.data.get_control_blend(sample_pos)
			var old_auto: bool = terrain.data.get_control_auto(sample_pos)
			var new_blend := maxf(old_blend if old_overlay_id == texture_id and not old_auto else 0.0, texture_weight)
			var changed := old_overlay_id != texture_id or not is_equal_approx(old_blend, new_blend) or old_auto
			if changed:
				control_changes.append({
					"key": cell["key"],
					"position": sample_pos,
					"weight": texture_weight,
					"old_base_id": old_base_id,
					"old_overlay_id": old_overlay_id,
					"old_blend": old_blend,
					"old_auto": old_auto,
					"new_overlay_id": texture_id,
					"new_blend": new_blend,
					"new_auto": false,
				})
				texture_writes += 1

	return {
		"samples": samples,
		"height_writes": height_writes,
		"texture_writes": texture_writes,
		"height_changes": height_changes,
		"control_changes": control_changes,
	}


func _commit_bake(terrain: Node, height_changes: Array, control_changes: Array) -> void:
	var undo_redo: EditorUndoRedoManager = editor_plugin.get_undo_redo()
	var stored_height_changes := height_changes.duplicate(true)
	var stored_control_changes := control_changes.duplicate(true)
	undo_redo.create_action("Bake Road Relief")
	undo_redo.add_do_method(self, &"_apply_bake_changes", terrain, stored_height_changes, stored_control_changes, true)
	undo_redo.add_undo_method(self, &"_apply_bake_changes", terrain, stored_height_changes, stored_control_changes, false)
	undo_redo.commit_action()


func _commit_remove_last_bake(terrain: Node, height_changes: Array, control_changes: Array) -> void:
	var undo_redo: EditorUndoRedoManager = editor_plugin.get_undo_redo()
	var stored_height_changes := height_changes.duplicate(true)
	var stored_control_changes := control_changes.duplicate(true)
	undo_redo.create_action("Remove Last Road Bake")
	undo_redo.add_do_method(self, &"_apply_bake_changes", terrain, stored_height_changes, stored_control_changes, false)
	undo_redo.add_undo_method(self, &"_apply_bake_changes", terrain, stored_height_changes, stored_control_changes, true)
	undo_redo.commit_action()


func _apply_bake_changes(terrain: Node, height_changes: Array, control_changes: Array, use_new_values: bool) -> void:
	if not is_instance_valid(terrain) or not terrain.data:
		return

	for change in height_changes:
		var height := float(change["new_height"]) if use_new_values else float(change["old_height"])
		terrain.data.set_height(change["position"], height)

	for change in control_changes:
		var position: Vector3 = change["position"]
		if use_new_values:
			terrain.data.set_control_auto(position, bool(change["new_auto"]))
			terrain.data.set_control_overlay_id(position, int(change["new_overlay_id"]))
			terrain.data.set_control_blend(position, float(change["new_blend"]))
		else:
			terrain.data.set_control_auto(position, bool(change["old_auto"]))
			terrain.data.set_control_base_id(position, int(change["old_base_id"]))
			terrain.data.set_control_overlay_id(position, int(change["old_overlay_id"]))
			terrain.data.set_control_blend(position, float(change["old_blend"]))

	terrain.data.calc_height_range(true)
	terrain.data.update_maps(TERRAIN_HEIGHT, true, true)
	if not control_changes.is_empty():
		terrain.data.update_maps(TERRAIN_CONTROL, true, true)


func _get_grid_step(terrain: Node, requested_step: float) -> float:
	var terrain_step := 1.0
	if terrain.has_method("get_vertex_spacing"):
		terrain_step = maxf(float(terrain.get_vertex_spacing()), 0.25)
	return maxf(0.25, minf(requested_step, terrain_step))


func _snap_down(value: float, origin: float, spacing: float) -> float:
	return origin + floorf((value - origin) / spacing) * spacing


func _snap_up(value: float, origin: float, spacing: float) -> float:
	return origin + ceilf((value - origin) / spacing) * spacing


func _closest_point_on_segment_xz(point: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ab := Vector2(b.x - a.x, b.z - a.z)
	var ap := Vector2(point.x - a.x, point.z - a.z)
	var length_squared := ab.length_squared()
	if length_squared <= 0.000001:
		return Vector3(a.x, 0.0, a.z)

	var t := clampf(ap.dot(ab) / length_squared, 0.0, 1.0)
	return Vector3(lerpf(a.x, b.x, t), 0.0, lerpf(a.z, b.z, t))


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _road_weight(distance: float, inner_radius: float, falloff: float) -> float:
	if distance <= inner_radius:
		return 1.0
	if falloff <= 0.0:
		return 0.0
	var t := clampf((distance - inner_radius) / falloff, 0.0, 1.0)
	return 1.0 - (t * t * (3.0 - 2.0 * t))


func _texture_weight(weight: float, cutoff: float) -> float:
	cutoff = clampf(cutoff, 0.0, 0.95)
	if weight <= cutoff:
		return 0.0
	var remapped := (weight - cutoff) / (1.0 - cutoff)
	return remapped * remapped * (3.0 - 2.0 * remapped)


func _get_tangent(points: Array[Vector3], index: int) -> Vector3:
	if points.size() < 2:
		return Vector3.FORWARD
	if index == 0:
		return _flat_direction(points[1] - points[0])
	if index == points.size() - 1:
		return _flat_direction(points[index] - points[index - 1])
	return _flat_direction(points[index + 1] - points[index - 1])


func _flat_direction(vector: Vector3) -> Vector3:
	vector.y = 0.0
	if vector.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return vector.normalized()


func _sample_catmull_rom(points: Array[Vector3], sample_step: float) -> Array[Vector3]:
	if points.size() < 2:
		return points.duplicate()

	var sampled: Array[Vector3] = []
	for segment in range(points.size() - 1):
		var p0: Vector3 = points[maxi(segment - 1, 0)]
		var p1: Vector3 = points[segment]
		var p2: Vector3 = points[segment + 1]
		var p3: Vector3 = points[mini(segment + 2, points.size() - 1)]
		var distance := p1.distance_to(p2)
		var steps := maxi(2, ceili(distance / maxf(sample_step, 0.25)))

		for step in range(steps):
			var t := float(step) / float(steps)
			var point := _catmull_rom_point(p0, p1, p2, p3, t)
			if sampled.is_empty() or sampled[-1].distance_to(point) > 0.001:
				sampled.append(point)

	sampled.append(points[-1])
	return sampled


func _catmull_rom_point(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2 := t * t
	var t3 := t2 * t
	return (
		p1 * 2.0
		+ (p2 - p0) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (p3 - p0 + (p1 - p2) * 3.0) * t3
	) * 0.5
