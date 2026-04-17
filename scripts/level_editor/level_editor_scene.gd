@tool
class_name LevelEditorScene
extends Control

const LEVEL_ROOT_SCENE: PackedScene = preload("res://scenes/levels/LevelRoot.tscn")
const LEVELS_DIR: String = "res://scenes/levels"
const LEVEL_FILE_PREFIX: String = "Level"
const NO_FLOOR_CHAR: String = "_"

signal request_main_menu

enum EditMode {
	PLACE,
	DELETE,
}

enum PaintTool {
	FLOOR,
	WALL,
	BOX,
	PLAYER,
	EXIT,
}

@export var default_level_size: Vector2i = Vector2i(5, 5)

@onready var _list_container: VBoxContainer = $MainHBox/ListPanel/ListVBox/ListScroll/LevelList
@onready var _list_panel: Panel = $MainHBox/ListPanel
@onready var _add_level_button: Button = $MainHBox/ListPanel/ListVBox/AddLevelButton
@onready var _editor_panel: Control = $MainHBox/EditorPanel
@onready var _level_title_label: Label = $MainHBox/EditorPanel/TopVBox/TitleRow/LevelTitle
@onready var _size_x_spin: SpinBox = $MainHBox/EditorPanel/TopVBox/SizeRow/SizeXSpin
@onready var _size_y_spin: SpinBox = $MainHBox/EditorPanel/TopVBox/SizeRow/SizeYSpin
@onready var _size_update_button: Button = $MainHBox/EditorPanel/TopVBox/SizeRow/UpdateSizeButton
@onready var _save_button: Button = $MainHBox/EditorPanel/TopVBox/TitleRow/SaveButton
@onready var _export_button: Button = $MainHBox/EditorPanel/TopVBox/TitleRow/ExportButton
@onready var _back_button: Button = $MainHBox/EditorPanel/TopVBox/TitleRow/BackButton
@onready var _main_menu_button: Button = $MainHBox/EditorPanel/TopVBox/TitleRow/MainMenuButton
@onready var _export_feedback_label: Label = $MainHBox/EditorPanel/TopVBox/ExportFeedbackLabel
@onready var _canvas_panel: Panel = $MainHBox/EditorPanel/TopVBox/CanvasPanel
@onready var _mode_place_button: Button = $MainHBox/EditorPanel/TopVBox/ToolbarVBox/ModeRow/PlaceModeButton
@onready var _mode_delete_button: Button = $MainHBox/EditorPanel/TopVBox/ToolbarVBox/ModeRow/DeleteModeButton
@onready var _tool_floor_button: Button = $MainHBox/EditorPanel/TopVBox/ToolbarVBox/ToolScroll/ToolRow/FloorToolButton
@onready var _tool_wall_button: Button = $MainHBox/EditorPanel/TopVBox/ToolbarVBox/ToolScroll/ToolRow/WallToolButton
@onready var _tool_box_button: Button = $MainHBox/EditorPanel/TopVBox/ToolbarVBox/ToolScroll/ToolRow/BoxToolButton
@onready var _tool_player_button: Button = $MainHBox/EditorPanel/TopVBox/ToolbarVBox/ToolScroll/ToolRow/PlayerToolButton
@onready var _tool_exit_button: Button = $MainHBox/EditorPanel/TopVBox/ToolbarVBox/ToolScroll/ToolRow/ExitToolButton
@onready var _level_host: Node2D = $MainHBox/EditorPanel/TopVBox/CanvasPanel/LevelHost

var _mode_group: ButtonGroup = ButtonGroup.new()
var _tool_group: ButtonGroup = ButtonGroup.new()

var _current_level_root: LevelRoot
var _current_level_path: String = ""
var _current_level_name: String = ""
var _edit_mode: EditMode = EditMode.PLACE
var _paint_tool: PaintTool = PaintTool.FLOOR
var _is_panning_canvas: bool = false
var _last_pan_mouse_position: Vector2 = Vector2.ZERO
var _canvas_zoom: float = 1.0

const MIN_CANVAS_ZOOM: float = 0.4
const MAX_CANVAS_ZOOM: float = 2.4
const CANVAS_ZOOM_STEP: float = 0.1


func _ready() -> void:
	if not Engine.is_editor_hint():
		pass
	_bind_buttons()
	_refresh_level_list()
	_close_editor()


