extends Resource
class_name ItemAction

const TRIGGER_PRIMARY := &"primary"
const TRIGGER_SECONDARY := &"secondary"
const TRIGGER_THROW := &"throw"

## Configures trigger.
@export var trigger: StringName = TRIGGER_PRIMARY
## Name shown to players and editor tools.
@export var display_name := ""


func can_execute(_actor: Node, _equipment: Node, stack: Resource, _slot: StringName, _held_instance: Node3D) -> bool:
	return stack != null and not bool(stack.call("is_empty"))


func execute(_actor: Node, _equipment: Node, _stack: Resource, _slot: StringName, _held_instance: Node3D) -> bool:
	return false
