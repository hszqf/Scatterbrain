class_name ReplayController
extends Node

@export var board_view_path: NodePath
@export var replay_layer_path: NodePath
@export var step_duration: float = 0.35
@export var step_pause: float = 0.08

var _board_view: BoardView
var _replay_layer: Node2D


func _ready() -> void:
	_board_view = get_node(board_view_path)
	_replay_layer = get_node(replay_layer_path)


func has_steps(steps: Array[Dictionary]) -> bool:
	return not steps.is_empty()


func play_steps(steps: Array[Dictionary]) -> void:
	_sync_replay_layer_transform()
	for child: Node in _replay_layer.get_children():
		child.queue_free()
	for step: Dictionary in steps:
		_sync_replay_layer_transform()
		await _play_step(step)
		_sync_replay_layer_transform()
	for child: Node in _replay_layer.get_children():
		child.queue_free()


func _play_step(step: Dictionary) -> void:
	_sync_replay_layer_transform()
	if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
		await get_tree().create_timer(step_duration).timeout
		await get_tree().create_timer(step_pause).timeout
		return

	var node := preload("res://scenes/entities/BoxView.tscn").instantiate() as BoxView
	node.set_is_ghost(true)
	node.set_is_conflict(bool(step.get("is_conflict", false)))
	_replay_layer.add_child(node)

	var from_pos: Vector2i = step.get("from", Vector2i.ZERO)
	var to_pos: Vector2i = step.get("to", from_pos)
	node.set_board_position(from_pos, _board_view.cell_size)

	var tween: Tween = create_tween()
	tween.tween_property(node, "position", _board_view.board_to_pixel_center(to_pos), step_duration)
	await tween.finished
	await get_tree().create_timer(step_pause).timeout
	node.queue_free()


func _sync_replay_layer_transform() -> void:
	if _board_view == null or _replay_layer == null:
		return
	_replay_layer.position = _board_view.position
	_replay_layer.scale = _board_view.scale
