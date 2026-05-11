extends StaticBody3D
class_name StaticBlock

enum BlockKind {
	GROUND,
	BREAKABLE,
	WALL
}

@export var block_kind: BlockKind = BlockKind.GROUND
@export var block_name: String = "VillageBlock"

@export var max_health: int = 1
@export var can_drop_item: bool = false
@export var drop_item_id: String = ""

var health: int


func _ready() -> void:
	health = max_health


func hit(damage: int = 1) -> void:
	# Apenas blocos quebráveis recebem dano.
	if block_kind != BlockKind.BREAKABLE:
		return

	health -= damage

	if health <= 0:
		break_block()


func break_block() -> void:
	drop_item()
	queue_free()


func drop_item() -> void:
	if not can_drop_item:
		return

	if drop_item_id.is_empty():
		return

	# Por enquanto apenas mostra no console.
	# Depois aqui você instancia moeda, minério, gema etc.
	print("Drop item: ", drop_item_id, " at ", global_position)


func is_breakable() -> bool:
	return block_kind == BlockKind.BREAKABLE


func is_ground() -> bool:
	return block_kind == BlockKind.GROUND


func is_wall() -> bool:
	return block_kind == BlockKind.WALL
