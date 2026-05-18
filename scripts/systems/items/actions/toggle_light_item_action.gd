extends "res://scripts/systems/items/actions/item_action.gd"
class_name ToggleLightItemAction


func _init() -> void:
	trigger = TRIGGER_PRIMARY
	display_name = "Toggle Light"


func execute(_actor: Node, _equipment: Node, _stack: Resource, _slot: StringName, held_instance: Node3D) -> bool:
	if held_instance == null:
		return false

	if held_instance.has_method("toggle_light"):
		held_instance.call("toggle_light")
		return true

	var light := _find_light(held_instance)
	if light == null:
		return false
	light.visible = not light.visible
	return true


func _find_light(node: Node) -> Light3D:
	if node is Light3D:
		return node as Light3D
	for child in node.get_children():
		var light := _find_light(child)
		if light != null:
			return light
	return null
