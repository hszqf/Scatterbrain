class_name WorldDefaults
extends RefCounted

## Default immutable world baseline loaded from level data.
var board_size: Vector2i
var player_start: Vector2i
var exit_position: Vector2i
var memory_capacity: int
var obsession_capacity: int
var default_entity_positions: Dictionary[StringName, Vector2i] = {}


static func from_level(level: LevelDefinition) -> WorldDefaults:
	var defaults := WorldDefaults.new()
	defaults.board_size = level.board_size
	defaults.player_start = level.player_start
	defaults.exit_position = level.exit_position
	defaults.memory_capacity = level.memory_capacity
	defaults.obsession_capacity = level.obsession_capacity
	for i: int in range(level.box_start_positions.size()):
		defaults.default_entity_positions[StringName("box_%d" % i)] = level.box_start_positions[i]
	return defaults
