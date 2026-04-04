class_name CompiledWorld
extends RefCounted

## Runtime state produced by recompile.
var board_size: Vector2i
var player_position: Vector2i
var exit_position: Vector2i
var floor_cells: Dictionary[Vector2i, bool] = {}
var wall_positions: Dictionary[Vector2i, bool] = {}
var entity_positions: Dictionary[StringName, Vector2i] = {}
var ghost_entities: Dictionary[StringName, Vector2i] = {}


func is_inside(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < board_size.x and pos.y < board_size.y


func has_floor_at(pos: Vector2i) -> bool:
	return floor_cells.has(pos)


func has_wall_at(pos: Vector2i) -> bool:
	return wall_positions.has(pos)


func has_box_at(pos: Vector2i) -> bool:
	for value: Vector2i in entity_positions.values():
		if value == pos:
			return true
	return false


func is_walkable_for_player(pos: Vector2i) -> bool:
	if not is_inside(pos):
		return false
	if not has_floor_at(pos):
		return false
	if has_wall_at(pos):
		return false
	if has_box_at(pos):
		return false
	return true


func is_blocked_for_box(pos: Vector2i) -> bool:
	if not is_inside(pos):
		return true
	if has_wall_at(pos):
		return true
	if has_box_at(pos):
		return true
	if pos == player_position:
		return true
	return false


func get_entity_position(entity_id: StringName) -> Vector2i:
	if entity_positions.has(entity_id):
		return entity_positions[entity_id]
	if ghost_entities.has(entity_id):
		return ghost_entities[entity_id]
	return Vector2i(-1, -1)


func is_solid_at(pos: Vector2i) -> bool:
	if has_wall_at(pos):
		return true
	if pos == player_position:
		return true
	return has_box_at(pos)
