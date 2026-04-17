@tool
class_name LevelRoot
extends Node2D

const CELL_SCENE: PackedScene = preload("res://scenes/level_editor/LevelCellTemplate.tscn")

@export var grid_size: Vector3i = Vector3i(6, 3, 1):
	set(value):
		grid_size = Vector3i(max(value.x, 1), max(value.y, 1), max(value.z, 1))
		if level_layout != null:
			level_layout.grid_size = grid_size
		if Engine.is_editor_hint() and auto_rebuild_in_editor:
			rebuild_grid()

@export var memory_capacity: int = 4
@export var cell_size: int = 96:
	set(value):
		cell_size = max(value, 8)
		if level_layout != null:
			level_layout.cell_size = cell_size
		if Engine.is_editor_hint() and auto_rebuild_in_editor:
			rebuild_grid()

@export var level_layout: LevelLayoutData
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
		ensure_editor_grid_from_layout_or_legacy()


func ensure_editor_grid_from_layout_or_legacy() -> bool:
	if _ensure_layout_data("editor_open"):
		return _rebuild_grid_from_layout()
	push_error("[LevelRoot] Missing level layout and legacy cell nodes. Refuse to auto-build fake grid.")
	return false


func rebuild_grid() -> void:
	sync_layout_from_grid()
	if not _ensure_layout_data("rebuild"):
		push_error("[LevelRoot] rebuild_grid aborted: missing layout data.")
		return
	_rebuild_grid_from_layout()


func validate_level(print_logs: bool = false) -> LevelValidationResult:
	var result := LevelValidationResult.new()
	var layout: LevelLayoutData = _runtime_layout_data()
	if layout == null:
		result.add_error("Missing level layout data.")
		if print_logs:
			for message: String in result.errors:
				push_error("[LevelRoot] %s" % message)
		return result

	var spawn_count: int = 0
	var exit_count: int = 0
	for cell_data: LevelCellData in layout.cells:
		if cell_data == null:
			continue
		if cell_data.is_player_spawn:
			spawn_count += 1
		if cell_data.is_exit:
			exit_count += 1
		if not cell_data.has_floor:
			if cell_data.content_type != LevelCell.CellContentType.EMPTY:
				result.add_error("Cell %s has content but no floor." % str(cell_data.coord))
			if cell_data.is_player_spawn:
				result.add_error("Cell %s has player spawn but no floor." % str(cell_data.coord))
			if cell_data.is_exit:
				result.add_error("Cell %s has exit but no floor." % str(cell_data.coord))

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
	sync_layout_from_grid()


func clear_contents() -> void:
	for cell: LevelCell in _all_cells():
		cell.content_type = LevelCell.CellContentType.EMPTY
		cell.is_player_spawn = false
		cell.is_exit = false
	sync_layout_from_grid()


func build_runtime_data() -> LevelRuntimeData:
	var layout: LevelLayoutData = _runtime_layout_data()
	var data := LevelRuntimeData.new()
	if layout == null:
		data.grid_size = grid_size
		data.memory_capacity = memory_capacity
		push_error("[LevelRoot] build_runtime_data failed: missing level layout and legacy cells.")
		return data

	data.grid_size = layout.grid_size
	data.memory_capacity = layout.memory_capacity
	for cell_data: LevelCellData in layout.cells:
		if cell_data == null:
			continue
		if not cell_data.has_floor:
			continue
		data.floor_cells.append(cell_data.coord)
		if cell_data.is_player_spawn:
			data.player_start = cell_data.coord
		if cell_data.is_exit:
			data.exit_position = cell_data.coord
		match cell_data.content_type:
			LevelCell.CellContentType.WALL:
				data.walls.append(cell_data.coord)
			LevelCell.CellContentType.BOX:
				data.boxes.append(cell_data.coord)
			_:
				pass

	var validation: LevelValidationResult = validate_level()
	if not validation.is_valid:
		push_warning("Building runtime data from invalid level. Check validation logs.")
	return data


