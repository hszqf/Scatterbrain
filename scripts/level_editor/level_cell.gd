@tool
class_name LevelCell
extends Node2D

enum CellContentType {
	EMPTY,
	WALL,
	BOX,
}

@export var coord: Vector3i = Vector3i.ZERO:
	set(value):
		coord = value
		_refresh_visuals()

@export var has_floor: bool = true:
	set(value):
		has_floor = value
		_sanitize_flags_for_floor()
		_refresh_visuals()

@export var content_type: CellContentType = CellContentType.EMPTY:
	set(value):
		content_type = value
		_sanitize_flags_for_floor()
		_refresh_visuals()

@export var is_player_spawn: bool = false:
	set(value):
		is_player_spawn = value
		_sanitize_flags_for_floor()
		_refresh_visuals()

@export var is_exit: bool = false:
	set(value):
		is_exit = value
		_sanitize_flags_for_floor()
		_refresh_visuals()

@export var cell_size: int = 96:
	set(value):
		cell_size = max(value, 8)
		_refresh_visuals()

@export var show_coord_label: bool = true:
	set(value):
		show_coord_label = value
		_refresh_visuals()

@onready var _floor_layer: Node2D = get_node_or_null("FloorLayer")
@onready var _cell_layer: Node2D = get_node_or_null("CellLayer")
@onready var _coord_label: Label = get_node_or_null("CoordLabel")


func _ready() -> void:
	_ensure_runtime_nodes()
	_refresh_visuals()


func _ensure_runtime_nodes() -> void:
	if _floor_layer == null:
		_floor_layer = Node2D.new()
		_floor_layer.name = "FloorLayer"
		add_child(_floor_layer)
	if _cell_layer == null:
		_cell_layer = Node2D.new()
		_cell_layer.name = "CellLayer"
		add_child(_cell_layer)
	if _coord_label == null:
		_coord_label = Label.new()
		_coord_label.name = "CoordLabel"
		add_child(_coord_label)


func _sanitize_flags_for_floor() -> void:
	if has_floor:
		return
	if content_type != CellContentType.EMPTY:
		content_type = CellContentType.EMPTY
	if is_player_spawn:
		is_player_spawn = false
	if is_exit:
		is_exit = false


func _refresh_visuals() -> void:
	if not is_node_ready():
		return
	position = Vector2(coord.x * cell_size, coord.y * cell_size)
	_sanitize_flags_for_floor()
	_coord_label.visible = show_coord_label
	_coord_label.text = "(%d,%d,%d)" % [coord.x, coord.y, coord.z]
	_coord_label.position = Vector2(6, 4)
	_coord_label.add_theme_color_override("font_color", Color("f2f2f2"))
	_coord_label.add_theme_font_size_override("font_size", 11)
	_rebuild_layer_visuals()


func _rebuild_layer_visuals() -> void:
	for child: Node in _floor_layer.get_children():
		child.queue_free()
	for child: Node in _cell_layer.get_children():
		child.queue_free()

	if has_floor:
		var floor_polygon := Polygon2D.new()
		floor_polygon.polygon = PackedVector2Array([
			Vector2.ZERO,
			Vector2(cell_size, 0),
			Vector2(cell_size, cell_size),
			Vector2(0, cell_size),
		])
		floor_polygon.color = Color("232d3a")
		_floor_layer.add_child(floor_polygon)

		var floor_border := Line2D.new()
		floor_border.width = 1.5
		floor_border.default_color = Color("45566d")
		floor_border.closed = true
		floor_border.points = PackedVector2Array([
			Vector2(0, 0),
			Vector2(cell_size, 0),
			Vector2(cell_size, cell_size),
			Vector2(0, cell_size),
		])
		_floor_layer.add_child(floor_border)

	match content_type:
		CellContentType.WALL:
			_add_center_block(Color("6f7f97"), 0.78)
		CellContentType.BOX:
			_add_center_block(Color("b57f43"), 0.62)
		_:
			pass

	if is_player_spawn:
		var spawn_dot := Polygon2D.new()
		var pad: float = float(cell_size) * 0.35
		spawn_dot.polygon = PackedVector2Array([
			Vector2(pad, pad),
			Vector2(cell_size - pad, pad),
			Vector2(cell_size - pad, cell_size - pad),
			Vector2(pad, cell_size - pad),
		])
		spawn_dot.color = Color("43c85e")
		_cell_layer.add_child(spawn_dot)

	if is_exit:
		var exit_ring := Line2D.new()
		exit_ring.width = 4.0
		exit_ring.default_color = Color("47b8ff")
		exit_ring.closed = true
		var inset: float = float(cell_size) * 0.2
		exit_ring.points = PackedVector2Array([
			Vector2(inset, inset),
			Vector2(cell_size - inset, inset),
			Vector2(cell_size - inset, cell_size - inset),
			Vector2(inset, cell_size - inset),
		])
		_cell_layer.add_child(exit_ring)


func _add_center_block(color: Color, size_ratio: float) -> void:
	var side: float = float(cell_size) * size_ratio
	var offset: float = (float(cell_size) - side) * 0.5
	var block := Polygon2D.new()
	block.polygon = PackedVector2Array([
		Vector2(offset, offset),
		Vector2(offset + side, offset),
		Vector2(offset + side, offset + side),
		Vector2(offset, offset + side),
	])
	block.color = color
	_cell_layer.add_child(block)
