extends Node2D

@export_range(-24.0, 24.0, 0.05, "or_greater", "or_less") var pointer_hour_offset := 0.0:
	set(value):
		pointer_hour_offset = value
		_apply_current_hour()
@export_range(1.0, 48.0, 0.05, "or_greater") var hours_per_rotation := 12.0:
	set(value):
		hours_per_rotation = value
		_apply_current_hour()
@export var clockwise := true:
	set(value):
		clockwise = value
		_apply_current_hour()
@export_range(-360.0, 360.0, 0.1, "or_greater", "or_less") var zero_hour_rotation_degrees := 0.0:
	set(value):
		zero_hour_rotation_degrees = value
		_apply_current_hour()

var _handle: Node2D
var _handle_zero_rotation := 0.0
var _current_hour := 0.0


func _ready() -> void:
	_handle = get_node_or_null("handle") as Node2D
	if _handle != null:
		_handle_zero_rotation = _handle.rotation
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
	_handle.rotation = _handle_zero_rotation + deg_to_rad(zero_hour_rotation_degrees) + hour_rotation