func _bind_buttons() -> void:
	_add_level_button.pressed.connect(_on_add_level_pressed)
	_size_update_button.pressed.connect(_on_update_size_pressed)
	_save_button.pressed.connect(_on_save_pressed)
	_export_button.pressed.connect(_on_export_pressed)
	_back_button.pressed.connect(_on_back_pressed)
	_main_menu_button.pressed.connect(_on_main_menu_pressed)
	_canvas_panel.gui_input.connect(_on_canvas_gui_input)

	_mode_place_button.button_group = _mode_group
	_mode_delete_button.button_group = _mode_group
	_mode_place_button.toggle_mode = true
	_mode_delete_button.toggle_mode = true
	_mode_place_button.pressed.connect(func() -> void: _set_mode(EditMode.PLACE))
	_mode_delete_button.pressed.connect(func() -> void: _set_mode(EditMode.DELETE))

	_tool_floor_button.button_group = _tool_group
	_tool_wall_button.button_group = _tool_group
	_tool_box_button.button_group = _tool_group
	_tool_player_button.button_group = _tool_group
	_tool_exit_button.button_group = _tool_group
	for button: Button in [_tool_floor_button, _tool_wall_button, _tool_box_button, _tool_player_button, _tool_exit_button]:
		button.toggle_mode = true

	_tool_floor_button.pressed.connect(func() -> void: _set_tool(PaintTool.FLOOR))
	_tool_wall_button.pressed.connect(func() -> void: _set_tool(PaintTool.WALL))
	_tool_box_button.pressed.connect(func() -> void: _set_tool(PaintTool.BOX))
	_tool_player_button.pressed.connect(func() -> void: _set_tool(PaintTool.PLAYER))
	_tool_exit_button.pressed.connect(func() -> void: _set_tool(PaintTool.EXIT))

	_set_mode(EditMode.PLACE)
	_set_tool(PaintTool.FLOOR)


func _refresh_level_list() -> void:
	for child: Node in _list_container.get_children():
		child.queue_free()
	for level_path: String in _list_level_paths():
		var row := HBoxContainer.new()
		var level_label := Label.new()
		level_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		level_label.text = _level_name_from_path(level_path)
		var edit_button := Button.new()
		edit_button.text = "编辑"
		edit_button.pressed.connect(func() -> void: _open_level(level_path))
		var delete_button := Button.new()
		delete_button.text = "删除"
		delete_button.pressed.connect(func() -> void: _delete_level(level_path))
		row.add_child(level_label)
		row.add_child(edit_button)
		row.add_child(delete_button)
		_list_container.add_child(row)


func _on_add_level_pressed() -> void:
	var level_number: int = _next_level_number()
	var level_name: String = "%s%03d" % [LEVEL_FILE_PREFIX, level_number]
	var level_path: String = "%s/%s.tscn" % [LEVELS_DIR, level_name]
	var root: LevelRoot = _create_default_level_root(level_name)
	if not _save_level_root(root, level_path):
		return
	_open_level(level_path)
	_refresh_level_list()


func _open_level(level_path: String) -> void:
	_close_level_root()
	var packed: PackedScene = load(level_path)
	if packed == null:
		push_error("[LevelEditor] Failed to load level: %s" % level_path)
		return
	var instance: Node = packed.instantiate()
	if instance is not LevelRoot:
		push_error("[LevelEditor] Scene root is not LevelRoot: %s" % level_path)
		instance.queue_free()
		return
	_current_level_root = instance
	_current_level_path = level_path
	_current_level_name = _level_name_from_path(level_path)
	_level_host.add_child(_current_level_root)
	_current_level_root.auto_rebuild_in_editor = false
	_current_level_root.rebuild_grid()
	_align_level_root()
	_sync_level_header()
	_list_panel.visible = false
	_editor_panel.visible = true


func _delete_level(level_path: String) -> void:
	if _current_level_path == level_path:
		_close_editor()
	var error: int = DirAccess.remove_absolute(level_path)
	if error != OK:
		push_error("[LevelEditor] Failed to delete %s (code %d)" % [level_path, error])
	_refresh_level_list()


func _close_editor() -> void:
	_close_level_root()
	_current_level_path = ""
	_current_level_name = ""
	_is_panning_canvas = false
	_list_panel.visible = true
	_editor_panel.visible = false


func _close_level_root() -> void:
	if _current_level_root != null:
		_current_level_root.queue_free()
		_current_level_root = null


