@tool
class_name LevelRoot
extends Node2D

const CELL_SCENE: PackedScene = preload("res://scenes/levels/LevelCell.tscn")

@export var grid_size: Vector3i = Vector3i(6, 3, 1):
	set(value):
		grid_size = Vector3i(max(value.x, 1), max(value.y, 1), max(value.z, 1))
		if Engine.is_editor_hint() and auto_rebuild_in_editor:
			rebuild_grid()

@export var memory_capacity: int = 4
@export var cell_size: int = 96:
	set(value):
		cell_size = max(value, 8)
		if Engine.is_editor_hint() and auto_rebuild_in_editor:
			rebuild_grid()

@export var auto_rebuild_in_editor: bool = true

@export var rebuild_grid_button: bool = false:
	set(value):
		if value:
			rebuild_grid()
		rebuild_grid_button = false

@export var validate_level_button: bool = false:
	set(value):
		if value:
			validate_level(true)
		validate_level_button = false

@export var fill_floor_button: bool = false:
	set(value):
		if value:
			fill_floor()
		fill_floor_button = false

@export var clear_contents_button: bool = false:
	set(value):
		if value:
			clear_contents()
		clear_contents_button = false

@onready var _grid: Node2D = $Grid


func _ready() -> void:
	if Engine.is_editor_hint():
		rebuild_grid()


func rebuild_grid() -> void:
	if not is_node_ready():
		return
	for z: int in range(grid_size.z):
		var slice: Node2D = _ensure_slice(z)
		_rebuild_slice_cells(slice, z)
	_remove_out_of_range_slices()


func validate_level(print_logs: bool = false) -> LevelValidationResult:
	var result := LevelValidationResult.new()
	var spawn_count: int = 0
	var exit_count: int = 0

	for cell: LevelCell in _all_cells():
		if cell.is_player_spawn:
			spawn_count += 1
		if cell.is_exit:
			exit_count += 1
		if not cell.has_floor:
			if cell.content_type != LevelCell.CellContentType.EMPTY:
				result.add_error("Cell %s has content but no floor." % str(cell.coord))
			if cell.is_player_spawn:
				result.add_error("Cell %s has player spawn but no floor." % str(cell.coord))
			if cell.is_exit:
				result.add_error("Cell %s has exit but no floor." % str(cell.coord))

	if spawn_count != 1:
		result.add_error("Expected exactly 1 player spawn, found %d." % spawn_count)
	if exit_count != 1:
		result.add_error("Expected exactly 1 exit, found %d." % exit_count)

	if print_logs:
		if result.is_valid:
			print("[LevelRoot] Validate pass")
		else:
			for message: String in result.errors:
				push_error("[LevelRoot] %s" % message)
	return result


func fill_floor() -> void:
	for cell: LevelCell in _all_cells():
		cell.has_floor = true


func clear_contents() -> void:
	for cell: LevelCell in _all_cells():
		cell.content_type = LevelCell.CellContentType.EMPTY
		cell.is_player_spawn = false
		cell.is_exit = false


func build_runtime_data() -> LevelRuntimeData:
	var result := validate_level()
	if not result.is_valid:
		push_warning("Building runtime data from invalid level. Check validation logs.")

	var data := LevelRuntimeData.new()
	data.grid_size = grid_size
	data.memory_capacity = memory_capacity

	for cell: LevelCell in _all_cells():
		if cell.has_floor:
			data.floor_cells.append(cell.coord)
		else:
			continue

		if cell.is_player_spawn:
			data.player_start = cell.coord
		if cell.is_exit:
			data.exit_position = cell.coord
		match cell.content_type:
			LevelCell.CellContentType.WALL:
				data.walls.append(cell.coord)
			LevelCell.CellContentType.BOX:
				data.boxes.append(cell.coord)
			_:
				pass
	return data


func _ensure_slice(z: int) -> Node2D:
	var slice_name: String = "Slice_%d" % z
	if _grid.has_node(slice_name):
		return _grid.get_node(slice_name)
	var node := Node2D.new()
	node.name = slice_name
	_grid.add_child(node)
	node.owner = owner
	return node


func _rebuild_slice_cells(slice: Node2D, z: int) -> void:
	for y: int in range(grid_size.y):
		for x: int in range(grid_size.x):
			var coord := Vector3i(x, y, z)
			var cell_name: String = _cell_name(coord)
			if slice.has_node(cell_name):
				var existing: LevelCell = slice.get_node(cell_name)
				existing.coord = coord
				existing.cell_size = cell_size
				continue
			var instance: LevelCell = CELL_SCENE.instantiate()
			instance.name = cell_name
			instance.coord = coord
			instance.cell_size = cell_size
			instance.has_floor = true
			slice.add_child(instance)
			instance.owner = owner
	_remove_out_of_range_cells(slice, z)


func _remove_out_of_range_slices() -> void:
	for child: Node in _grid.get_children():
		if not child.name.begins_with("Slice_"):
			continue
		var z_text: String = child.name.trim_prefix("Slice_")
		if not z_text.is_valid_int():
			continue
		var z: int = z_text.to_int()
		if z < 0 or z >= grid_size.z:
			child.queue_free()


func _remove_out_of_range_cells(slice: Node2D, z: int) -> void:
	for child: Node in slice.get_children():
		if child is not LevelCell:
			continue
		var cell: LevelCell = child
		var c: Vector3i = cell.coord
		if c.x < 0 or c.y < 0 or c.z != z or c.x >= grid_size.x or c.y >= grid_size.y:
			cell.queue_free()


func _all_cells() -> Array[LevelCell]:
	var cells: Array[LevelCell] = []
	for slice_node: Node in _grid.get_children():
		for cell_node: Node in slice_node.get_children():
			if cell_node is LevelCell:
				cells.append(cell_node)
	return cells


func _cell_name(coord: Vector3i) -> String:
	return "Cell_%d_%d_%d" % [coord.x, coord.y, coord.z]
