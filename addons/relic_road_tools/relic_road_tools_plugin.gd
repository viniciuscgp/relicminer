@tool
extends EditorPlugin


var dock: Control


func _enter_tree() -> void:
	dock = preload("res://addons/relic_road_tools/road_baker_dock.gd").new()
	dock.editor_plugin = self
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


func get_scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()