func _on_back_pressed() -> void:
	_close_editor()


func _on_main_menu_pressed() -> void:
	request_main_menu.emit()


func _on_update_size_pressed() -> void:
	if _current_level_root == null:
		return
	var width: int = maxi(int(_size_x_spin.value), 1)
	var height: int = maxi(int(_size_y_spin.value), 1)
	_current_level_root.grid_size = Vector3i(width, height, 1)
	_current_level_root.rebuild_grid()
	_align_level_root()
	_sync_level_header()
	_save_current_level()


func _on_save_pressed() -> void:
	_save_current_level()


func _on_export_pressed() -> void:
	_export_current_level_to_clipboard()


func _save_current_level() -> void:
	if _current_level_root == null or _current_level_path.is_empty():
		return
	var snapshot: Dictionary = _snapshot_level_data(_current_level_root)
	_save_level_snapshot(snapshot, _current_level_path)
	_refresh_level_list()


func _save_level_root(level_root: LevelRoot, level_path: String) -> bool:
	if level_root == null:
		return false
	var packed := PackedScene.new()
	var pack_error: int = packed.pack(level_root)
	if pack_error != OK:
		push_error("[LevelEditor] Pack scene failed: %s (code %d)" % [level_path, pack_error])
		return false
	var save_error: int = ResourceSaver.save(packed, level_path)
	if save_error != OK:
		push_error("[LevelEditor] Save scene failed: %s (code %d)" % [level_path, save_error])
		return false
	return true


func _snapshot_level_data(level_root: LevelRoot) -> Dictionary:
	if level_root == null:
		return {}
	var snapshot: Dictionary = level_root.snapshot_level_state()
	snapshot["level_name"] = level_root.name
	return snapshot


func _build_clean_level_root_from_snapshot(snapshot: Dictionary) -> LevelRoot:
	var clean_root: LevelRoot = LEVEL_ROOT_SCENE.instantiate()
	clean_root.auto_rebuild_in_editor = false
	clean_root.name = String(snapshot.get("level_name", "Level"))
	clean_root.apply_snapshot(snapshot)
	return clean_root


func _save_level_snapshot(snapshot: Dictionary, level_path: String) -> bool:
	if snapshot.is_empty():
		return false
	var editor_snapshot: Dictionary = _canonicalize_snapshot(snapshot)
	DebugLog.log(DebugLog.EDITOR_SAVE, _build_snapshot_summary("editor_live_snapshot", editor_snapshot))
	var clean_root: LevelRoot = _build_clean_level_root_from_snapshot(snapshot)
	var clean_roundtrip_snapshot: Dictionary = _canonicalize_snapshot(clean_root.snapshot_level_state())
	DebugLog.log(DebugLog.EDITOR_SAVE, _build_snapshot_summary("clean_root_roundtrip_snapshot", clean_roundtrip_snapshot))
	var editor_vs_clean: bool = _snapshots_match(editor_snapshot, clean_roundtrip_snapshot)
	DebugLog.log(
		DebugLog.EDITOR_SAVE,
		"compare editor_vs_clean=%s\n%s" % [_same_or_diff(editor_vs_clean), _snapshot_diff_summary(editor_snapshot, clean_roundtrip_snapshot)]
	)
	if not editor_vs_clean:
		push_error("[LevelEditor] Save aborted: editor/clean mismatch for %s" % level_path)
		clean_root.queue_free()
		return false
	var is_saved: bool = _save_level_root(clean_root, level_path)
	clean_root.queue_free()
	if not is_saved:
		return false
	var saved_roundtrip_snapshot: Dictionary = _load_saved_roundtrip_snapshot(level_path)
	if saved_roundtrip_snapshot.is_empty():
		push_error("[LevelEditor] Save aborted: cannot load saved scene for %s" % level_path)
		return false
	DebugLog.log(DebugLog.EDITOR_SAVE, _build_snapshot_summary("saved_scene_roundtrip_snapshot", saved_roundtrip_snapshot))
	var clean_vs_saved: bool = _snapshots_match(clean_roundtrip_snapshot, saved_roundtrip_snapshot)
	DebugLog.log(
		DebugLog.EDITOR_SAVE,
		"compare clean_vs_saved=%s\n%s" % [_same_or_diff(clean_vs_saved), _snapshot_diff_summary(clean_roundtrip_snapshot, saved_roundtrip_snapshot)]
	)
	var editor_vs_saved: bool = _snapshots_match(editor_snapshot, saved_roundtrip_snapshot)
	DebugLog.log(
		DebugLog.EDITOR_SAVE,
		"compare editor_vs_saved=%s\n%s" % [_same_or_diff(editor_vs_saved), _snapshot_diff_summary(editor_snapshot, saved_roundtrip_snapshot)]
	)
	if not clean_vs_saved or not editor_vs_saved:
		push_error("[LevelEditor] Save mismatch after disk roundtrip for %s" % level_path)
		return false
	return true