func snapshot_level_state() -> Dictionary:
	if not sync_layout_from_grid():
		_ensure_layout_data("snapshot")
	var layout: LevelLayoutData = _runtime_layout_data()
	if layout == null:
		return {
			"grid_size": grid_size,
			"memory_capacity": memory_capacity,
			"cell_size": cell_size,
			"cells": [],
		}

	var snapshot: Dictionary = {
		"grid_size": layout.grid_size,
		"memory_capacity": layout.memory_capacity,
		"cell_size": layout.cell_size,
		"cells": [],
	}
	var cells: Array[Dictionary] = []
	for cell_data: LevelCellData in layout.cells:
		if cell_data == null:
			continue
		cells.append({
			"coord": cell_data.coord,
			"has_floor": cell_data.has_floor,
			"content_type": int(cell_data.content_type),
			"is_player_spawn": cell_data.is_player_spawn,
			"is_exit": cell_data.is_exit,
		})
	cells.sort_custom(_compare_cell_dict)
	snapshot["cells"] = cells
	return snapshot


func apply_snapshot(snapshot: Dictionary) -> void:
	var layout: LevelLayoutData = _layout_from_snapshot(snapshot)
	level_layout = layout
	grid_size = layout.grid_size
	memory_capacity = layout.memory_capacity
	cell_size = layout.cell_size
	_rebuild_grid_from_layout()


func sync_layout_from_grid() -> bool:
	var cells: Array[LevelCell] = _all_cells()
	if cells.is_empty():
		return false
	if level_layout == null:
		level_layout = LevelLayoutData.new()
	level_layout.grid_size = grid_size
	level_layout.memory_capacity = memory_capacity
	level_layout.cell_size = cell_size
	var serialized: Array[LevelCellData] = []
	for cell: LevelCell in cells:
		if cell == null or cell.is_queued_for_deletion():
			continue
		var cell_data := LevelCellData.new()
		cell_data.coord = cell.coord
		cell_data.has_floor = cell.has_floor
		cell_data.content_type = int(cell.content_type)
		cell_data.is_player_spawn = cell.is_player_spawn
		cell_data.is_exit = cell.is_exit
		serialized.append(cell_data)
	serialized.sort_custom(_compare_cell_resource)
	level_layout.cells = serialized
	return true


func _runtime_layout_data() -> LevelLayoutData:
	if _has_layout_cells(level_layout):
		_sync_runtime_properties_to_layout(level_layout)
		return level_layout
	if _has_legacy_cells():
		_migrate_legacy_cells_to_layout()
		return level_layout
	return null


func _ensure_layout_data(context: String) -> bool:
	if _has_layout_cells(level_layout):
		_sync_runtime_properties_to_layout(level_layout)
		return true
	if _has_legacy_cells():
		_migrate_legacy_cells_to_layout()
		return true
	push_error("[LevelRoot] %s: level data missing (layout + legacy cells both empty)." % context)
	return false


func _migrate_legacy_cells_to_layout() -> void:
	if not _has_legacy_cells():
		return
	if level_layout == null:
		level_layout = LevelLayoutData.new()
	level_layout.grid_size = grid_size
	level_layout.memory_capacity = memory_capacity
	level_layout.cell_size = cell_size
	var serialized: Array[LevelCellData] = []
	for cell: LevelCell in _all_cells():
		if cell == null or cell.is_queued_for_deletion():
			continue
		var cell_data := LevelCellData.new()
		cell_data.coord = cell.coord
		cell_data.has_floor = cell.has_floor
		cell_data.content_type = int(cell.content_type)
		cell_data.is_player_spawn = cell.is_player_spawn
		cell_data.is_exit = cell.is_exit
		serialized.append(cell_data)
	serialized.sort_custom(_compare_cell_resource)
	level_layout.cells = serialized
	print("[LevelRoot] Migrated legacy cell nodes into level_layout.")


func _rebuild_grid_from_layout() -> bool:
	var grid: Node2D = _resolve_grid()
	if grid == null:
		return false
	if level_layout == null:
		return false
	_rebuild_grid_internal(grid)
	_apply_layout_to_cells(level_layout)
	return true


