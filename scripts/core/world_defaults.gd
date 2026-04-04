class_name WorldDefaults
extends RefCounted

## Default immutable world baseline loaded from scene runtime data.
var board_size: Vector2i
var player_start: Vector2i
var exit_position: Vector2i
var memory_capacity: int
var obsession_capacity: int
var floor_cells: Array[Vector2i] = []
var wall_positions: Array[Vector2i] = []
var default_entity_positions: Dictionary[StringName, Vector2i] = {}


static func from_runtime_data(level_data: LevelRuntimeData) -> WorldDefaults:
	var defaults := WorldDefaults.new()
	defaults.board_size = Vector2i(level_data.grid_size.x, level_data.grid_size.y)
	defaults.player_start = Vector2i(level_data.player_start.x, level_data.player_start.y)
	defaults.exit_position = Vector2i(level_data.exit_position.x, level_data.exit_position.y)
	defaults.memory_capacity = level_data.memory_capacity
	defaults.obsession_capacity = 0
	for floor_coord: Vector3i in level_data.floor_cells:
		defaults.floor_cells.append(Vector2i(floor_coord.x, floor_coord.y))
	for wall_coord: Vector3i in level_data.walls:
		defaults.wall_positions.append(Vector2i(wall_coord.x, wall_coord.y))
	for i: int in range(level_data.boxes.size()):
		var box_coord: Vector3i = level_data.boxes[i]
		defaults.default_entity_positions[StringName("box_%d" % i)] = Vector2i(box_coord.x, box_coord.y)
	return defaults