func _export_current_level_to_clipboard() -> void:
	if _current_level_root == null:
		return
	var snapshot: Dictionary = _snapshot_level_data(_current_level_root)
	if snapshot.is_empty():
		_show_export_feedback("导出失败")
		return
	var export_text: String = _build_export_text(snapshot)
	DisplayServer.clipboard_set(export_text)
	_show_export_feedback("已尝试复制")


func _show_export_feedback(text: String) -> void:
	_export_feedback_label.text = text


func _build_export_text(snapshot: Dictionary) -> String:
	var level_name: String = String(snapshot.get("level_name", _current_level_name))
	var level_index: int = _parse_level_index(level_name)
	var grid_size: Vector3i = snapshot.get("grid_size", Vector3i.ONE)
	var memory_capacity: int = int(snapshot.get("memory_capacity", 1))
	var grid_rows: Array[String] = _build_export_grid_rows(snapshot)
	var lines: Array[String] = [
		level_name,
		"第%d关" % level_index,
		"size=%dx%d" % [grid_size.x, grid_size.y],
		"memory_capacity=%d" % memory_capacity,
		"legend: # wall, . floor, B box, P player, E exit, %s no_floor" % NO_FLOOR_CHAR,
		"",
	]
	lines.append_array(grid_rows)
	return "\n".join(lines)


func _build_export_grid_rows(snapshot: Dictionary) -> Array[String]:
	var grid_size: Vector3i = snapshot.get("grid_size", Vector3i.ONE)
	var cell_lookup: Dictionary = _snapshot_cell_lookup(snapshot)
	var rows: Array[String] = []
	for y: int in range(grid_size.y):
		var chars: Array[String] = []
		for x: int in range(grid_size.x):
			var coord := Vector3i(x, y, 0)
			var cell_data: Dictionary = cell_lookup.get(coord, {})
			chars.append(_cell_char_from_snapshot_cell(cell_data))
		rows.append("".join(chars))
	return rows


func _snapshot_cell_lookup(snapshot: Dictionary) -> Dictionary:
	var lookup: Dictionary = {}
	var cells: Array = snapshot.get("cells", [])
	for cell_data_variant: Variant in cells:
		if cell_data_variant is not Dictionary:
			continue
		var cell_data: Dictionary = cell_data_variant
		var coord: Vector3i = cell_data.get("coord", Vector3i.ZERO)
		lookup[coord] = cell_data
	return lookup


func _cell_char_from_snapshot_cell(cell_data: Dictionary) -> String:
	if cell_data.is_empty():
		return NO_FLOOR_CHAR
	var has_floor: bool = bool(cell_data.get("has_floor", false))
	if not has_floor:
		return NO_FLOOR_CHAR
	var content_type: int = int(cell_data.get("content_type", LevelCell.CellContentType.EMPTY))
	var is_player_spawn: bool = bool(cell_data.get("is_player_spawn", false))
	var is_exit: bool = bool(cell_data.get("is_exit", false))
	if content_type == LevelCell.CellContentType.WALL:
		return "#"
	if is_player_spawn:
		return "P"
	if is_exit:
		return "E"
	if content_type == LevelCell.CellContentType.BOX:
		return "B"
	return "."


func _parse_level_index(level_name: String) -> int:
	var suffix: String = level_name.trim_prefix(LEVEL_FILE_PREFIX)
	if suffix.is_valid_int():
		return suffix.to_int()
	return 0


func _sync_level_header() -> void:
	if _current_level_root == null:
		return
	_level_title_label.text = "%s · 关卡大小 %d * %d" % [
		_current_level_name,
		_current_level_root.grid_size.x,
		_current_level_root.grid_size.y,
	]
	_size_x_spin.value = _current_level_root.grid_size.x
	_size_y_spin.value = _current_level_root.grid_size.y


