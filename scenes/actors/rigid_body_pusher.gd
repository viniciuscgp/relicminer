extends Node
class_name RigidBodyPusher

## Speed value used for push.
@export var push_speed := 1.25


func push_collisions(actor: CharacterBody3D, move_direction: Vector3) -> void:
	if actor == null:
		return

	for index in range(actor.get_slide_collision_count()):
		var collision := actor.get_slide_collision(index)
		var body := collision.get_collider() as RigidBody3D
		if body == null or body.freeze:
			continue

		var push_direction := -collision.get_normal()
		push_direction.y = 0.0
		if push_direction.length_squared() < 0.001:
			push_direction = move_direction
		push_direction.y = 0.0
		if push_direction.length_squared() < 0.001:
			continue

		push_direction = push_direction.normalized()
		var mass_factor := clampf(1.0 / maxf(body.mass, 0.1), 0.15, 1.0)
		body.apply_central_impulse(push_direction * push_speed * mass_factor)
