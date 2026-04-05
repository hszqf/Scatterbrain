class_name BoardView
extends Node2D

## Renders board grid and synchronizes entity visual nodes.
@export var cell_size: int = 72
@export var player_path: NodePath
@export var exit_path: NodePath
@export var box_layer_path: NodePath

var _player_view: PlayerView
var _exit_view: ExitView
var _box_layer: Node2D
var _boxes: Dictionary[StringName, BoxView] = {}
var _world: CompiledWorld
var _replay_presenting_subjects: Dictionary[StringName, bool] = {}


func _ready() -> void:
	_player_view = get_node(player_path)
	_exit_view = get_node(exit_path)
	_box_layer = get_node(box_layer_path)


func sync_world(world: CompiledWorld) -> void:
	_world = world
	_player_view.set_board_position(world.player_position, cell_size)
	_exit_view.set_board_position(world.exit_position, cell_size)

	for entity_id: StringName in world.entity_positions.keys():
		var box_view: BoxView = _ensure_box(entity_id)
		if _replay_presenting_subjects.has(entity_id):
			continue
		box_view.visible = true
		box_view.set_board_position(world.entity_positions[entity_id], cell_size)
		box_view.set_is_ghost(false)
		box_view.set_is_conflict(false)

	for entity_id: StringName in world.ghost_entities.keys():
		var ghost_view: BoxView = _ensure_box(entity_id)
		if _replay_presenting_subjects.has(entity_id):
			continue
		ghost_view.visible = true
		ghost_view.set_board_position(world.ghost_entities[entity_id], cell_size)
		ghost_view.set_is_ghost(true)
		ghost_view.set_is_conflict(false)

	for entity_id: StringName in _boxes.keys():
		if _replay_presenting_subjects.has(entity_id):
			continue
		if not world.entity_positions.has(entity_id) and not world.ghost_entities.has(entity_id):
			_boxes[entity_id].visible = false

	queue_redraw()


func begin_replay_presentation(subject_ids: Array[StringName]) -> void:
	_replay_presenting_subjects.clear()
	for subject_id: StringName in subject_ids:
		_replay_presenting_subjects[subject_id] = true


func end_replay_presentation() -> void:
	_replay_presenting_subjects.clear()
	if _world != null:
		sync_world(_world)


func get_replay_presenting_subjects() -> Array[StringName]:
	var subjects: Array[StringName] = []
	for subject_id: StringName in _replay_presenting_subjects.keys():
		subjects.append(subject_id)
	subjects.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return subjects


func is_replay_presenting_subject(entity_id: StringName) -> bool:
	return _replay_presenting_subjects.has(entity_id)


func board_to_pixel_center(pos: Vector2i) -> Vector2:
	return Vector2((pos.x + 0.5) * cell_size, (pos.y + 0.5) * cell_size)


func board_pixel_size() -> Vector2:
	if _player_view == null:
		return Vector2.ZERO
	var world_size: Vector2i = _player_view.board_size_hint
	return Vector2(world_size.x * cell_size, world_size.y * cell_size)


func _draw() -> void:
	if _player_view == null:
		return
	var world_size: Vector2i = _player_view.board_size_hint
	if world_size == Vector2i.ZERO:
		return
	var bg := Rect2(Vector2.ZERO, Vector2(world_size.x * cell_size, world_size.y * cell_size))
	draw_rect(bg, Color("11161d"), true)

	if _world != null:
		for y: int in range(world_size.y):
			for x: int in range(world_size.x):
				var cell := Vector2i(x, y)
				var cell_rect := Rect2(Vector2(x * cell_size, y * cell_size), Vector2(cell_size, cell_size))
				if _world.has_floor_at(cell):
					draw_rect(cell_rect, Color("232d3a"), true)
				if _world.has_wall_at(cell):
					var pad: float = float(cell_size) * 0.11
					draw_rect(cell_rect.grow(-pad), Color("6f7f97"), true)

	for y: int in range(world_size.y + 1):
		draw_line(Vector2(0, y * cell_size), Vector2(world_size.x * cell_size, y * cell_size), Color("2b3644"), 1.5)
	for x: int in range(world_size.x + 1):
		draw_line(Vector2(x * cell_size, 0), Vector2(x * cell_size, world_size.y * cell_size), Color("2b3644"), 1.5)


func set_board_size(size: Vector2i) -> void:
	_player_view.board_size_hint = size
	queue_redraw()


func _ensure_box(entity_id: StringName) -> BoxView:
	if _boxes.has(entity_id):
		return _boxes[entity_id]
	var box_scene: PackedScene = preload("res://scenes/entities/BoxView.tscn")
	var node: BoxView = box_scene.instantiate()
	node.name = String(entity_id)
	_box_layer.add_child(node)
	_boxes[entity_id] = node
	return node


func get_box_view(entity_id: StringName) -> BoxView:
	return _ensure_box(entity_id)