func _on_canvas_gui_input(event: InputEvent) -> void:
	if _current_level_root == null:
		return
	if event is InputEventMouseButton:
		_handle_canvas_mouse_button(event)
		return
	if event is InputEventMouseMotion:
		_handle_canvas_mouse_motion(event)
		return


func _handle_canvas_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_set_canvas_zoom(_canvas_zoom + CANVAS_ZOOM_STEP)
		accept_event()
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_set_canvas_zoom(_canvas_zoom - CANVAS_ZOOM_STEP)
		accept_event()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		var coord: Vector3i = _mouse_to_coord(event.position)
		if coord.x >= 0:
			_apply_tool_at(coord)
			_save_current_level()
		else:
			_is_panning_canvas = true
			_last_pan_mouse_position = event.position
		accept_event()
		return
	_is_panning_canvas = false


func _handle_canvas_mouse_motion(event: InputEventMouseMotion) -> void:
	if not _is_panning_canvas or not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var delta: Vector2 = event.position - _last_pan_mouse_position
	_current_level_root.position += delta
	_last_pan_mouse_position = event.position
	accept_event()


func _mouse_to_coord(local_mouse_pos: Vector2) -> Vector3i:
	if _current_level_root == null:
		return Vector3i(-1, -1, -1)
	var local_to_level: Vector2 = (local_mouse_pos - _current_level_root.position) / _current_level_root.scale
	var cell_size: int = maxi(_current_level_root.cell_size, 1)
	var x: int = int(floor(local_to_level.x / float(cell_size)))
	var y: int = int(floor(local_to_level.y / float(cell_size)))
	if x < 0 or y < 0 or x >= _current_level_root.grid_size.x or y >= _current_level_root.grid_size.y:
		return Vector3i(-1, -1, -1)
	return Vector3i(x, y, 0)


func _apply_tool_at(coord: Vector3i) -> void:
	if _current_level_root == null:
		return
	var cell: LevelCell = _find_cell(coord)
	if cell == null:
		return
	if _edit_mode == EditMode.PLACE:
		_apply_place(cell)
	else:
		_apply_delete(cell)


func _apply_place(cell: LevelCell) -> void:
	match _paint_tool:
		PaintTool.FLOOR:
			cell.has_floor = true
		PaintTool.WALL:
			cell.has_floor = true
			cell.content_type = LevelCell.CellContentType.WALL
			cell.is_player_spawn = false
			cell.is_exit = false
		PaintTool.BOX:
			cell.has_floor = true
			cell.content_type = LevelCell.CellContentType.BOX
			cell.is_player_spawn = false
			cell.is_exit = false
		PaintTool.PLAYER:
			_clear_player_spawn()
			cell.has_floor = true
			cell.content_type = LevelCell.CellContentType.EMPTY
			cell.is_player_spawn = true
			cell.is_exit = false
		PaintTool.EXIT:
			_clear_exit()
			cell.has_floor = true
			cell.content_type = LevelCell.CellContentType.EMPTY
			cell.is_exit = true
			cell.is_player_spawn = false


func _apply_delete(cell: LevelCell) -> void:
	match _paint_tool:
		PaintTool.FLOOR:
			cell.has_floor = false
		PaintTool.WALL:
			if cell.content_type == LevelCell.CellContentType.WALL:
				cell.content_type = LevelCell.CellContentType.EMPTY
		PaintTool.BOX:
			if cell.content_type == LevelCell.CellContentType.BOX:
				cell.content_type = LevelCell.CellContentType.EMPTY
		PaintTool.PLAYER:
			cell.is_player_spawn = false
		PaintTool.EXIT:
			cell.is_exit = false


func _clear_player_spawn() -> void:
	if _current_level_root == null:
		return
	for cell: LevelCell in _all_cells():
		cell.is_player_spawn = false


func _clear_exit() -> void:
	if _current_level_root == null:
		return
	for cell: LevelCell in _all_cells():
		cell.is_exit = false


func _find_cell(coord: Vector3i) -> LevelCell:
	for cell: LevelCell in _all_cells():
		if cell.coord == coord:
			return cell
	return null


