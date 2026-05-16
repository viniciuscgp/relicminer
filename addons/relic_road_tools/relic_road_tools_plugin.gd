@tool
extends EditorPlugin


var road_dock: Control
var water_dock: Control


func _enter_tree() -> void:
	road_dock = preload("res://addons/relic_road_tools/road_baker_dock.gd").new()
	road_dock.editor_plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, road_dock)

	water_dock = preload("res://addons/relic_road_tools/water_baker_dock.gd").new()
	water_dock.editor_plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, water_dock)


func _exit_tree() -> void:
	if water_dock:
		remove_control_from_docks(water_dock)
		water_dock.queue_free()
		water_dock = null

	if road_dock:
		remove_control_from_docks(road_dock)
		road_dock.queue_free()
		road_dock = null


func get_scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()
