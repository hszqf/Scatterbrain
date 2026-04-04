class_name LevelRuntimeData
extends RefCounted

## Runtime-friendly data extracted from a scene-authored level.
var grid_size: Vector3i = Vector3i.ZERO
var memory_capacity: int = 4
var player_start: Vector3i = Vector3i.ZERO
var exit_position: Vector3i = Vector3i.ZERO
var floor_cells: Array[Vector3i] = []
var walls: Array[Vector3i] = []
var boxes: Array[Vector3i] = []
