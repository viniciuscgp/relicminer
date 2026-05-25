@tool
extends Node3D


## Configures marker label.
@export var marker_label: String = "":
	set(value):
		marker_label = value
		_update_label()

## Configures depth.
@export_range(0.1, 100.0, 0.1, "or_greater") var depth: float = 3.0:
	set(value):
		depth = value
		_update_label()

## Offset applied to surface.
@export var surface_offset: float = 0.0:
	set(value):
		surface_offset = value
		_update_label()


func _ready() -> void:
	_update_label()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_label()


func _update_label() -> void:
	var label_node := get_node_or_null("Label3D") as Label3D
	if not label_node:
		return

	var text: String = marker_label if not marker_label.is_empty() else name
	text += "\nfallback d %.1f" % depth
	if not is_zero_approx(surface_offset):
		text += "\noffset %.1f" % surface_offset
	text += "\nsurface y %.1f" % (global_position.y + surface_offset)
	if label_node.text != text:
		label_node.text = text