func _all_cells() -> Array[LevelCell]:
	if _current_level_root == null:
		return []
	var cells: Array[LevelCell] = []
	var grid: Node = _current_level_root.get_node_or_null("Grid")
	if grid == null:
		return cells
	for slice_node: Node in grid.get_children():
		for cell_node: Node in slice_node.get_children():
			if cell_node is LevelCell:
				var cell: LevelCell = cell_node
				if not cell.is_queued_for_deletion():
					cells.append(cell)
	return cells


func _align_level_root() -> void:
	if _current_level_root == null:
		return
	_canvas_zoom = 1.0
	_current_level_root.scale = Vector2.ONE * _canvas_zoom
	_current_level_root.position = Vector2(12, 12)


func _set_canvas_zoom(next_zoom: float) -> void:
	if _current_level_root == null:
		return
	_canvas_zoom = clampf(next_zoom, MIN_CANVAS_ZOOM, MAX_CANVAS_ZOOM)
	_current_level_root.scale = Vector2.ONE * _canvas_zoom


func _set_mode(mode: EditMode) -> void:
	_edit_mode = mode
	_mode_place_button.button_pressed = mode == EditMode.PLACE
	_mode_delete_button.button_pressed = mode == EditMode.DELETE


func _set_tool(tool: PaintTool) -> void:
	_paint_tool = tool
	_tool_floor_button.button_pressed = tool == PaintTool.FLOOR
	_tool_wall_button.button_pressed = tool == PaintTool.WALL
	_tool_box_button.button_pressed = tool == PaintTool.BOX
	_tool_player_button.button_pressed = tool == PaintTool.PLAYER
	_tool_exit_button.button_pressed = tool == PaintTool.EXIT


func _level_name_from_path(path: String) -> String:
	return path.get_file().trim_suffix(".tscn")


