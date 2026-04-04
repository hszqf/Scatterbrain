class_name CompiledWorld
extends RefCounted

## Runtime state produced by recompile.
var board_size: Vector2i
var player_position: Vector2i
var exit_position: Vector2i
var entity_positions: Dictionary[StringName, Vector2i] = {}
var ghost_entities: Dictionary[StringName, Vector2i] = {}


func is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < board_size.x and pos.y < board_size.y


func get_entity_position(entity_id: StringName) -> Vector2i:
	if entity_positions.has(entity_id):
		return entity_positions[entity_id]
	if ghost_entities.has(entity_id):
		return ghost_entities[entity_id]
	return Vector2i(-1, -1)


func is_solid_at(pos: Vector2i) -> bool:
	if pos == player_position:
		return true
	for value: Vector2i in entity_positions.values():
		if value == pos:
			return true
	return false
