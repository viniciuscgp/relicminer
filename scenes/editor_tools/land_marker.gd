@tool
extends Node3D

## Configures label.
@export var label: String = "Label":
	set(value):
		label = value
		_update_label()


func _ready() -> void:
	_update_label()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_label()


func _update_label() -> void:
	var label_node := get_node_or_null("Label3D") as Label3D
	if label_node and label_node.text != label:
		label_node.text = label
