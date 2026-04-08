class_name PlacementRules
extends RefCounted


static func can_land_solid(state: SimulationState, subject_id: StringName, position: Vector2i) -> bool:
	if state.defaults == null:
		return false
	if not _is_inside(state.defaults.board_size, position):
		return false
	if not _has_floor(state.defaults.floor_cells, position):
		return false
	if _has_wall(state.defaults.wall_positions, position):
		return false
	if position == state.player_position:
		return false
	for other_id: StringName in state.position_by_subject.keys():
		if other_id == subject_id:
			continue
		if not state.subject_exists(other_id):
			continue
		if bool(state.is_ghost_by_subject.get(other_id, false)):
			continue
		if state.position_by_subject[other_id] == position:
			return false
	return true


static func _is_inside(board_size: Vector2i, position: Vector2i) -> bool:
	return position.x >= 0 and position.y >= 0 and position.x < board_size.x and position.y < board_size.y


static func _has_floor(floor_cells: Array[Vector2i], position: Vector2i) -> bool:
	return floor_cells.has(position)


static func _has_wall(wall_positions: Array[Vector2i], position: Vector2i) -> bool:
	return wall_positions.has(position)