func _apply_layout_to_cells(layout: LevelLayoutData) -> void:
	if layout == null:
		return
	grid_size = Vector3i(max(layout.grid_size.x, 1), max(layout.grid_size.y, 1), max(layout.grid_size.z, 1))
	memory_capacity = layout.memory_capacity
	cell_size = max(layout.cell_size, 8)
	var lookup: Dictionary = {}
	for cell: LevelCell in _all_cells():
		lookup[cell.coord] = cell
	for cell_data: LevelCellData in layout.cells:
		if cell_data == null:
			continue
		var target: LevelCell = lookup.get(cell_data.coord)
		if target == null:
			continue
		target.has_floor = cell_data.has_floor
		target.content_type = int(cell_data.content_type)
		target.is_player_spawn = cell_data.is_player_spawn
		target.is_exit = cell_data.is_exit


func _layout_from_snapshot(snapshot: Dictionary) -> LevelLayoutData:
	var layout := LevelLayoutData.new()
	layout.grid_size = snapshot.get("grid_size", grid_size)
	layout.memory_capacity = int(snapshot.get("memory_capacity", memory_capacity))
	layout.cell_size = max(int(snapshot.get("cell_size", cell_size)), 8)
	var cells: Array[LevelCellData] = []
	for cell_data_variant: Variant in snapshot.get("cells", []):
		if cell_data_variant is not Dictionary:
			continue
		var cell_dict: Dictionary = cell_data_variant
		var cell_data := LevelCellData.new()
		cell_data.coord = cell_dict.get("coord", Vector3i.ZERO)
		cell_data.has_floor = bool(cell_dict.get("has_floor", false))
		cell_data.content_type = int(cell_dict.get("content_type", LevelCell.CellContentType.EMPTY))
		cell_data.is_player_spawn = bool(cell_dict.get("is_player_spawn", false))
		cell_data.is_exit = bool(cell_dict.get("is_exit", false))
		cells.append(cell_data)
	cells.sort_custom(_compare_cell_resource)
	layout.cells = cells
	return layout


func _sync_runtime_properties_to_layout(layout: LevelLayoutData) -> void:
	layout.grid_size = grid_size
	layout.memory_capacity = memory_capacity
	layout.cell_size = cell_size


func _has_legacy_cells() -> bool:
	return not _all_cells().is_empty()


func _has_layout_cells(layout: LevelLayoutData) -> bool:
	if layout == null:
		return false
	return not layout.cells.is_empty()


func _ensure_slice(z: int) -> Node2D:
	var grid: Node2D = _resolve_grid()
	var slice_name: String = "Slice_%d" % z
	if grid.has_node(slice_name):
		return grid.get_node(slice_name)
	var node := Node2D.new()
	node.name = slice_name
	grid.add_child(node)
	node.owner = _resolve_persistent_owner()
	return node


func _rebuild_grid_internal(grid: Node2D) -> void:
	for z: int in range(grid_size.z):
		var slice: Node2D = _ensure_slice(z)
		_rebuild_slice_cells(slice, z)
	_remove_out_of_range_slices()


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
			instance.has_floor = false
			slice.add_child(instance)
			instance.owner = _resolve_persistent_owner()
	_remove_out_of_range_cells(slice, z)


func _remove_out_of_range_slices() -> void:
	var grid: Node2D = _resolve_grid()
	for child: Node in grid.get_children():
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
	var grid: Node2D = _resolve_grid()
	if grid == null:
		return cells
	for slice_node: Node in grid.get_children():
		for cell_node: Node in slice_node.get_children():
			if cell_node is LevelCell:
				cells.append(cell_node)
	return cells


func _cell_name(coord: Vector3i) -> String:
	return "Cell_%d_%d_%d" % [coord.x, coord.y, coord.z]


func _resolve_grid() -> Node2D:
	if _grid == null and has_node("Grid"):
		_grid = get_node("Grid")
	return _grid


func _resolve_persistent_owner() -> Node:
	if owner != null:
		return owner
	return self


func _compare_cell_dict(a: Dictionary, b: Dictionary) -> bool:
	var ac: Vector3i = a.get("coord", Vector3i.ZERO)
	var bc: Vector3i = b.get("coord", Vector3i.ZERO)
	return _compare_coord(ac, bc)


func _compare_cell_resource(a: LevelCellData, b: LevelCellData) -> bool:
	if a == null:
		return true
	if b == null:
		return false
	return _compare_coord(a.coord, b.coord)


func _compare_coord(a: Vector3i, b: Vector3i) -> bool:
	if a.z != b.z:
		return a.z < b.z
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
