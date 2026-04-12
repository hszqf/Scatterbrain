@tool
class_name LevelEditorScene
extends Control

const LEVEL_ROOT_SCENE: PackedScene = preload("res://scenes/levels/LevelRoot.tscn")
const LEVELS_DIR: String = "res://scenes/levels"
const LEVEL_FILE_PREFIX: String = "Level"

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
@onready var _back_button: Button = $MainHBox/EditorPanel/TopVBox/TitleRow/BackButton
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
	_back_button.pressed.connect(_on_back_pressed)
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


func _save_current_level() -> void:
	if _current_level_root == null or _current_level_path.is_empty():
		return
	_save_level_root(_current_level_root, _current_level_path)
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
				cells.append(cell_node)
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
