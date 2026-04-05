class_name ReplayController
extends Node

@export var board_view_path: NodePath
@export var replay_layer_path: NodePath
@export var step_duration: float = 0.45
@export var step_pause: float = 0.12

var _board_view: BoardView
var _replay_layer: Node2D
var _replay_actors: Dictionary[StringName, BoxView] = {}


func _ready() -> void:
	_board_view = get_node(board_view_path)
	_replay_layer = get_node(replay_layer_path)


func has_steps(steps: Array[Dictionary]) -> bool:
	return not steps.is_empty()


func play_steps(steps: Array[Dictionary]) -> void:
	_sync_replay_layer_transform()
	var replay_subjects: Array[StringName] = _collect_replay_subjects(steps)
	_board_view.set_temporarily_hidden_subjects(replay_subjects)
	var first_step_by_subject: Dictionary = _first_step_by_subject(steps)
	for child: Node in _replay_layer.get_children():
		child.queue_free()
	_replay_actors.clear()
	for subject_id: StringName in replay_subjects:
		var step: Dictionary = first_step_by_subject.get(subject_id, {})
		_replay_actors[subject_id] = _create_replay_actor(subject_id, step.get("from", Vector2i.ZERO))
	for step: Dictionary in steps:
		_sync_replay_layer_transform()
		await _play_step(step)
		_sync_replay_layer_transform()
	_replay_actors.clear()
	for child: Node in _replay_layer.get_children():
		child.queue_free()
	_board_view.clear_temporarily_hidden_subjects()


func _play_step(step: Dictionary) -> void:
	_sync_replay_layer_transform()
	if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
		await get_tree().create_timer(step_duration).timeout
		await get_tree().create_timer(step_pause).timeout
		return

	var subject_id: StringName = step.get("subject", &"")
	if not _replay_actors.has(subject_id):
		return
	var node: BoxView = _replay_actors[subject_id]
	node.set_is_ghost(true)
	node.set_is_conflict(bool(step.get("is_conflict", false)))
	var from_pos: Vector2i = step.get("from", Vector2i.ZERO)
	var to_pos: Vector2i = step.get("to", from_pos)
	node.set_board_position(from_pos, _board_view.cell_size)

	var tween: Tween = create_tween()
	tween.tween_property(node, "position", _board_view.board_to_pixel_center(to_pos), step_duration)
	await tween.finished
	await get_tree().create_timer(step_pause).timeout


func _sync_replay_layer_transform() -> void:
	if _board_view == null or _replay_layer == null:
		return
	_replay_layer.position = _board_view.position
	_replay_layer.scale = _board_view.scale


func get_replay_actor_subjects() -> Array[StringName]:
	var subjects: Array[StringName] = []
	for subject_id: StringName in _replay_actors.keys():
		subjects.append(subject_id)
	subjects.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return subjects


func get_replay_hidden_subjects() -> Array[StringName]:
	if _board_view == null:
		return []
	return _board_view.get_temporarily_hidden_subjects()


func _collect_replay_subjects(steps: Array[Dictionary]) -> Array[StringName]:
	var seen: Dictionary[StringName, bool] = {}
	for step: Dictionary in steps:
		if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
			continue
		var subject_id: StringName = step.get("subject", &"")
		if subject_id == &"":
			continue
		seen[subject_id] = true
	var subjects: Array[StringName] = []
	for subject_id: StringName in seen.keys():
		subjects.append(subject_id)
	subjects.sort_custom(func(a: StringName, b: StringName) -> bool:
		return String(a) < String(b)
	)
	return subjects


func _first_step_by_subject(steps: Array[Dictionary]) -> Dictionary:
	var first_steps: Dictionary = {}
	for step: Dictionary in steps:
		if int(step.get("type", -1)) == ChangeRecord.ChangeType.EMPTY:
			continue
		var subject_id: StringName = step.get("subject", &"")
		if subject_id == &"" or first_steps.has(subject_id):
			continue
		first_steps[subject_id] = step
	return first_steps


func _create_replay_actor(subject_id: StringName, start_position: Vector2i) -> BoxView:
	var node := preload("res://scenes/entities/BoxView.tscn").instantiate() as BoxView
	node.name = "%s_replay" % String(subject_id)
	node.set_is_ghost(true)
	node.set_is_conflict(false)
	node.set_board_position(start_position, _board_view.cell_size)
	_replay_layer.add_child(node)
	return node
