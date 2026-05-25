extends Node

## NodePath used to locate the handle node.
@export var handle_path: NodePath = NodePath("clock/handle")

## Offset applied to pointer hour.
@export_range(-24.0, 24.0, 0.05, "or_greater", "or_less") var pointer_hour_offset := 0.0:
	set(value):
		pointer_hour_offset = value
		_apply_current_hour()
## Configures hours per rotation.
@export_range(1.0, 48.0, 0.05, "or_greater") var hours_per_rotation := 12.0:
	set(value):
		hours_per_rotation = value
		_apply_current_hour()
## Controls whether clockwise is enabled.
@export var clockwise := true:
	set(value):
		clockwise = value
		_apply_current_hour()
## Configures zero hour rotation degrees.
@export_range(-360.0, 360.0, 0.1, "or_greater", "or_less") var zero_hour_rotation_degrees := 0.0:
	set(value):
		zero_hour_rotation_degrees = value
		_apply_current_hour()

var _handle: CanvasItem
var _handle_zero_rotation := 0.0
var _current_hour := 0.0


func _ready() -> void:
	_handle = _find_handle()
	if _handle != null:
		_handle_zero_rotation = _get_handle_rotation()
	_apply_current_hour()


func set_current_hour(hour: float) -> void:
	_current_hour = hour
	_apply_current_hour()


func _apply_current_hour() -> void:
	if _handle == null:
		return

	var rotation_direction := 1.0 if clockwise else -1.0
	var rotation_hours := maxf(hours_per_rotation, 0.001)
	var hour_progress := fposmod(_current_hour + pointer_hour_offset, rotation_hours) / rotation_hours
	var hour_rotation := hour_progress * TAU * rotation_direction
	_set_handle_rotation(_handle_zero_rotation + deg_to_rad(zero_hour_rotation_degrees) + hour_rotation)


func _find_handle() -> CanvasItem:
	if not handle_path.is_empty():
		var configured_handle := get_node_or_null(handle_path) as CanvasItem
		if configured_handle != null:
			return configured_handle

	var legacy_handle := get_node_or_null("handle") as CanvasItem
	if legacy_handle != null:
		return legacy_handle

	return find_child("handle", true, false) as CanvasItem


func _get_handle_rotation() -> float:
	var control_handle := _handle as Control
	if control_handle != null:
		return control_handle.rotation

	var node_2d_handle := _handle as Node2D
	if node_2d_handle != null:
		return node_2d_handle.rotation

	return 0.0


func _set_handle_rotation(value: float) -> void:
	var control_handle := _handle as Control
	if control_handle != null:
		control_handle.rotation = value
		return

	var node_2d_handle := _handle as Node2D
	if node_2d_handle != null:
		node_2d_handle.rotation = value