func _list_level_paths() -> Array[String]:
	var result: Array[String] = []
	var dir: DirAccess = DirAccess.open(LEVELS_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not file_name.begins_with(LEVEL_FILE_PREFIX) or not file_name.ends_with(".tscn"):
			continue
		result.append("%s/%s" % [LEVELS_DIR, file_name])
	dir.list_dir_end()
	result.sort()
	return result


func _next_level_number() -> int:
	var max_number: int = 0
	for level_path: String in _list_level_paths():
		var level_name: String = _level_name_from_path(level_path)
		var suffix: String = level_name.trim_prefix(LEVEL_FILE_PREFIX)
		if suffix.is_valid_int():
			max_number = maxi(max_number, suffix.to_int())
	return max_number + 1


func _create_default_level_root(level_name: String) -> LevelRoot:
	var root: LevelRoot = LEVEL_ROOT_SCENE.instantiate()
	root.name = level_name
	root.auto_rebuild_in_editor = false
	root.grid_size = Vector3i(default_level_size.x, default_level_size.y, 1)
	root.rebuild_grid()
	for cell: LevelCell in _all_cells_for(root):
		cell.has_floor = true
		cell.content_type = LevelCell.CellContentType.EMPTY
		cell.is_player_spawn = false
		cell.is_exit = false
	var spawn_cell: LevelCell = _find_cell_in(root, Vector3i(0, 0, 0))
	if spawn_cell != null:
		spawn_cell.is_player_spawn = true
	var exit_cell: LevelCell = _find_cell_in(root, Vector3i(default_level_size.x - 1, default_level_size.y - 1, 0))
	if exit_cell != null:
		exit_cell.is_exit = true
	return root


func _all_cells_for(level_root: LevelRoot) -> Array[LevelCell]:
	var cells: Array[LevelCell] = []
	var grid: Node = level_root.get_node_or_null("Grid")
	if grid == null:
		return cells
	for slice_node: Node in grid.get_children():
		for cell_node: Node in slice_node.get_children():
			if cell_node is LevelCell:
				cells.append(cell_node)
	return cells


func _find_cell_in(level_root: LevelRoot, coord: Vector3i) -> LevelCell:
	for cell: LevelCell in _all_cells_for(level_root):
		if cell.coord == coord:
			return cell
	return null


func _canonicalize_snapshot(snapshot: Dictionary) -> Dictionary:
	var canonical: Dictionary = {
		"level_name": String(snapshot.get("level_name", _current_level_name)),
		"grid_size": snapshot.get("grid_size", Vector3i.ZERO),
		"memory_capacity": int(snapshot.get("memory_capacity", -1)),
		"cells": [],
	}
	var rows: Array[Dictionary] = []
	var cells: Array = snapshot.get("cells", [])
	for cell_data_variant: Variant in cells:
		if cell_data_variant is not Dictionary:
			continue
		var cell_data: Dictionary = cell_data_variant
		rows.append({
			"coord": cell_data.get("coord", Vector3i.ZERO),
			"has_floor": bool(cell_data.get("has_floor", false)),
			"content_type": int(cell_data.get("content_type", LevelCell.CellContentType.EMPTY)),
			"is_player_spawn": bool(cell_data.get("is_player_spawn", false)),
			"is_exit": bool(cell_data.get("is_exit", false)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ac: Vector3i = a.get("coord", Vector3i.ZERO)
		var bc: Vector3i = b.get("coord", Vector3i.ZERO)
		if ac.z != bc.z:
			return ac.z < bc.z
		if ac.y != bc.y:
			return ac.y < bc.y
		return ac.x < bc.x
	)
	canonical["cells"] = rows
	return canonical


func _snapshots_match(left: Dictionary, right: Dictionary) -> bool:
	return left == right


func _same_or_diff(is_same: bool) -> String:
	return "same" if is_same else "diff"


func _snapshot_diff_summary(source: Dictionary, target: Dictionary) -> String:
	var src_grid: Vector3i = source.get("grid_size", Vector3i.ZERO)
	var dst_grid: Vector3i = target.get("grid_size", Vector3i.ZERO)
	var src_memory: int = int(source.get("memory_capacity", -1))
	var dst_memory: int = int(target.get("memory_capacity", -1))
	var lines: Array[String] = []
	if src_grid != dst_grid:
		lines.append("grid_size mismatch: %s vs %s" % [src_grid, dst_grid])
	if src_memory != dst_memory:
		lines.append("memory_capacity mismatch: %d vs %d" % [src_memory, dst_memory])
	var src_cells: Dictionary = _canonical_cell_map(source)
	var dst_cells: Dictionary = _canonical_cell_map(target)
	var floor_diff: Dictionary = _coord_set_diff(_coords_by_flag(src_cells, "has_floor", true), _coords_by_flag(dst_cells, "has_floor", true))
	lines.append("missing floor coords: %s" % _join_coords(floor_diff.get("missing", [])))
	lines.append("extra floor coords: %s" % _join_coords(floor_diff.get("extra", [])))
	lines.append("spawn mismatch: %s" % _join_coords(_spawn_exit_mismatch(src_cells, dst_cells, "is_player_spawn")))
	lines.append("exit mismatch: %s" % _join_coords(_spawn_exit_mismatch(src_cells, dst_cells, "is_exit")))
	lines.append("content mismatch: %s" % _join_content_mismatches(src_cells, dst_cells))
	return "\n".join(lines)


func _canonical_cell_map(snapshot: Dictionary) -> Dictionary:
	var map: Dictionary = {}
	for cell_data: Dictionary in snapshot.get("cells", []):
		map[cell_data.get("coord", Vector3i.ZERO)] = cell_data
	return map


func _coords_by_flag(cell_map: Dictionary, key: String, expected: bool) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for coord: Variant in cell_map.keys():
		var cell_data: Dictionary = cell_map.get(coord, {})
		if bool(cell_data.get(key, false)) == expected:
			result.append(coord)
	result.sort_custom(_compare_coord)
	return result


func _coord_set_diff(left: Array[Vector3i], right: Array[Vector3i]) -> Dictionary:
	var left_map: Dictionary = {}
	for coord: Vector3i in left:
		left_map[coord] = true
	var right_map: Dictionary = {}
	for coord: Vector3i in right:
		right_map[coord] = true
	var missing: Array[Vector3i] = []
	var extra: Array[Vector3i] = []
	for coord: Vector3i in left:
		if not right_map.has(coord):
			missing.append(coord)
	for coord: Vector3i in right:
		if not left_map.has(coord):
			extra.append(coord)
	missing.sort_custom(_compare_coord)
	extra.sort_custom(_compare_coord)
	return {"missing": missing, "extra": extra}


func _spawn_exit_mismatch(src_cells: Dictionary, dst_cells: Dictionary, flag_key: String) -> Array[Vector3i]:
	var mismatches: Array[Vector3i] = []
	for coord: Variant in src_cells.keys():
		var src: Dictionary = src_cells.get(coord, {})
		var dst: Dictionary = dst_cells.get(coord, {})
		if bool(src.get(flag_key, false)) != bool(dst.get(flag_key, false)):
			mismatches.append(coord)
	for coord: Variant in dst_cells.keys():
		if src_cells.has(coord):
			continue
		var dst_only: Dictionary = dst_cells.get(coord, {})
		if bool(dst_only.get(flag_key, false)):
			mismatches.append(coord)
	mismatches.sort_custom(_compare_coord)
	return mismatches


func _join_content_mismatches(src_cells: Dictionary, dst_cells: Dictionary) -> String:
	var mismatches: Array[String] = []
	for coord: Variant in src_cells.keys():
		var src: Dictionary = src_cells.get(coord, {})
		var dst: Dictionary = dst_cells.get(coord, {})
		var src_type: int = int(src.get("content_type", LevelCell.CellContentType.EMPTY))
		var dst_type: int = int(dst.get("content_type", LevelCell.CellContentType.EMPTY))
		if src_type != dst_type:
			mismatches.append("%s:%d->%d" % [coord, src_type, dst_type])
	for coord: Variant in dst_cells.keys():
		if src_cells.has(coord):
			continue
		var dst_only: Dictionary = dst_cells.get(coord, {})
		var dst_type: int = int(dst_only.get("content_type", LevelCell.CellContentType.EMPTY))
		if dst_type != LevelCell.CellContentType.EMPTY:
			mismatches.append("%s:%d->%d" % [coord, LevelCell.CellContentType.EMPTY, dst_type])
	if mismatches.is_empty():
		return "-"
	return ", ".join(mismatches)


func _join_coords(coords: Array) -> String:
	if coords.is_empty():
		return "-"
	var parts: Array[String] = []
	for coord: Variant in coords:
		parts.append(str(coord))
	return ", ".join(parts)


func _build_snapshot_summary(label: String, snapshot: Dictionary) -> String:
	var grid_size: Vector3i = snapshot.get("grid_size", Vector3i.ZERO)
	var memory_capacity: int = int(snapshot.get("memory_capacity", -1))
	var rows: Array[String] = _build_export_grid_rows(snapshot)
	var stats: Dictionary = _snapshot_stats(snapshot)
	return "%s\nlevel=%s\nsize=%dx%d\nmemory_capacity=%d\nrows=%s\nfloor=%d wall=%d box=%d spawn=%d exit=%d" % [
		label,
		String(snapshot.get("level_name", _current_level_name)),
		grid_size.x,
		grid_size.y,
		memory_capacity,
		"|".join(rows),
		int(stats.get("floor", 0)),
		int(stats.get("wall", 0)),
		int(stats.get("box", 0)),
		int(stats.get("spawn", 0)),
		int(stats.get("exit", 0)),
	]


func _snapshot_stats(snapshot: Dictionary) -> Dictionary:
	var floor_count: int = 0
	var wall_count: int = 0
	var box_count: int = 0
	var spawn_count: int = 0
	var exit_count: int = 0
	for cell_data: Dictionary in snapshot.get("cells", []):
		var has_floor: bool = bool(cell_data.get("has_floor", false))
		if has_floor:
			floor_count += 1
		var content_type: int = int(cell_data.get("content_type", LevelCell.CellContentType.EMPTY))
		if content_type == LevelCell.CellContentType.WALL:
			wall_count += 1
		elif content_type == LevelCell.CellContentType.BOX:
			box_count += 1
		if bool(cell_data.get("is_player_spawn", false)):
			spawn_count += 1
		if bool(cell_data.get("is_exit", false)):
			exit_count += 1
	return {
		"floor": floor_count,
		"wall": wall_count,
		"box": box_count,
		"spawn": spawn_count,
		"exit": exit_count,
	}


func _load_saved_roundtrip_snapshot(level_path: String) -> Dictionary:
	var packed: PackedScene = load(level_path)
	if packed == null:
		return {}
	var instance: Node = packed.instantiate()
	if instance is not LevelRoot:
		instance.queue_free()
		return {}
	var root: LevelRoot = instance
	root.auto_rebuild_in_editor = false
	root.rebuild_grid()
	var snapshot: Dictionary = _canonicalize_snapshot(_snapshot_level_data(root))
	root.queue_free()
	return snapshot


func _compare_coord(a: Vector3i, b: Vector3i) -> bool:
	if a.z != b.z:
		return a.z < b.z
	if a.y != b.y:
		return a.y < b.y
	return a.x < b.x
