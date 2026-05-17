extends RefCounted
class_name ItemIconRenderer

const ICON_SIZE := 128
const CAMERA_FOV := 35.0
const CAMERA_DIR := Vector3(1.0, 0.85, 1.0)
const CAMERA_FILL := 1.18
const LIGHT_ROTATION_DEGREES := Vector3(-45.0, -30.0, 0.0)
const LIGHT_ENERGY := 1.35
const AMBIENT_COLOR := Color(0.68, 0.66, 0.58)
const AMBIENT_ENERGY := 0.65

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func has_cached_icon(item: Resource) -> bool:
	var item_id := _get_item_id(item)
	return not item_id.is_empty() and _cache.has(item_id)


static func get_cached_icon(item: Resource) -> Texture2D:
	var item_id := _get_item_id(item)
	if item_id.is_empty():
		return null

	return _cache.get(item_id, null) as Texture2D


static func get_icon_or_fallback(item: Resource) -> Texture2D:
	var cached := get_cached_icon(item)
	if cached != null:
		return cached

	if item != null:
		return item.get("icon") as Texture2D
	return null


static func bake_icon_async(item: Resource) -> Texture2D:
	var item_id := _get_item_id(item)
	if item_id.is_empty():
		return null

	if _cache.has(item_id):
		return _cache[item_id] as Texture2D

	var world_scene := item.get("world_scene") as PackedScene
	if world_scene == null:
		var fallback := item.get("icon") as Texture2D
		_cache[item_id] = fallback
		return fallback

	var texture := await _render_scene_to_texture(world_scene, item)
	if texture == null:
		texture = item.get("icon") as Texture2D

	_cache[item_id] = texture
	return texture


static func _get_item_id(item: Resource) -> String:
	if item == null:
		return ""

	var item_id: Variant = item.get("id")
	if item_id == null:
		return ""
	return str(item_id)


static func _render_scene_to_texture(scene: PackedScene, item: Resource) -> Texture2D:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null

	var viewport := SubViewport.new()
	viewport.size = Vector2i(ICON_SIZE, ICON_SIZE)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.world_3d = World3D.new()
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tree.root.add_child(viewport)

	_add_lighting(viewport)

	var camera := Camera3D.new()
	camera.fov = CAMERA_FOV
	camera.current = true
	viewport.add_child(camera)

	var instance := scene.instantiate()
	if instance.has_method("setup"):
		instance.call("setup", item, 1)
	viewport.add_child(instance)
	_freeze_instance(instance)

	await RenderingServer.frame_post_draw

	var aabb := _compute_world_aabb(instance)
	_frame_camera(camera, aabb)

	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

	var image := viewport.get_texture().get_image()
	var texture: Texture2D = null
	if image != null:
		texture = ImageTexture.create_from_image(image)

	viewport.queue_free()
	return texture


static func _add_lighting(parent: Node) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = LIGHT_ROTATION_DEGREES
	light.light_energy = LIGHT_ENERGY
	parent.add_child(light)

	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	environment_node.environment = environment
	parent.add_child(environment_node)


static func _freeze_instance(root: Node) -> void:
	for node in _walk(root):
		node.set_process(false)
		node.set_physics_process(false)

		if node is CollisionShape3D:
			(node as CollisionShape3D).disabled = true
		elif node is RigidBody3D:
			(node as RigidBody3D).freeze = true


static func _frame_camera(camera: Camera3D, aabb: AABB) -> void:
	var center := aabb.get_center()
	var radius := aabb.size.length() * 0.5

	if radius < 0.01:
		center = Vector3.ZERO
		radius = 0.5

	var direction := CAMERA_DIR.normalized()
	var distance := radius / sin(deg_to_rad(camera.fov * 0.5)) * CAMERA_FILL
	camera.global_position = center + direction * distance
	camera.look_at(center, Vector3.UP)


static func _compute_world_aabb(root: Node) -> AABB:
	var combined := AABB()
	var first := true

	for node in _walk(root):
		if not node is VisualInstance3D:
			continue

		var visual := node as VisualInstance3D
		var local := visual.get_aabb()
		if local.size == Vector3.ZERO:
			continue

		var world: AABB = visual.global_transform * local
		if first:
			combined = world
			first = false
		else:
			combined = combined.merge(world)

	return combined


static func _walk(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_walk(child))
	return result
