class_name LevelDefinition
extends Resource

## Serialized configuration for one level.
@export var level_id: String = "level_001"
@export var board_size: Vector2i = Vector2i(6, 3)
@export var player_start: Vector2i = Vector2i(1, 1)
@export var box_start_positions: Array[Vector2i] = [Vector2i(3, 1)]
@export var exit_position: Vector2i = Vector2i(5, 1)
@export var memory_capacity: int = 4
@export var obsession_capacity: int = 0
